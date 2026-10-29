// ReviewTagTests.swift
// Trip clustering, persist+keep, and sheet data without PhotoKit albums.

import XCTest
import SwiftData
import CoreLocation
@testable import Moments

final class ReviewTagTests: XCTestCase {
    
    private func calendarDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day, hour: 12)
        )!
    }
    
    func testTripClusteringFromGPSAndDatesFormsTwoNamedTrips() async {
        let home = CLLocation(latitude: -34.6037, longitude: -58.3816)
        let mdq = (lat: -38.0055, lon: -57.5426)
        let cba = (lat: -31.4201, lon: -64.1888)
        
        var photos: [TripPhotoFix] = []
        for day in [2, 8, 15, 22, 28] {
            photos.append(TripPhotoFix(
                id: "home-\(day)",
                date: calendarDate(year: 2025, month: 1, day: day),
                latitude: home.coordinate.latitude,
                longitude: home.coordinate.longitude
            ))
        }
        for day in [10, 12, 14] {
            photos.append(TripPhotoFix(
                id: "mdq-\(day)",
                date: calendarDate(year: 2025, month: 3, day: day),
                latitude: mdq.lat,
                longitude: mdq.lon
            ))
        }
        for day in [3, 5, 7] {
            photos.append(TripPhotoFix(
                id: "cba-\(day)",
                date: calendarDate(year: 2025, month: 7, day: day),
                latitude: cba.lat,
                longitude: cba.lon
            ))
        }
        
        let geocoder = StubReverseGeocoder(places: [
            (mdq.lat, mdq.lon, "Mar del Plata"),
            (cba.lat, cba.lon, "Córdoba"),
            (home.coordinate.latitude, home.coordinate.longitude, "Buenos Aires")
        ])
        
        let trips = await TripClustering.detectTrips(
            photos: photos,
            homeLocations: [home],
            geocoder: geocoder
        )
        
        XCTAssertEqual(trips.count, 2, "Home photos must not form a trip")
        XCTAssertEqual(trips.map(\.title), [
            "Viaje a Mar del Plata · mar 2025",
            "Viaje a Córdoba · jul 2025"
        ])
        XCTAssertEqual(Set(trips[0].photoIds), Set(["mdq-10", "mdq-12", "mdq-14"]))
        XCTAssertEqual(Set(trips[1].photoIds), Set(["cba-3", "cba-5", "cba-7"]))
    }
    
    @MainActor
    func testTaggingPersistsAndMarksPhotoKept() throws {
        let schema = Schema([PersistedPhoto.self, PhotoTag.self, PersistedPerson.self, PersistedPlaceCluster.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let photo = PersistedPhoto(localIdentifier: "tag-keep-1", creationDate: Date())
        photo.analysisCompleted = true
        photo.cleanupCategory = .screenshot
        photo.keepDecision = .none
        context.insert(photo)
        try context.save()
        
        ReviewTagService.apply(
            options: [.familia, .viajes],
            to: [photo],
            context: context
        )
        
        let tags = try context.fetch(FetchDescriptor<PhotoTag>())
        XCTAssertEqual(Set(tags.map(\.id)), Set([ReviewTagOption.familia.id, ReviewTagOption.viajes.id]))
        XCTAssertTrue(tags.allSatisfy { $0.photoIdArray.contains(photo.id) })
        XCTAssertEqual(photo.keepDecision, .forever)
        XCTAssertTrue(photo.isKeptByUser)
        
        let again = try context.fetch(FetchDescriptor<PhotoTag>())
        XCTAssertEqual(again.count, 2, "Re-applying must not duplicate tags")
        ReviewTagService.apply(options: [.familia], to: [photo], context: context)
        XCTAssertEqual((try context.fetch(FetchDescriptor<PhotoTag>())).count, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PhotoTag>()).first { $0.id == ReviewTagOption.familia.id }?.photoIdArray.count,
            1
        )
    }
    
    @MainActor
    func testTagSheetDataHasNoDuplicatesOrPhotoKitAlbums() async throws {
        let schema = Schema([PersistedPhoto.self, PhotoTag.self, PersistedPerson.self, PersistedPlaceCluster.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let homeDate = calendarDate(year: 2025, month: 1, day: 4)
        for index in 1...5 {
            let home = PersistedPhoto(localIdentifier: "sheet-home-\(index)", creationDate: homeDate.addingTimeInterval(Double(index) * 86_400))
            home.analysisCompleted = true
            home.latitude = -34.6037
            home.longitude = -58.3816
            context.insert(home)
        }
        let mdq = PersistedPhoto(
            localIdentifier: "sheet-mdq",
            creationDate: calendarDate(year: 2025, month: 3, day: 12)
        )
        mdq.analysisCompleted = true
        mdq.latitude = -38.0055
        mdq.longitude = -57.5426
        mdq.cleanupCategory = .screenshot
        context.insert(mdq)
        
        let sofia = PersistedPerson(id: "p-sofia", name: "Sofía", faceClusterId: "c-sofia")
        context.insert(sofia)
        let duplicateSofia = PersistedPerson(id: "p-sofia-2", name: "Sofía", faceClusterId: "c-sofia-2")
        context.insert(duplicateSofia)
        context.insert(PersistedPerson(id: "p-wa", name: "WhatsApp", faceClusterId: "c-wa"))
        context.insert(PersistedPerson(id: "p-ig", name: "Instagram", faceClusterId: "c-ig"))
        context.insert(PersistedPerson(id: "p-moments", name: "Moments", faceClusterId: "c-mo"))
        try context.save()
        
        let geocoder = StubReverseGeocoder(places: [
            (-38.0055, -57.5426, "Mar del Plata"),
            (-34.6037, -58.3816, "Buenos Aires")
        ])
        let data = await ReviewTagService.sheetData(
            photos: [mdq],
            context: context,
            geocoder: geocoder
        )
        
        XCTAssertFalse(data.hasDuplicateIds)
        XCTAssertFalse(data.hasDuplicateTitles)
        XCTAssertFalse(data.containsPhotoKitAlbum)
        XCTAssertEqual(data.categories.map(\.title), ["Familia", "Amigos", "Viajes"])
        XCTAssertEqual(data.people.filter { $0.title == "Sofía" }.count, 1)
        XCTAssertFalse(data.titles.contains { ReviewTagSheetData.forbiddenAlbumTitles.contains($0.lowercased()) })
        XCTAssertEqual(data.trips.count, 1)
        XCTAssertEqual(data.trips.first?.title, "Viaje a Mar del Plata · mar 2025")
        XCTAssertTrue(data.trips.first?.isPreselected == true)
        XCTAssertNil(AlbumService.userAlbumTitles().first { data.titles.contains($0) })
    }
}