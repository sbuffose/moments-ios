// Build266SurfaceTests.swift
// Regression coverage for the build-266 screen recording: localized
// cleanup names, one library source of truth, day-cover fallback.

import XCTest
import SwiftData
import UIKit
@testable import Moments

final class Build266SurfaceTests: XCTestCase {
    
    func testAllCleanupCategoryDisplayNamesAreLocalizedInEsARAndEn() throws {
        let resources = LocalizationFormatAudit.resourcesDirectoryFromTestFile()
        XCTAssertFalse(CleanupCategoryType.allCases.isEmpty)
        
        for language in ["es-AR", "en"] {
            let stringsURL = resources.appendingPathComponent("\(language).lproj/Localizable.strings")
            XCTAssertTrue(FileManager.default.fileExists(atPath: stringsURL.path), stringsURL.path)
            let dict = try XCTUnwrap(
                NSDictionary(contentsOf: stringsURL) as? [String: String],
                "Could not parse \(language) strings"
            )
            let lproj = Bundle(url: resources.appendingPathComponent("\(language).lproj"))
            
            for category in CleanupCategoryType.allCases {
                let fromFile = try XCTUnwrap(
                    dict[category.localizedKey],
                    "Missing \(category.localizedKey) in \(language)"
                )
                XCTAssertNotEqual(fromFile, category.localizedKey, "\(category.rawValue) \(language) equals its key")
                XCTAssertFalse(
                    fromFile.hasPrefix("cleanup_category_"),
                    "\(category.rawValue) \(language) still has key prefix: \(fromFile)"
                )
                XCTAssertFalse(fromFile.contains("cleanup_category_"))
                
                let displayed = lproj.map { category.displayName(in: $0) } ?? fromFile
                XCTAssertNotEqual(displayed, category.localizedKey, "displayName \(category.rawValue) \(language)")
                XCTAssertFalse(
                    displayed.hasPrefix("cleanup_category_"),
                    "displayName leaked key in \(language): \(displayed)"
                )
                XCTAssertFalse(displayed.contains("_"), "displayName looks like a raw key: \(displayed)")
            }
        }
    }
    
    @MainActor
    func testAsistenteHomeAndSettingsCountsComeFromTheSameService() throws {
        let schema = Schema([PersistedPhoto.self, SimilarGroup.self, LearnedPreferences.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        for index in 1...40 {
            let photo = PersistedPhoto(localIdentifier: "sot-\(index)", creationDate: Date())
            photo.analysisCompleted = true
            photo.cleanupCategory = index <= 30 ? .screenshot : .livePhoto
            photo.deletionLikelihoodScore = 0.8
            photo.estimatedFileSize = index <= 20 ? 1_690_000 : 800_000_000
            photo.isProtected = false
            context.insert(photo)
        }
        try context.save()
        
        let inventory = LibraryInventoryService.snapshot(from: context)
        XCTAssertEqual(inventory.indexedCount, 40)
        XCTAssertEqual(inventory.analyzedCount, 40)
        XCTAssertGreaterThan(inventory.totalReclaimableItems, DailyReviewBatch.size)
        XCTAssertEqual(inventory.todayBatchItems, DailyReviewBatch.size)
        XCTAssertGreaterThan(inventory.totalReclaimableBytes, inventory.todayBatchBytes)
        
        XCTAssertEqual(HomeLibraryCopy.indexedCount(from: inventory), inventory.indexedCount)
        XCTAssertEqual(SettingsLibraryCopy.indexedCount(from: inventory), inventory.indexedCount)
        XCTAssertEqual(AssistantLibraryCopy.todayBatchItems(from: inventory), inventory.todayBatchItems)
        XCTAssertEqual(AssistantLibraryCopy.totalReclaimableItems(from: inventory), inventory.totalReclaimableItems)
        XCTAssertEqual(AssistantLibraryCopy.quickDeleteLimit(from: inventory), DailyReviewBatch.size)
        XCTAssertFalse(AssistantLibraryCopy.offersDeleteAll(from: inventory))
        
        let homeHeadline = HomeLibraryCopy.heroHeadline(from: inventory)
        XCTAssertTrue(homeHeadline.contains("En el lote de hoy"), homeHeadline)
        XCTAssertTrue(homeHeadline.contains("en total podés liberar"), homeHeadline)
        
        let settings = SettingsLibraryCopy.statusText(
            from: inventory,
            isIndexing: false,
            isAnalyzing: false,
            analyzed: inventory.analyzedCount,
            toAnalyze: inventory.indexedCount,
            progress: 1
        )
        XCTAssertEqual(settings, "40 elementos indexados")
        XCTAssertFalse(settings.hasPrefix("0 "), "Settings must show the real indexed count, not 0")
        XCTAssertNotEqual(settings, "0 elementos indexados")
    }
    
    func testMomentCoverFallsBackToARealPhotoFromThatDay() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 11))!
        let other = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 14))!
        
        let oct26 = PersistedPhoto(localIdentifier: "fixture-oct26-cover", creationDate: day)
        oct26.id = "oct26-id"
        let oct20 = PersistedPhoto(localIdentifier: "fixture-oct20-other", creationDate: other)
        oct20.id = "oct20-id"
        
        let cover = PhotoIdentifierResolver.coverLocalIdentifier(
            storedCover: "missing-uuid",
            photoIds: ["oct26-id"],
            startDate: day,
            endDate: day,
            photos: [oct26, oct20]
        )
        XCTAssertEqual(cover, "fixture-oct26-cover")
        
        let dayFallback = PhotoIdentifierResolver.fallbackCoverForDay(
            startDate: day,
            endDate: day,
            photos: [oct20, oct26]
        )
        XCTAssertEqual(dayFallback, "fixture-oct26-cover")
    }
    
    @MainActor
    func testThumbnailCacheKeepsDegradedImage() {
        let image = UIImage(systemName: "photo") ?? UIImage()
        ThumbnailCache.shared.store(image, for: "cache-keep")
        XCTAssertNotNil(ThumbnailCache.shared.cachedImage(for: "cache-keep"))
    }
    
    @MainActor
    func testBlackFrameFixtureLeadsTheDailyReviewQueue() throws {
        let schema = Schema([PersistedPhoto.self, SimilarGroup.self, LearnedPreferences.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let best = PersistedPhoto(localIdentifier: "dup-best", creationDate: Date())
        best.analysisCompleted = true
        best.cleanupCategory = .duplicate
        best.deletionLikelihoodScore = 0.20
        best.isBestInGroup = true
        context.insert(best)
        let copy = PersistedPhoto(localIdentifier: "dup-copy", creationDate: Date())
        copy.analysisCompleted = true
        copy.cleanupCategory = .duplicate
        copy.deletionLikelihoodScore = 0.88
        context.insert(copy)
        let group = SimilarGroup(id: "dup-group", photoIds: [best.id, copy.id], bestPhotoId: best.id)
        group.isExactDuplicate = true
        context.insert(group)
        
        let black = PersistedPhoto(localIdentifier: "fixture-black-frame-1", creationDate: Date())
        black.analysisCompleted = true
        black.cleanupCategory = .underexposed
        black.deletionLikelihoodScore = 0.99
        black.exposureScore = 0.01
        black.keepDecision = .forever
        context.insert(black)
        try context.save()
        
        black.keepDecision = .none
        black.exposureScore = 0.01
        black.deletionLikelihoodScore = 0.99
        try context.save()
        
        XCTAssertEqual(
            PhotoLuminanceClass.classify(meanLuminance: black.exposureScore ?? 1),
            .blackFrame
        )
        
        let photos = try context.fetch(FetchDescriptor<PersistedPhoto>())
        let groups = try context.fetch(FetchDescriptor<SimilarGroup>())
        let queue = CleanupViewModel.makeQueue(photos: photos, groups: groups)
        let capped = DailyReviewBatch.cap(queue)
        XCTAssertFalse(capped.batch.isEmpty)
        guard case .single(let first) = capped.batch.first else {
            return XCTFail("Black-frame single must lead the daily batch, not a group")
        }
        XCTAssertEqual(first.localIdentifier, "fixture-black-frame-1")
        XCTAssertEqual(
            PhotoLuminanceClass.classify(meanLuminance: first.exposureScore ?? 1),
            .blackFrame
        )
    }
}
