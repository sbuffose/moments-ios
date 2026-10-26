// CleanupViewModel.swift
// ViewModel para la funcionalidad de limpieza

import Foundation
import SwiftData
import Photos
import Combine

@MainActor
class CleanupViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isLoading = true
    @Published var selectedCategory: CleanupCategoryItem?
    @Published var selectedPhotos: Set<String> = []
    @Published var reviewedPhotos: Set<String> = []
    @Published var keptPhotos: Set<String> = []
    @Published var isDeleting = false
    @Published var showDeleteConfirmation = false
    @Published var errorMessage: String?
    @Published var spaceFreed: Int64 = 0
    @Published var lastDeletedSize: Int64 = 0
    
    @Published var categories: [CleanupCategoryItem] = []
    @Published var estimatedSpaceFreed: Int64 = 0
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private var allPhotos: [PersistedPhoto] = []
    
    // MARK: - Persistence Keys
    
    private let selectedPhotosKey = "com.moments.cleanup.selectedPhotos"
    private let reviewedPhotosKey = "com.moments.cleanup.reviewedPhotos"
    private let keptPhotosKey = "com.moments.cleanup.keptPhotos"
    
    // MARK: - Category Item
    
    struct CleanupCategoryItem: Identifiable {
        let id: String
        let category: CleanupCategoryType
        let count: Int
        let photos: [PersistedPhoto]
        let estimatedSize: Int64
        let confidenceTier: CleanupConfidenceTier
        
        // Photos split by confidence
        var veryLikelyPhotos: [PersistedPhoto] {
            photos.filter { $0.cleanupConfidenceTier == .veryLikely }
        }
        
        var maybePhotos: [PersistedPhoto] {
            photos.filter { $0.cleanupConfidenceTier == .maybe || $0.cleanupConfidenceTier == nil }
        }
        
        var icon: String { category.iconName }
        var localizedKey: String { category.localizedKey }
    }
    
    // Published tiers
    @Published var veryLikelyCategories: [CleanupCategoryItem] = []
    @Published var maybeCategories: [CleanupCategoryItem] = []
    
    // MARK: - Computed Properties
    
    var totalCleanupItems: Int {
        categories.reduce(0) { $0 + $1.count }
    }
    
    // MARK: - Initialization
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadPersistedProgress()
        Task {
            await loadCleanupSuggestions()
        }
    }
    
    // MARK: - Progress Persistence
    
    private func loadPersistedProgress() {
        if let selectedData = UserDefaults.standard.array(forKey: selectedPhotosKey) as? [String] {
            selectedPhotos = Set(selectedData)
        }
        if let reviewedData = UserDefaults.standard.array(forKey: reviewedPhotosKey) as? [String] {
            reviewedPhotos = Set(reviewedData)
        }
        if let keptData = UserDefaults.standard.array(forKey: keptPhotosKey) as? [String] {
            keptPhotos = Set(keptData)
        }
    }
    
    func persistProgress() {
        UserDefaults.standard.set(Array(selectedPhotos), forKey: selectedPhotosKey)
        UserDefaults.standard.set(Array(reviewedPhotos), forKey: reviewedPhotosKey)
        UserDefaults.standard.set(Array(keptPhotos), forKey: keptPhotosKey)
    }
    
    func clearPersistedProgress() {
        UserDefaults.standard.removeObject(forKey: selectedPhotosKey)
        UserDefaults.standard.removeObject(forKey: reviewedPhotosKey)
        UserDefaults.standard.removeObject(forKey: keptPhotosKey)
        selectedPhotos.removeAll()
        reviewedPhotos.removeAll()
        keptPhotos.removeAll()
    }
    
    // MARK: - Review Actions
    
    func markAsReviewed(_ photoId: String, delete: Bool) {
        reviewedPhotos.insert(photoId)
        if delete {
            selectedPhotos.insert(photoId)
            keptPhotos.remove(photoId)
        } else {
            selectedPhotos.remove(photoId)
            keptPhotos.insert(photoId)
        }
        persistProgress()
    }
    
    func hasReviewProgress(for photos: [PersistedPhoto]) -> Bool {
        let photoIds = Set(photos.map { $0.id })
        return !reviewedPhotos.intersection(photoIds).isEmpty
    }
    
    func unreviewedPhotos(from photos: [PersistedPhoto]) -> [PersistedPhoto] {
        photos.filter { !reviewedPhotos.contains($0.id) }
    }
    
    func reviewedCount(from photos: [PersistedPhoto]) -> Int {
        let photoIds = Set(photos.map { $0.id })
        return reviewedPhotos.intersection(photoIds).count
    }
    
    func photosMarkedForDeletion(from photos: [PersistedPhoto]) -> [PersistedPhoto] {
        photos.filter { selectedPhotos.contains($0.id) }
    }
    
    func deletionSizeForReview(from photos: [PersistedPhoto]) -> Int64 {
        photosMarkedForDeletion(from: photos).reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    // MARK: - Loading
    
    func loadCleanupSuggestions() async {
        guard let context = modelContext else { return }
        
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.analysisCompleted }
            )
            
            var fetchedPhotos = try context.fetch(descriptor)
            fetchedPhotos.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            allPhotos = fetchedPhotos
            
            await MainActor.run {
                self.buildCategories()
                self.calculateEstimatedSpace()
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Error al cargar fotos: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func buildCategories() {
        var items: [CleanupCategoryItem] = []
        
        // IMPORTANT: Filter out protected photos from cleanup suggestions
        let cleanablePhotos = allPhotos.filter { !$0.isProtected }
        
        // Group photos by cleanup category
        let categoryGroups = Dictionary(grouping: cleanablePhotos) { $0.cleanupCategory }
        
        // Create category items for each non-empty category
        for categoryType in CleanupCategoryType.allCases {
            guard categoryType != .none else { continue }
            
            var photosForCategory: [PersistedPhoto]
            var defaultConfidence: CleanupConfidenceTier = .maybe
            
            // For some categories, use the stored cleanupCategory
            // For others, calculate on the fly for backwards compatibility
            switch categoryType {
            case .screenshot:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .screenshot || $0.mediaSubtypesRaw.contains("screenshot") 
                }
                defaultConfidence = .veryLikely // Screenshots are very likely junk
            case .screenRecording:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .screenRecording || 
                    ($0.mediaTypeRaw == "video" && $0.mediaSubtypesRaw.contains("screenRecording"))
                }
                defaultConfidence = .maybe // Screen recordings might be important
            case .blurry:
                // Stricter blur detection - only include photos with very low sharpness
                // Threshold lowered from 0.3 to 0.15 to reduce false positives
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .blurry || 
                    ($0.mediaTypeRaw == "image" && ($0.sharpnessScore ?? 1.0) < 0.15)
                }
                // Very blurry (<0.08) is very likely, somewhat blurry (<0.15) is maybe
                photosForCategory.forEach { photo in
                    if (photo.sharpnessScore ?? 1.0) < 0.08 {
                        photo.cleanupConfidenceTier = .veryLikely
                    } else {
                        photo.cleanupConfidenceTier = .maybe
                    }
                }
            case .overexposed:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .overexposed || 
                    ($0.mediaTypeRaw == "image" && ($0.exposureScore ?? 0.5) > 0.85)
                }
                defaultConfidence = .maybe
            case .underexposed:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .underexposed || 
                    ($0.mediaTypeRaw == "image" && ($0.exposureScore ?? 0.5) < 0.15)
                }
                // Very dark (<0.05) is very likely pocket shot
                photosForCategory.forEach { photo in
                    if (photo.exposureScore ?? 0.5) < 0.05 {
                        photo.cleanupConfidenceTier = .veryLikely
                    } else {
                        photo.cleanupConfidenceTier = .maybe
                    }
                }
            case .burst:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .burst || 
                    ($0.burstIdentifier != nil && !$0.representsBurst)
                }
                defaultConfidence = .veryLikely // Non-representative burst photos are safe to delete
            case .nearDuplicate:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .nearDuplicate && $0.isBestInGroup != true
                }
                defaultConfidence = .veryLikely // We've already picked the best
            case .duplicate:
                photosForCategory = categoryGroups[.duplicate] ?? []
                defaultConfidence = .veryLikely // Exact duplicates
            case .accidental:
                photosForCategory = cleanablePhotos.filter { photo in
                    if photo.cleanupCategory == .accidental { return true }
                    guard photo.mediaTypeRaw == "image" else { return false }
                    
                    // Very dark with no faces
                    if let exposure = photo.exposureScore, exposure < 0.05 {
                        if let faces = photo.facesDetected, faces == 0 {
                            return true
                        }
                    }
                    
                    // Very blurry without faces
                    if let sharpness = photo.sharpnessScore, sharpness < 0.1 {
                        if let faces = photo.facesDetected, faces == 0 {
                            return true
                        }
                    }
                    
                    return false
                }
                defaultConfidence = .veryLikely // Pocket shots are safe
            case .document:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .document || ($0.isDocument == true && $0.cleanupCategory != .receipt)
                }
                defaultConfidence = .maybe // Documents might be important
            case .receipt:
                photosForCategory = categoryGroups[.receipt] ?? []
                defaultConfidence = .maybe // Receipts might be needed
            case .qrCode:
                photosForCategory = categoryGroups[.qrCode] ?? []
                defaultConfidence = .veryLikely // QR codes are usually temporary
            case .largeVideo:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .largeVideo || 
                    ($0.mediaTypeRaw == "video" && ($0.estimatedFileSize ?? 0) > 100_000_000)
                }.sorted { ($0.estimatedFileSize ?? 0) > ($1.estimatedFileSize ?? 0) }
                defaultConfidence = .maybe // Large videos might be precious
            case .downloadedMeme:
                photosForCategory = cleanablePhotos.filter { $0.cleanupCategory == .downloadedMeme }
                defaultConfidence = .veryLikely // Downloaded memes
            case .forwardedImage:
                photosForCategory = cleanablePhotos.filter { $0.cleanupCategory == .forwardedImage }
                defaultConfidence = .veryLikely // Forwarded images
            case .none:
                continue
            }
            
            // Set default confidence for photos that don't have one yet
            for photo in photosForCategory where photo.cleanupConfidenceTier == nil {
                photo.cleanupConfidenceTier = defaultConfidence
            }
            
            // Deduplicate and sort by deletion likelihood score (highest first)
            let uniquePhotos = Array(Set(photosForCategory.map { $0.id }))
                .compactMap { id in photosForCategory.first { $0.id == id } }
                .sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
            
            if !uniquePhotos.isEmpty {
                items.append(CleanupCategoryItem(
                    id: categoryType.rawValue,
                    category: categoryType,
                    count: uniquePhotos.count,
                    photos: uniquePhotos,
                    estimatedSize: uniquePhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) },
                    confidenceTier: defaultConfidence
                ))
            }
        }
        
        // Split categories into "Muy probable" and "Quizás" tiers
        veryLikelyCategories = items.filter { item in
            item.veryLikelyPhotos.count > 0
        }.map { item in
            let sortedPhotos = item.veryLikelyPhotos.sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
            return CleanupCategoryItem(
                id: "\(item.id)_veryLikely",
                category: item.category,
                count: sortedPhotos.count,
                photos: sortedPhotos,
                estimatedSize: sortedPhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) },
                confidenceTier: .veryLikely
            )
        }.filter { $0.count > 0 }
        
        maybeCategories = items.filter { item in
            item.maybePhotos.count > 0
        }.map { item in
            let sortedPhotos = item.maybePhotos.sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
            return CleanupCategoryItem(
                id: "\(item.id)_maybe",
                category: item.category,
                count: sortedPhotos.count,
                photos: sortedPhotos,
                estimatedSize: sortedPhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) },
                confidenceTier: .maybe
            )
        }.filter { $0.count > 0 }
        
        // Sort categories by average deletion score (highest first), then by space
        categories = items.sorted { item1, item2 in
            let avgScore1 = item1.photos.isEmpty ? 0 : item1.photos.reduce(0) { $0 + $1.deletionLikelihoodScore } / Double(item1.photos.count)
            let avgScore2 = item2.photos.isEmpty ? 0 : item2.photos.reduce(0) { $0 + $1.deletionLikelihoodScore } / Double(item2.photos.count)
            
            // Combine score and space: 60% score, 40% space (normalized)
            let maxSize = max(item1.estimatedSize, item2.estimatedSize, 1)
            let sortScore1 = avgScore1 * 0.6 + (Double(item1.estimatedSize) / Double(maxSize)) * 0.4
            let sortScore2 = avgScore2 * 0.6 + (Double(item2.estimatedSize) / Double(maxSize)) * 0.4
            
            return sortScore1 > sortScore2
        }
    }
    
    private func calculateEstimatedSpace() {
        // Sum sizes but avoid double-counting photos in multiple categories
        var countedPhotoIds: Set<String> = []
        var totalSize: Int64 = 0
        
        for category in categories {
            for photo in category.photos {
                if !countedPhotoIds.contains(photo.id) {
                    countedPhotoIds.insert(photo.id)
                    totalSize += photo.estimatedFileSize ?? 0
                }
            }
        }
        
        estimatedSpaceFreed = totalSize
    }
    
    // MARK: - Selection
    
    func selectAll(in category: CleanupCategoryItem) {
        for photo in category.photos {
            // Don't auto-select the "best" photo in duplicate groups
            if photo.isBestInGroup != true {
                selectedPhotos.insert(photo.id)
            }
        }
    }
    
    func deselectAll(in category: CleanupCategoryItem) {
        for photo in category.photos {
            selectedPhotos.remove(photo.id)
        }
    }
    
    func toggleSelection(for photo: PersistedPhoto) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }
    
    func isSelected(_ photo: PersistedPhoto) -> Bool {
        selectedPhotos.contains(photo.id)
    }
    
    var selectedCount: Int {
        selectedPhotos.count
    }
    
    var selectedSize: Int64 {
        allPhotos
            .filter { selectedPhotos.contains($0.id) }
            .reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    // MARK: - Deletion
    
    func deleteSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        guard let context = modelContext else { return }
        
        isDeleting = true
        
        let photosToDelete = allPhotos.filter { selectedPhotos.contains($0.id) }
        let identifiers = photosToDelete.map { $0.localIdentifier }
        let sizeFreed = selectedSize
        
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            
            // Remove from SwiftData
            for photo in photosToDelete {
                context.delete(photo)
            }
            try context.save()
            
            // Update state
            selectedPhotos.removeAll()
            spaceFreed = sizeFreed
            lastDeletedSize = sizeFreed
            await loadCleanupSuggestions()
            
        } catch {
            errorMessage = "Error al eliminar: \(error.localizedDescription)"
        }
        
        isDeleting = false
    }
}

// MARK: - Formatted Size

extension CleanupViewModel {
    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
