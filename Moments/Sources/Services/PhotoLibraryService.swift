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
        await MainActor.run {
            self.authorizationStatus = status
            self.isLimitedAccess = (status == .limited)
        }
        return status
    }
    
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
            self.isLimitedAccess = (status == .limited)
        }
        return status == .authorized || status == .limited
    }
    
    // MARK: - Library Scanning
    
    func scanLibrary(progressHandler: @escaping (Double, Int) async -> Void) async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        
        let allAssets = PHAsset.fetchAssets(with: fetchOptions)
        let totalCount = allAssets.count
        
        guard totalCount > 0 else { return }
        
        let batchSize = 100
        var processedCount = 0
        
        let existingIds = await fetchExistingPhotoIds()
        
        allAssets.enumerateObjects { [weak self] asset, index, _ in
            guard let self = self else { return }
            
            if !existingIds.contains(asset.localIdentifier) {
                let persistedPhoto = self.createPersistedPhoto(from: asset)
                self.modelContext.insert(persistedPhoto)
            }
            
            processedCount += 1
            
            if processedCount % batchSize == 0 {
                try? self.modelContext.save()
                
                Task {
                    let progress = Double(processedCount) / Double(totalCount)
                    await progressHandler(progress, processedCount)
                }
            }
        }
        
        try? modelContext.save()
        await progressHandler(1.0, processedCount)
    }
    
    private func fetchExistingPhotoIds() async -> Set<String> {
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
    
    func fetchAsset(for photo: PersistedPhoto) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
        return result.firstObject
    }
    
    func fetchAssets(for photos: [PersistedPhoto]) -> [String: PHAsset] {
        let identifiers = photos.map { $0.localIdentifier }
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
    
    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    func loadFullSizeImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
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
    
    func getResourceInfo(for asset: PHAsset) async -> (fileSize: Int64, uniformTypeIdentifier: String?) {
        await withCheckedContinuation { continuation in
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
            
            continuation.resume(returning: (totalSize, uti))
        }
    }
    
    // MARK: - Change Observation
    
    func registerForLibraryChanges(_ handler: @escaping (PHChange) -> Void) -> Any {
        let observer = PhotoLibraryChangeObserver(handler: handler)
        PHPhotoLibrary.shared().register(observer)
        return observer
    }
    
    func unregisterForLibraryChanges(_ observer: Any) {
        if let obs = observer as? PHPhotoLibraryChangeObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(obs)
        }
    }
}

// MARK: - Change Observer

class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let handler: (PHChange) -> Void
    
    init(handler: @escaping (PHChange) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        handler(changeInstance)
    }
}
