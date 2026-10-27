// MetadataExtractionService.swift
// Servicio para extraer metadatos EXIF/TIFF/GPS de fotos

import Foundation
import Photos
import ImageIO
import UIKit

actor MetadataExtractionService {
    static let shared = MetadataExtractionService()
    
    private init() {}
    
    // MARK: - Metadata Result
    
    struct PhotoMetadata: Sendable {
        let hasExifData: Bool
        let cameraMake: String?
        let cameraModel: String?
        let lensMake: String?
        let lensModel: String?
        let software: String?
        let originalFilename: String?
        let dateTimeOriginal: Date?
        let gpsLatitude: Double?
        let gpsLongitude: Double?
        let gpsAltitude: Double?
        let orientation: Int?
        let colorSpace: String?
        let fNumber: Double?
        let exposureTime: Double?
        let iso: Int?
        let focalLength: Double?
        let flashFired: Bool?
        let whiteBalance: String?
        
        var origin: PhotoOrigin {
            determineOrigin()
        }
        
        private func determineOrigin() -> PhotoOrigin {
            // If we have camera make/model, it's from a camera
            if let make = cameraMake, !make.isEmpty {
                return .camera
            }
            
            if let model = cameraModel, !model.isEmpty {
                return .camera
            }
            
            // Check software for editing apps
            if let software = software?.lowercased() {
                if software.contains("photoshop") || software.contains("lightroom") || 
                   software.contains("snapseed") || software.contains("vsco") {
                    return .editedExport
                }
                
                // WhatsApp pattern
                if software.contains("whatsapp") {
                    return .whatsapp
                }
                
                // Instagram pattern
                if software.contains("instagram") {
                    return .instagram
                }
            }
            
            // No EXIF data - likely downloaded or received
            if !hasExifData {
                return .download
            }
            
            return .unknown
        }
    }
    
    // MARK: - Origin Detection
    
    struct OriginDetectionResult: Sendable {
        let origin: PhotoOrigin
        let confidence: Double
        let metadata: PhotoMetadata?
    }
    
    // MARK: - Extraction Methods
    
    func extractMetadata(for asset: PHAsset) async -> PhotoMetadata? {
        // First try to get metadata from PHAsset properties (no network needed)
        let basicMetadata = extractBasicMetadata(from: asset)
        
        // Only request file metadata if available locally (no iCloud download)
        return await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = false // CRITICAL: Never download iCloud originals for metadata
            
            asset.requestContentEditingInput(with: options) { input, info in
                // Check if asset is only in iCloud
                let isInCloud = (info?[PHContentEditingInputResultIsInCloudKey] as? Bool) ?? false
                
                if isInCloud {
                    // Use basic metadata from PHAsset properties only
                    continuation.resume(returning: basicMetadata)
                    return
                }
                
                guard let input = input, let url = input.fullSizeImageURL else {
                    continuation.resume(returning: basicMetadata)
                    return
                }
                
                // Merge file metadata with basic metadata
                if let fileMetadata = self.extractMetadataFromURL(url) {
                    continuation.resume(returning: fileMetadata)
                } else {
                    continuation.resume(returning: basicMetadata)
                }
            }
        }
    }
    
    /// Extract basic metadata from PHAsset properties without file access
    private func extractBasicMetadata(from asset: PHAsset) -> PhotoMetadata {
        return PhotoMetadata(
            hasExifData: false,
            cameraMake: nil,
            cameraModel: nil,
            lensMake: nil,
            lensModel: nil,
            software: nil,
            originalFilename: nil,
            dateTimeOriginal: asset.creationDate,
            gpsLatitude: asset.location?.coordinate.latitude,
            gpsLongitude: asset.location?.coordinate.longitude,
            gpsAltitude: asset.location?.altitude,
            orientation: nil,
            colorSpace: nil,
            fNumber: nil,
            exposureTime: nil,
            iso: nil,
            focalLength: nil,
            flashFired: nil,
            whiteBalance: nil
        )
    }
    
    private nonisolated func extractMetadataFromURL(_ url: URL) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return PhotoMetadata(
                hasExifData: false,
                cameraMake: nil, cameraModel: nil, lensMake: nil, lensModel: nil,
                software: nil, originalFilename: nil, dateTimeOriginal: nil,
                gpsLatitude: nil, gpsLongitude: nil, gpsAltitude: nil,
                orientation: nil, colorSpace: nil, fNumber: nil, exposureTime: nil,
                iso: nil, focalLength: nil, flashFired: nil, whiteBalance: nil
            )
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return PhotoMetadata(
                hasExifData: false,
                cameraMake: nil, cameraModel: nil, lensMake: nil, lensModel: nil,
                software: nil, originalFilename: nil, dateTimeOriginal: nil,
                gpsLatitude: nil, gpsLongitude: nil, gpsAltitude: nil,
                orientation: nil, colorSpace: nil, fNumber: nil, exposureTime: nil,
                iso: nil, focalLength: nil, flashFired: nil, whiteBalance: nil
            )
        }
        
        // EXIF dictionary
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        
        // TIFF dictionary
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        
        // GPS dictionary
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        
        // IPTC dictionary (for original filename sometimes)
        let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
        
        let hasExif = exif != nil || tiff != nil
        
        // Camera info from TIFF
        let cameraMake = tiff?[kCGImagePropertyTIFFMake as String] as? String
        let cameraModel = tiff?[kCGImagePropertyTIFFModel as String] as? String
        let software = tiff?[kCGImagePropertyTIFFSoftware as String] as? String
        
        // Lens info from EXIF
        let lensMake = exif?[kCGImagePropertyExifLensMake as String] as? String
        let lensModel = exif?[kCGImagePropertyExifLensModel as String] as? String
        
        // Date/time from EXIF
        var dateTimeOriginal: Date?
        if let dateString = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            dateTimeOriginal = formatter.date(from: dateString)
        }
        
        // GPS coordinates
        var gpsLatitude: Double?
        var gpsLongitude: Double?
        var gpsAltitude: Double?
        
        if let lat = gps?[kCGImagePropertyGPSLatitude as String] as? Double,
           let latRef = gps?[kCGImagePropertyGPSLatitudeRef as String] as? String {
            gpsLatitude = latRef == "S" ? -lat : lat
        }
        
        if let lon = gps?[kCGImagePropertyGPSLongitude as String] as? Double,
           let lonRef = gps?[kCGImagePropertyGPSLongitudeRef as String] as? String {
            gpsLongitude = lonRef == "W" ? -lon : lon
        }
        
        gpsAltitude = gps?[kCGImagePropertyGPSAltitude as String] as? Double
        
        // Camera settings
        let fNumber = exif?[kCGImagePropertyExifFNumber as String] as? Double
        let exposureTime = exif?[kCGImagePropertyExifExposureTime as String] as? Double
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first
        let focalLength = exif?[kCGImagePropertyExifFocalLength as String] as? Double
        let flashValue = exif?[kCGImagePropertyExifFlash as String] as? Int
        let flashFired = flashValue != nil ? (flashValue! & 1) == 1 : nil
        
        // Orientation
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int
        
        // Color space
        let colorSpace = properties[kCGImagePropertyColorModel as String] as? String
        
        // White balance
        let whiteBalance = exif?[kCGImagePropertyExifWhiteBalance as String] as? Int == 0 ? "auto" : "manual"
        
        // Original filename (from IPTC if available)
        let originalFilename = iptc?[kCGImagePropertyIPTCObjectName as String] as? String
        
        return PhotoMetadata(
            hasExifData: hasExif,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensMake: lensMake,
            lensModel: lensModel,
            software: software,
            originalFilename: originalFilename,
            dateTimeOriginal: dateTimeOriginal,
            gpsLatitude: gpsLatitude,
            gpsLongitude: gpsLongitude,
            gpsAltitude: gpsAltitude,
            orientation: orientation,
            colorSpace: colorSpace,
            fNumber: fNumber,
            exposureTime: exposureTime,
            iso: iso,
            focalLength: focalLength,
            flashFired: flashFired,
            whiteBalance: whiteBalance
        )
    }
    
    // MARK: - Origin Detection with Heuristics
    
    func detectOrigin(for asset: PHAsset, metadata: PhotoMetadata?) -> OriginDetectionResult {
        var origin: PhotoOrigin = .unknown
        var confidence: Double = 0.5
        
        // Check media subtypes first
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return OriginDetectionResult(origin: .screenshot, confidence: 1.0, metadata: metadata)
        }
        
        if asset.mediaSubtypes.contains(.videoScreenRecording) {
            return OriginDetectionResult(origin: .screenRecording, confidence: 1.0, metadata: metadata)
        }
        
        // Check source type
        switch asset.sourceType {
        case .typeUserLibrary:
            // Could be camera or any source, need more analysis
            break
        case .typeCloudShared:
            origin = .cloudSync
            confidence = 0.8
        case .typeiTunesSynced:
            origin = .cloudSync
            confidence = 0.7
        default:
            break
        }
        
        // Check metadata for origin clues
        if let meta = metadata {
            // Has camera EXIF = likely camera photo
            if meta.hasExifData && (meta.cameraMake != nil || meta.cameraModel != nil) {
                return OriginDetectionResult(origin: .camera, confidence: 0.95, metadata: metadata)
            }
            
            // Check software field
            if let software = meta.software?.lowercased() {
                if software.contains("whatsapp") {
                    return OriginDetectionResult(origin: .whatsapp, confidence: 0.9, metadata: metadata)
                }
                if software.contains("instagram") {
                    return OriginDetectionResult(origin: .instagram, confidence: 0.9, metadata: metadata)
                }
                if software.contains("telegram") {
                    return OriginDetectionResult(origin: .telegram, confidence: 0.9, metadata: metadata)
                }
                if software.contains("snapchat") {
                    return OriginDetectionResult(origin: .snapchat, confidence: 0.9, metadata: metadata)
                }
            }
            
            // No EXIF and no camera = likely downloaded/received
            if !meta.hasExifData {
                origin = .download
                confidence = 0.7
            }
        }
        
        // Use image dimensions as additional heuristic
        let width = asset.pixelWidth
        let height = asset.pixelHeight
        
        // Common WhatsApp dimensions
        if isWhatsAppDimension(width: width, height: height) && origin == .download {
            origin = .whatsapp
            confidence = 0.6
        }
        
        // Common Instagram dimensions
        if isInstagramDimension(width: width, height: height) && origin == .download {
            origin = .instagram
            confidence = 0.6
        }
        
        // Meme-like aspect ratios (typically square or weird ratios, low res)
        if isMemelikeDimension(width: width, height: height) && origin == .download {
            confidence = 0.8
        }
        
        return OriginDetectionResult(origin: origin, confidence: confidence, metadata: metadata)
    }
    
    private nonisolated func isWhatsAppDimension(width: Int, height: Int) -> Bool {
        // WhatsApp compresses images to max 1600px on longest side typically
        // Also common: 1280x720, 960x540, etc.
        let maxDim = max(width, height)
        let whatsappSizes = [1600, 1280, 1024, 960, 800, 640]
        return whatsappSizes.contains(maxDim) || (maxDim <= 1600 && maxDim >= 400)
    }
    
    private nonisolated func isInstagramDimension(width: Int, height: Int) -> Bool {
        // Instagram common dimensions: 1080x1080 (square), 1080x1350 (portrait), 1080x608 (landscape)
        if width == 1080 && (height == 1080 || height == 1350 || height == 608 || height == 566) {
            return true
        }
        // Older Instagram: 640x640
        if width == 640 && height == 640 {
            return true
        }
        return false
    }
    
    private nonisolated func isMemelikeDimension(width: Int, height: Int) -> Bool {
        // Memes are often:
        // - Low resolution (< 1000px)
        // - Square or near-square
        // - Odd aspect ratios
        let maxDim = max(width, height)
        let minDim = min(width, height)
        let ratio = Double(maxDim) / Double(minDim)
        
        // Low res with square-ish ratio
        if maxDim < 1000 && ratio < 1.5 {
            return true
        }
        
        // Very low res
        if maxDim < 500 {
            return true
        }
        
        return false
    }
}
