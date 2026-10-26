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
    
    // MARK: - Library Scanning (Resumable)
    
    func scanLibrary(progressHandler: @escaping @Sendable (Double, Int) async -> Void) async {
        // Load or create analysis state for resumable indexing
        let analysisState = loadOrCreateAnalysisState()
        
        // Check if we're resuming an interrupted scan
        let isResuming = analysisState.indexingInProgress && analysisState.lastIndexedPhotoDate != nil
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        
        // If resuming, only fetch photos newer than the last indexed one
        if isResuming, let lastDate = analysisState.lastIndexedPhotoDate {
            fetchOptions.predicate = NSPredicate(format: "creationDate > %@", lastDate as NSDate)
        }
        
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        let totalCount = allAssets.count + analysisState.indexedCount
        
        guard allAssets.count > 0 else {
            // Already fully indexed
            analysisState.indexingInProgress = false
            try? modelContext.save()
            await progressHandler(1.0, analysisState.indexedCount)
            return
        }
        
        // Mark indexing as in progress
        analysisState.indexingInProgress = true
        analysisState.totalLibraryCount = totalCount
        try? modelContext.save()
        
        let existingIds = fetchExistingPhotoIds()
        
        let batchSize = 100
        var processedCount = analysisState.indexedCount
        var photosToInsert: [PersistedPhoto] = []
        var lastProcessedDate: Date?
        var lastProcessedId: String?
        
        // Collect all assets first
        var assets: [PHAsset] = []
        allAssets.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        // Process in batches on main actor
        for asset in assets {
            if !existingIds.contains(asset.localIdentifier) {
                let photo = createPersistedPhoto(from: asset)
                photosToInsert.append(photo)
            }
            
            lastProcessedDate = asset.creationDate
            lastProcessedId = asset.localIdentifier
            processedCount += 1
            
            if processedCount % batchSize == 0 {
                for photo in photosToInsert {
                    modelContext.insert(photo)
                }
                photosToInsert.removeAll()
                
                // Update resumable state
                analysisState.lastIndexedPhotoDate = lastProcessedDate
                analysisState.lastIndexedPhotoId = lastProcessedId
                analysisState.indexedCount = processedCount
                
                try? modelContext.save()
                
                let progress = Double(processedCount) / Double(totalCount)
                await progressHandler(progress, processedCount)
            }
        }
        
        // Insert remaining
        for photo in photosToInsert {
            modelContext.insert(photo)
        }
        
        // Mark indexing complete
        analysisState.indexingInProgress = false
        analysisState.lastIndexedPhotoDate = lastProcessedDate
        analysisState.lastIndexedPhotoId = lastProcessedId
        analysisState.indexedCount = processedCount
        analysisState.lastScanDate = Date()
        
        try? modelContext.save()
        await progressHandler(1.0, processedCount)
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
        
        let photo = PersistedPhoto(
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
        
        return photo
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
            options.isNetworkAccessAllowed = true
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
    
    nonisolated func loadFullSizeImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            var hasResumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
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
