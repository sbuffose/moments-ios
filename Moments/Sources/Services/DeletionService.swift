// DeletionService.swift
// Handles the final review trash and verifies deletions actually applied

import Foundation
import SwiftData
import Photos

@MainActor
class DeletionService: ObservableObject {
    private var modelContext: ModelContext?
    
    @Published var pendingTrashCount: Int = 0
    @Published var pendingTrashSize: Int64 = 0
    @Published var totalFreedSpace: Int64 = 0
    @Published var isDeleting: Bool = false
    @Published var lastDeletionError: String?
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadPendingTrash()
        loadTotalFreedSpace()
    }
    
    // MARK: - Add to Pending Trash
    
    func addToTrash(photos: [PersistedPhoto], category: String? = nil) async {
        guard let context = modelContext else { return }
        
        for photo in photos {
            // Check if already in trash
            let existingDescriptor = FetchDescriptor<PendingTrashItem>(
                predicate: #Predicate<PendingTrashItem> { $0.photoId == photo.id }
            )
            
            if let existing = try? context.fetch(existingDescriptor).first {
                continue
            }
            
            let trashItem = PendingTrashItem(
                photoId: photo.id,
                localIdentifier: photo.localIdentifier,
                sourceCategory: category ?? photo.cleanupCategoryRaw,
                estimatedFileSize: photo.estimatedFileSize ?? 0
            )
            
            context.insert(trashItem)
        }
        
        try? context.save()
        loadPendingTrash()
    }
    
    // MARK: - Remove from Pending Trash
    
    func removeFromTrash(photoIds: [String]) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PendingTrashItem>()
        let allItems = (try? context.fetch(descriptor)) ?? []
        
        for item in allItems where photoIds.contains(item.photoId) {
            context.delete(item)
        }
        
        try? context.save()
        loadPendingTrash()
    }
    
    // MARK: - Clear Pending Trash
    
    func clearTrash() async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PendingTrashItem>()
        let allItems = (try? context.fetch(descriptor)) ?? []
        
        for item in allItems {
            context.delete(item)
        }
        
        try? context.save()
        loadPendingTrash()
    }
    
    // MARK: - Get Pending Trash Items
    
    func getPendingTrashItems() -> [PendingTrashItem] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<PendingTrashItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .descending)]
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    // MARK: - Execute Deletion with Verification
    
    func executeAndVerifyDeletion() async -> DeletionResult {
        guard let context = modelContext else {
            return DeletionResult(success: false, deletedCount: 0, failedCount: 0, freedSpace: 0, error: "No context")
        }
        
        isDeleting = true
        lastDeletionError = nil
        defer { isDeleting = false }
        
        let trashItems = getPendingTrashItems().filter { $0.isSelected }
        
        guard !trashItems.isEmpty else {
            return DeletionResult(success: true, deletedCount: 0, failedCount: 0, freedSpace: 0, error: nil)
        }
        
        let localIdentifiers = trashItems.map { $0.localIdentifier }
        
        // Create deletion records for verification
        var deletionRecords: [DeletionRecord] = []
        for item in trashItems {
            let record = DeletionRecord(
                localIdentifier: item.localIdentifier,
                photoId: item.photoId,
                category: item.sourceCategory,
                fileSize: item.estimatedFileSize
            )
            deletionRecords.append(record)
            context.insert(record)
        }
        try? context.save()
        
        // Fetch assets
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: fetchOptions)
        
        var assetsToDelete: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            assetsToDelete.append(asset)
        }
        
        guard !assetsToDelete.isEmpty else {
            // Assets already deleted or not found
            await clearTrash()
            return DeletionResult(success: true, deletedCount: 0, failedCount: trashItems.count, freedSpace: 0, error: "Assets not found")
        }
        
        // Perform deletion
        var deletionError: Error?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }
        } catch {
            deletionError = error
            lastDeletionError = error.localizedDescription
        }
        
        // VERIFY deletion actually applied
        try? await Task.sleep(nanoseconds: 500_000_000) // Wait 500ms for PhotoKit to sync
        
        let verificationResult = await verifyDeletions(
            localIdentifiers: localIdentifiers,
            records: deletionRecords
        )
        
        // Update deletion records with verification
        for record in deletionRecords {
            record.verifiedAt = Date()
            record.wasSuccessful = verificationResult.deletedIdentifiers.contains(record.localIdentifier)
        }
        try? context.save()
        
        // Calculate freed space
        let freedSpace = trashItems
            .filter { verificationResult.deletedIdentifiers.contains($0.localIdentifier) }
            .reduce(0) { $0 + $1.estimatedFileSize }
        
        // Update total freed space
        totalFreedSpace += freedSpace
        UserDefaults.standard.set(totalFreedSpace, forKey: "totalFreedSpace")
        
        // Remove verified deletions from trash
        let deletedPhotoIds = trashItems
            .filter { verificationResult.deletedIdentifiers.contains($0.localIdentifier) }
            .map { $0.photoId }
        await removeFromTrash(photoIds: deletedPhotoIds)
        
        // Delete from PersistedPhoto
        await removePersistedPhotos(ids: deletedPhotoIds)
        
        return DeletionResult(
            success: deletionError == nil && verificationResult.failedCount == 0,
            deletedCount: verificationResult.deletedCount,
            failedCount: verificationResult.failedCount,
            freedSpace: freedSpace,
            error: deletionError?.localizedDescription ?? verificationResult.error
        )
    }
    
    // MARK: - Verify Deletions
    
    private func verifyDeletions(localIdentifiers: [String], records: [DeletionRecord]) async -> VerificationResult {
        // Re-fetch the assets to check if they still exist
        let fetchOptions = PHFetchOptions()
        let remainingAssets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: fetchOptions)
        
        var stillExistingIdentifiers = Set<String>()
        remainingAssets.enumerateObjects { asset, _, _ in
            stillExistingIdentifiers.insert(asset.localIdentifier)
        }
        
        let deletedIdentifiers = Set(localIdentifiers).subtracting(stillExistingIdentifiers)
        let failedIdentifiers = stillExistingIdentifiers
        
        var error: String? = nil
        if !failedIdentifiers.isEmpty {
            error = String(localized: "deletion_verification_failed \(failedIdentifiers.count)")
        }
        
        return VerificationResult(
            deletedIdentifiers: deletedIdentifiers,
            failedIdentifiers: failedIdentifiers,
            deletedCount: deletedIdentifiers.count,
            failedCount: failedIdentifiers.count,
            error: error
        )
    }
    
    // MARK: - Remove Persisted Photos
    
    private func removePersistedPhotos(ids: [String]) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPhoto>()
        let allPhotos = (try? context.fetch(descriptor)) ?? []
        
        for photo in allPhotos where ids.contains(photo.id) {
            context.delete(photo)
        }
        
        try? context.save()
    }
    
    // MARK: - Load State
    
    private func loadPendingTrash() {
        let items = getPendingTrashItems()
        pendingTrashCount = items.count
        pendingTrashSize = items.reduce(0) { $0 + $1.estimatedFileSize }
    }
    
    private func loadTotalFreedSpace() {
        totalFreedSpace = UserDefaults.standard.value(forKey: "totalFreedSpace") as? Int64 ?? 0
    }
    
    // MARK: - Format Size
    
    func formattedPendingSize() -> String {
        ByteCountFormatter.string(fromByteCount: pendingTrashSize, countStyle: .file)
    }
    
    func formattedTotalFreed() -> String {
        ByteCountFormatter.string(fromByteCount: totalFreedSpace, countStyle: .file)
    }
}

// MARK: - Result Types

struct DeletionResult {
    let success: Bool
    let deletedCount: Int
    let failedCount: Int
    let freedSpace: Int64
    let error: String?
    
    var freedSpaceFormatted: String {
        ByteCountFormatter.string(fromByteCount: freedSpace, countStyle: .file)
    }
}

struct VerificationResult {
    let deletedIdentifiers: Set<String>
    let failedIdentifiers: Set<String>
    let deletedCount: Int
    let failedCount: Int
    let error: String?
}
