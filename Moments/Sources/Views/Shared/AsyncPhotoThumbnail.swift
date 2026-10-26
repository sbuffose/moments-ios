// AsyncPhotoThumbnail.swift
// Vista para cargar thumbnails de fotos de forma asíncrona

import SwiftUI
import Photos

// MARK: - Shared Caching Image Manager

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    
    let cachingManager = PHCachingImageManager()
    
    private init() {
        cachingManager.allowsCachingHighQualityImages = true
    }
    
    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        cachingManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }
    
    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        cachingManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }
}

struct AsyncPhotoThumbnail: View {
    let localIdentifier: String
    var targetSize: CGSize = CGSize(width: 200, height: 200)
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var requestID: PHImageRequestID?
    
    private var scaledTargetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            cancelRequest()
        }
        .onChange(of: localIdentifier) { _, _ in
            cancelRequest()
            image = nil
            loadImage()
        }
    }
    
    private func loadImage() {
        isLoading = true
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            isLoading = false
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .fast
        
        requestID = ThumbnailCache.shared.cachingManager.requestImage(
            for: asset,
            targetSize: scaledTargetSize,
            contentMode: .aspectFill,
            options: options
        ) { loadedImage, info in
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !isCancelled else { return }
            
            DispatchQueue.main.async {
                if let loadedImage = loadedImage {
                    self.image = loadedImage
                }
                
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func cancelRequest() {
        if let requestID = requestID {
            ThumbnailCache.shared.cachingManager.cancelImageRequest(requestID)
            self.requestID = nil
        }
    }
}

// MARK: - Full Size Photo View

struct AsyncFullPhoto: View {
    let localIdentifier: String
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: localIdentifier) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        isLoading = true
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            isLoading = false
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        let loadedImage = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        
        await MainActor.run {
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

// MARK: - Photo Grid Item

struct PhotoGridItem: View {
    let photo: PersistedPhoto
    var showFavorite: Bool = true
    var onTap: (() -> Void)?
    
    var body: some View {
        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if photo.isFavorite && showFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.mediaTypeRaw == "video" {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill")
                        if photo.duration > 0 {
                            Text(formatDuration(photo.duration))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
