// PhotoLibraryService.swift
// Servicio para interactuar con PhotoKit

import Foundation
import Photos
import SwiftData
import UIKit

@MainActor
class PhotoLibraryService: ObservableObject {
    private let modelContext: ModelContext
    
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isLimitedAccess = false
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() async -> PHAuthorizationStatus {
        if MomentsTestRuntime.shouldSkipLiveScan {
            authorizationStatus = .authorized
            return .authorized
        }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationStatus = status
        self.isLimitedAccess = (status == .limited)
        return status
    }
    
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authorizationStatus = status
        self.isLimitedAccess = (status == .limited)
        return status == .authorized || status == .limited
    }
    
    // MARK: - Library Scanning (Idempotent & Incremental)
    
    func scanLibrary(progressHandler: @escaping @Sendable (Double, Int) async -> Void) async {
        // Load or create analysis state for resumable indexing
        let analysisState = loadOrCreateAnalysisState()
        
        // Get existing photo IDs to avoid duplicates (idempotency)
        let existingIds = fetchExistingPhotoIds()
        let existingCount = existingIds.count
        
        // Fetch all assets from PhotoKit
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        
        // For incremental updates: only fetch photos newer than last scan
        // This uses lastScanDate for completed scans (not lastIndexedPhotoDate which is for interrupted scans)
        if let lastScan = analysisState.lastScanDate, !analysisState.indexingInProgress {
            fetchOptions.predicate = NSPredicate(format: "modificationDate > %@", lastScan as NSDate)
        }
        
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        
        // If no new assets and we have a completed scan, report existing count
        guard allAssets.count > 0 else {
            analysisState.indexingInProgress = false
            try? modelContext.save()
            await progressHandler(1.0, existingCount)
            return
        }
        
        // Mark indexing as in progress
        analysisState.indexingInProgress = true
        try? modelContext.save()
        
        let batchSize = 100
        var newlyInsertedCount = 0
        var processedInThisScan = 0
        var photosToInsert: [PersistedPhoto] = []
        
        // Collect all assets first
        var assets: [PHAsset] = []
        allAssets.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        let totalToProcess = assets.count
        
        // Process in batches on main actor
        for asset in assets {
            // IDEMPOTENCY: Only insert if not already in database
            if !existingIds.contains(asset.localIdentifier) {
                let photo = createPersistedPhoto(from: asset)
                photosToInsert.append(photo)
                newlyInsertedCount += 1
            }
            
            processedInThisScan += 1
            
            // Batch insert every batchSize items
            if processedInThisScan % batchSize == 0 {
                for photo in photosToInsert {
                    modelContext.insert(photo)
                }
                photosToInsert.removeAll()
                try? modelContext.save()
                
                // Progress based on photos processed in this scan
                let progress = Double(processedInThisScan) / Double(totalToProcess)
                // Report TOTAL photos in database (existing + newly inserted)
                let totalInDatabase = existingCount + newlyInsertedCount
                await progressHandler(progress, totalInDatabase)
            }
        }
        
        // Insert remaining photos
        for photo in photosToInsert {
            modelContext.insert(photo)
        }
        
        // Update analysis state with correct count
        let finalCount = existingCount + newlyInsertedCount
        analysisState.indexingInProgress = false
        analysisState.indexedCount = finalCount
        analysisState.totalLibraryCount = finalCount
        analysisState.lastScanDate = Date()
        
        try? modelContext.save()
        await progressHandler(1.0, finalCount)
    }
    
    private func loadOrCreateAnalysisState() -> AnalysisState {
        let descriptor = FetchDescriptor<AnalysisState>(
            predicate: #Predicate { $0.id == "main" }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        
        let newState = AnalysisState(id: "main")
        modelContext.insert(newState)
        return newState
    }
    
    func pauseIndexing() {
        if let state = try? modelContext.fetch(FetchDescriptor<AnalysisState>()).first {
            state.indexingPausedAt = Date()
            try? modelContext.save()
        }
    }
    
    // MARK: - Single Asset Indexing (for background processing)
    
    func indexSingleAsset(_ asset: PHAsset) async {
        // Single-id fetch instead of loading every persisted identifier (O(n) per asset).
        let assetId = asset.localIdentifier
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.localIdentifier == assetId }
        )
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            return
        }
        
        let photo = createPersistedPhoto(from: asset)
        modelContext.insert(photo)
        
        if let state = try? modelContext.fetch(FetchDescriptor<AnalysisState>()).first {
            state.indexedCount += 1
            state.lastIndexedPhotoDate = asset.creationDate
        }
        
        try? modelContext.save()
    }
    
    // MARK: - Resumable Scan with Checkpointing
    
    func scanLibraryWithCheckpointing(
        checkpointHandler: @escaping (String) -> Void,
        isAlreadyIndexed: @escaping (String) -> Bool,
        progressHandler: @escaping @Sendable (Double, Int) async -> Void
    ) async {
        let analysisState = loadOrCreateAnalysisState()
        let existingIds = fetchExistingPhotoIds()
        let existingCount = existingIds.count
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        
        guard allAssets.count > 0 else {
            analysisState.indexingInProgress = false
            try? modelContext.save()
            await progressHandler(1.0, existingCount)
            return
        }
        
        analysisState.indexingInProgress = true
        try? modelContext.save()
        
        var assets: [PHAsset] = []
        allAssets.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        let totalToProcess = assets.count
        var newlyInsertedCount = 0
        var processedInThisScan = 0
        let batchSize = 50
        var photosToInsert: [PersistedPhoto] = []
        
        for asset in assets {
            let assetId = asset.localIdentifier
            
            if existingIds.contains(assetId) || isAlreadyIndexed(assetId) {
                processedInThisScan += 1
                continue
            }
            
            let photo = createPersistedPhoto(from: asset)
            photosToInsert.append(photo)
            newlyInsertedCount += 1
            processedInThisScan += 1
            
            checkpointHandler(assetId)
            
            if processedInThisScan % batchSize == 0 {
                for photo in photosToInsert {
                    modelContext.insert(photo)
                }
                photosToInsert.removeAll()
                try? modelContext.save()
                
                let progress = Double(processedInThisScan) / Double(totalToProcess)
                let totalInDatabase = existingCount + newlyInsertedCount
                await progressHandler(progress, totalInDatabase)
            }
        }
        
        for photo in photosToInsert {
            modelContext.insert(photo)
        }
        
        let finalCount = existingCount + newlyInsertedCount
        analysisState.indexingInProgress = false
        analysisState.indexedCount = finalCount
        analysisState.totalLibraryCount = finalCount
        analysisState.lastScanDate = Date()
        
        try? modelContext.save()
        await progressHandler(1.0, finalCount)
    }
    
    func getIndexingProgress() -> (indexed: Int, total: Int, inProgress: Bool) {
        let descriptor = FetchDescriptor<AnalysisState>(
            predicate: #Predicate { $0.id == "main" }
        )
        
        if let state = try? modelContext.fetch(descriptor).first {
            return (state.indexedCount, state.totalLibraryCount, state.indexingInProgress)
        }
        return (0, 0, false)
    }
    
    private func fetchExistingPhotoIds() -> Set<String> {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: nil,
            sortBy: []
        )
        
        do {
            let existing = try modelContext.fetch(descriptor)
            return Set(existing.map { $0.localIdentifier })
        } catch {
            return Set()
        }
    }
    
    private func createPersistedPhoto(from asset: PHAsset) -> PersistedPhoto {
        Self.persistedPhoto(from: asset)
    }
    
    /// Safe to call from a background actor — PHAsset reads are thread-safe.
    nonisolated static func persistedPhoto(from asset: PHAsset) -> PersistedPhoto {
        let mediaType: String
        switch asset.mediaType {
        case .image: mediaType = "image"
        case .video: mediaType = "video"
        case .audio: mediaType = "audio"
        default: mediaType = "unknown"
        }
        
        var subtypes: [String] = []
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            subtypes.append("screenshot")
        }
        if asset.mediaSubtypes.contains(.videoScreenRecording) {
            subtypes.append("screenRecording")
        }
        if asset.mediaSubtypes.contains(.photoLive) {
            subtypes.append("livePhoto")
        }
        if asset.mediaSubtypes.contains(.photoPanorama) {
            subtypes.append("panorama")
        }
        if asset.mediaSubtypes.contains(.photoHDR) {
            subtypes.append("hdr")
        }
        if asset.mediaSubtypes.contains(.photoDepthEffect) {
            subtypes.append("depthEffect")
        }
        if asset.mediaSubtypes.contains(.videoHighFrameRate) {
            subtypes.append("highFrameRate")
        }
        if asset.mediaSubtypes.contains(.videoTimelapse) {
            subtypes.append("timelapse")
        }
        if asset.mediaSubtypes.contains(.videoCinematic) {
            subtypes.append("cinematicVideo")
        }
        
        return PersistedPhoto(
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            mediaTypeRaw: mediaType,
            mediaSubtypesRaw: subtypes.joined(separator: ","),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            altitude: asset.location?.altitude,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            burstIdentifier: asset.burstIdentifier,
            representsBurst: asset.representsBurst
        )
    }
    
    // MARK: - Asset Fetching
    
    nonisolated func fetchAsset(for photo: PersistedPhoto) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
        return result.firstObject
    }
    
    nonisolated func fetchAssets(for identifiers: [String]) -> [String: PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        
        var assetMap: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            assetMap[asset.localIdentifier] = asset
        }
        return assetMap
    }
    
    // MARK: - Image Loading
    
    func loadImage(for photo: PersistedPhoto, targetSize: CGSize) async -> UIImage? {
        guard let asset = fetchAsset(for: photo) else { return nil }
        return await loadImage(for: asset, targetSize: targetSize)
    }
    
    nonisolated func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            options.resizeMode = .exact
            
            var hasResumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded && !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    /// Screen-sized decode — never PHImageManagerMaximumSize (48 MP ≈ 190 MB decoded).
    nonisolated static func displayTargetSize() -> CGSize {
        CGSize(width: 1320, height: 2868)
    }
    
    nonisolated func loadFullSizeImage(for asset: PHAsset) async -> UIImage? {
        await loadImage(for: asset, targetSize: PhotoLibraryService.displayTargetSize())
    }
    
    // MARK: - Deletion
    
    func deletePhotos(_ photos: [PersistedPhoto]) async throws {
        let identifiers = photos.map { $0.localIdentifier }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        
        for photo in photos {
            modelContext.delete(photo)
        }
        try modelContext.save()
    }
    
    // MARK: - Resource Info
    
    nonisolated func getResourceInfo(for asset: PHAsset) -> (fileSize: Int64, uniformTypeIdentifier: String?) {
        let resources = PHAssetResource.assetResources(for: asset)
        
        var totalSize: Int64 = 0
        var uti: String?
        
        for resource in resources {
            if let size = resource.value(forKey: "fileSize") as? Int64 {
                totalSize += size
            }
            if uti == nil {
                uti = resource.uniformTypeIdentifier
            }
        }
        
        return (totalSize, uti)
    }
    
    // MARK: - Change Observation
    
    nonisolated func registerForLibraryChanges(_ handler: @escaping @Sendable (PHChange) -> Void) -> PhotoLibraryChangeObserver {
        let observer = PhotoLibraryChangeObserver(handler: handler)
        PHPhotoLibrary.shared().register(observer)
        return observer
    }
    
    nonisolated func unregisterForLibraryChanges(_ observer: PhotoLibraryChangeObserver) {
        PHPhotoLibrary.shared().unregisterChangeObserver(observer)
    }
}

// MARK: - Change Observer

final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let handler: @Sendable (PHChange) -> Void
    
    init(handler: @escaping @Sendable (PHChange) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        handler(changeInstance)
    }
}
