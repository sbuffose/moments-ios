// TimelineModels.swift
// Modelos para la línea de tiempo y momentos

import Foundation

/// Un momento o evento agrupado
public struct Moment: Codable, Identifiable, Sendable {
    public let id: String
    public var title: String?
    public var subtitle: String?
    public let startDate: Date
    public let endDate: Date
    public let photos: [PhotoMetadata]
    public var coverPhotoId: String?
    public var location: Coordinate?
    public var locationName: String?
    public var isTrip: Bool
    public var tripDestination: String?
    
    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        subtitle: String? = nil,
        startDate: Date,
        endDate: Date,
        photos: [PhotoMetadata],
        coverPhotoId: String? = nil,
        location: Coordinate? = nil,
        locationName: String? = nil,
        isTrip: Bool = false,
        tripDestination: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.startDate = startDate
        self.endDate = endDate
        self.photos = photos
        self.coverPhotoId = coverPhotoId ?? photos.first?.id
        self.location = location
        self.locationName = locationName
        self.isTrip = isTrip
        self.tripDestination = tripDestination
    }
    
    public var photoCount: Int {
        photos.count
    }
    
    public var durationDays: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: startDate, to: endDate)
        return max(1, (components.day ?? 0) + 1)
    }
    
    public var coverPhoto: PhotoMetadata? {
        guard let coverId = coverPhotoId else { return photos.first }
        return photos.first { $0.id == coverId }
    }
    
    /// Genera un título automático basado en la fecha y ubicación
    public func generateTitle(locale: Locale = Locale(identifier: "es_AR")) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        
        if durationDays == 1 {
            formatter.dateFormat = "EEEE d 'de' MMMM"
        } else {
            formatter.dateFormat = "d 'de' MMMM"
        }
        
        if let locationName = locationName {
            return "\(locationName)"
        } else if isTrip, let destination = tripDestination {
            return "Viaje a \(destination)"
        } else {
            return formatter.string(from: startDate)
        }
    }
}

/// Agrupación por año/mes para la línea de tiempo
public struct TimelineSection: Codable, Identifiable, Sendable {
    public let id: String
    public let year: Int
    public let month: Int?
    public let moments: [Moment]
    
    public init(year: Int, month: Int? = nil, moments: [Moment]) {
        self.id = month != nil ? "\(year)-\(month!)" : "\(year)"
        self.year = year
        self.month = month
        self.moments = moments
    }
    
    public var totalPhotos: Int {
        moments.reduce(0) { $0 + $1.photoCount }
    }
    
    public var monthName: String? {
        guard let month = month else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        return formatter.monthSymbols[month - 1].capitalized
    }
}

/// Viaje detectado
public struct Trip: Codable, Identifiable, Sendable {
    public let id: String
    public let destination: String
    public let startDate: Date
    public let endDate: Date
    public let centerLocation: Coordinate
    public let moments: [Moment]
    public let distanceFromHome: Double // en km
    
    public init(
        id: String = UUID().uuidString,
        destination: String,
        startDate: Date,
        endDate: Date,
        centerLocation: Coordinate,
        moments: [Moment],
        distanceFromHome: Double
    ) {
        self.id = id
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.centerLocation = centerLocation
        self.moments = moments
        self.distanceFromHome = distanceFromHome
    }
    
    public var durationDays: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: startDate, to: endDate)
        return max(1, (components.day ?? 0) + 1)
    }
    
    public var totalPhotos: Int {
        moments.reduce(0) { $0 + $1.photoCount }
    }
}
