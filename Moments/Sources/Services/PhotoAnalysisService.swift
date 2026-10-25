// PhotoAnalysisService.swift
// Servicio para analizar fotos con Vision y Core Image

import Foundation
import SwiftData
import Photos
import Vision
import CoreImage
import UIKit

@MainActor
class PhotoAnalysisService: ObservableObject {
    private let modelContext: ModelContext
    private let imageAnalyzer = ImageAnalyzer()
    private let faceAnalyzer = FaceAnalyzer()
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Full Analysis
    
    func analyzeAllPhotos(progressHandler: @escaping (Double) async -> Void) async {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { !$0.analysisCompleted },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        do {
            let photosToAnalyze = try modelContext.fetch(descriptor)
            let total = photosToAnalyze.count
            guard total > 0 else { return }
            
            let batchSize = 20
            
            for (index, photo) in photosToAnalyze.enumerated() {
                await analyzePhoto(photo)
                
                if (index + 1) % batchSize == 0 {
                    try? modelContext.save()
                    await progressHandler(Double(index + 1) / Double(total))
                }
            }
            
            try modelContext.save()
            await progressHandler(1.0)
            
        } catch {
            print("Error fetching photos for analysis: \(error)")
        }
    }
    
    func analyzePhoto(_ photo: PersistedPhoto) async {
        guard let asset = fetchAsset(for: photo) else {
            photo.analysisCompleted = true
            return
        }
        
        guard let image = await loadImage(for: asset) else {
            photo.analysisCompleted = true
            return
        }
        
        // Análisis de calidad
        let qualityMetrics = await imageAnalyzer.analyzeQuality(image: image)
        photo.sharpnessScore = qualityMetrics.sharpness
        photo.exposureScore = qualityMetrics.exposure
        
        // Detección de texto/documentos
        let textAnalysis = await imageAnalyzer.analyzeText(image: image)
        photo.hasText = textAnalysis.hasText
        photo.isDocument = textAnalysis.isDocument
        
        // Feature print para duplicados
        if let featurePrint = await imageAnalyzer.generateFeaturePrint(image: image) {
            photo.imageFeaturePrintData = featurePrint
        }
        
        // Detección de rostros
        let faces = await faceAnalyzer.detectFaces(in: image, photoId: photo.id)
        photo.facesDetected = faces.count
        
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
        
        // Tamaño de archivo
        let resourceInfo = await getResourceInfo(for: asset)
        photo.estimatedFileSize = resourceInfo.fileSize
        
        photo.analysisCompleted = true
        photo.lastAnalyzedAt = Date()
    }
    
    // MARK: - Helpers
    
    private func fetchAsset(for photo: PersistedPhoto) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
        return result.firstObject
    }
    
    private func loadImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            let targetSize = CGSize(width: 1024, height: 1024)
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    private func getResourceInfo(for asset: PHAsset) async -> (fileSize: Int64, uti: String?) {
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
}

// MARK: - Image Analyzer

class ImageAnalyzer {
    private let context = CIContext()
    
    struct QualityMetrics {
        let sharpness: Double
        let exposure: Double
    }
    
    struct TextAnalysis {
        let hasText: Bool
        let isDocument: Bool
        let detectedText: String?
    }
    
    func analyzeQuality(image: UIImage) async -> QualityMetrics {
        guard let ciImage = CIImage(image: image) else {
            return QualityMetrics(sharpness: 0.5, exposure: 0.5)
        }
        
        let sharpness = calculateSharpness(ciImage)
        let exposure = calculateExposure(ciImage)
        
        return QualityMetrics(sharpness: sharpness, exposure: exposure)
    }
    
    private func calculateSharpness(_ image: CIImage) -> Double {
        guard let filter = CIFilter(name: "CILaplacianFilter") else { return 0.5 }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        
        guard let output = filter.outputImage else { return 0.5 }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let extent = output.extent
        
        guard extent.width > 0 && extent.height > 0 else { return 0.5 }
        
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: extent.midX, y: extent.midY, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        let variance = Double(bitmap[0]) / 255.0
        return min(max(variance, 0), 1)
    }
    
    private func calculateExposure(_ image: CIImage) -> Double {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        
        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 else { return 0.5 }
        
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
    
    func analyzeText(image: UIImage) async -> TextAnalysis {
        guard let cgImage = image.cgImage else {
            return TextAnalysis(hasText: false, isDocument: false, detectedText: nil)
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      error == nil else {
                    continuation.resume(returning: TextAnalysis(hasText: false, isDocument: false, detectedText: nil))
                    return
                }
                
                let hasText = !observations.isEmpty
                let textCount = observations.count
                let isDocument = textCount > 10 // Heurística: muchas líneas = documento
                
                let allText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                continuation.resume(returning: TextAnalysis(
                    hasText: hasText,
                    isDocument: isDocument,
                    detectedText: allText.isEmpty ? nil : allText
                ))
            }
            
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: TextAnalysis(hasText: false, isDocument: false, detectedText: nil))
            }
        }
    }
    
    func generateFeaturePrint(image: UIImage) async -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard let observation = request.results?.first as? VNFeaturePrintObservation,
                      error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let data = observation.data
                continuation.resume(returning: data)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

// MARK: - Face Analyzer

class FaceAnalyzer {
    
    struct FaceData {
        let boundingBox: CGRect
        let featurePrint: Data?
        let quality: Double
    }
    
    func detectFaces(in image: UIImage, photoId: String) async -> [FaceData] {
        guard let cgImage = image.cgImage else { return [] }
        
        return await withCheckedContinuation { continuation in
            var faceDataArray: [FaceData] = []
            
            let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
                guard let observations = request.results as? [VNFaceObservation],
                      error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                
                for observation in observations {
                    let quality = Double(observation.confidence)
                    
                    let faceData = FaceData(
                        boundingBox: observation.boundingBox,
                        featurePrint: nil, // Se calculará con face landmarks
                        quality: quality
                    )
                    faceDataArray.append(faceData)
                }
                
                continuation.resume(returning: faceDataArray)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([faceDetectionRequest])
            } catch {
                continuation.resume(returning: [])
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
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard let observation = request.results?.first as? VNFeaturePrintObservation,
                      error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: observation.data)
            }
            
            let handler = VNImageRequestHandler(cgImage: croppedCGImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
