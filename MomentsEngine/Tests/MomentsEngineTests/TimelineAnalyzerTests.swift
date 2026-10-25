// TimelineAnalyzerTests.swift
// Tests para el analizador de línea de tiempo

import XCTest
@testable import MomentsEngine

final class TimelineAnalyzerTests: XCTestCase {
    
    var analyzer: TimelineAnalyzer!
    
    override func setUp() {
        super.setUp()
        analyzer = TimelineAnalyzer()
    }
    
    // MARK: - Moment Generation Tests
    
    func testGenerateMomentsFromPhotos() {
        let baseDate = Date()
        let photos = [
            createPhoto(id: "1", date: baseDate),
            createPhoto(id: "2", date: baseDate.addingTimeInterval(3600)), // 1 hora después
            createPhoto(id: "3", date: baseDate.addingTimeInterval(7200)), // 2 horas después
            createPhoto(id: "4", date: baseDate.addingTimeInterval(86400)), // 1 día después
            createPhoto(id: "5", date: baseDate.addingTimeInterval(90000)), // 25 horas después
            createPhoto(id: "6", date: baseDate.addingTimeInterval(93600)), // 26 horas después
        ]
        
        let moments = analyzer.generateMoments(from: photos)
        
        XCTAssertEqual(moments.count, 2)
        XCTAssertEqual(moments[0].photos.count, 3)
        XCTAssertEqual(moments[1].photos.count, 3)
    }
    
    func testMomentSplitByDistance() {
        let baseDate = Date()
        // Buenos Aires
        let location1 = Coordinate(latitude: -34.6037, longitude: -58.3816)
        // Mar del Plata (400 km)
        let location2 = Coordinate(latitude: -38.0023, longitude: -57.5575)
        
        let photos = [
            createPhoto(id: "1", date: baseDate, location: location1),
            createPhoto(id: "2", date: baseDate.addingTimeInterval(3600), location: location1),
            createPhoto(id: "3", date: baseDate.addingTimeInterval(7200), location: location1),
            createPhoto(id: "4", date: baseDate.addingTimeInterval(10800), location: location2), // Lejos
            createPhoto(id: "5", date: baseDate.addingTimeInterval(14400), location: location2),
            createPhoto(id: "6", date: baseDate.addingTimeInterval(18000), location: location2),
        ]
        
        let moments = analyzer.generateMoments(from: photos)
        
        XCTAssertEqual(moments.count, 2)
    }
    
    func testMinimumPhotosPerMoment() {
        let baseDate = Date()
        let photos = [
            createPhoto(id: "1", date: baseDate),
            createPhoto(id: "2", date: baseDate.addingTimeInterval(3600)),
            // Solo 2 fotos - no debería crear momento (mínimo es 3)
        ]
        
        let moments = analyzer.generateMoments(from: photos)
        
        XCTAssertEqual(moments.count, 0)
    }
    
    // MARK: - Trip Detection Tests
    
    func testDetectTrip() {
        let baseDate = Date()
        let homeLocation = HomeLocation(
            coordinate: Coordinate(latitude: -34.6037, longitude: -58.3816), // Buenos Aires
            confidence: 0.8,
            photoCount: 100
        )
        
        // Fotos en Mar del Plata (viaje)
        let tripLocation = Coordinate(latitude: -38.0023, longitude: -57.5575)
        
        let photos = (0..<10).map { i in
            createPhoto(
                id: "\(i)",
                date: baseDate.addingTimeInterval(Double(i) * 3600),
                location: tripLocation
            )
        }
        
        var config = TimelineAnalyzer.Configuration()
        config.minimumPhotosPerMoment = 3
        analyzer = TimelineAnalyzer(configuration: config)
        
        let moments = analyzer.generateMoments(from: photos)
        let trips = analyzer.detectTrips(moments: moments, homeLocation: homeLocation)
        
        XCTAssertGreaterThan(trips.count, 0)
        if let trip = trips.first {
            XCTAssertGreaterThan(trip.distanceFromHome, 50) // Más de 50 km
        }
    }
    
    // MARK: - Timeline Sections Tests
    
    func testCreateTimelineSections() {
        let calendar = Calendar.current
        var dateComponents = DateComponents()
        dateComponents.year = 2024
        dateComponents.month = 6
        dateComponents.day = 15
        let date1 = calendar.date(from: dateComponents)!
        
        dateComponents.month = 7
        let date2 = calendar.date(from: dateComponents)!
        
        dateComponents.year = 2023
        let date3 = calendar.date(from: dateComponents)!
        
        let moments = [
            createMoment(id: "1", startDate: date1),
            createMoment(id: "2", startDate: date2),
            createMoment(id: "3", startDate: date3),
        ]
        
        let sections = analyzer.createTimelineSections(from: moments)
        
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.first?.year, 2024) // Más reciente primero
    }
    
    // MARK: - Cover Photo Selection Tests
    
    func testSelectCoverPhotoPrefersFaces() {
        let photos = [
            createPhoto(id: "1", sharpnessScore: 0.9, facesDetected: 0),
            createPhoto(id: "2", sharpnessScore: 0.7, facesDetected: 2),
            createPhoto(id: "3", sharpnessScore: 0.8, facesDetected: 1),
        ]
        
        let cover = analyzer.selectCoverPhoto(from: photos)
        
        // Debería preferir la foto con rostros
        XCTAssertEqual(cover?.id, "2")
    }
    
    func testSelectCoverPhotoFallsBackToQuality() {
        let photos = [
            createPhoto(id: "1", sharpnessScore: 0.9),
            createPhoto(id: "2", sharpnessScore: 0.5),
            createPhoto(id: "3", sharpnessScore: 0.7),
        ]
        
        let cover = analyzer.selectCoverPhoto(from: photos)
        
        XCTAssertEqual(cover?.id, "1")
    }
    
    // MARK: - Central Location Calculation Tests
    
    func testCalculateCentralLocation() {
        let photos = [
            createPhoto(id: "1", location: Coordinate(latitude: 0, longitude: 0)),
            createPhoto(id: "2", location: Coordinate(latitude: 2, longitude: 2)),
            createPhoto(id: "3", location: Coordinate(latitude: 1, longitude: 1)),
        ]
        
        let center = analyzer.calculateCentralLocation(from: photos)
        
        XCTAssertNotNil(center)
        XCTAssertEqual(center?.latitude, 1.0, accuracy: 0.01)
        XCTAssertEqual(center?.longitude, 1.0, accuracy: 0.01)
    }
    
    func testCalculateCentralLocationWithNoLocations() {
        let photos = [
            createPhoto(id: "1"),
            createPhoto(id: "2"),
        ]
        
        let center = analyzer.calculateCentralLocation(from: photos)
        
        XCTAssertNil(center)
    }
    
    // MARK: - Helpers
    
    private func createPhoto(
        id: String,
        date: Date = Date(),
        location: Coordinate? = nil,
        sharpnessScore: Double? = nil,
        facesDetected: Int? = nil
    ) -> PhotoMetadata {
        PhotoMetadata(
            id: id,
            creationDate: date,
            modificationDate: nil,
            mediaType: .image,
            mediaSubtypes: [],
            pixelWidth: 4032,
            pixelHeight: 3024,
            location: location,
            sharpnessScore: sharpnessScore,
            facesDetected: facesDetected
        )
    }
    
    private func createMoment(id: String, startDate: Date) -> Moment {
        Moment(
            id: id,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            photos: []
        )
    }
}
