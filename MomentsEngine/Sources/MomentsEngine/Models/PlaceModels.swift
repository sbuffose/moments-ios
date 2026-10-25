// PlaceModels.swift
// Modelos para lugares y ubicaciones

import Foundation

/// Un lugar visitado con fotos
public struct Place: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var address: String?
    public var city: String?
    public var country: String?
    public let coordinate: Coordinate
    public let radius: Double // metros
    public let photoIds: [String]
    public let firstVisit: Date?
    public let lastVisit: Date?
    public let visitCount: Int
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        address: String? = nil,
        city: String? = nil,
        country: String? = nil,
        coordinate: Coordinate,
        radius: Double = 100,
        photoIds: [String],
        firstVisit: Date? = nil,
        lastVisit: Date? = nil,
        visitCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.country = country
        self.coordinate = coordinate
        self.radius = radius
        self.photoIds = photoIds
        self.firstVisit = firstVisit
        self.lastVisit = lastVisit
        self.visitCount = visitCount
    }
    
    public var photoCount: Int {
        photoIds.count
    }
    
    public var displayName: String {
        if !name.isEmpty {
            return name
        } else if let city = city {
            return city
        } else if let country = country {
            return country
        } else {
            return "Ubicación desconocida"
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.id == rhs.id
    }
}

/// Cluster de ubicaciones en el mapa
public struct PlaceCluster: Identifiable, Sendable {
    public let id: String
    public let coordinate: Coordinate
    public let places: [Place]
    
    public init(id: String = UUID().uuidString, coordinate: Coordinate, places: [Place]) {
        self.id = id
        self.coordinate = coordinate
        self.places = places
    }
    
    public var photoCount: Int {
        places.reduce(0) { $0 + $1.photoCount }
    }
    
    public var placeCount: Int {
        places.count
    }
}

/// Ubicación del hogar (calculada)
public struct HomeLocation: Codable, Sendable {
    public let coordinate: Coordinate
    public let confidence: Double // 0.0 - 1.0
    public let photoCount: Int
    
    public init(coordinate: Coordinate, confidence: Double, photoCount: Int) {
        self.coordinate = coordinate
        self.confidence = confidence
        self.photoCount = photoCount
    }
}
