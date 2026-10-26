// PersistedModels.swift
// Modelos SwiftData para persistencia local

import Foundation
import SwiftData

// MARK: - Photo Origin Enum

enum PhotoOrigin: String, Codable, CaseIterable, Sendable {
    case camera = "camera"
    case screenshot = "screenshot"
    case screenRecording = "screenRecording"
    case whatsapp = "whatsapp"
    case telegram = "telegram"
    case instagram = "instagram"
    case messenger = "messenger"
    case snapchat = "snapchat"
    case twitter = "twitter"
    case tiktok = "tiktok"
    case download = "download"
    case savedFromWeb = "savedFromWeb"
    case editedExport = "editedExport"
    case airdrop = "airdrop"
    case email = "email"
    case cloudSync = "cloudSync"
    case unknown = "unknown"
    
    var localizedKey: String {
        "origin_\(rawValue)"
    }
    
    var iconName: String {
        switch self {
        case .camera: return "camera"
        case .screenshot: return "rectangle.on.rectangle"
        case .screenRecording: return "record.circle"
        case .whatsapp: return "message.fill"
        case .telegram: return "paperplane.fill"
        case .instagram: return "camera.filters"
        case .messenger: return "message.circle.fill"
        case .snapchat: return "camera.badge.ellipsis"
        case .twitter: return "at"
        case .tiktok: return "music.note"
        case .download: return "arrow.down.circle"
        case .savedFromWeb: return "globe"
        case .editedExport: return "paintbrush"
        case .airdrop: return "airplayaudio"
        case .email: return "envelope"
        case .cloudSync: return "cloud"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var isMessagingApp: Bool {
        switch self {
        case .whatsapp, .telegram, .instagram, .messenger, .snapchat, .twitter, .tiktok:
            return true
        default:
            return false
        }
    }
}

// MARK: - Place Cluster Type

enum PlaceClusterType: String, Codable, CaseIterable, Sendable {
    case home = "home"
    case work = "work"
    case familyHome = "familyHome"
    case gym = "gym"
    case school = "school"
    case frequentPlace = "frequentPlace"
    case tripDestination = "tripDestination"
    case custom = "custom"
    case unknown = "unknown"
    
    var localizedKey: String {
        "place_type_\(rawValue)"
    }
    
    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        case .familyHome: return "house.and.flag.fill"
        case .gym: return "dumbbell.fill"
        case .school: return "graduationcap.fill"
        case .frequentPlace: return "mappin.circle.fill"
        case .tripDestination: return "airplane"
        case .custom: return "star.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Cleanup Category Enum

enum CleanupCategoryType: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case screenshot = "screenshot"
    case screenRecording = "screenRecording"
    case blurry = "blurry"
    case overexposed = "overexposed"
    case underexposed = "underexposed"
    case duplicate = "duplicate"
    case nearDuplicate = "nearDuplicate"
    case burst = "burst"
    case accidental = "accidental"
    case document = "document"
    case receipt = "receipt"
    case qrCode = "qrCode"
    case largeVideo = "largeVideo"
    case downloadedMeme = "downloadedMeme"
    case forwardedImage = "forwardedImage"
    
    var localizedKey: String {
        "cleanup_category_\(rawValue)"
    }
    
    var iconName: String {
        switch self {
        case .none: return "photo"
        case .screenshot: return "rectangle.on.rectangle"
        case .screenRecording: return "record.circle"
        case .blurry: return "camera.metering.unknown"
        case .overexposed: return "sun.max.fill"
        case .underexposed: return "moon.fill"
        case .duplicate: return "doc.on.doc.fill"
        case .nearDuplicate: return "square.on.square"
        case .burst: return "square.stack.3d.up.fill"
        case .accidental: return "hand.raised.slash"
        case .document: return "doc.text"
        case .receipt: return "receipt"
        case .qrCode: return "qrcode"
        case .largeVideo: return "film"
        case .downloadedMeme: return "arrow.down.circle"
        case .forwardedImage: return "arrowshape.turn.up.right"
        }
    }
}

// MARK: - Cataloging Card Type

enum CatalogingCardType: String, Codable, Sendable {
    case unknownPerson = "unknownPerson"
    case unknownPlace = "unknownPlace"
    case messagingAppPhotos = "messagingAppPhotos"
    case recurringDate = "recurringDate"
    case downloadedContent = "downloadedContent"
}

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
    
    // Análisis de calidad
    var sharpnessScore: Double?
    var exposureScore: Double?
    var facesDetected: Int?
    var estimatedFileSize: Int64?
    var hasText: Bool?
    var isDocument: Bool?
    var imageFeaturePrintData: Data?
    var analysisCompleted: Bool
    var lastAnalyzedAt: Date?
    
    // Search index fields
    var visionLabels: String?
    var visionLabelsConfidence: String?
    var ocrText: String?
    var placeName: String?
    var placeCity: String?
    var placeCountry: String?
    var cleanupCategoryRaw: String?
    var duplicateGroupId: String?
    var isBestInGroup: Bool?
    var hasBarcode: Bool?
    var deviceTilt: Double?
    var detailScore: Double?
    var facesOpenScore: Double?
    
    // Origin/Source metadata
    var originRaw: String?
    var cameraMake: String?
    var cameraModel: String?
    var lensMake: String?
    var lensModel: String?
    var software: String?
    var originalFilename: String?
    var hasExifData: Bool?
    var sourceAppIdentifier: String?
    var placeClusterId: String?
    
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
        self.cleanupCategoryRaw = CleanupCategoryType.none.rawValue
        self.isBestInGroup = nil
        self.originRaw = PhotoOrigin.unknown.rawValue
    }
    
    // Computed properties
    var cleanupCategory: CleanupCategoryType {
        get { CleanupCategoryType(rawValue: cleanupCategoryRaw ?? "none") ?? .none }
        set { cleanupCategoryRaw = newValue.rawValue }
    }
    
    var origin: PhotoOrigin {
        get { PhotoOrigin(rawValue: originRaw ?? "unknown") ?? .unknown }
        set { originRaw = newValue.rawValue }
    }
    
    var labelsArray: [String] {
        visionLabels?.components(separatedBy: "|") ?? []
    }
    
    var searchableText: String {
        var parts: [String] = []
        if let labels = visionLabels { parts.append(labels) }
        if let ocr = ocrText { parts.append(ocr) }
        if let place = placeName { parts.append(place) }
        if let city = placeCity { parts.append(city) }
        if let country = placeCountry { parts.append(country) }
        if let origin = originRaw { parts.append(origin) }
        if let camera = cameraModel { parts.append(camera) }
        return parts.joined(separator: " ").lowercased()
    }
    
    var isFromMessagingApp: Bool {
        origin.isMessagingApp
    }
    
    var isDownloadedWithoutExif: Bool {
        hasExifData == false && (origin == .download || origin == .savedFromWeb || origin.isMessagingApp)
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
    var photoIds: String
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
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
}

// MARK: - Place Cluster (for home, work, etc.)

@Model
final class PersistedPlaceCluster {
    @Attribute(.unique) var id: String
    var name: String?
    var placeTypeRaw: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var address: String?
    var city: String?
    var country: String?
    var photoCount: Int
    var firstVisit: Date?
    var lastVisit: Date?
    var visitCount: Int
    var isUserLabeled: Bool
    
    init(
        id: String = UUID().uuidString,
        name: String? = nil,
        placeType: PlaceClusterType = .unknown,
        latitude: Double,
        longitude: Double,
        radius: Double = 100,
        address: String? = nil,
        city: String? = nil,
        country: String? = nil,
        photoCount: Int = 0,
        firstVisit: Date? = nil,
        lastVisit: Date? = nil,
        visitCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.placeTypeRaw = placeType.rawValue
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.address = address
        self.city = city
        self.country = country
        self.photoCount = photoCount
        self.firstVisit = firstVisit
        self.lastVisit = lastVisit
        self.visitCount = visitCount
        self.isUserLabeled = false
    }
    
    var placeType: PlaceClusterType {
        get { PlaceClusterType(rawValue: placeTypeRaw) ?? .unknown }
        set { placeTypeRaw = newValue.rawValue }
    }
    
    var displayName: String {
        if let name = name, !name.isEmpty { return name }
        if let city = city { return city }
        return String(localized: "place_type_\(placeTypeRaw)")
    }
}

// MARK: - Lugar Persistido (legacy, kept for compatibility)

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
    var photoIds: String
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
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
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
    var photoIds: String
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
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
    
    var isNamed: Bool { name != nil && !name!.isEmpty }
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

// MARK: - Cataloging Card (for interactive labeling)

@Model
final class PersistedCatalogingCard {
    @Attribute(.unique) var id: String
    var cardTypeRaw: String
    var targetId: String?
    var photoCount: Int
    var createdAt: Date
    var isDismissed: Bool
    var isCompleted: Bool
    var priority: Int
    var detailsJson: String?
    
    init(
        id: String = UUID().uuidString,
        cardType: CatalogingCardType,
        targetId: String? = nil,
        photoCount: Int = 0,
        priority: Int = 0
    ) {
        self.id = id
        self.cardTypeRaw = cardType.rawValue
        self.targetId = targetId
        self.photoCount = photoCount
        self.createdAt = Date()
        self.isDismissed = false
        self.isCompleted = false
        self.priority = priority
    }
    
    var cardType: CatalogingCardType {
        get { CatalogingCardType(rawValue: cardTypeRaw) ?? .unknownPerson }
        set { cardTypeRaw = newValue.rawValue }
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
    var yearsDetected: Int
    var isUserConfirmed: Bool
    
    init(
        id: String = UUID().uuidString,
        typeRaw: String = "unknown",
        personId: String? = nil,
        personName: String? = nil,
        dayOfYear: Int,
        month: Int,
        day: Int,
        confidence: Double = 0,
        yearsDetected: Int = 0
    ) {
        self.id = id
        self.typeRaw = typeRaw
        self.personId = personId
        self.personName = personName
        self.dayOfYear = dayOfYear
        self.month = month
        self.day = day
        self.confidence = confidence
        self.yearsDetected = yearsDetected
        self.isUserConfirmed = false
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
    var workLatitude: Double?
    var workLongitude: Double?
    var workConfidence: Double?
    var version: Int
    
    init(id: String = "main") {
        self.id = id
        self.totalPhotosScanned = 0
        self.totalPhotosAnalyzed = 0
        self.version = 1
    }
}
