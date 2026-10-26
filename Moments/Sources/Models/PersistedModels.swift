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

// MARK: - Protection Reason

enum ProtectionReason: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case favorite = "favorite"
    case edited = "edited"
    case inAlbum = "inAlbum"
    case sharedOrReceived = "sharedOrReceived"
    case onlyPhotoOfDay = "onlyPhotoOfDay"
    case onlyPhotoOfTrip = "onlyPhotoOfTrip"
    case hasNamedPerson = "hasNamedPerson"
    case hidden = "hidden"
    case importantDate = "importantDate"
    case userProtected = "userProtected"
    
    var localizedDescription: String {
        switch self {
        case .none: return ""
        case .favorite: return String(localized: "protection_favorite")
        case .edited: return String(localized: "protection_edited")
        case .inAlbum: return String(localized: "protection_in_album")
        case .sharedOrReceived: return String(localized: "protection_shared")
        case .onlyPhotoOfDay: return String(localized: "protection_only_of_day")
        case .onlyPhotoOfTrip: return String(localized: "protection_only_of_trip")
        case .hasNamedPerson: return String(localized: "protection_named_person")
        case .hidden: return String(localized: "protection_hidden")
        case .importantDate: return String(localized: "protection_important_date")
        case .userProtected: return String(localized: "protection_user_protected")
        }
    }
    
    var iconName: String {
        switch self {
        case .none: return "circle"
        case .favorite: return "heart.fill"
        case .edited: return "paintbrush.fill"
        case .inAlbum: return "rectangle.stack.fill"
        case .sharedOrReceived: return "person.2.fill"
        case .onlyPhotoOfDay: return "calendar"
        case .onlyPhotoOfTrip: return "airplane"
        case .hasNamedPerson: return "person.fill"
        case .hidden: return "eye.slash.fill"
        case .importantDate: return "gift.fill"
        case .userProtected: return "lock.fill"
        }
    }
}

// MARK: - Cleanup Confidence Tier

enum CleanupConfidenceTier: String, Codable, CaseIterable, Sendable {
    case veryLikely = "veryLikely"  // "Muy probable"
    case maybe = "maybe"             // "Quizás"
    
    var localizedKey: String {
        switch self {
        case .veryLikely: return "confidence_very_likely"
        case .maybe: return "confidence_maybe"
        }
    }
    
    var headerText: String {
        switch self {
        case .veryLikely: return String(localized: "cleanup_very_likely_header")
        case .maybe: return String(localized: "cleanup_maybe_header")
        }
    }
}

// MARK: - Similar Group Feedback

enum SimilarGroupFeedback: String, Codable, Sendable {
    case none = "none"
    case confirmed = "confirmed"
    case notSimilar = "notSimilar"
}

// MARK: - Best Shot Reason

enum BestShotReason: String, Codable, CaseIterable, Sendable {
    case sharpest = "sharpest"
    case eyesOpen = "eyesOpen"
    case smile = "smile"
    case bestAesthetics = "bestAesthetics"
    case edited = "edited"
    case favorited = "favorited"
    case highestResolution = "highestResolution"
    case livePhoto = "livePhoto"
    
    var localizedDescription: String {
        switch self {
        case .sharpest: return String(localized: "best_shot_sharpest")
        case .eyesOpen: return String(localized: "best_shot_eyes_open")
        case .smile: return String(localized: "best_shot_smile")
        case .bestAesthetics: return String(localized: "best_shot_aesthetics")
        case .edited: return String(localized: "best_shot_edited")
        case .favorited: return String(localized: "best_shot_favorited")
        case .highestResolution: return String(localized: "best_shot_resolution")
        case .livePhoto: return String(localized: "best_shot_live_photo")
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
    case confirmBirthday = "confirmBirthday"
    case confirmWedding = "confirmWedding"
    case confirmChildRelation = "confirmChildRelation"
    case confirmAnniversary = "confirmAnniversary"
}

// MARK: - Important Date Types

enum ImportantDateType: String, Codable, CaseIterable, Sendable {
    case birthday = "birthday"
    case friendBirthday = "friendBirthday"
    case wedding = "wedding"
    case anniversary = "anniversary"
    case childBirthday = "childBirthday"
    case other = "other"
    
    var localizedKey: String {
        "important_date_type_\(rawValue)"
    }
    
    var iconName: String {
        switch self {
        case .birthday: return "gift.fill"
        case .friendBirthday: return "person.2.fill"
        case .wedding: return "heart.fill"
        case .anniversary: return "heart.circle.fill"
        case .childBirthday: return "figure.and.child.holdinghands"
        case .other: return "calendar"
        }
    }
    
    var notificationEmoji: String {
        switch self {
        case .birthday: return "🎂"
        case .friendBirthday: return "🎁"
        case .wedding: return "💒"
        case .anniversary: return "💑"
        case .childBirthday: return "🎈"
        case .other: return "📅"
        }
    }
}

enum ImportantDateSource: String, Codable, CaseIterable, Sendable {
    case photos = "photos"
    case contacts = "contacts"
    case user = "user"
    
    var localizedKey: String {
        "important_date_source_\(rawValue)"
    }
}

// MARK: - Relationship Type

enum RelationshipType: String, Codable, CaseIterable, Sendable {
    case partner = "partner"
    case spouse = "spouse"
    case child = "child"
    case parent = "parent"
    case sibling = "sibling"
    case friend = "friend"
    case colleague = "colleague"
    case other = "other"
    
    var localizedKey: String {
        "relationship_type_\(rawValue)"
    }
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
    
    // Protection status
    var isProtected: Bool
    var protectionReasonRaw: String?
    var protectionReasons: [String]?
    var isInUserAlbum: Bool
    var isOnlyPhotoOfDay: Bool
    var isEdited: Bool
    var isSharedOrReceived: Bool
    
    // Cleanup confidence
    var cleanupConfidenceTierRaw: String?
    var bestShotReasons: [String]?
    var similarGroupFeedbackRaw: String?
    
    // Live Photo handling
    var isLivePhoto: Bool
    var livePhotoVideoIdentifier: String?
    
    // iCloud status
    var isPendingICloud: Bool
    
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
        self.isProtected = false
        self.protectionReasonRaw = ProtectionReason.none.rawValue
        self.isInUserAlbum = false
        self.isOnlyPhotoOfDay = false
        self.isEdited = false
        self.isSharedOrReceived = false
        self.isLivePhoto = false
        self.isPendingICloud = false
    }
    
    // Computed properties for enums
    var protectionReason: ProtectionReason {
        get { ProtectionReason(rawValue: protectionReasonRaw ?? "none") ?? .none }
        set { protectionReasonRaw = newValue.rawValue }
    }
    
    var cleanupConfidenceTier: CleanupConfidenceTier? {
        get { cleanupConfidenceTierRaw.flatMap { CleanupConfidenceTier(rawValue: $0) } }
        set { cleanupConfidenceTierRaw = newValue?.rawValue }
    }
    
    var similarGroupFeedback: SimilarGroupFeedback {
        get { SimilarGroupFeedback(rawValue: similarGroupFeedbackRaw ?? "none") ?? .none }
        set { similarGroupFeedbackRaw = newValue.rawValue }
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
    var birthYear: Int?
    var isFavorite: Bool
    
    // Relationships
    var partnerId: String?
    var childIds: String?
    var parentIds: String?
    var contactIdentifier: String?
    
    init(
        id: String = UUID().uuidString,
        name: String? = nil,
        faceClusterId: String,
        representativeFacePhotoId: String? = nil,
        photoIds: [String] = [],
        faceCount: Int = 0,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        birthYear: Int? = nil,
        isFavorite: Bool = false,
        partnerId: String? = nil,
        childIds: [String] = [],
        parentIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.faceClusterId = faceClusterId
        self.representativeFacePhotoId = representativeFacePhotoId
        self.photoIds = (try? JSONEncoder().encode(photoIds).base64EncodedString()) ?? "[]"
        self.faceCount = faceCount
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.birthYear = birthYear
        self.isFavorite = isFavorite
        self.partnerId = partnerId
        self.childIds = (try? JSONEncoder().encode(childIds).base64EncodedString()) ?? "[]"
        self.parentIds = (try? JSONEncoder().encode(parentIds).base64EncodedString()) ?? "[]"
    }
    
    var photoIdArray: [String] {
        guard let data = Data(base64Encoded: photoIds),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
    
    var childIdArray: [String] {
        guard let data = Data(base64Encoded: childIds ?? ""),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
    
    var parentIdArray: [String] {
        guard let data = Data(base64Encoded: parentIds ?? ""),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
    
    var isNamed: Bool { name != nil && !name!.isEmpty }
    
    var hasBirthday: Bool { birthdayMonth != nil && birthdayDay != nil }
    
    var birthdayDate: DateComponents? {
        guard let month = birthdayMonth, let day = birthdayDay else { return nil }
        return DateComponents(month: month, day: day)
    }
    
    var currentAge: Int? {
        guard let year = birthYear else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        return currentYear - year
    }
    
    func setChildIds(_ ids: [String]) {
        childIds = (try? JSONEncoder().encode(ids).base64EncodedString()) ?? "[]"
    }
    
    func setParentIds(_ ids: [String]) {
        parentIds = (try? JSONEncoder().encode(ids).base64EncodedString()) ?? "[]"
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

// MARK: - Evento Recurrente Persistido (legacy)

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

// MARK: - Important Date (birthdays, anniversaries, etc.)

@Model
final class PersistedImportantDate {
    @Attribute(.unique) var id: String
    var dateTypeRaw: String
    var sourceRaw: String
    var month: Int
    var day: Int
    var year: Int?
    var personId: String?
    var secondPersonId: String?
    var personName: String?
    var secondPersonName: String?
    var childOfPersonId: String?
    var confidence: Double
    var yearsDetected: Int
    var photoIdsJson: String?
    var isUserConfirmed: Bool
    var isDismissed: Bool
    var notificationEnabled: Bool
    var notificationLeadDays: Int
    var calendarEventId: String?
    var detectedLabels: String?
    var detectedOcrText: String?
    var createdAt: Date
    var lastUpdatedAt: Date
    
    init(
        id: String = UUID().uuidString,
        dateType: ImportantDateType = .birthday,
        source: ImportantDateSource = .photos,
        month: Int,
        day: Int,
        year: Int? = nil,
        personId: String? = nil,
        secondPersonId: String? = nil,
        personName: String? = nil,
        secondPersonName: String? = nil,
        childOfPersonId: String? = nil,
        confidence: Double = 0.0,
        yearsDetected: Int = 0,
        photoIds: [String] = [],
        notificationLeadDays: Int = 3
    ) {
        self.id = id
        self.dateTypeRaw = dateType.rawValue
        self.sourceRaw = source.rawValue
        self.month = month
        self.day = day
        self.year = year
        self.personId = personId
        self.secondPersonId = secondPersonId
        self.personName = personName
        self.secondPersonName = secondPersonName
        self.childOfPersonId = childOfPersonId
        self.confidence = confidence
        self.yearsDetected = yearsDetected
        self.photoIdsJson = (try? JSONEncoder().encode(photoIds).base64EncodedString()) ?? "[]"
        self.isUserConfirmed = false
        self.isDismissed = false
        self.notificationEnabled = false
        self.notificationLeadDays = notificationLeadDays
        self.createdAt = Date()
        self.lastUpdatedAt = Date()
    }
    
    var dateType: ImportantDateType {
        get { ImportantDateType(rawValue: dateTypeRaw) ?? .birthday }
        set { dateTypeRaw = newValue.rawValue }
    }
    
    var source: ImportantDateSource {
        get { ImportantDateSource(rawValue: sourceRaw) ?? .photos }
        set { sourceRaw = newValue.rawValue }
    }
    
    var photoIdArray: [String] {
        guard let data = Data(base64Encoded: photoIdsJson ?? ""),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
    
    func setPhotoIds(_ ids: [String]) {
        photoIdsJson = (try? JSONEncoder().encode(ids).base64EncodedString()) ?? "[]"
    }
    
    var displayDate: String {
        String(format: "%02d/%02d", day, month)
    }
    
    var displayName: String {
        switch dateType {
        case .birthday, .friendBirthday:
            return personName ?? String(localized: "important_date_unknown_person")
        case .wedding, .anniversary:
            if let name1 = personName, let name2 = secondPersonName {
                return "\(name1) y \(name2)"
            }
            return personName ?? String(localized: "important_date_unknown_couple")
        case .childBirthday:
            return personName ?? String(localized: "important_date_unknown_child")
        case .other:
            return personName ?? String(localized: "important_date_event")
        }
    }
    
    var anniversaryYear: Int? {
        guard let eventYear = year else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        return currentYear - eventYear
    }
    
    var nextOccurrence: Date? {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = currentYear
        
        guard let thisYear = calendar.date(from: components) else { return nil }
        
        if thisYear >= now {
            return thisYear
        } else {
            components.year = currentYear + 1
            return calendar.date(from: components)
        }
    }
    
    var daysUntilNext: Int? {
        guard let next = nextOccurrence else { return nil }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let nextDay = calendar.startOfDay(for: next)
        return calendar.dateComponents([.day], from: now, to: nextDay).day
    }
}

// MARK: - Notification Settings

@Model
final class PersistedNotificationSettings {
    @Attribute(.unique) var id: String
    var notificationsEnabled: Bool
    var defaultLeadDays: Int
    var notifyOnDay: Bool
    var notifyBirthdays: Bool
    var notifyAnniversaries: Bool
    var notifyChildBirthdays: Bool
    var lastPermissionRequest: Date?
    
    init(id: String = "main") {
        self.id = id
        self.notificationsEnabled = false
        self.defaultLeadDays = 3
        self.notifyOnDay = true
        self.notifyBirthdays = true
        self.notifyAnniversaries = true
        self.notifyChildBirthdays = true
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
    
    // Resumable indexing
    var lastIndexedPhotoDate: Date?
    var lastIndexedPhotoId: String?
    var indexingInProgress: Bool
    var indexingPausedAt: Date?
    var totalLibraryCount: Int
    var indexedCount: Int
    
    init(id: String = "main") {
        self.id = id
        self.totalPhotosScanned = 0
        self.totalPhotosAnalyzed = 0
        self.version = 1
        self.indexingInProgress = false
        self.totalLibraryCount = 0
        self.indexedCount = 0
    }
}

// MARK: - Remember List Item ("Recordá esto")

@Model
final class RememberListItem {
    @Attribute(.unique) var id: String
    var fact: String
    var category: String
    var personId: String?
    var personName: String?
    var secondPersonId: String?
    var secondPersonName: String?
    var relatedPhotoIds: String?
    var source: String
    var createdAt: Date
    var lastUsedAt: Date?
    var usageCount: Int
    var isUserEdited: Bool
    
    init(
        id: String = UUID().uuidString,
        fact: String,
        category: String = "general",
        personId: String? = nil,
        personName: String? = nil,
        source: String = "cataloging"
    ) {
        self.id = id
        self.fact = fact
        self.category = category
        self.personId = personId
        self.personName = personName
        self.source = source
        self.createdAt = Date()
        self.usageCount = 0
        self.isUserEdited = false
    }
    
    var relatedPhotoIdArray: [String] {
        guard let json = relatedPhotoIds else { return [] }
        return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
}

// MARK: - Pending Trash (Final review before deletion)

@Model
final class PendingTrashItem {
    @Attribute(.unique) var id: String
    var photoId: String
    var localIdentifier: String
    var addedAt: Date
    var sourceCategory: String?
    var previewThumbnailData: Data?
    var estimatedFileSize: Int64
    var isSelected: Bool
    
    init(
        id: String = UUID().uuidString,
        photoId: String,
        localIdentifier: String,
        sourceCategory: String? = nil,
        estimatedFileSize: Int64 = 0
    ) {
        self.id = id
        self.photoId = photoId
        self.localIdentifier = localIdentifier
        self.addedAt = Date()
        self.sourceCategory = sourceCategory
        self.estimatedFileSize = estimatedFileSize
        self.isSelected = true
    }
}

// MARK: - Similar Group

@Model
final class SimilarGroup {
    @Attribute(.unique) var id: String
    var photoIdsJson: String
    var bestPhotoId: String?
    var bestShotReasonsJson: String?
    var feedbackRaw: String
    var createdAt: Date
    var lastUpdatedAt: Date
    var timeWindowStart: Date?
    var timeWindowEnd: Date?
    var averageSimilarity: Double
    
    init(
        id: String = UUID().uuidString,
        photoIds: [String],
        bestPhotoId: String? = nil,
        bestShotReasons: [BestShotReason] = []
    ) {
        self.id = id
        self.photoIdsJson = (try? JSONEncoder().encode(photoIds)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.bestPhotoId = bestPhotoId
        self.bestShotReasonsJson = (try? JSONEncoder().encode(bestShotReasons.map { $0.rawValue })).flatMap { String(data: $0, encoding: .utf8) }
        self.feedbackRaw = SimilarGroupFeedback.none.rawValue
        self.createdAt = Date()
        self.lastUpdatedAt = Date()
        self.averageSimilarity = 0.0
    }
    
    var photoIds: [String] {
        guard let data = photoIdsJson.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    
    var bestShotReasons: [BestShotReason] {
        guard let json = bestShotReasonsJson,
              let data = json.data(using: .utf8),
              let rawValues = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return rawValues.compactMap { BestShotReason(rawValue: $0) }
    }
    
    var feedback: SimilarGroupFeedback {
        get { SimilarGroupFeedback(rawValue: feedbackRaw) ?? .none }
        set { feedbackRaw = newValue.rawValue }
    }
}

// MARK: - Deletion Verification Record

@Model
final class DeletionRecord {
    @Attribute(.unique) var id: String
    var localIdentifier: String
    var requestedAt: Date
    var verifiedAt: Date?
    var wasSuccessful: Bool?
    var photoId: String
    var category: String?
    var fileSize: Int64
    
    init(
        id: String = UUID().uuidString,
        localIdentifier: String,
        photoId: String,
        category: String? = nil,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.photoId = photoId
        self.category = category
        self.fileSize = fileSize
        self.requestedAt = Date()
    }
}
