// PhotoMetadata.swift
// Modelo de metadatos de foto agnóstico a PhotoKit

import Foundation

/// Metadatos de una foto/video extraídos de PhotoKit
/// Diseñado para ser serializable y testeable sin dependencias de iOS
public struct PhotoMetadata: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let mediaType: MediaType
    public let mediaSubtypes: Set<MediaSubtype>
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: TimeInterval
    public let location: Coordinate?
    public let isFavorite: Bool
    public let isHidden: Bool
    public let burstIdentifier: String?
    public let representsBurst: Bool
    
    // Análisis adicional (calculado después)
    public var sharpnessScore: Double?
    public var exposureScore: Double?
    public var facesDetected: Int?
    public var faceFeaturePrints: [[Double]]?
    public var imageFeaturePrint: [Double]?
    public var estimatedFileSize: Int64?
    public var dominantColors: [String]?
    public var hasText: Bool?
    public var isDocument: Bool?
    
    public init(
        id: String,
        creationDate: Date?,
        modificationDate: Date?,
        mediaType: MediaType,
        mediaSubtypes: Set<MediaSubtype>,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval = 0,
        location: Coordinate? = nil,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        burstIdentifier: String? = nil,
        representsBurst: Bool = false,
        sharpnessScore: Double? = nil,
        exposureScore: Double? = nil,
        facesDetected: Int? = nil,
        faceFeaturePrints: [[Double]]? = nil,
        imageFeaturePrint: [Double]? = nil,
        estimatedFileSize: Int64? = nil,
        dominantColors: [String]? = nil,
        hasText: Bool? = nil,
        isDocument: Bool? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.location = location
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.burstIdentifier = burstIdentifier
        self.representsBurst = representsBurst
        self.sharpnessScore = sharpnessScore
        self.exposureScore = exposureScore
        self.facesDetected = facesDetected
        self.faceFeaturePrints = faceFeaturePrints
        self.imageFeaturePrint = imageFeaturePrint
        self.estimatedFileSize = estimatedFileSize
        self.dominantColors = dominantColors
        self.hasText = hasText
        self.isDocument = isDocument
    }
    
    public var aspectRatio: Double {
        guard pixelHeight > 0 else { return 1.0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
    
    public var isLandscape: Bool {
        pixelWidth > pixelHeight
    }
    
    public var isPortrait: Bool {
        pixelHeight > pixelWidth
    }
    
    public var isSquare: Bool {
        pixelWidth == pixelHeight
    }
    
    public var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000.0
    }
}

// MARK: - Tipos de Medios

public enum MediaType: String, Codable, Sendable {
    case image
    case video
    case audio
    case unknown
}

public enum MediaSubtype: String, Codable, Sendable, Hashable {
    case screenshot
    case screenRecording
    case livePhoto
    case panorama
    case hdr
    case depthEffect
    case highFrameRate
    case timelapse
    case cinematicVideo
    case spatialMedia
}

// MARK: - Coordenadas

public struct Coordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    
    public init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
    
    /// Distancia en metros a otra coordenada (fórmula Haversine)
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0 // metros
        
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
}
