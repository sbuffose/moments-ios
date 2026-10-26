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
    
    func prefetch(localIdentifiers: [String], targetSize: CGSize) {
        guard !localIdentifiers.isEmpty else { return }
        let scale = UIScreen.main.scale
        let scaledSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        startCaching(assets: assets, targetSize: scaledSize)
    }
    
    func stopPrefetch(localIdentifiers: [String], targetSize: CGSize) {
        guard !localIdentifiers.isEmpty else { return }
        let scale = UIScreen.main.scale
        let scaledSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        stopCaching(assets: assets, targetSize: scaledSize)
    }
}

// MARK: - Photo Grid with Prefetch

struct PrefetchingPhotoGrid<Content: View>: View {
    let photos: [PersistedPhoto]
    let columns: [GridItem]
    let spacing: CGFloat
    let thumbnailSize: CGSize
    let content: (PersistedPhoto) -> Content
    
    @State private var visibleRange: Range<Int> = 0..<0
    private let prefetchBuffer = 20
    
    init(
        photos: [PersistedPhoto],
        columns: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 2)],
        spacing: CGFloat = 2,
        thumbnailSize: CGSize = CGSize(width: 200, height: 200),
        @ViewBuilder content: @escaping (PersistedPhoto) -> Content
    ) {
        self.photos = photos
        self.columns = columns
        self.spacing = spacing
        self.thumbnailSize = thumbnailSize
        self.content = content
    }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                content(photo)
                    .onAppear {
                        updateVisibleRange(addingIndex: index)
                    }
            }
        }
        .onChange(of: visibleRange) { oldRange, newRange in
            Task { @MainActor in
                prefetchForRange(newRange)
            }
        }
    }
    
    private func updateVisibleRange(addingIndex index: Int) {
        let newStart = max(0, index - prefetchBuffer)
        let newEnd = min(photos.count, index + prefetchBuffer)
        
        if visibleRange.lowerBound != newStart || visibleRange.upperBound != newEnd {
            visibleRange = newStart..<newEnd
        }
    }
    
    private func prefetchForRange(_ range: Range<Int>) {
        guard !photos.isEmpty else { return }
        let identifiers = photos[range].map { $0.localIdentifier }
        ThumbnailCache.shared.prefetch(localIdentifiers: identifiers, targetSize: thumbnailSize)
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerEffect: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: phase * geometry.size.width * 1.6 - geometry.size.width * 0.3)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(
                    .linear(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
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
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else if isLoading {
                ShimmerEffect()
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
