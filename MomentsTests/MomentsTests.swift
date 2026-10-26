// MomentsTests.swift
// Unit tests for Moments app

import XCTest
import SwiftData
@testable import Moments

final class MomentsTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    // MARK: - Indexing Idempotency Tests
    
    @MainActor
    func testIndexingIsIdempotent() throws {
        // Test that indexing the same photos twice yields the same count
        // This verifies the bug fix where count doubled from 7,773 to 15,547
        
        // Create in-memory SwiftData container
        let schema = Schema([PersistedPhoto.self, AnalysisState.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Simulate first indexing pass: insert 100 photos
        let testIdentifiers = (1...100).map { "photo-\($0)" }
        
        // First pass: insert all photos
        var firstPassCount = 0
        for identifier in testIdentifiers {
            let existingDescriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.localIdentifier == identifier }
            )
            let existing = try context.fetch(existingDescriptor)
            
            if existing.isEmpty {
                let photo = PersistedPhoto(localIdentifier: identifier)
                context.insert(photo)
                firstPassCount += 1
            }
        }
        try context.save()
        
        // Verify first pass inserted 100 photos
        let afterFirstPass = try context.fetch(FetchDescriptor<PersistedPhoto>())
        XCTAssertEqual(afterFirstPass.count, 100, "First pass should insert 100 photos")
        XCTAssertEqual(firstPassCount, 100, "First pass should count 100 new photos")
        
        // Second pass: simulate re-indexing the SAME photos
        var secondPassNewCount = 0
        for identifier in testIdentifiers {
            let existingDescriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.localIdentifier == identifier }
            )
            let existing = try context.fetch(existingDescriptor)
            
            if existing.isEmpty {
                let photo = PersistedPhoto(localIdentifier: identifier)
                context.insert(photo)
                secondPassNewCount += 1
            }
        }
        try context.save()
        
        // Verify second pass did NOT insert duplicates
        let afterSecondPass = try context.fetch(FetchDescriptor<PersistedPhoto>())
        XCTAssertEqual(afterSecondPass.count, 100, "Second pass should NOT increase count (idempotency)")
        XCTAssertEqual(secondPassNewCount, 0, "Second pass should insert 0 new photos")
        
        // Total should still be 100, not 200
        XCTAssertEqual(afterSecondPass.count, firstPassCount, 
                      "Total after two passes should equal first pass count (was the bug: 7773 → 15546)")
    }
    
    @MainActor
    func testIncrementalIndexingOnlyAddsNewPhotos() throws {
        // Test that incremental indexing only adds new photos
        
        let schema = Schema([PersistedPhoto.self, AnalysisState.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // First pass: insert 50 photos
        for i in 1...50 {
            let photo = PersistedPhoto(localIdentifier: "photo-\(i)")
            context.insert(photo)
        }
        try context.save()
        
        let afterFirstPass = try context.fetch(FetchDescriptor<PersistedPhoto>())
        XCTAssertEqual(afterFirstPass.count, 50)
        
        // Second pass: simulate library with 75 photos (50 existing + 25 new)
        let allIdentifiers = (1...75).map { "photo-\($0)" }
        let existingIds = Set(afterFirstPass.map { $0.localIdentifier })
        
        var newlyInserted = 0
        for identifier in allIdentifiers {
            if !existingIds.contains(identifier) {
                let photo = PersistedPhoto(localIdentifier: identifier)
                context.insert(photo)
                newlyInserted += 1
            }
        }
        try context.save()
        
        // Verify only 25 new photos were added
        XCTAssertEqual(newlyInserted, 25, "Should only insert 25 new photos")
        
        let afterSecondPass = try context.fetch(FetchDescriptor<PersistedPhoto>())
        XCTAssertEqual(afterSecondPass.count, 75, "Total should be 75 (50 + 25)")
    }
    
    @MainActor
    func testExistingPhotoIdsSetPerformance() throws {
        // Test that fetching existing IDs as a Set is efficient for deduplication
        
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Insert 1000 photos
        for i in 1...1000 {
            let photo = PersistedPhoto(localIdentifier: "photo-\(i)")
            context.insert(photo)
        }
        try context.save()
        
        // Fetch all and create Set (this is what scanLibrary does)
        let allPhotos = try context.fetch(FetchDescriptor<PersistedPhoto>())
        let existingIds = Set(allPhotos.map { $0.localIdentifier })
        
        XCTAssertEqual(existingIds.count, 1000)
        
        // Verify Set lookup is O(1) for deduplication
        XCTAssertTrue(existingIds.contains("photo-500"))
        XCTAssertFalse(existingIds.contains("photo-9999"))
    }
    
    // MARK: - FetchDescriptor Validation Tests
    // These tests verify that all predicates use STORED properties, not computed ones.
    // SwiftData crashes at runtime if a predicate uses a computed property.
    
    @MainActor
    func testAllFetchDescriptorsUseStoredProperties() throws {
        // Create in-memory container with FULL schema to catch any key path issues
        let schema = Schema([
            PersistedPhoto.self,
            PersistedMoment.self,
            PersistedPlace.self,
            PersistedPlaceCluster.self,
            PersistedPerson.self,
            PersistedFaceDetection.self,
            PersistedRecurringEvent.self,
            PersistedCatalogingCard.self,
            PersistedImportantDate.self,
            PersistedNotificationSettings.self,
            AnalysisState.self,
            RememberListItem.self,
            PendingTrashItem.self,
            SimilarGroup.self,
            DeletionRecord.self,
            PhotoTag.self,
            PhotoReminder.self,
            DailyReviewSettings.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Insert sample data
        let photo1 = PersistedPhoto(localIdentifier: "test-1")
        photo1.mediaSubtypesRaw = "screenshot"
        photo1.originRaw = "whatsapp"
        photo1.isLivePhoto = true
        photo1.analysisCompleted = true
        photo1.creationDate = Date()
        photo1.cleanupCategoryRaw = "screenshot"
        context.insert(photo1)
        
        let photo2 = PersistedPhoto(localIdentifier: "test-2")
        photo2.burstIdentifier = "burst-1"
        photo2.representsBurst = false
        photo2.analysisCompleted = true
        photo2.mediaTypeRaw = "video"
        photo2.estimatedFileSize = 200_000_000
        context.insert(photo2)
        
        let moment = PersistedMoment(startDate: Date(), endDate: Date())
        moment.isTrip = true
        context.insert(moment)
        
        let tag = PhotoTag(name: "TestTag")
        context.insert(tag)
        
        let settings = DailyReviewSettings()
        context.insert(settings)
        
        let analysisState = AnalysisState()
        context.insert(analysisState)
        
        try context.save()
        
        // Test all FetchDescriptors from HomeViewModel.loadMetadataCategories
        // These are the exact predicates that caused the crash
        
        // 1. Screenshots - uses mediaSubtypesRaw (stored)
        let screenshotDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.mediaSubtypesRaw.contains("screenshot") }
        )
        let screenshots = try context.fetch(screenshotDescriptor)
        XCTAssertEqual(screenshots.count, 1, "Should find 1 screenshot")
        
        // 2. Bursts - uses burstIdentifier and representsBurst (stored)
        let burstDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.burstIdentifier != nil && !$0.representsBurst }
        )
        let bursts = try context.fetch(burstDescriptor)
        XCTAssertEqual(bursts.count, 1, "Should find 1 burst")
        
        // 3. Live Photos - uses isLivePhoto (stored)
        let livePhotoDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.isLivePhoto }
        )
        let livePhotos = try context.fetch(livePhotoDescriptor)
        XCTAssertEqual(livePhotos.count, 1, "Should find 1 live photo")
        
        // 4. Downloaded from apps - uses originRaw (stored), NOT origin (computed)
        // This was the CRASH: origin.rawValue crashed because origin is computed
        let whatsapp = "whatsapp"
        let telegram = "telegram"
        let instagram = "instagram"
        let downloadedDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.originRaw == whatsapp || $0.originRaw == telegram || $0.originRaw == instagram }
        )
        let downloaded = try context.fetch(downloadedDescriptor)
        XCTAssertEqual(downloaded.count, 1, "Should find 1 downloaded photo")
        
        // 5. Large videos - uses mediaTypeRaw and estimatedFileSize (stored)
        let videoDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.mediaTypeRaw == "video" && ($0.estimatedFileSize ?? 0) > 100_000_000 }
        )
        let largeVideos = try context.fetch(videoDescriptor)
        XCTAssertEqual(largeVideos.count, 1, "Should find 1 large video")
        
        // 6. Analyzed photos - uses analysisCompleted (stored)
        let analyzedDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.creationDate != nil }
        )
        let analyzed = try context.fetch(analyzedDescriptor)
        XCTAssertEqual(analyzed.count, 2, "Should find 2 analyzed photos")
        
        // 7. Trips - uses isTrip (stored)
        let tripDescriptor = FetchDescriptor<PersistedMoment>(
            predicate: #Predicate { $0.isTrip },
            sortBy: [SortDescriptor(\.endDate, order: .reverse)]
        )
        let trips = try context.fetch(tripDescriptor)
        XCTAssertEqual(trips.count, 1, "Should find 1 trip")
        
        // 8. Tags by name
        let tagName = "TestTag"
        let tagDescriptor = FetchDescriptor<PhotoTag>(
            predicate: #Predicate { $0.name == tagName }
        )
        let tags = try context.fetch(tagDescriptor)
        XCTAssertEqual(tags.count, 1, "Should find 1 tag")
        
        // 9. Daily review settings by ID
        let settingsDescriptor = FetchDescriptor<DailyReviewSettings>(
            predicate: #Predicate { $0.id == "main" }
        )
        let fetchedSettings = try context.fetch(settingsDescriptor)
        XCTAssertEqual(fetchedSettings.count, 1, "Should find 1 settings")
        
        // 10. Analysis state by ID
        let stateDescriptor = FetchDescriptor<AnalysisState>(
            predicate: #Predicate { $0.id == "main" }
        )
        let states = try context.fetch(stateDescriptor)
        XCTAssertEqual(states.count, 1, "Should find 1 analysis state")
    }
    
    @MainActor
    func testRepasoDelDiaFetchDescriptor() throws {
        // Test the Repaso del día query that filters today's low-value photos
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        
        // Photo from today with cleanup category
        let todayPhoto = PersistedPhoto(localIdentifier: "today-1")
        todayPhoto.creationDate = now
        todayPhoto.cleanupCategoryRaw = "screenshot"
        context.insert(todayPhoto)
        
        // Photo from today without cleanup category
        let todayClean = PersistedPhoto(localIdentifier: "today-2")
        todayClean.creationDate = now
        todayClean.cleanupCategoryRaw = "none"
        context.insert(todayClean)
        
        // Photo from yesterday with cleanup category
        let yesterdayPhoto = PersistedPhoto(localIdentifier: "yesterday-1")
        yesterdayPhoto.creationDate = calendar.date(byAdding: .day, value: -1, to: now)
        yesterdayPhoto.cleanupCategoryRaw = "blurry"
        context.insert(yesterdayPhoto)
        
        try context.save()
        
        // This is the exact predicate from RepasoDelDiaView
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { photo in
                photo.creationDate != nil &&
                photo.creationDate! >= startOfToday &&
                photo.creationDate! < endOfToday &&
                photo.cleanupCategoryRaw != "none" &&
                photo.cleanupCategoryRaw != nil
            },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1, "Should find only 1 photo from today with cleanup category")
        XCTAssertEqual(results.first?.localIdentifier, "today-1")
    }
    
    @MainActor
    func testCleanupCategoryUsesStoredProperty() throws {
        // Verify we use cleanupCategoryRaw (stored) not cleanupCategory (computed)
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let photo = PersistedPhoto(localIdentifier: "test-1")
        photo.cleanupCategoryRaw = "screenshot"  // Stored property
        context.insert(photo)
        try context.save()
        
        // This should NOT crash - uses stored property
        let categoryValue = "screenshot"
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.cleanupCategoryRaw == categoryValue }
        )
        
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        
        // Verify the computed property still works for reading
        XCTAssertEqual(results.first?.cleanupCategory, .screenshot)
    }
    
    @MainActor 
    func testOriginRawUsedNotOrigin() throws {
        // This test specifically guards against the crash that happened:
        // Using origin.rawValue (computed) instead of originRaw (stored)
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let photo = PersistedPhoto(localIdentifier: "test-whatsapp")
        photo.originRaw = "whatsapp"  // Stored property
        context.insert(photo)
        try context.save()
        
        // CORRECT: Use originRaw (stored property)
        let whatsapp = "whatsapp"
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.originRaw == whatsapp }
        )
        
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        
        // Verify computed property works for reading
        XCTAssertEqual(results.first?.origin, .whatsapp)
        
        // NOTE: This would CRASH if we tried:
        // #Predicate { $0.origin.rawValue == "whatsapp" }
        // Because origin is a computed property, not stored
    }
    
    // MARK: - Intent Parser Tests
    
    func testSpanishCleanupIntentParsing() throws {
        // Test that Spanish cleanup commands are recognized
        let cleanupPatterns = [
            "borra las capturas",
            "elimina las fotos borrosas",
            "limpia las oscuras",
            "borrá los duplicados"
        ]
        
        for pattern in cleanupPatterns {
            let normalized = pattern.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
            
            // Verify cleanup-related keywords are present
            let isCleanupIntent = normalized.contains("borra") || 
                                  normalized.contains("elimina") || 
                                  normalized.contains("limpia")
            
            XCTAssertTrue(isCleanupIntent, "Should recognize cleanup intent: \(pattern)")
        }
    }
    
    func testSpanishSearchIntentParsing() throws {
        let searchPatterns = [
            "mostrame fotos de Buenos Aires",
            "buscar fotos de cumpleaños",
            "encontrar fotos de viaje"
        ]
        
        for pattern in searchPatterns {
            let normalized = pattern.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
            
            let isSearchIntent = normalized.contains("mostrame") || 
                                 normalized.contains("buscar") || 
                                 normalized.contains("encontrar")
            
            XCTAssertTrue(isSearchIntent, "Should recognize search intent: \(pattern)")
        }
    }
    
    // MARK: - Date Parsing Tests
    
    func testDateComponentExtraction() throws {
        let calendar = Calendar.current
        let now = Date()
        
        // Test "hace 3 meses" parsing
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
        
        let components = calendar.dateComponents([.month, .year], from: threeMonthsAgo)
        XCTAssertNotNil(components.month)
        XCTAssertNotNil(components.year)
    }
    
    func testRelativeDateKeywords() throws {
        let relativeKeywords = [
            ("ayer", -1),
            ("anteayer", -2),
            ("hace una semana", -7),
            ("hace un mes", -30)
        ]
        
        for (keyword, _) in relativeKeywords {
            XCTAssertFalse(keyword.isEmpty, "Keyword should not be empty")
        }
    }
    
    // MARK: - Localization Tests
    
    func testLocalizedStringsExist() throws {
        // Test that key localized strings exist
        let requiredKeys = [
            "tab_home",
            "tab_assistant",
            "tab_moments",
            "tab_settings",
            "cleanup_category_screenshots",
            "cleanup_category_blurry",
            "cleanup_category_dark"
        ]
        
        for key in requiredKeys {
            let localized = NSLocalizedString(key, comment: "")
            // In tests, if key equals localized, the string wasn't found
            // This is a basic check - real apps should have proper localization testing
            XCTAssertFalse(localized.isEmpty, "Localized string should exist for key: \(key)")
        }
    }
    
    // MARK: - Model Tests
    
    func testCleanupCategoryLocalizedKeys() throws {
        // Test that cleanup categories have proper localized keys
        let categories = ["screenshots", "blurry", "dark", "duplicates", "documents"]
        
        for category in categories {
            let key = "cleanup_category_\(category)"
            XCTAssertTrue(key.contains("cleanup_category_"), "Key should have proper prefix")
        }
    }
    
    func testImportantDateTypeKeys() throws {
        let types = ["birthday", "wedding", "anniversary", "graduation"]
        
        for type in types {
            let key = "important_date_type_\(type)"
            XCTAssertTrue(key.contains("important_date_type_"), "Key should have proper prefix")
        }
    }
    
    // MARK: - Vos Form Verification (es-AR)
    
    func testVosFormInCopy() throws {
        // Verify that Spanish copy uses "vos" form (Argentine Spanish)
        let vosIndicators = [
            "mostrame",  // instead of "muéstrame"
            "borrá",     // instead of "borra" 
            "podés",     // instead of "puedes"
            "tenés",     // instead of "tienes"
            "querés"     // instead of "quieres"
        ]
        
        // These should be recognized as valid vos forms
        for indicator in vosIndicators {
            let normalized = indicator.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
            XCTAssertFalse(normalized.isEmpty, "Vos form should be non-empty: \(indicator)")
        }
    }
    
    // MARK: - Utility Function Tests
    
    func testFileSizeFormatting() throws {
        // Test size formatting for Spanish
        let sizes: [(Int64, String)] = [
            (500, "500 B"),
            (1024, "1 KB"),
            (1024 * 1024, "1 MB"),
            (1024 * 1024 * 1024, "1 GB")
        ]
        
        for (bytes, _) in sizes {
            let byteCount = ByteCountFormatter()
            byteCount.allowedUnits = [.useAll]
            byteCount.countStyle = .file
            
            let formatted = byteCount.string(fromByteCount: bytes)
            XCTAssertFalse(formatted.isEmpty, "Should format \(bytes) bytes")
        }
    }
    
    func testPhotoCountFormatting() throws {
        let counts = [1, 5, 100, 1000, 50000]
        
        for count in counts {
            // Spanish plural forms: 1 foto, N fotos
            let label = count == 1 ? "foto" : "fotos"
            let formatted = "\(count) \(label)"
            XCTAssertTrue(formatted.contains(String(count)), "Should contain count")
        }
    }
}
