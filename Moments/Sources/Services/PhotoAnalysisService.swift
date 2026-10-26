// PhotoAnalysisService.swift
// Servicio para analizar fotos con Vision y Core Image

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
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Full Analysis
    
    func analyzeAllPhotos(progressHandler: @escaping @Sendable (Double) async -> Void) async {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { !$0.analysisCompleted }
        )
        
        do {
            var photosToAnalyze = try modelContext.fetch(descriptor)
            photosToAnalyze.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            let total = photosToAnalyze.count
            guard total > 0 else { return }
            
            let batchSize = 20
            
            // Check battery state before processing
            let backgroundService = BackgroundProcessingService.shared
            
            for (index, photo) in photosToAnalyze.enumerated() {
                // Respect battery constraints
                if await backgroundService.shouldPauseForBattery {
                    // Wait for better conditions
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if Task.isCancelled { return }
                }
                
                await analyzePhoto(photo)
                
                if (index + 1) % batchSize == 0 {
                    try? modelContext.save()
                    await progressHandler(Double(index + 1) / Double(total))
                    
                    // Yield to allow other tasks
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            
            try modelContext.save()
            await progressHandler(1.0)
            
            // After initial analysis, detect duplicates
            await detectDuplicates()
            
        } catch {
            print("Error fetching photos for analysis: \(error)")
        }
    }
    
    func analyzePhoto(_ photo: PersistedPhoto) async {
        guard let asset = fetchAsset(for: photo) else {
            photo.analysisCompleted = true
            return
        }
        
        // Check if this is a Live Photo
        photo.isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        if photo.isLivePhoto {
            // Get paired video identifier for Live Photo duplicate detection
            let resources = PHAssetResource.assetResources(for: asset)
            photo.livePhotoVideoIdentifier = resources.first { $0.type == .pairedVideo }?.assetLocalIdentifier
        }
        
        // Check if photo is edited (has adjustments)
        let resources = PHAssetResource.assetResources(for: asset)
        photo.isEdited = resources.contains { $0.type == .adjustmentData }
        
        // Check shared status
        photo.isSharedOrReceived = asset.sourceType.contains(.typeCloudShared) ||
                                   asset.sourceType.contains(.typeiTunesSynced)
        
        // Try to load local image, fall back to thumbnail if iCloud-only
        var image = await loadImage(for: asset)
        if image == nil {
            image = await loadThumbnail(for: asset)
        }
        
        guard let analysisImage = image else {
            // Image only in iCloud and no thumbnail - mark for later
            photo.analysisCompleted = false
            return
        }
        
        // Análisis de calidad
        let qualityMetrics = await imageAnalyzer.analyzeQuality(image: analysisImage)
        photo.sharpnessScore = qualityMetrics.sharpness
        photo.exposureScore = qualityMetrics.exposure
        photo.detailScore = qualityMetrics.detail
        photo.deviceTilt = qualityMetrics.tilt
        
        // Detección de texto/documentos
        let textAnalysis = await imageAnalyzer.analyzeText(image: analysisImage)
        photo.hasText = textAnalysis.hasText
        photo.isDocument = textAnalysis.isDocument
        photo.ocrText = textAnalysis.detectedText
        
        // Vision labels (clasificación de imagen)
        let labels = await imageAnalyzer.classifyImage(image: analysisImage)
        if !labels.isEmpty {
            let labelStrings = labels.map { $0.label }
            let confidences = labels.map { String(format: "%.2f", $0.confidence) }
            photo.visionLabels = SpanishSynonyms.addSpanishSynonyms(to: labelStrings.joined(separator: "|"))
            photo.visionLabelsConfidence = confidences.joined(separator: "|")
        }
        
        // Barcode/QR detection
        let barcodeResult = await imageAnalyzer.detectBarcodes(image: analysisImage)
        photo.hasBarcode = barcodeResult.hasBarcode
        if barcodeResult.hasQR {
            photo.cleanupCategory = .qrCode
        }
        
        // Determine cleanup category
        await determineCleanupCategory(photo: photo, textAnalysis: textAnalysis, qualityMetrics: qualityMetrics)
        
        // Feature print para duplicados
        if let featurePrint = await imageAnalyzer.generateFeaturePrint(image: analysisImage) {
            photo.imageFeaturePrintData = featurePrint
        }
        
        // Detección de rostros
        let faces = await faceAnalyzer.detectFaces(in: analysisImage, photoId: photo.id)
        photo.facesDetected = faces.count
        
        // Calculate faces open score (for burst best-selection)
        if !faces.isEmpty {
            photo.facesOpenScore = faces.reduce(0.0) { $0 + $1.quality } / Double(faces.count)
        }
        
        for faceData in faces {
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
            modelContext.insert(detection)
        }
        
        // Reverse geocoding for location
        if let lat = photo.latitude, let lon = photo.longitude {
            if let locationInfo = await geocodingService.getLocationName(latitude: lat, longitude: lon) {
                photo.placeName = locationInfo.name
                photo.placeCity = locationInfo.city
                photo.placeCountry = locationInfo.country
            }
        }
        
        // Tamaño de archivo
        let resourceInfo = await getResourceInfo(for: asset)
        photo.estimatedFileSize = resourceInfo.fileSize
        
        // Extract EXIF metadata and determine origin
        let metadata = await metadataService.extractMetadata(for: asset)
        let originResult = await metadataService.detectOrigin(for: asset, metadata: metadata)
        
        photo.origin = originResult.origin
        photo.hasExifData = metadata?.hasExifData ?? false
        photo.cameraMake = metadata?.cameraMake
        photo.cameraModel = metadata?.cameraModel
        photo.lensMake = metadata?.lensMake
        photo.lensModel = metadata?.lensModel
        photo.software = metadata?.software
        photo.originalFilename = metadata?.originalFilename
        
        // Mark downloaded memes/forwards as cleanup category
        if photo.isDownloadedWithoutExif && photo.cleanupCategory == .none {
            // Only if it looks like a meme (low res, no faces)
            let maxDim = max(photo.pixelWidth, photo.pixelHeight)
            if maxDim < 1000 && (photo.facesDetected ?? 0) == 0 {
                photo.cleanupCategory = .downloadedMeme
            } else if photo.origin.isMessagingApp && (photo.facesDetected ?? 0) == 0 {
                photo.cleanupCategory = .forwardedImage
            }
        }
        
        photo.analysisCompleted = true
        photo.lastAnalyzedAt = Date()
    }
    
    private func determineCleanupCategory(photo: PersistedPhoto, textAnalysis: ImageAnalyzer.TextAnalysis, qualityMetrics: ImageAnalyzer.QualityMetrics) async {
        // Already categorized
        if photo.cleanupCategory != .none { return }
        
        // Screenshots
        if photo.mediaSubtypesRaw.contains("screenshot") {
            photo.cleanupCategory = .screenshot
            return
        }
        
        // Screen recordings
        if photo.mediaTypeRaw == "video" && photo.mediaSubtypesRaw.contains("screenRecording") {
            photo.cleanupCategory = .screenRecording
            return
        }
        
        // Large videos (> 100 MB)
        if photo.mediaTypeRaw == "video" && (photo.estimatedFileSize ?? 0) > 100_000_000 {
            photo.cleanupCategory = .largeVideo
            return
        }
        
        // Non-representative burst photos
        if photo.burstIdentifier != nil && !photo.representsBurst {
            photo.cleanupCategory = .burst
            return
        }
        
        // Receipts (document with specific text patterns)
        if textAnalysis.isReceipt {
            photo.cleanupCategory = .receipt
            return
        }
        
        // Documents
        if textAnalysis.isDocument {
            photo.cleanupCategory = .document
            return
        }
        
        // Blurry photos
        if let sharpness = photo.sharpnessScore, sharpness < 0.3, photo.mediaTypeRaw == "image" {
            photo.cleanupCategory = .blurry
            return
        }
        
        // Overexposed
        if let exposure = photo.exposureScore, exposure > 0.85, photo.mediaTypeRaw == "image" {
            photo.cleanupCategory = .overexposed
            return
        }
        
        // Underexposed
        if let exposure = photo.exposureScore, exposure < 0.15, photo.mediaTypeRaw == "image" {
            photo.cleanupCategory = .underexposed
            return
        }
        
        // Accidental shots (pocket/floor shots)
        if await isAccidentalShot(photo: photo, qualityMetrics: qualityMetrics) {
            photo.cleanupCategory = .accidental
            return
        }
    }
    
    private func isAccidentalShot(photo: PersistedPhoto, qualityMetrics: ImageAnalyzer.QualityMetrics) async -> Bool {
        guard photo.mediaTypeRaw == "image" else { return false }
        
        // Very dark with no faces
        if let exposure = photo.exposureScore, exposure < 0.05 {
            if let faces = photo.facesDetected, faces == 0 {
                return true
            }
        }
        
        // Very blurry with no content
        if let sharpness = photo.sharpnessScore, sharpness < 0.1 {
            if let faces = photo.facesDetected, faces == 0 {
                if let detail = photo.detailScore, detail < 0.1 {
                    return true
                }
            }
        }
        
        // Extreme tilt (pocket shot indicator)
        if let tilt = photo.deviceTilt {
            // Unusual angles suggest accidental capture
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
    
    // MARK: - Duplicate Detection (Live Photo Aware)
    
    func detectDuplicates() async {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.imageFeaturePrintData != nil }
        )
        
        do {
            var photos = try modelContext.fetch(descriptor)
            photos.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            
            guard photos.count > 1 else { return }
            
            // Check for user feedback on similar groups that should be excluded
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
                if processedIds.contains(photo.id) { continue }
                guard let featurePrint1 = photo.imageFeaturePrintData else { continue }
                
                var duplicateGroup: [PersistedPhoto] = [photo]
                
                for j in (i + 1)..<photos.count {
                    let otherPhoto = photos[j]
                    if processedIds.contains(otherPhoto.id) { continue }
                    guard let featurePrint2 = otherPhoto.imageFeaturePrintData else { continue }
                    
                    // Check if this pair was marked as "not similar" by user
                    let pairKey = [photo.id, otherPhoto.id].sorted().joined(separator: "_")
                    if excludedPairs.contains(pairKey) { continue }
                    
                    // LIVE PHOTO AWARENESS: Don't match Live Photo with its own still/video
                    if photo.isLivePhoto && otherPhoto.localIdentifier == photo.livePhotoVideoIdentifier {
                        continue
                    }
                    if otherPhoto.isLivePhoto && photo.localIdentifier == otherPhoto.livePhotoVideoIdentifier {
                        continue
                    }
                    
                    let distance = await imageAnalyzer.compareFeaturePrints(featurePrint1, featurePrint2)
                    
                    // Near-duplicate threshold
                    if let dist = distance, dist < 0.15 {
                        duplicateGroup.append(otherPhoto)
                    }
                }
                
                if duplicateGroup.count > 1 {
                    let currentGroupId = "dup_\(groupId)"
                    groupId += 1
                    
                    // Find the best photo in the group with reasons
                    let (bestPhoto, reasons) = selectBestPhotoWithReasons(from: duplicateGroup)
                    
                    // Create SimilarGroup for tracking
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
                            // High confidence if visual similarity is very high
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
    
    // MARK: - Select Best Photo with Explained Reasons
    
    private func selectBestPhotoWithReasons(from photos: [PersistedPhoto]) -> (PersistedPhoto, [BestShotReason]) {
        var scores: [(PersistedPhoto, Double, [BestShotReason])] = []
        
        for photo in photos {
            var score: Double = 0
            var reasons: [BestShotReason] = []
            
            // Check if favorited (strongest signal)
            if photo.isFavorite {
                score += 100
                reasons.append(.favorited)
            }
            
            // Check if edited (user chose to edit this one)
            if photo.isEdited {
                score += 80
                reasons.append(.edited)
            }
            
            // Live Photo bonus (more content value)
            if photo.isLivePhoto {
                score += 15
                reasons.append(.livePhoto)
            }
            
            // Sharpness is most important for quality
            if let sharpness = photo.sharpnessScore, sharpness > 0.7 {
                score += sharpness * 40
                if sharpness > 0.85 {
                    reasons.append(.sharpest)
                }
            }
            
            // Good exposure
            if let exposure = photo.exposureScore {
                let exposureScore = 1.0 - abs(exposure - 0.5) * 2
                score += exposureScore * 20
                if exposureScore > 0.8 {
                    reasons.append(.bestAesthetics)
                }
            }
            
            // Faces with eyes open
            if let facesOpen = photo.facesOpenScore, facesOpen > 0.8 {
                score += facesOpen * 30
                reasons.append(.eyesOpen)
            }
            
            // Has faces (smile detection would be part of faces analysis)
            if let faces = photo.facesDetected, faces > 0 {
                score += 10
            }
            
            // Higher resolution
            let resolution = photo.pixelWidth * photo.pixelHeight
            if resolution > 8_000_000 { // > 8MP
                score += 5
                reasons.append(.highestResolution)
            }
            
            // Represents burst (already selected as best by iOS)
            if photo.representsBurst {
                score += 5
            }
            
            scores.append((photo, score, reasons))
        }
        
        let best = scores.max(by: { $0.1 < $1.1 }) ?? (photos[0], 0, [])
        
        // Remove duplicates in reasons and take top 3
        let uniqueReasons = Array(Set(best.2)).prefix(3)
        
        return (best.0, Array(uniqueReasons))
    }
    
    // MARK: - Helpers
    
    private func fetchAsset(for photo: PersistedPhoto) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
        return result.firstObject
    }
    
    private func loadImage(for asset: PHAsset) async -> UIImage? {
        // NEVER force iCloud downloads - use local data only
        // If original not available, use thumbnail for analysis
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false  // CRITICAL: Never download from iCloud
            options.isSynchronous = false
            options.resizeMode = .exact
            
            let targetSize = CGSize(width: 1024, height: 1024)
            
            var hasResumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                
                // If the image is in iCloud and we got a degraded version, use it anyway
                // Better to analyze a thumbnail than to download gigabytes
                if !hasResumed {
                    if image != nil && (!isDegraded || isInCloud) {
                        hasResumed = true
                        continuation.resume(returning: image)
                    } else if image == nil && isInCloud {
                        // Image only in iCloud, try to get thumbnail
                        hasResumed = true
                        continuation.resume(returning: nil)
                    } else if image != nil {
                        // Got degraded local image, use it
                        hasResumed = true
                        continuation.resume(returning: image)
                    }
                }
            }
        }
    }
    
    // Load thumbnail for iCloud-only photos
    private func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            
            let targetSize = CGSize(width: 256, height: 256)
            
            var hasResumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
        }
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
        
        // Laplacian kernel for blur detection
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
        
        // Calculate variance of Laplacian
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
        
        // Higher variance = sharper image
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
        
        // Use histogram to measure detail/variation
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
        
        // Calculate entropy as a measure of detail
        var nonZeroCount = 0
        for i in stride(from: 0, to: histogramData.count, by: 4) {
            if histogramData[i] > 5 {
                nonZeroCount += 1
            }
        }
        
        return Double(nonZeroCount) / 64.0
    }
    
    private func extractDeviceTilt(from image: UIImage) -> Double? {
        // Device tilt is not directly available from UIImage
        // Would need to be captured at photo time via CMMotionManager
        // Return nil for now - can be enhanced with Core Motion data in future
        return nil
    }
    
    func analyzeText(image: UIImage) async -> TextAnalysis {
        guard let cgImage = image.cgImage else {
            return TextAnalysis(hasText: false, isDocument: false, isReceipt: false, detectedText: nil)
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      error == nil else {
                    continuation.resume(returning: TextAnalysis(hasText: false, isDocument: false, isReceipt: false, detectedText: nil))
                    return
                }
                
                let hasText = !observations.isEmpty
                let textCount = observations.count
                let isDocument = textCount > 10
                
                let allText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                // Check for receipt patterns
                let isReceipt = self.detectReceiptPattern(in: allText)
                
                continuation.resume(returning: TextAnalysis(
                    hasText: hasText,
                    isDocument: isDocument,
                    isReceipt: isReceipt,
                    detectedText: allText.isEmpty ? nil : String(allText.prefix(2000))
                ))
            }
            
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es", "en"]
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: TextAnalysis(hasText: false, isDocument: false, isReceipt: false, detectedText: nil))
            }
        }
    }
    
    private func detectReceiptPattern(in text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Common receipt indicators
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
        
        // Also check for price patterns like "$123.45" or "123,45"
        let priceRegex = try? NSRegularExpression(pattern: "\\$?\\d+[,.]\\d{2}", options: [])
        let priceMatches = priceRegex?.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? 0
        
        return matches >= 3 || (matches >= 2 && priceMatches >= 2)
    }
    
    func classifyImage(image: UIImage) async -> [LabelResult] {
        guard let cgImage = image.cgImage else { return [] }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let request = VNClassifyImageRequest { request, error in
                guard !hasResumed else { return }
                guard let observations = request.results as? [VNClassificationObservation],
                      error == nil else {
                    hasResumed = true
                    continuation.resume(returning: [])
                    return
                }
                
                // Filter to high-confidence labels
                let topLabels = observations
                    .filter { $0.confidence > 0.3 }
                    .prefix(10)
                    .map { LabelResult(label: $0.identifier, confidence: $0.confidence) }
                
                hasResumed = true
                continuation.resume(returning: Array(topLabels))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func detectBarcodes(image: UIImage) async -> BarcodeResult {
        guard let cgImage = image.cgImage else {
            return BarcodeResult(hasBarcode: false, hasQR: false, barcodeTypes: [])
        }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let request = VNDetectBarcodesRequest { request, error in
                guard !hasResumed else { return }
                guard let observations = request.results as? [VNBarcodeObservation],
                      error == nil else {
                    hasResumed = true
                    continuation.resume(returning: BarcodeResult(hasBarcode: false, hasQR: false, barcodeTypes: []))
                    return
                }
                
                let hasBarcode = !observations.isEmpty
                let hasQR = observations.contains { $0.symbology == .qr }
                let types = observations.map { $0.symbology.rawValue }
                
                hasResumed = true
                continuation.resume(returning: BarcodeResult(hasBarcode: hasBarcode, hasQR: hasQR, barcodeTypes: types))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: BarcodeResult(hasBarcode: false, hasQR: false, barcodeTypes: []))
                }
            }
        }
    }
    
    func generateFeaturePrint(image: UIImage) async -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard !hasResumed else { return }
                guard let observation = request.results?.first as? VNFeaturePrintObservation,
                      error == nil else {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }
                
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
                    hasResumed = true
                    continuation.resume(returning: data)
                } catch {
                    hasResumed = true
                    continuation.resume(returning: nil)
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: nil)
                }
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
            var faceDataArray: [FaceData] = []
            
            let faceDetectionRequest = VNDetectFaceCaptureQualityRequest { request, error in
                guard !hasResumed else { return }
                guard let observations = request.results as? [VNFaceObservation],
                      error == nil else {
                    hasResumed = true
                    continuation.resume(returning: [])
                    return
                }
                
                for observation in observations {
                    // Use face capture quality as quality score
                    let quality = Double(observation.faceCaptureQuality ?? observation.confidence)
                    
                    let faceData = FaceData(
                        boundingBox: observation.boundingBox,
                        featurePrint: nil,
                        quality: quality
                    )
                    faceDataArray.append(faceData)
                }
                
                hasResumed = true
                continuation.resume(returning: faceDataArray)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([faceDetectionRequest])
            } catch {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func generateFaceFeaturePrint(image: UIImage, boundingBox: CGRect) async -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let faceRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        ).insetBy(dx: -20, dy: -20)
        
        guard let croppedCGImage = cgImage.cropping(to: faceRect) else { return nil }
        
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard !hasResumed else { return }
                guard let observation = request.results?.first as? VNFeaturePrintObservation,
                      error == nil else {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }
                
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
                    hasResumed = true
                    continuation.resume(returning: data)
                } catch {
                    hasResumed = true
                    continuation.resume(returning: nil)
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: croppedCGImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
