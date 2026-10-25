// PlaceAnalyzerTests.swift
// Tests para el analizador de lugares

import XCTest
@testable import MomentsEngine

final class PlaceAnalyzerTests: XCTestCase {
    
    var analyzer: PlaceAnalyzer!
    
    override func setUp() {
        super.setUp()
        analyzer = PlaceAnalyzer()
    }
    
    // MARK: - Place Clustering Tests
    
    func testClusterNearbyPhotos() {
        // Fotos muy cercanas (dentro de 200m)
        let photos = [
            createPhoto(id: "1", location: Coordinate(latitude: -34.6037, longitude: -58.3816)),
            createPhoto(id: "2", location: Coordinate(latitude: -34.6038, longitude: -58.3817)),
            createPhoto(id: "3", location: Coordinate(latitude: -34.6036, longitude: -58.3815)),
        ]
        
        let places = analyzer.clusterPlaces(from: photos)
        
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.photoCount, 3)
    }
    
    func testClusterFarPhotosIntoSeparatePlaces() {
        // Buenos Aires
        let ba = Coordinate(latitude: -34.6037, longitude: -58.3816)
        // Córdoba (700 km)
        let cordoba = Coordinate(latitude: -31.4201, longitude: -64.1888)
        
        let photos = [
            createPhoto(id: "1", location: ba),
            createPhoto(id: "2", location: ba),
            createPhoto(id: "3", location: cordoba),
            createPhoto(id: "4", location: cordoba),
        ]
        
        let places = analyzer.clusterPlaces(from: photos)
        
        XCTAssertEqual(places.count, 2)
    }
    
    func testMinimumPhotosForPlace() {
        // Solo 1 foto en una ubicación
        let photos = [
            createPhoto(id: "1", location: Coordinate(latitude: -34.6037, longitude: -58.3816)),
        ]
        
        let places = analyzer.clusterPlaces(from: photos)
        
        XCTAssertEqual(places.count, 0) // Mínimo 2 fotos
    }
    
    // MARK: - Home Detection Tests
    
    func testDetectHomeLocation() {
        // Simular muchas fotos en casa y pocas en otros lugares
        let homeCoord = Coordinate(latitude: -34.6037, longitude: -58.3816)
        
        var photos: [PhotoMetadata] = []
        
        // 50 fotos en casa
        for i in 0..<50 {
            photos.append(createPhoto(
                id: "home_\(i)",
                location: Coordinate(
                    latitude: homeCoord.latitude + Double.random(in: -0.001...0.001),
                    longitude: homeCoord.longitude + Double.random(in: -0.001...0.001)
                )
            ))
        }
        
        // 10 fotos en otros lugares
        for i in 0..<10 {
            photos.append(createPhoto(
                id: "other_\(i)",
                location: Coordinate(
                    latitude: -31.4201 + Double.random(in: -0.1...0.1),
                    longitude: -64.1888 + Double.random(in: -0.1...0.1)
                )
            ))
        }
        
        let home = analyzer.detectHomeLocation(from: photos)
        
        XCTAssertNotNil(home)
        if let home = home {
            XCTAssertEqual(home.coordinate.latitude, homeCoord.latitude, accuracy: 0.01)
            XCTAssertGreaterThan(home.confidence, 0.5)
        }
    }
    
    func testNoHomeDetectionWithFewPhotos() {
        let photos = (0..<5).map { i in
            createPhoto(id: "\(i)", location: Coordinate(latitude: Double(i), longitude: Double(i)))
        }
        
        let home = analyzer.detectHomeLocation(from: photos)
        
        XCTAssertNil(home) // Necesita al menos 10 fotos
    }
    
    // MARK: - Map Clustering Tests
    
    func testClusterForMapAtLowZoom() {
        let places = [
            createPlace(id: "1", coordinate: Coordinate(latitude: -34.6, longitude: -58.3)),
            createPlace(id: "2", coordinate: Coordinate(latitude: -34.61, longitude: -58.31)),
            createPlace(id: "3", coordinate: Coordinate(latitude: -31.4, longitude: -64.1)), // Lejos
        ]
        
        let clusters = analyzer.clusterForMap(places: places, zoomLevel: 5, mapBounds: nil)
        
        // A bajo zoom, los dos primeros deberían agruparse
        XCTAssertEqual(clusters.count, 2)
    }
    
    func testClusterForMapAtHighZoom() {
        let places = [
            createPlace(id: "1", coordinate: Coordinate(latitude: -34.6, longitude: -58.3)),
            createPlace(id: "2", coordinate: Coordinate(latitude: -34.61, longitude: -58.31)),
        ]
        
        let clusters = analyzer.clusterForMap(places: places, zoomLevel: 16, mapBounds: nil)
        
        // A alto zoom, no se agrupan
        XCTAssertEqual(clusters.count, 2)
        XCTAssertTrue(clusters.allSatisfy { $0.places.count == 1 })
    }
    
    func testClusterForMapWithBounds() {
        let places = [
            createPlace(id: "1", coordinate: Coordinate(latitude: 0, longitude: 0)),
            createPlace(id: "2", coordinate: Coordinate(latitude: 0.01, longitude: 0.01)),
            createPlace(id: "3", coordinate: Coordinate(latitude: 50, longitude: 50)), // Fuera de bounds
        ]
        
        let bounds = (minLat: -1.0, maxLat: 1.0, minLon: -1.0, maxLon: 1.0)
        let clusters = analyzer.clusterForMap(places: places, zoomLevel: 10, mapBounds: bounds)
        
        let totalPlacesInClusters = clusters.reduce(0) { $0 + $1.places.count }
        XCTAssertEqual(totalPlacesInClusters, 2) // Solo los dos dentro de bounds
    }
    
    // MARK: - Visit Pattern Analysis Tests
    
    func testAnalyzeVisitPattern() {
        let place = createPlace(id: "1", photoIds: ["1", "2", "3", "4"])
        
        let calendar = Calendar.current
        var date1 = DateComponents()
        date1.year = 2024
        date1.month = 1
        date1.day = 1
        
        var date2 = DateComponents()
        date2.year = 2024
        date2.month = 2
        date2.day = 1
        
        let photos = [
            createPhoto(id: "1", date: calendar.date(from: date1)!),
            createPhoto(id: "2", date: calendar.date(from: date1)!),
            createPhoto(id: "3", date: calendar.date(from: date2)!),
            createPhoto(id: "4", date: calendar.date(from: date2)!),
        ]
        
        let pattern = analyzer.analyzeVisitPattern(for: place, photos: photos)
        
        XCTAssertEqual(pattern.visits.count, 2)
        XCTAssertEqual(pattern.frequency, .monthly)
    }
    
    // MARK: - Coordinate Distance Tests
    
    func testCoordinateDistance() {
        // Buenos Aires a Mar del Plata ~ 400 km
        let ba = Coordinate(latitude: -34.6037, longitude: -58.3816)
        let mdq = Coordinate(latitude: -38.0023, longitude: -57.5575)
        
        let distance = ba.distance(to: mdq) / 1000 // km
        
        XCTAssertEqual(distance, 400, accuracy: 50) // ± 50 km
    }
    
    func testCoordinateDistanceSamePoint() {
        let coord = Coordinate(latitude: -34.6037, longitude: -58.3816)
        
        let distance = coord.distance(to: coord)
        
        XCTAssertEqual(distance, 0, accuracy: 0.1)
    }
    
    // MARK: - Helpers
    
    private func createPhoto(
        id: String,
        location: Coordinate? = nil,
        date: Date = Date()
    ) -> PhotoMetadata {
        PhotoMetadata(
            id: id,
            creationDate: date,
            modificationDate: nil,
            mediaType: .image,
            mediaSubtypes: [],
            pixelWidth: 4032,
            pixelHeight: 3024,
            location: location
        )
    }
    
    private func createPlace(
        id: String,
        coordinate: Coordinate = Coordinate(latitude: 0, longitude: 0),
        photoIds: [String] = []
    ) -> Place {
        Place(
            id: id,
            name: "Test Place",
            coordinate: coordinate,
            photoIds: photoIds
        )
    }
}
