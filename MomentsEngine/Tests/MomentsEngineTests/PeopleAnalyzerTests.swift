// PeopleAnalyzerTests.swift
// Tests para el analizador de personas

import XCTest
@testable import MomentsEngine

final class PeopleAnalyzerTests: XCTestCase {
    
    var analyzer: PeopleAnalyzer!
    
    override func setUp() {
        super.setUp()
        analyzer = PeopleAnalyzer()
    }
    
    // MARK: - Face Clustering Tests
    
    func testClusterSimilarFaces() {
        // Crear detecciones con feature prints similares
        let basePrint = [0.5, 0.5, 0.5, 0.5, 0.5]
        
        let detections = [
            createFaceDetection(id: "1", photoId: "p1", featurePrint: basePrint),
            createFaceDetection(id: "2", photoId: "p2", featurePrint: basePrint.map { $0 + 0.01 }),
            createFaceDetection(id: "3", photoId: "p3", featurePrint: basePrint.map { $0 - 0.01 }),
            // Este es diferente
            createFaceDetection(id: "4", photoId: "p4", featurePrint: [-0.5, -0.5, -0.5, -0.5, -0.5]),
            createFaceDetection(id: "5", photoId: "p5", featurePrint: [-0.5, -0.5, -0.5, -0.5, -0.5]),
            createFaceDetection(id: "6", photoId: "p6", featurePrint: [-0.5, -0.5, -0.5, -0.5, -0.5]),
        ]
        
        let clusters = analyzer.clusterFaces(detections: detections)
        
        XCTAssertEqual(clusters.count, 2)
    }
    
    func testMinimumFacesForCluster() {
        let detections = [
            createFaceDetection(id: "1", photoId: "p1", featurePrint: [0.5, 0.5]),
            createFaceDetection(id: "2", photoId: "p2", featurePrint: [0.5, 0.5]),
            // Solo 2 detecciones similares, mínimo es 3
        ]
        
        let clusters = analyzer.clusterFaces(detections: detections)
        
        XCTAssertEqual(clusters.count, 0)
    }
    
    // MARK: - Person Creation Tests
    
    func testCreatePeopleFromClusters() {
        let clusters = [
            FaceCluster(
                id: "c1",
                centroidFeaturePrint: [0.5, 0.5],
                faceIds: ["f1", "f2", "f3"],
                photoIds: ["p1", "p2", "p3"]
            ),
            FaceCluster(
                id: "c2",
                centroidFeaturePrint: [-0.5, -0.5],
                faceIds: ["f4", "f5", "f6", "f7"],
                photoIds: ["p4", "p5", "p6", "p7"]
            ),
        ]
        
        let people = analyzer.createPeople(from: clusters)
        
        XCTAssertEqual(people.count, 2)
        XCTAssertEqual(people[0].photoCount, 3)
        XCTAssertEqual(people[1].photoCount, 4)
        XCTAssertFalse(people[0].isNamed)
    }
    
    // MARK: - Face Assignment Tests
    
    func testAssignNewFaceToExistingCluster() {
        let clusters = [
            FaceCluster(
                id: "c1",
                centroidFeaturePrint: [0.5, 0.5, 0.5],
                faceIds: ["f1"],
                photoIds: ["p1"]
            ),
        ]
        
        let newFace = createFaceDetection(
            id: "new",
            photoId: "pNew",
            featurePrint: [0.51, 0.51, 0.51] // Similar
        )
        
        let assignedCluster = analyzer.assignToCluster(detection: newFace, clusters: clusters)
        
        XCTAssertEqual(assignedCluster, "c1")
    }
    
    func testNoAssignmentForDissimilarFace() {
        let clusters = [
            FaceCluster(
                id: "c1",
                centroidFeaturePrint: [0.5, 0.5, 0.5],
                faceIds: ["f1"],
                photoIds: ["p1"]
            ),
        ]
        
        let newFace = createFaceDetection(
            id: "new",
            photoId: "pNew",
            featurePrint: [-0.5, -0.5, -0.5] // Muy diferente
        )
        
        let assignedCluster = analyzer.assignToCluster(detection: newFace, clusters: clusters)
        
        XCTAssertNil(assignedCluster)
    }
    
    // MARK: - Recurring Event Detection Tests
    
    func testDetectRecurringBirthday() {
        let calendar = Calendar.current
        
        // Crear fotos del 15 de marzo en múltiples años
        var photos: [PhotoMetadata] = []
        for year in 2020...2024 {
            var components = DateComponents()
            components.year = year
            components.month = 3
            components.day = 15
            let date = calendar.date(from: components)!
            
            photos.append(createPhoto(id: "photo_\(year)", date: date))
        }
        
        let person = Person(
            id: "p1",
            name: "Juan",
            faceClusterId: "c1",
            photoIds: photos.map { $0.id },
            faceCount: 5
        )
        
        let events = analyzer.detectRecurringEvents(person: person, photos: photos)
        
        XCTAssertGreaterThan(events.count, 0)
        if let birthday = events.first {
            XCTAssertEqual(birthday.month, 3)
            XCTAssertEqual(birthday.day, 15)
            XCTAssertGreaterThanOrEqual(birthday.occurrences.count, 2)
        }
    }
    
    // MARK: - On This Day Tests
    
    func testGenerateOnThisDayMemories() {
        let calendar = Calendar.current
        let today = Date()
        let todayComponents = calendar.dateComponents([.month, .day], from: today)
        
        // Crear fotos de años anteriores en el mismo día
        var photos: [PhotoMetadata] = []
        for yearsAgo in 1...3 {
            var components = DateComponents()
            components.year = calendar.component(.year, from: today) - yearsAgo
            components.month = todayComponents.month
            components.day = todayComponents.day
            let date = calendar.date(from: components)!
            
            photos.append(createPhoto(id: "photo_\(yearsAgo)", date: date))
        }
        
        let memories = analyzer.generateOnThisDayMemories(
            for: today,
            photos: photos,
            moments: [],
            people: []
        )
        
        XCTAssertEqual(memories.count, 3)
        XCTAssertEqual(memories[0].yearsAgo, 1)
        XCTAssertEqual(memories[1].yearsAgo, 2)
        XCTAssertEqual(memories[2].yearsAgo, 3)
    }
    
    // MARK: - Upcoming Birthdays Tests
    
    func testUpcomingBirthdays() {
        let calendar = Calendar.current
        let today = Date()
        
        // Evento en 5 días
        var futureComponents = calendar.dateComponents([.year, .month, .day], from: today)
        if let day = futureComponents.day {
            futureComponents.day = day + 5
        }
        let futureDate = calendar.date(from: futureComponents) ?? today
        let futureComps = calendar.dateComponents([.month, .day], from: futureDate)
        
        let events = [
            RecurringEvent(
                id: "e1",
                type: .birthday,
                personId: "p1",
                personName: "Juan",
                dayOfYear: calendar.ordinality(of: .day, in: .year, for: futureDate) ?? 1,
                month: futureComps.month ?? 1,
                day: futureComps.day ?? 1,
                occurrences: [],
                confidence: 0.9
            ),
        ]
        
        let upcoming = analyzer.upcomingBirthdays(events: events, withinDays: 30)
        
        XCTAssertEqual(upcoming.count, 1)
        if let first = upcoming.first, let expected = events[0].daysUntilNext(from: Date()) {
            // daysUntilNext uses calendar day components, so a 5-day offset
            // from "now" can be 4 when the target is midnight.
            XCTAssertEqual(first.daysUntil, expected)
            XCTAssertGreaterThan(expected, 0)
            XCTAssertLessThanOrEqual(expected, 30)
        }
    }
    
    // MARK: - Helpers
    
    private func createFaceDetection(
        id: String,
        photoId: String,
        featurePrint: [Double]
    ) -> FaceDetection {
        FaceDetection(
            id: id,
            photoId: photoId,
            boundingBox: BoundingBox(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            featurePrint: featurePrint,
            quality: 0.8
        )
    }
    
    private func createPhoto(
        id: String,
        date: Date = Date()
    ) -> PhotoMetadata {
        PhotoMetadata(
            id: id,
            creationDate: date,
            modificationDate: nil,
            mediaType: .image,
            mediaSubtypes: [],
            pixelWidth: 4032,
            pixelHeight: 3024
        )
    }
}
