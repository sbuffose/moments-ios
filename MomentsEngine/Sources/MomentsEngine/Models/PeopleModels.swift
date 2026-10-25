// PeopleModels.swift
// Modelos para personas y detección de rostros

import Foundation

/// Una persona identificada por clustering de rostros
public struct Person: Codable, Identifiable, Sendable {
    public let id: String
    public var name: String?
    public var isNamed: Bool { name != nil && !name!.isEmpty }
    public let faceClusterId: String
    public let representativeFacePhotoId: String?
    public let photoIds: [String]
    public let faceCount: Int
    public var birthday: DateComponents?
    public var isFavorite: Bool
    
    public init(
        id: String = UUID().uuidString,
        name: String? = nil,
        faceClusterId: String,
        representativeFacePhotoId: String? = nil,
        photoIds: [String],
        faceCount: Int,
        birthday: DateComponents? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.faceClusterId = faceClusterId
        self.representativeFacePhotoId = representativeFacePhotoId
        self.photoIds = photoIds
        self.faceCount = faceCount
        self.birthday = birthday
        self.isFavorite = isFavorite
    }
    
    public var photoCount: Int {
        photoIds.count
    }
    
    public var displayName: String {
        name ?? "Persona sin nombre"
    }
}

/// Cluster de rostros (agrupación por similitud)
public struct FaceCluster: Codable, Identifiable, Sendable {
    public let id: String
    public let centroidFeaturePrint: [Double]
    public let faceIds: [String]
    public let photoIds: [String]
    
    public init(
        id: String = UUID().uuidString,
        centroidFeaturePrint: [Double],
        faceIds: [String],
        photoIds: [String]
    ) {
        self.id = id
        self.centroidFeaturePrint = centroidFeaturePrint
        self.faceIds = faceIds
        self.photoIds = photoIds
    }
}

/// Detección de un rostro individual
public struct FaceDetection: Codable, Identifiable, Sendable {
    public let id: String
    public let photoId: String
    public let boundingBox: BoundingBox
    public let featurePrint: [Double]
    public let quality: Double // 0.0 - 1.0
    public var clusterId: String?
    
    public init(
        id: String = UUID().uuidString,
        photoId: String,
        boundingBox: BoundingBox,
        featurePrint: [Double],
        quality: Double,
        clusterId: String? = nil
    ) {
        self.id = id
        self.photoId = photoId
        self.boundingBox = boundingBox
        self.featurePrint = featurePrint
        self.quality = quality
        self.clusterId = clusterId
    }
}

/// Bounding box normalizado (0-1)
public struct BoundingBox: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    public var center: (x: Double, y: Double) {
        (x + width / 2, y + height / 2)
    }
    
    public var area: Double {
        width * height
    }
}

/// Evento recurrente detectado
public struct RecurringEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let type: RecurringEventType
    public let personId: String?
    public let personName: String?
    public let dayOfYear: Int // 1-366
    public let month: Int // 1-12
    public let day: Int // 1-31
    public let occurrences: [RecurringEventOccurrence]
    public let confidence: Double
    
    public init(
        id: String = UUID().uuidString,
        type: RecurringEventType,
        personId: String? = nil,
        personName: String? = nil,
        dayOfYear: Int,
        month: Int,
        day: Int,
        occurrences: [RecurringEventOccurrence],
        confidence: Double
    ) {
        self.id = id
        self.type = type
        self.personId = personId
        self.personName = personName
        self.dayOfYear = dayOfYear
        self.month = month
        self.day = day
        self.occurrences = occurrences
        self.confidence = confidence
    }
    
    public var yearsDetected: Int {
        occurrences.count
    }
    
    public var displayTitle: String {
        switch type {
        case .birthday:
            if let name = personName {
                return "Cumpleaños de \(name)"
            }
            return "Cumpleaños"
        case .anniversary:
            return "Aniversario"
        case .holiday:
            return "Festivo"
        case .annualEvent:
            return "Evento anual"
        case .unknown:
            return "Evento recurrente"
        }
    }
    
    /// Fecha del próximo evento
    public func nextOccurrence(from date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = calendar.component(.year, from: date)
        
        guard var nextDate = calendar.date(from: components) else { return nil }
        
        if nextDate <= date {
            components.year = (components.year ?? 0) + 1
            nextDate = calendar.date(from: components) ?? nextDate
        }
        
        return nextDate
    }
    
    /// Días hasta el próximo evento
    public func daysUntilNext(from date: Date = Date()) -> Int? {
        guard let next = nextOccurrence(from: date) else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date, to: next)
        return components.day
    }
}

public enum RecurringEventType: String, Codable, Sendable {
    case birthday
    case anniversary
    case holiday
    case annualEvent
    case unknown
}

/// Una ocurrencia de un evento recurrente
public struct RecurringEventOccurrence: Codable, Identifiable, Sendable {
    public let id: String
    public let year: Int
    public let date: Date
    public let photoIds: [String]
    public let hasPartyIndicators: Bool // torta, decoraciones, etc.
    
    public init(
        id: String = UUID().uuidString,
        year: Int,
        date: Date,
        photoIds: [String],
        hasPartyIndicators: Bool = false
    ) {
        self.id = id
        self.year = year
        self.date = date
        self.photoIds = photoIds
        self.hasPartyIndicators = hasPartyIndicators
    }
}

/// Memoria "En este día"
public struct OnThisDayMemory: Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let yearsAgo: Int
    public let photos: [PhotoMetadata]
    public let moment: Moment?
    public let relatedPeople: [Person]
    
    public init(
        id: String = UUID().uuidString,
        date: Date,
        yearsAgo: Int,
        photos: [PhotoMetadata],
        moment: Moment? = nil,
        relatedPeople: [Person] = []
    ) {
        self.id = id
        self.date = date
        self.yearsAgo = yearsAgo
        self.photos = photos
        self.moment = moment
        self.relatedPeople = relatedPeople
    }
    
    public var title: String {
        if yearsAgo == 1 {
            return "Hace 1 año"
        } else {
            return "Hace \(yearsAgo) años"
        }
    }
}
