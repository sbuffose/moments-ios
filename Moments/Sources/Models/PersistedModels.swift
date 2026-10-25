// PersistedModels.swift
// Modelos SwiftData para persistencia local

import Foundation
import SwiftData

// MARK: - Foto Persistida

@Model
final class PersistedPhoto {
    @Attribute(.unique) var id: String
    var localIdentifier: String
    var creationDate: Date?
    var modificationDate: Date?
    var mediaTypeRaw: String
    var mediaSubtypesRaw: String
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: Double
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var isFavorite: Bool
    var isHidden: Bool
    var burstIdentifier: String?
    var representsBurst: Bool
    
    // Análisis
    var sharpnessScore: Double?
    var exposureScore: Double?
    var facesDetected: Int?
    var estimatedFileSize: Int64?
    var hasText: Bool?
    var isDocument: Bool?
    var imageFeaturePrintData: Data?
    var analysisCompleted: Bool
    var lastAnalyzedAt: Date?
    
    // Relaciones
    @Relationship(deleteRule: .cascade, inverse: \PersistedFaceDetection.photo)
    var faceDetections: [PersistedFaceDetection]?
    
    init(
        id: String = UUID().uuidString,
        localIdentifier: String,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        mediaTypeRaw: String = "image",
        mediaSubtypesRaw: String = "",
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        duration: Double = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        burstIdentifier: String? = nil,
        representsBurst: Bool = false
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.mediaTypeRaw = mediaTypeRaw
        self.mediaSubtypesRaw = mediaSubtypesRaw
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.burstIdentifier = burstIdentifier
        self.representsBurst = representsBurst
        self.analysisCompleted = false
    }
}

// MARK: - Momento Persistido

@Model
final class PersistedMoment {
    @Attribute(.unique) var id: String
    var title: String?
    var subtitle: String?
    var startDate: Date
    var endDate: Date
    var photoIds: String // JSON array
    var coverPhotoId: String?
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
    var isTrip: Bool
    var tripDestination: String?
    
    init(
        id: String = UUID().uuidString,
        title: String? = nil,
        subtitle: String? = nil,
        startDate: Date,
        endDate: Date,
        photoIds: [String] = [],
        coverPhotoId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        isTrip: Bool = false,
        tripDestination: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.startDate = startDate
        self.endDate = endDate
        self.photoIds = (try? JSONEncoder().encode(photoIds).base64EncodedString()) ?? "[]"
        self.coverPhotoId = coverPhotoId
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.isTrip = isTrip
        self.tripDestination = tripDestination
    }
    
    var photoIdArray: [String] {
        guard let data = Data(base64Encoded: photoIds),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
}

// MARK: - Lugar Persistido

@Model
final class PersistedPlace {
    @Attribute(.unique) var id: String
    var name: String
    var address: String?
    var city: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var radius: Double
    var photoIds: String // JSON array
    var firstVisit: Date?
    var lastVisit: Date?
    var visitCount: Int
    
    init(
        id: String = UUID().uuidString,
        name: String = "",
        address: String? = nil,
        city: String? = nil,
        country: String? = nil,
        latitude: Double,
        longitude: Double,
        radius: Double = 100,
        photoIds: [String] = [],
        firstVisit: Date? = nil,
        lastVisit: Date? = nil,
        visitCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.photoIds = (try? JSONEncoder().encode(photoIds).base64EncodedString()) ?? "[]"
        self.firstVisit = firstVisit
        self.lastVisit = lastVisit
        self.visitCount = visitCount
    }
    
    var photoIdArray: [String] {
        guard let data = Data(base64Encoded: photoIds),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
}

// MARK: - Persona Persistida

@Model
final class PersistedPerson {
    @Attribute(.unique) var id: String
    var name: String?
    var faceClusterId: String
    var representativeFacePhotoId: String?
    var photoIds: String // JSON array
    var faceCount: Int
    var birthdayMonth: Int?
    var birthdayDay: Int?
    var isFavorite: Bool
    
    init(
        id: String = UUID().uuidString,
        name: String? = nil,
        faceClusterId: String,
        representativeFacePhotoId: String? = nil,
        photoIds: [String] = [],
        faceCount: Int = 0,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.faceClusterId = faceClusterId
        self.representativeFacePhotoId = representativeFacePhotoId
        self.photoIds = (try? JSONEncoder().encode(photoIds).base64EncodedString()) ?? "[]"
        self.faceCount = faceCount
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.isFavorite = isFavorite
    }
    
    var photoIdArray: [String] {
        guard let data = Data(base64Encoded: photoIds),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
    
    var isNamed: Bool {
        name != nil && !name!.isEmpty
    }
}

// MARK: - Detección de Rostro Persistida

@Model
final class PersistedFaceDetection {
    @Attribute(.unique) var id: String
    var photoId: String
    var boundingBoxX: Double
    var boundingBoxY: Double
    var boundingBoxWidth: Double
    var boundingBoxHeight: Double
    var featurePrintData: Data?
    var quality: Double
    var clusterId: String?
    
    var photo: PersistedPhoto?
    
    init(
        id: String = UUID().uuidString,
        photoId: String,
        boundingBoxX: Double,
        boundingBoxY: Double,
        boundingBoxWidth: Double,
        boundingBoxHeight: Double,
        featurePrintData: Data? = nil,
        quality: Double = 0,
        clusterId: String? = nil
    ) {
        self.id = id
        self.photoId = photoId
        self.boundingBoxX = boundingBoxX
        self.boundingBoxY = boundingBoxY
        self.boundingBoxWidth = boundingBoxWidth
        self.boundingBoxHeight = boundingBoxHeight
        self.featurePrintData = featurePrintData
        self.quality = quality
        self.clusterId = clusterId
    }
}

// MARK: - Evento Recurrente Persistido

@Model
final class PersistedRecurringEvent {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var personId: String?
    var personName: String?
    var dayOfYear: Int
    var month: Int
    var day: Int
    var occurrencesData: Data?
    var confidence: Double
    
    init(
        id: String = UUID().uuidString,
        typeRaw: String = "unknown",
        personId: String? = nil,
        personName: String? = nil,
        dayOfYear: Int,
        month: Int,
        day: Int,
        confidence: Double = 0
    ) {
        self.id = id
        self.typeRaw = typeRaw
        self.personId = personId
        self.personName = personName
        self.dayOfYear = dayOfYear
        self.month = month
        self.day = day
        self.confidence = confidence
    }
}

// MARK: - Estado del Análisis

@Model
final class AnalysisState {
    @Attribute(.unique) var id: String
    var lastScanDate: Date?
    var totalPhotosScanned: Int
    var totalPhotosAnalyzed: Int
    var homeLatitude: Double?
    var homeLongitude: Double?
    var homeConfidence: Double?
    var version: Int
    
    init(id: String = "main") {
        self.id = id
        self.totalPhotosScanned = 0
        self.totalPhotosAnalyzed = 0
        self.version = 1
    }
}
