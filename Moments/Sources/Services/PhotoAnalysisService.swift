// PhotoAnalysisService.swift
// Servicio para analizar fotos con Vision y Core Image
// Non-blocking background analysis with bounded concurrency

import Foundation
import SwiftData
import Photos
import Vision
import CoreImage
import UIKit
import Accelerate

@MainActor
class PhotoAnalysisService: ObservableObject {
    private let modelContext: ModelContext
    private let imageAnalyzer = ImageAnalyzer()
    private let faceAnalyzer = FaceAnalyzer()
    private let geocodingService = GeocodingService.shared
    private let metadataService = MetadataExtractionService.shared
    
    private let maxConcurrentAnalysis = 3
    private let batchSaveInterval = 20
    private let thumbnailSize = CGSize(width: 300, height: 300)
    private let imageLoadTimeout: TimeInterval = 5.0
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Background Analysis (Non-blocking)
    
    func analyzePhotosInBackground(progressHandler: @escaping @Sendable (Int, Int, Double) async -> Void) async {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { !$0.analysisCompleted }
        )
        
        do {
            var photosToAnalyze = try modelContext.fetch(descriptor)
            photosToAnalyze.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            let total = photosToAnalyze.count
            
            guard total > 0 else {
                await progressHandler(0, 0, 1.0)
                return
            }
            
            var analyzedCount = 0
            
            for batch in photosToAnalyze.chunked(into: maxConcurrentAnalysis) {
                if Task.isCancelled { break }
                
                await withTaskGroup(of: Void.self) { group in
                    for photo in batch {
                        group.addTask { [weak self] in
                            guard let self = self else { return }
                            await self.analyzePhotoSafely(photo)
                        }
                    }
                }
                
                analyzedCount += batch.count
                
                if analyzedCount % batchSaveInterval == 0 || analyzedCount == total {
                    try? modelContext.save()
                }
                
                let progress = Double(analyzedCount) / Double(total)
                await progressHandler(analyzedCount, total, progress)
                
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            
            try? modelContext.save()
            await progressHandler(total, total, 1.0)
            
            await detectDuplicates()
            
        } catch {
            print("Error fetching photos for analysis: \(error)")
        }
    }
    
    func analyzeAllPhotos(progressHandler: @escaping @Sendable (Double) async -> Void) async {
        await analyzePhotosInBackground { analyzed, total, progress in
            await progressHandler(progress)
        }
    }
    
    private func analyzePhotoSafely(_ photo: PersistedPhoto) async {
        guard let asset = fetchAsset(for: photo) else {
            await MainActor.run { photo.analysisCompleted = true }
            return
        }
        
        await MainActor.run {
            photo.isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
            if photo.isLivePhoto {
                let resources = PHAssetResource.assetResources(for: asset)
                photo.livePhotoVideoIdentifier = resources.first { $0.type == .pairedVideo }?.assetLocalIdentifier
            }
            
            let resources = PHAssetResource.assetResources(for: asset)
            photo.isEdited = resources.contains { $0.type == .adjustmentData }
            
            photo.isSharedOrReceived = asset.sourceType.contains(.typeCloudShared) ||
                                       asset.sourceType.contains(.typeiTunesSynced)
        }
        
        let image = await loadImageWithTimeout(for: asset, timeout: imageLoadTimeout)
        
        guard let analysisImage = image else {
            await MainActor.run {
                photo.isPendingICloud = true
                photo.analysisCompleted = false
            }
            return
        }
        
        let qualityMetrics = await imageAnalyzer.analyzeQuality(image: analysisImage)
        let textAnalysis = await imageAnalyzer.analyzeText(image: analysisImage)
        let labels = await imageAnalyzer.classifyImage(image: analysisImage)
        let barcodeResult = await imageAnalyzer.detectBarcodes(image: analysisImage)
        let featurePrint = await imageAnalyzer.generateFeaturePrint(image: analysisImage)
        let faces = await faceAnalyzer.detectFaces(in: analysisImage, photoId: photo.id)
        
        let resourceInfo = await getResourceInfo(for: asset)
        let metadata = await metadataService.extractMetadata(for: asset)
        let originResult = await metadataService.detectOrigin(for: asset, metadata: metadata)
        
        var locationInfo: (name: String?, city: String?, country: String?)?
        if let lat = photo.latitude, let lon = photo.longitude {
            locationInfo = await geocodingService.getLocationName(latitude: lat, longitude: lon)
        }
        
        await MainActor.run {
            photo.sharpnessScore = qualityMetrics.sharpness
            photo.exposureScore = qualityMetrics.exposure
            photo.detailScore = qualityMetrics.detail
            photo.deviceTilt = qualityMetrics.tilt
            
            photo.hasText = textAnalysis.hasText
            photo.isDocument = textAnalysis.isDocument
            photo.ocrText = textAnalysis.detectedText
            
            if !labels.isEmpty {
                let labelStrings = labels.map { $0.label }
                let confidences = labels.map { String(format: "%.2f", $0.confidence) }
                photo.visionLabels = SpanishSynonyms.addSpanishSynonyms(to: labelStrings.joined(separator: "|"))
                photo.visionLabelsConfidence = confidences.joined(separator: "|")
            }
            
            photo.hasBarcode = barcodeResult.hasBarcode
            if barcodeResult.hasQR {
                photo.cleanupCategory = .qrCode
            }
            
            if let fp = featurePrint {
                photo.imageFeaturePrintData = fp
            }
            
            photo.facesDetected = faces.count
            if !faces.isEmpty {
                photo.facesOpenScore = faces.reduce(0.0) { $0 + $1.quality } / Double(faces.count)
            }
            
            photo.estimatedFileSize = resourceInfo.fileSize
            
            photo.origin = originResult.origin
            photo.hasExifData = metadata?.hasExifData ?? false
            photo.cameraMake = metadata?.cameraMake
            photo.cameraModel = metadata?.cameraModel
            photo.lensMake = metadata?.lensMake
            photo.lensModel = metadata?.lensModel
            photo.software = metadata?.software
            photo.originalFilename = metadata?.originalFilename
            
            if let loc = locationInfo {
                photo.placeName = loc.name
                photo.placeCity = loc.city
                photo.placeCountry = loc.country
            }
            
            if photo.isDownloadedWithoutExif && photo.cleanupCategory == .none {
                let maxDim = max(photo.pixelWidth, photo.pixelHeight)
                if maxDim < 1000 && (photo.facesDetected ?? 0) == 0 {
                    photo.cleanupCategory = .downloadedMeme
                } else if photo.origin.isMessagingApp && (photo.facesDetected ?? 0) == 0 {
                    photo.cleanupCategory = .forwardedImage
                }
            }
            
            photo.isPendingICloud = false
            photo.analysisCompleted = true
            photo.lastAnalyzedAt = Date()
        }
        
        await determineCleanupCategory(photo: photo, textAnalysis: textAnalysis, qualityMetrics: qualityMetrics)
        
        for faceData in faces {
            await MainActor.run {
                let detection = PersistedFaceDetection(
                    photoId: photo.id,
                    boundingBoxX: faceData.boundingBox.origin.x,
                    boundingBoxY: faceData.boundingBox.origin.y,
                    boundingBoxWidth: faceData.boundingBox.size.width,
                    boundingBoxHeight: faceData.boundingBox.size.height,
                    featurePrintData: faceData.featurePrint,
                    quality: faceData.quality
                )
                detection.photo = photo
                self.modelContext.insert(detection)
            }
        }
    }
    
    private func determineCleanupCategory(photo: PersistedPhoto, textAnalysis: ImageAnalyzer.TextAnalysis, qualityMetrics: ImageAnalyzer.QualityMetrics) async {
        await MainActor.run {
            if photo.cleanupCategory != .none { return }
            
            if photo.mediaSubtypesRaw.contains("screenshot") {
                photo.cleanupCategory = .screenshot
                return
            }
            
            if photo.mediaTypeRaw == "video" && photo.mediaSubtypesRaw.contains("screenRecording") {
                photo.cleanupCategory = .screenRecording
                return
            }
            
            if photo.mediaTypeRaw == "video" && (photo.estimatedFileSize ?? 0) > 100_000_000 {
                photo.cleanupCategory = .largeVideo
                return
            }
            
            if photo.burstIdentifier != nil && !photo.representsBurst {
                photo.cleanupCategory = .burst
                return
            }
            
            if textAnalysis.isReceipt {
                photo.cleanupCategory = .receipt
                return
            }
            
            if textAnalysis.isDocument {
                photo.cleanupCategory = .document
                return
            }
            
            if let sharpness = photo.sharpnessScore, sharpness < 0.3, photo.mediaTypeRaw == "image" {
                photo.cleanupCategory = .blurry
                return
            }
            
            if let exposure = photo.exposureScore, exposure > 0.85, photo.mediaTypeRaw == "image" {
                photo.cleanupCategory = .overexposed
                return
            }
            
            if let exposure = photo.exposureScore, exposure < 0.15, photo.mediaTypeRaw == "image" {
                photo.cleanupCategory = .underexposed
                return
            }
            
            if isAccidentalShot(photo: photo, qualityMetrics: qualityMetrics) {
                photo.cleanupCategory = .accidental
                return
            }
        }
    }
    
    private func isAccidentalShot(photo: PersistedPhoto, qualityMetrics: ImageAnalyzer.QualityMetrics) -> Bool {
        guard photo.mediaTypeRaw == "image" else { return false }
        
        if let exposure = photo.exposureScore, exposure < 0.05 {
            if let faces = photo.facesDetected, faces == 0 {
                return true
            }
        }
        
        if let sharpness = photo.sharpnessScore, sharpness < 0.1 {
            if let faces = photo.facesDetected, faces == 0 {
                if let detail = photo.detailScore, detail < 0.1 {
                    return true
                }
            }
        }
        
        if let tilt = photo.deviceTilt {
            if abs(tilt) > 60 || abs(tilt - 180) < 30 {
                if let detail = photo.detailScore, detail < 0.2 {
                    if let faces = photo.facesDetected, faces == 0 {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - Image Loading with Timeout
    
    private func loadImageWithTimeout(for asset: PHAsset, timeout: TimeInterval) async -> UIImage? {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                await self.loadImageSafely(for: asset)
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }
            
            group.cancelAll()
            return nil
        }
    }
    
    private func loadImageSafely(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            options.resizeMode = .fast
            
            var hasResumed = false
            let resumeOnce: (UIImage?) -> Void = { image in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil
                
                if isCancelled || hasError {
                    resumeOnce(nil)
                    return
                }
                
                if let image = image {
                    if !isDegraded {
                        resumeOnce(image)
                    }
                } else {
                    resumeOnce(nil)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resumeOnce(nil)
            }
        }
    }
    
    // MARK: - Duplicate Detection
    
    func detectDuplicates() async {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.imageFeaturePrintData != nil }
        )
        
        do {
            var photos = try modelContext.fetch(descriptor)
            photos.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            
            guard photos.count > 1 else { return }
            
            let feedbackDescriptor = FetchDescriptor<SimilarGroup>(
                predicate: #Predicate<SimilarGroup> { $0.feedbackRaw == "notSimilar" }
            )
            let excludedGroups = (try? modelContext.fetch(feedbackDescriptor)) ?? []
            var excludedPairs = Set<String>()
            for group in excludedGroups {
                let ids = group.photoIds
                for i in 0..<ids.count {
                    for j in (i+1)..<ids.count {
                        let pairKey = [ids[i], ids[j]].sorted().joined(separator: "_")
                        excludedPairs.insert(pairKey)
                    }
                }
            }
            
            var processedIds: Set<String> = []
            var groupId = 0
            
            for (i, photo) in photos.enumerated() {
                if Task.isCancelled { break }
                if processedIds.contains(photo.id) { continue }
                guard let featurePrint1 = photo.imageFeaturePrintData else { continue }
                
                var duplicateGroup: [PersistedPhoto] = [photo]
                
                for j in (i + 1)..<photos.count {
                    let otherPhoto = photos[j]
                    if processedIds.contains(otherPhoto.id) { continue }
                    guard let featurePrint2 = otherPhoto.imageFeaturePrintData else { continue }
                    
                    let pairKey = [photo.id, otherPhoto.id].sorted().joined(separator: "_")
                    if excludedPairs.contains(pairKey) { continue }
                    
                    if photo.isLivePhoto && otherPhoto.localIdentifier == photo.livePhotoVideoIdentifier {
                        continue
                    }
                    if otherPhoto.isLivePhoto && photo.localIdentifier == otherPhoto.livePhotoVideoIdentifier {
                        continue
                    }
                    
                    let distance = await imageAnalyzer.compareFeaturePrints(featurePrint1, featurePrint2)
                    
                    if let dist = distance, dist < 0.15 {
                        duplicateGroup.append(otherPhoto)
                    }
                }
                
                if duplicateGroup.count > 1 {
                    let currentGroupId = "dup_\(groupId)"
                    groupId += 1
                    
                    let (bestPhoto, reasons) = selectBestPhotoWithReasons(from: duplicateGroup)
                    
                    let similarGroup = SimilarGroup(
                        photoIds: duplicateGroup.map { $0.id },
                        bestPhotoId: bestPhoto.id,
                        bestShotReasons: reasons
                    )
                    similarGroup.timeWindowStart = duplicateGroup.compactMap { $0.creationDate }.min()
                    similarGroup.timeWindowEnd = duplicateGroup.compactMap { $0.creationDate }.max()
                    modelContext.insert(similarGroup)
                    
                    for dupPhoto in duplicateGroup {
                        processedIds.insert(dupPhoto.id)
                        dupPhoto.duplicateGroupId = currentGroupId
                        dupPhoto.isBestInGroup = (dupPhoto.id == bestPhoto.id)
                        dupPhoto.bestShotReasons = reasons.map { $0.rawValue }
                        
                        if dupPhoto.id != bestPhoto.id {
                            dupPhoto.cleanupCategory = .nearDuplicate
                            dupPhoto.cleanupConfidenceTier = .veryLikely
                        }
                    }
                }
            }
            
            try? modelContext.save()
            
        } catch {
            print("Error detecting duplicates: \(error)")
        }
    }
    
    private func selectBestPhotoWithReasons(from photos: [PersistedPhoto]) -> (PersistedPhoto, [BestShotReason]) {
        var scores: [(PersistedPhoto, Double, [BestShotReason])] = []
        
        for photo in photos {
            var score: Double = 0
            var reasons: [BestShotReason] = []
            
            if photo.isFavorite {
                score += 100
                reasons.append(.favorited)
            }
            
            if photo.isEdited {
                score += 80
                reasons.append(.edited)
            }
            
            if photo.isLivePhoto {
                score += 15
                reasons.append(.livePhoto)
            }
            
            if let sharpness = photo.sharpnessScore, sharpness > 0.7 {
                score += sharpness * 40
                if sharpness > 0.85 {
                    reasons.append(.sharpest)
                }
            }
            
            if let exposure = photo.exposureScore {
                let exposureScore = 1.0 - abs(exposure - 0.5) * 2
                score += exposureScore * 20
                if exposureScore > 0.8 {
                    reasons.append(.bestAesthetics)
                }
            }
            
            if let facesOpen = photo.facesOpenScore, facesOpen > 0.8 {
                score += facesOpen * 30
                reasons.append(.eyesOpen)
            }
            
            if let faces = photo.facesDetected, faces > 0 {
                score += 10
            }
            
            let resolution = photo.pixelWidth * photo.pixelHeight
            if resolution > 8_000_000 {
                score += 5
                reasons.append(.highestResolution)
            }
            
            if photo.representsBurst {
                score += 5
            }
            
            scores.append((photo, score, reasons))
        }
        
        let best = scores.max(by: { $0.1 < $1.1 }) ?? (photos[0], 0, [])
        let uniqueReasons = Array(Set(best.2)).prefix(3)
        
        return (best.0, Array(uniqueReasons))
    }
    
    // MARK: - Helpers
    
    private func fetchAsset(for photo: PersistedPhoto) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
        return result.firstObject
    }
    
    private func getResourceInfo(for asset: PHAsset) async -> (fileSize: Int64, uti: String?) {
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
}

// MARK: - Array Chunking Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Image Analyzer

final class ImageAnalyzer: Sendable {
    
    struct QualityMetrics: Sendable {
        let sharpness: Double
        let exposure: Double
        let detail: Double
        let tilt: Double?
    }
    
    struct TextAnalysis: Sendable {
        let hasText: Bool
        let isDocument: Bool
        let isReceipt: Bool
        let detectedText: String?
    }
    
    struct LabelResult: Sendable {
        let label: String
        let confidence: Float
    }
    
    struct BarcodeResult: Sendable {
        let hasBarcode: Bool
        let hasQR: Bool
        let barcodeTypes: [String]
    }
    
    func analyzeQuality(image: UIImage) async -> QualityMetrics {
        guard let ciImage = CIImage(image: image) else {
            return QualityMetrics(sharpness: 0.5, exposure: 0.5, detail: 0.5, tilt: nil)
        }
        
        let sharpness = calculateLaplacianVariance(ciImage)
        let exposure = calculateExposure(ciImage)
        let detail = calculateDetailScore(ciImage)
        let tilt = extractDeviceTilt(from: image)
        
        return QualityMetrics(sharpness: sharpness, exposure: exposure, detail: detail, tilt: tilt)
    }
    
    private func calculateLaplacianVariance(_ image: CIImage) -> Double {
        let context = CIContext()
        
        guard let laplacianFilter = CIFilter(name: "CIConvolution3X3") else { return 0.5 }
        
        let laplacianKernel: [CGFloat] = [
            0,  1, 0,
            1, -4, 1,
            0,  1, 0
        ]
        
        laplacianFilter.setValue(image, forKey: kCIInputImageKey)
        laplacianFilter.setValue(CIVector(values: laplacianKernel, count: 9), forKey: "inputWeights")
        laplacianFilter.setValue(0, forKey: "inputBias")
        
        guard let output = laplacianFilter.outputImage else { return 0.5 }
        
        let extent = output.extent
        guard extent.width > 0 && extent.height > 0 && !extent.isInfinite else { return 0.5 }
        
        guard let statsFilter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        
        let sampleRect = CGRect(
            x: extent.midX - 150,
            y: extent.midY - 150,
            width: 300,
            height: 300
        ).intersection(extent)
        
        guard !sampleRect.isEmpty else { return 0.5 }
        
        statsFilter.setValue(output, forKey: kCIInputImageKey)
        statsFilter.setValue(CIVector(cgRect: sampleRect), forKey: kCIInputExtentKey)
        
        guard let statsOutput = statsFilter.outputImage else { return 0.5 }
        
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            statsOutput,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        let variance = Double(pixel[0]) / 255.0
        return min(max(variance * 4, 0), 1)
    }
    
    private func calculateExposure(_ image: CIImage) -> Double {
        let context = CIContext()
        guard let filter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        
        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 && !extent.isInfinite else { return 0.5 }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        
        guard let output = filter.outputImage else { return 0.5 }
        
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        
        return luminance
    }
    
    private func calculateDetailScore(_ image: CIImage) -> Double {
        let context = CIContext()
        
        guard let histogramFilter = CIFilter(name: "CIAreaHistogram") else { return 0.5 }
        
        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 && !extent.isInfinite else { return 0.5 }
        
        let sampleRect = CGRect(
            x: extent.midX - 200,
            y: extent.midY - 200,
            width: 400,
            height: 400
        ).intersection(extent)
        
        guard !sampleRect.isEmpty else { return 0.5 }
        
        histogramFilter.setValue(image, forKey: kCIInputImageKey)
        histogramFilter.setValue(CIVector(cgRect: sampleRect), forKey: kCIInputExtentKey)
        histogramFilter.setValue(64, forKey: "inputCount")
        histogramFilter.setValue(1.0, forKey: "inputScale")
        
        guard let output = histogramFilter.outputImage else { return 0.5 }
        
        var histogramData = [UInt8](repeating: 0, count: 64 * 4)
        context.render(
            output,
            toBitmap: &histogramData,
            rowBytes: 64 * 4,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        var nonZeroCount = 0
        for i in stride(from: 0, to: histogramData.count, by: 4) {
            if histogramData[i] > 5 {
                nonZeroCount += 1
            }
        }
        
        return Double(nonZeroCount) / 64.0
    }
    
    private func extractDeviceTilt(from image: UIImage) -> Double? {
        return nil
    }
    
    func analyzeText(image: UIImage) async -> TextAnalysis {
        guard let cgImage = image.cgImage else {
            return TextAnalysis(hasText: false, isDocument: false, isReceipt: false, detectedText: nil)
        }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeOnce: (TextAnalysis) -> Void = { result in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
            
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      error == nil else {
                    resumeOnce(TextAnalysis(hasText: false, isDocument: false, isReceipt: false, detectedText: nil))
                    return
                }
                
                let hasText = !observations.isEmpty
                let textCount = observations.count
                let isDocument = textCount > 10
                
                let allText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                let isReceipt = self.detectReceiptPattern(in: allText)
                
                resumeOnce(TextAnalysis(
                    hasText: hasText,
                    isDocument: isDocument,
                    isReceipt: isReceipt,
                    detectedText: allText.isEmpty ? nil : String(allText.prefix(2000))
                ))
            }
            
            request.recognitionLevel = .fast
            request.recognitionLanguages = ["es", "en"]
            request.usesLanguageCorrection = false
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                resumeOnce(TextAnalysis(hasText: false, isDocument: false, isReceipt: false, detectedText: nil))
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resumeOnce(TextAnalysis(hasText: false, isDocument: false, isReceipt: false, detectedText: nil))
            }
        }
    }
    
    private func detectReceiptPattern(in text: String) -> Bool {
        let lowercased = text.lowercased()
        
        let receiptPatterns = [
            "total", "subtotal", "iva", "descuento",
            "factura", "ticket", "comprobante", "recibo",
            "efectivo", "tarjeta", "cambio", "vuelto",
            "precio", "cant", "cantidad", "unidad",
            "$", "ars", "usd", "pesos",
            "fecha:", "hora:", "cuit:", "sucursal"
        ]
        
        var matches = 0
        for pattern in receiptPatterns {
            if lowercased.contains(pattern) {
                matches += 1
            }
        }
        
        let priceRegex = try? NSRegularExpression(pattern: "\\$?\\d+[,.]\\d{2}", options: [])
        let priceMatches = priceRegex?.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? 0
        
        return matches >= 3 || (matches >= 2 && priceMatches >= 2)
    }
    
    func classifyImage(image: UIImage) async -> [LabelResult] {
        guard let cgImage = image.cgImage else { return [] }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeOnce: ([LabelResult]) -> Void = { result in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
            
            let request = VNClassifyImageRequest { request, error in
                guard let observations = request.results as? [VNClassificationObservation],
                      error == nil else {
                    resumeOnce([])
                    return
                }
                
                let topLabels = observations
                    .filter { $0.confidence > 0.3 }
                    .prefix(10)
                    .map { LabelResult(label: $0.identifier, confidence: $0.confidence) }
                
                resumeOnce(Array(topLabels))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                resumeOnce([])
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resumeOnce([])
            }
        }
    }
    
    func detectBarcodes(image: UIImage) async -> BarcodeResult {
        guard let cgImage = image.cgImage else {
            return BarcodeResult(hasBarcode: false, hasQR: false, barcodeTypes: [])
        }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeOnce: (BarcodeResult) -> Void = { result in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
            
            let request = VNDetectBarcodesRequest { request, error in
                guard let observations = request.results as? [VNBarcodeObservation],
                      error == nil else {
                    resumeOnce(BarcodeResult(hasBarcode: false, hasQR: false, barcodeTypes: []))
                    return
                }
                
                let hasBarcode = !observations.isEmpty
                let hasQR = observations.contains { $0.symbology == .qr }
                let types = observations.map { $0.symbology.rawValue }
                
                resumeOnce(BarcodeResult(hasBarcode: hasBarcode, hasQR: hasQR, barcodeTypes: types))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                resumeOnce(BarcodeResult(hasBarcode: false, hasQR: false, barcodeTypes: []))
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                resumeOnce(BarcodeResult(hasBarcode: false, hasQR: false, barcodeTypes: []))
            }
        }
    }
    
    func generateFeaturePrint(image: UIImage) async -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeOnce: (Data?) -> Void = { result in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
            
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard let observation = request.results?.first as? VNFeaturePrintObservation,
                      error == nil else {
                    resumeOnce(nil)
                    return
                }
                
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
                    resumeOnce(data)
                } catch {
                    resumeOnce(nil)
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                resumeOnce(nil)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resumeOnce(nil)
            }
        }
    }
    
    func compareFeaturePrints(_ data1: Data, _ data2: Data) async -> Float? {
        do {
            guard let fp1 = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data1),
                  let fp2 = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data2) else {
                return nil
            }
            
            var distance: Float = 0
            try fp1.computeDistance(&distance, to: fp2)
            return distance
        } catch {
            return nil
        }
    }
}

// MARK: - Face Analyzer

final class FaceAnalyzer: Sendable {
    
    struct FaceData: Sendable {
        let boundingBox: CGRect
        let featurePrint: Data?
        let quality: Double
    }
    
    func detectFaces(in image: UIImage, photoId: String) async -> [FaceData] {
        guard let cgImage = image.cgImage else { return [] }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeOnce: ([FaceData]) -> Void = { result in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: result)
                }
            }
            
            var faceDataArray: [FaceData] = []
            
            let faceDetectionRequest = VNDetectFaceCaptureQualityRequest { request, error in
                guard let observations = request.results as? [VNFaceObservation],
                      error == nil else {
                    resumeOnce([])
                    return
                }
                
                for observation in observations {
                    let quality = Double(observation.faceCaptureQuality ?? observation.confidence)
                    
                    let faceData = FaceData(
                        boundingBox: observation.boundingBox,
                        featurePrint: nil,
                        quality: quality
                    )
                    faceDataArray.append(faceData)
                }
                
                resumeOnce(faceDataArray)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([faceDetectionRequest])
            } catch {
                resumeOnce([])
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resumeOnce([])
            }
        }
    }
}
