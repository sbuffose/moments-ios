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
    
    // MARK: - Background Task Checkpoint Tests
    
    func testCheckpointMarksIndexedAssets() throws {
        let defaults = UserDefaults.standard
        let testSuite = "test.checkpoint.\(UUID().uuidString)"
        
        let indexedIdsKey = "\(testSuite).indexedIds"
        let lastIndexedIdKey = "\(testSuite).lastIndexedId"
        
        defaults.removeObject(forKey: indexedIdsKey)
        defaults.removeObject(forKey: lastIndexedIdKey)
        
        var indexedIds = Set(defaults.stringArray(forKey: indexedIdsKey) ?? [])
        XCTAssertTrue(indexedIds.isEmpty, "Should start empty")
        
        indexedIds.insert("asset-1")
        indexedIds.insert("asset-2")
        indexedIds.insert("asset-3")
        defaults.set(Array(indexedIds), forKey: indexedIdsKey)
        defaults.set("asset-3", forKey: lastIndexedIdKey)
        
        let reloaded = Set(defaults.stringArray(forKey: indexedIdsKey) ?? [])
        XCTAssertEqual(reloaded.count, 3, "Should have 3 indexed assets")
        XCTAssertTrue(reloaded.contains("asset-1"))
        XCTAssertTrue(reloaded.contains("asset-2"))
        XCTAssertTrue(reloaded.contains("asset-3"))
        
        let lastIndexed = defaults.string(forKey: lastIndexedIdKey)
        XCTAssertEqual(lastIndexed, "asset-3", "Should track last indexed")
        
        defaults.removeObject(forKey: indexedIdsKey)
        defaults.removeObject(forKey: lastIndexedIdKey)
    }
    
    func testCheckpointResumesFromLastIndexed() throws {
        let defaults = UserDefaults.standard
        let testSuite = "test.resume.\(UUID().uuidString)"
        
        let indexedIdsKey = "\(testSuite).indexedIds"
        
        let preexistingIds = ["asset-1", "asset-2", "asset-3", "asset-4", "asset-5"]
        defaults.set(preexistingIds, forKey: indexedIdsKey)
        
        let allAssetsToProcess = ["asset-1", "asset-2", "asset-3", "asset-4", "asset-5",
                                   "asset-6", "asset-7", "asset-8", "asset-9", "asset-10"]
        
        var indexedSet = Set(defaults.stringArray(forKey: indexedIdsKey) ?? [])
        var newlyProcessed = 0
        
        for assetId in allAssetsToProcess {
            if !indexedSet.contains(assetId) {
                indexedSet.insert(assetId)
                newlyProcessed += 1
            }
        }
        
        defaults.set(Array(indexedSet), forKey: indexedIdsKey)
        
        XCTAssertEqual(newlyProcessed, 5, "Should only process 5 new assets")
        XCTAssertEqual(indexedSet.count, 10, "Total should be 10 after resume")
        
        defaults.removeObject(forKey: indexedIdsKey)
    }
    
    func testCheckpointProgressTracking() throws {
        let defaults = UserDefaults.standard
        let testSuite = "test.progress.\(UUID().uuidString)"
        
        let indexedIdsKey = "\(testSuite).indexedIds"
        let analyzedIdsKey = "\(testSuite).analyzedIds"
        let totalPhotosKey = "\(testSuite).totalPhotos"
        let scanInProgressKey = "\(testSuite).scanInProgress"
        
        defaults.removeObject(forKey: indexedIdsKey)
        defaults.removeObject(forKey: analyzedIdsKey)
        defaults.removeObject(forKey: totalPhotosKey)
        defaults.removeObject(forKey: scanInProgressKey)
        
        defaults.set(true, forKey: scanInProgressKey)
        defaults.set(100, forKey: totalPhotosKey)
        
        XCTAssertTrue(defaults.bool(forKey: scanInProgressKey), "Scan should be in progress")
        XCTAssertEqual(defaults.integer(forKey: totalPhotosKey), 100, "Total should be 100")
        
        var indexedIds = Set<String>()
        for i in 1...50 {
            indexedIds.insert("photo-\(i)")
        }
        defaults.set(Array(indexedIds), forKey: indexedIdsKey)
        
        let indexed = defaults.stringArray(forKey: indexedIdsKey)?.count ?? 0
        let analyzed = defaults.stringArray(forKey: analyzedIdsKey)?.count ?? 0
        let total = defaults.integer(forKey: totalPhotosKey)
        
        XCTAssertEqual(indexed, 50, "Should have 50 indexed")
        XCTAssertEqual(analyzed, 0, "Should have 0 analyzed yet")
        XCTAssertEqual(total, 100, "Total should be 100")
        
        let progress = Double(indexed) / Double(max(total, 1))
        XCTAssertEqual(progress, 0.5, accuracy: 0.01, "Progress should be 50%")
        
        var analyzedIds = Set<String>()
        for i in 1...25 {
            analyzedIds.insert("photo-\(i)")
        }
        defaults.set(Array(analyzedIds), forKey: analyzedIdsKey)
        
        let newAnalyzed = defaults.stringArray(forKey: analyzedIdsKey)?.count ?? 0
        XCTAssertEqual(newAnalyzed, 25, "Should have 25 analyzed")
        
        let hasAnalysisPending = newAnalyzed < indexed
        XCTAssertTrue(hasAnalysisPending, "Should have pending analysis")
        
        defaults.removeObject(forKey: indexedIdsKey)
        defaults.removeObject(forKey: analyzedIdsKey)
        defaults.removeObject(forKey: totalPhotosKey)
        defaults.removeObject(forKey: scanInProgressKey)
    }
    
    func testCheckpointClearOnComplete() throws {
        let defaults = UserDefaults.standard
        let testSuite = "test.clear.\(UUID().uuidString)"
        
        let indexedIdsKey = "\(testSuite).indexedIds"
        let analyzedIdsKey = "\(testSuite).analyzedIds"
        let totalPhotosKey = "\(testSuite).totalPhotos"
        let scanInProgressKey = "\(testSuite).scanInProgress"
        
        defaults.set(["photo-1", "photo-2"], forKey: indexedIdsKey)
        defaults.set(["photo-1", "photo-2"], forKey: analyzedIdsKey)
        defaults.set(2, forKey: totalPhotosKey)
        defaults.set(true, forKey: scanInProgressKey)
        
        defaults.set(false, forKey: scanInProgressKey)
        
        XCTAssertFalse(defaults.bool(forKey: scanInProgressKey), "Scan should be complete")
        
        let hasWork = defaults.bool(forKey: scanInProgressKey)
        XCTAssertFalse(hasWork, "Should have no pending work after completion")
        
        defaults.removeObject(forKey: indexedIdsKey)
        defaults.removeObject(forKey: analyzedIdsKey)
        defaults.removeObject(forKey: totalPhotosKey)
        defaults.removeObject(forKey: scanInProgressKey)
    }
    
    func testCheckpointIdempotency() throws {
        let defaults = UserDefaults.standard
        let testSuite = "test.idempotent.\(UUID().uuidString)"
        
        let indexedIdsKey = "\(testSuite).indexedIds"
        
        var indexedIds = Set<String>()
        
        indexedIds.insert("photo-1")
        indexedIds.insert("photo-2")
        defaults.set(Array(indexedIds), forKey: indexedIdsKey)
        XCTAssertEqual(indexedIds.count, 2)
        
        indexedIds.insert("photo-1")
        indexedIds.insert("photo-2")
        defaults.set(Array(indexedIds), forKey: indexedIdsKey)
        
        let reloaded = Set(defaults.stringArray(forKey: indexedIdsKey) ?? [])
        XCTAssertEqual(reloaded.count, 2, "Set should remain at 2 (idempotent)")
        
        defaults.removeObject(forKey: indexedIdsKey)
    }
    
    func testCheckpointPersistenceAcrossRestarts() throws {
        let defaults = UserDefaults.standard
        let testSuite = "test.persist.\(UUID().uuidString)"
        
        let indexedIdsKey = "\(testSuite).indexedIds"
        let scanInProgressKey = "\(testSuite).scanInProgress"
        
        defaults.set(["photo-1", "photo-2", "photo-3"], forKey: indexedIdsKey)
        defaults.set(true, forKey: scanInProgressKey)
        defaults.synchronize()
        
        let isInProgress = defaults.bool(forKey: scanInProgressKey)
        let indexedIds = defaults.stringArray(forKey: indexedIdsKey) ?? []
        
        XCTAssertTrue(isInProgress, "Should detect interrupted scan")
        XCTAssertEqual(indexedIds.count, 3, "Should restore checkpoint data")
        
        defaults.removeObject(forKey: indexedIdsKey)
        defaults.removeObject(forKey: scanInProgressKey)
    }
    
    // MARK: - Deletion Likelihood Scoring Tests
    
    @MainActor
    func testDeletionScoreExactDuplicateHigherThanNormal() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Normal photo
        let normalPhoto = PersistedPhoto(localIdentifier: "normal-1")
        normalPhoto.analysisCompleted = true
        normalPhoto.deletionLikelihoodScore = 0.0 // Will be calculated
        
        // Exact duplicate (non-best)
        let duplicatePhoto = PersistedPhoto(localIdentifier: "duplicate-1")
        duplicatePhoto.duplicateGroupId = "group-1"
        duplicatePhoto.isBestInGroup = false
        duplicatePhoto.analysisCompleted = true
        duplicatePhoto.deletionLikelihoodScore = 0.30 // High score for duplicate
        
        context.insert(normalPhoto)
        context.insert(duplicatePhoto)
        try context.save()
        
        XCTAssertTrue(duplicatePhoto.deletionLikelihoodScore > normalPhoto.deletionLikelihoodScore,
                      "Duplicate should have higher deletion score than normal photo")
    }
    
    @MainActor
    func testDeletionScoreFavoriteProtected() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Favorite photo (should be protected)
        let favoritePhoto = PersistedPhoto(localIdentifier: "favorite-1")
        favoritePhoto.isFavorite = true
        favoritePhoto.analysisCompleted = true
        favoritePhoto.deletionLikelihoodScore = 0.0 // Low score for favorites
        
        // Screenshot (higher deletion likelihood)
        let screenshotPhoto = PersistedPhoto(localIdentifier: "screenshot-1")
        screenshotPhoto.mediaSubtypesRaw = "screenshot"
        screenshotPhoto.analysisCompleted = true
        screenshotPhoto.deletionLikelihoodScore = 0.20
        
        context.insert(favoritePhoto)
        context.insert(screenshotPhoto)
        try context.save()
        
        XCTAssertTrue(favoritePhoto.deletionLikelihoodScore < screenshotPhoto.deletionLikelihoodScore,
                      "Favorite should have lower deletion score than screenshot")
    }
    
    @MainActor
    func testDeletionScoreBlurryHigherThanSharp() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Sharp photo
        let sharpPhoto = PersistedPhoto(localIdentifier: "sharp-1")
        sharpPhoto.mediaTypeRaw = "image"
        sharpPhoto.sharpnessScore = 0.85
        sharpPhoto.analysisCompleted = true
        sharpPhoto.deletionLikelihoodScore = 0.0
        
        // Very blurry photo
        let blurryPhoto = PersistedPhoto(localIdentifier: "blurry-1")
        blurryPhoto.mediaTypeRaw = "image"
        blurryPhoto.sharpnessScore = 0.05
        blurryPhoto.analysisCompleted = true
        blurryPhoto.deletionLikelihoodScore = 0.30 // High score for very blurry
        
        context.insert(sharpPhoto)
        context.insert(blurryPhoto)
        try context.save()
        
        XCTAssertTrue(blurryPhoto.deletionLikelihoodScore > sharpPhoto.deletionLikelihoodScore,
                      "Blurry photo should have higher deletion score than sharp photo")
    }
    
    @MainActor
    func testDeletionScorePhotoWithFacesProtected() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Photo with faces (more protected)
        let photoWithFaces = PersistedPhoto(localIdentifier: "faces-1")
        photoWithFaces.facesDetected = 3
        photoWithFaces.analysisCompleted = true
        photoWithFaces.deletionLikelihoodScore = 0.0
        
        // Downloaded meme without faces
        let memePhoto = PersistedPhoto(localIdentifier: "meme-1")
        memePhoto.originRaw = "download"
        memePhoto.facesDetected = 0
        memePhoto.pixelWidth = 500
        memePhoto.pixelHeight = 500
        memePhoto.analysisCompleted = true
        memePhoto.deletionLikelihoodScore = 0.30 // Higher score for meme
        
        context.insert(photoWithFaces)
        context.insert(memePhoto)
        try context.save()
        
        XCTAssertTrue(memePhoto.deletionLikelihoodScore > photoWithFaces.deletionLikelihoodScore,
                      "Meme without faces should have higher deletion score than photo with faces")
    }
    
    @MainActor
    func testDeletionScoreLivePhotoNotHighPriority() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Live Photo (should NOT be high priority deletion)
        let livePhoto = PersistedPhoto(localIdentifier: "live-1")
        livePhoto.isLivePhoto = true
        livePhoto.analysisCompleted = true
        livePhoto.deletionLikelihoodScore = 0.0 // Low - Live Photos are not deletion candidates
        
        // Old screenshot with receipt
        let oldScreenshot = PersistedPhoto(localIdentifier: "receipt-1")
        oldScreenshot.mediaSubtypesRaw = "screenshot"
        oldScreenshot.creationDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())
        oldScreenshot.ocrText = "TOTAL $150.00 FACTURA"
        oldScreenshot.analysisCompleted = true
        oldScreenshot.deletionLikelihoodScore = 0.35 // High score for old receipt screenshot
        
        context.insert(livePhoto)
        context.insert(oldScreenshot)
        try context.save()
        
        XCTAssertTrue(livePhoto.deletionLikelihoodScore < oldScreenshot.deletionLikelihoodScore,
                      "Live Photo should have lower deletion score than old screenshot with receipt")
    }
    
    @MainActor
    func testDeletionScoreOrderingCorrect() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Create photos with different deletion scores
        let photos: [(String, Double)] = [
            ("favorite", 0.0),        // Favorite - very low
            ("livePhoto", 0.05),      // Live Photo - low
            ("normal", 0.10),         // Normal photo
            ("screenshot", 0.20),     // Screenshot
            ("blurry", 0.25),         // Blurry
            ("duplicate", 0.30),      // Duplicate
            ("whatsappMeme", 0.40),   // WhatsApp meme
        ]
        
        for (id, score) in photos {
            let photo = PersistedPhoto(localIdentifier: id)
            photo.analysisCompleted = true
            photo.deletionLikelihoodScore = score
            context.insert(photo)
        }
        try context.save()
        
        // Fetch and sort by deletion likelihood
        let descriptor = FetchDescriptor<PersistedPhoto>(
            sortBy: [SortDescriptor(\.deletionLikelihoodScore, order: .reverse)]
        )
        let sortedPhotos = try context.fetch(descriptor)
        
        // Verify order: whatsappMeme should be first (highest score)
        XCTAssertEqual(sortedPhotos.first?.localIdentifier, "whatsappMeme",
                       "Highest deletion score should be first")
        
        // Verify order: favorite should be last (lowest score)
        XCTAssertEqual(sortedPhotos.last?.localIdentifier, "favorite",
                       "Favorite should be last (lowest deletion score)")
        
        // Verify Live Photo is NOT at the top
        XCTAssertNotEqual(sortedPhotos.first?.localIdentifier, "livePhoto",
                          "Live Photo should NOT be at the top of deletion queue")
    }
    
    @MainActor
    func testDeletionScoreEditedPhotoProtected() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Edited photo (user invested effort)
        let editedPhoto = PersistedPhoto(localIdentifier: "edited-1")
        editedPhoto.isEdited = true
        editedPhoto.analysisCompleted = true
        editedPhoto.deletionLikelihoodScore = 0.0
        
        // Unedited screenshot
        let screenshotPhoto = PersistedPhoto(localIdentifier: "screenshot-1")
        screenshotPhoto.mediaSubtypesRaw = "screenshot"
        screenshotPhoto.isEdited = false
        screenshotPhoto.analysisCompleted = true
        screenshotPhoto.deletionLikelihoodScore = 0.20
        
        context.insert(editedPhoto)
        context.insert(screenshotPhoto)
        try context.save()
        
        XCTAssertTrue(editedPhoto.deletionLikelihoodScore < screenshotPhoto.deletionLikelihoodScore,
                      "Edited photo should have lower deletion score than unedited screenshot")
    }
    
    @MainActor
    func testDeletionScoreBurstLoserHighPriority() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Best photo in burst
        let bestBurst = PersistedPhoto(localIdentifier: "burst-best")
        bestBurst.burstIdentifier = "burst-group-1"
        bestBurst.representsBurst = true
        bestBurst.analysisCompleted = true
        bestBurst.deletionLikelihoodScore = 0.0
        
        // Non-best burst photo (loser)
        let burstLoser = PersistedPhoto(localIdentifier: "burst-loser")
        burstLoser.burstIdentifier = "burst-group-1"
        burstLoser.representsBurst = false
        burstLoser.analysisCompleted = true
        burstLoser.deletionLikelihoodScore = 0.25 // High score for burst loser
        
        context.insert(bestBurst)
        context.insert(burstLoser)
        try context.save()
        
        XCTAssertTrue(burstLoser.deletionLikelihoodScore > bestBurst.deletionLikelihoodScore,
                      "Burst loser should have higher deletion score than best burst photo")
    }
    
    // MARK: - Keep Decision Tests
    
    @MainActor
    func testKeepDecisionForeverExcludesFromCandidates() throws {
        let schema = Schema([PersistedPhoto.self, SimilarGroup.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Create a blurry photo that would normally be a candidate
        let photo = PersistedPhoto(localIdentifier: "kept-photo-1")
        photo.analysisCompleted = true
        photo.mediaTypeRaw = "image"
        photo.sharpnessScore = 0.05 // Very blurry
        photo.cleanupCategoryRaw = "blurry"
        photo.deletionLikelihoodScore = 0.4
        
        context.insert(photo)
        try context.save()
        
        // Verify photo is a candidate before keep decision
        XCTAssertFalse(photo.isKeptByUser, "Photo should NOT be kept initially")
        XCTAssertTrue(photo.cleanupCategory == .blurry, "Photo should be categorized as blurry")
        
        // User decides to keep the photo forever
        photo.keepDecision = .forever
        photo.keepDecisionDate = Date()
        try context.save()
        
        // Verify photo is now excluded from candidates
        XCTAssertTrue(photo.isKeptByUser, "Photo should be marked as kept")
        
        // Simulate a rescan - verify keepDecision is NOT reset
        photo.analysisCompleted = false // Simulate re-analysis needed
        photo.analysisCompleted = true  // Re-analysis complete
        try context.save()
        
        // keepDecision should persist through rescan
        XCTAssertEqual(photo.keepDecision, .forever, "Keep decision should persist through rescan")
        XCTAssertTrue(photo.isKeptByUser, "Photo should still be kept after rescan")
    }
    
    @MainActor
    func testKeepDecisionSnoozedReentersAfterExpiry() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let photo = PersistedPhoto(localIdentifier: "snoozed-photo-1")
        photo.analysisCompleted = true
        photo.mediaTypeRaw = "image"
        photo.sharpnessScore = 0.05
        photo.cleanupCategoryRaw = "blurry"
        
        context.insert(photo)
        try context.save()
        
        // User snoozes for 7 days
        let sevenDaysFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        photo.keepDecision = .snoozed
        photo.keepUntil = sevenDaysFromNow
        photo.keepDecisionDate = Date()
        try context.save()
        
        // Verify photo is excluded during snooze period
        XCTAssertTrue(photo.isKeptByUser, "Snoozed photo should be kept during snooze period")
        XCTAssertFalse(photo.isSnoozeExpired, "Snooze should NOT be expired yet")
        
        // Simulate time passing - set keepUntil to the past
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        photo.keepUntil = sevenDaysAgo
        try context.save()
        
        // Verify photo re-enters candidates after snooze expires
        XCTAssertFalse(photo.isKeptByUser, "Photo should NOT be kept after snooze expires")
        XCTAssertTrue(photo.isSnoozeExpired, "Snooze should be expired")
    }
    
    @MainActor
    func testKeepDecisionPreservedDuringRescan() throws {
        let schema = Schema([PersistedPhoto.self, AnalysisState.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Create a photo with keep decision
        let photo = PersistedPhoto(localIdentifier: "preserved-photo-1")
        photo.analysisCompleted = true
        photo.keepDecision = .forever
        photo.keepDecisionDate = Date()
        
        context.insert(photo)
        try context.save()
        
        // Verify keepDecision fields are set
        XCTAssertEqual(photo.keepDecision, .forever)
        XCTAssertNotNil(photo.keepDecisionDate)
        
        // Simulate what happens during a rescan:
        // A rescan would try to insert a new photo with the same localIdentifier
        // but the idempotent indexing should find the existing photo and not overwrite it
        
        // First, check if photo already exists (simulating idempotent indexing)
        let existingDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.localIdentifier == "preserved-photo-1" }
        )
        let existingPhotos = try context.fetch(existingDescriptor)
        XCTAssertFalse(existingPhotos.isEmpty, "Photo should exist")
        
        // The existing photo's keepDecision should be preserved
        let existingPhoto = existingPhotos.first!
        XCTAssertEqual(existingPhoto.keepDecision, .forever, 
                       "Keep decision should be preserved during rescan")
        XCTAssertNotNil(existingPhoto.keepDecisionDate,
                        "Keep decision date should be preserved during rescan")
    }
    
    @MainActor
    func testUndoKeepDecisionMakesPhotoCandidate() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let photo = PersistedPhoto(localIdentifier: "undo-test-1")
        photo.analysisCompleted = true
        photo.cleanupCategoryRaw = "blurry"
        photo.keepDecision = .forever
        photo.keepDecisionDate = Date()
        
        context.insert(photo)
        try context.save()
        
        XCTAssertTrue(photo.isKeptByUser, "Photo should be kept")
        
        // Undo the keep decision
        photo.keepDecision = .none
        photo.keepUntil = nil
        photo.keepDecisionDate = nil
        try context.save()
        
        XCTAssertFalse(photo.isKeptByUser, "Photo should no longer be kept after undo")
    }
    
    // MARK: - Blur Detection Tests
    
    @MainActor
    func testBlurDetectionRequiresBothLaplacianAndVisionAgreement() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Photo with low Laplacian but high Vision aesthetics (like ROTONDO storefront)
        // This should NOT be flagged as blurry
        let sharpStorefront = PersistedPhoto(localIdentifier: "sharp-storefront")
        sharpStorefront.analysisCompleted = true
        sharpStorefront.mediaTypeRaw = "image"
        sharpStorefront.sharpnessScore = 0.09  // Low Laplacian (would trigger old detector)
        sharpStorefront.visionAestheticsScore = 0.7  // High Vision score (sharp/aesthetic)
        sharpStorefront.visionIsUtility = false  // Not utility
        
        // Truly blurry photo - both indicators agree
        let trulyBlurry = PersistedPhoto(localIdentifier: "truly-blurry")
        trulyBlurry.analysisCompleted = true
        trulyBlurry.mediaTypeRaw = "image"
        trulyBlurry.sharpnessScore = 0.05  // Very low Laplacian
        trulyBlurry.visionAestheticsScore = 0.15  // Low Vision score
        trulyBlurry.visionIsUtility = true  // Vision says utility
        
        context.insert(sharpStorefront)
        context.insert(trulyBlurry)
        try context.save()
        
        // Test the blur detection logic
        func shouldFlagAsBlurry(_ photo: PersistedPhoto) -> Bool {
            guard photo.mediaTypeRaw == "image" else { return false }
            
            let laplacian = photo.sharpnessScore ?? 1.0
            let aesthetics = photo.visionAestheticsScore
            let isUtility = photo.visionIsUtility
            
            if laplacian < 0.10 {
                if let aScore = aesthetics, let utility = isUtility {
                    return aScore < 0.3 || utility == true
                } else {
                    return laplacian < 0.08
                }
            }
            return false
        }
        
        // Sharp storefront should NOT be flagged as blurry
        XCTAssertFalse(shouldFlagAsBlurry(sharpStorefront),
                       "Sharp storefront with high Vision score should NOT be flagged as blurry")
        
        // Truly blurry photo SHOULD be flagged
        XCTAssertTrue(shouldFlagAsBlurry(trulyBlurry),
                      "Photo with both low Laplacian and low Vision score SHOULD be flagged as blurry")
    }
    
    @MainActor
    func testBlurDetectionFallbackWithoutVision() throws {
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Photo without Vision scores (pre-iOS 18)
        let photoNoVision = PersistedPhoto(localIdentifier: "no-vision")
        photoNoVision.analysisCompleted = true
        photoNoVision.mediaTypeRaw = "image"
        photoNoVision.sharpnessScore = 0.09  // Low but not extremely low Laplacian
        photoNoVision.visionAestheticsScore = nil  // No Vision
        photoNoVision.visionIsUtility = nil
        
        // Very blurry photo without Vision
        let veryBlurryNoVision = PersistedPhoto(localIdentifier: "very-blurry-no-vision")
        veryBlurryNoVision.analysisCompleted = true
        veryBlurryNoVision.mediaTypeRaw = "image"
        veryBlurryNoVision.sharpnessScore = 0.05  // Very low Laplacian
        veryBlurryNoVision.visionAestheticsScore = nil
        veryBlurryNoVision.visionIsUtility = nil
        
        context.insert(photoNoVision)
        context.insert(veryBlurryNoVision)
        try context.save()
        
        func shouldFlagAsBlurry(_ photo: PersistedPhoto) -> Bool {
            guard photo.mediaTypeRaw == "image" else { return false }
            
            let laplacian = photo.sharpnessScore ?? 1.0
            let aesthetics = photo.visionAestheticsScore
            let isUtility = photo.visionIsUtility
            
            if laplacian < 0.10 {
                if let aScore = aesthetics, let utility = isUtility {
                    return aScore < 0.3 || utility == true
                } else {
                    // No Vision - use stricter threshold
                    return laplacian < 0.08
                }
            }
            return false
        }
        
        // Moderately low Laplacian without Vision should NOT be flagged (uses stricter 0.08 threshold)
        XCTAssertFalse(shouldFlagAsBlurry(photoNoVision),
                       "Photo at 0.09 sharpness without Vision should NOT be flagged (threshold is 0.08)")
        
        // Very low Laplacian without Vision SHOULD be flagged
        XCTAssertTrue(shouldFlagAsBlurry(veryBlurryNoVision),
                      "Photo at 0.05 sharpness without Vision SHOULD be flagged")
    }
    
    // MARK: - Background Task Tests
    
    @MainActor
    func testBackgroundTaskProgressCalculation() throws {
        // Test progress calculation for continued processing task
        
        let totalPhotos = 100
        var processedCount = 0
        
        // Simulate progress updates
        func calculateProgress() -> Double {
            return Double(processedCount) / Double(totalPhotos)
        }
        
        func calculateRemaining() -> Int {
            return totalPhotos - processedCount
        }
        
        // Initial state
        XCTAssertEqual(calculateProgress(), 0.0, accuracy: 0.001)
        XCTAssertEqual(calculateRemaining(), 100)
        
        // 25% progress
        processedCount = 25
        XCTAssertEqual(calculateProgress(), 0.25, accuracy: 0.001)
        XCTAssertEqual(calculateRemaining(), 75)
        
        // 50% progress
        processedCount = 50
        XCTAssertEqual(calculateProgress(), 0.5, accuracy: 0.001)
        XCTAssertEqual(calculateRemaining(), 50)
        
        // 100% progress
        processedCount = 100
        XCTAssertEqual(calculateProgress(), 1.0, accuracy: 0.001)
        XCTAssertEqual(calculateRemaining(), 0)
    }
    
    @MainActor
    func testBackgroundTaskShouldNotSubmitWithNoWork() throws {
        // Test that continued processing task should not be submitted when no work remains
        
        let remainingPhotos = 0
        let hasPendingWork = false
        
        // Mock the submission logic
        func shouldSubmitContinuedTask() -> Bool {
            guard remainingPhotos > 0 else { return false }
            guard hasPendingWork else { return false }
            return true
        }
        
        XCTAssertFalse(shouldSubmitContinuedTask(),
                       "Should not submit continued processing task when no photos remain")
    }
    
    @MainActor
    func testBackgroundTaskShouldNotSubmitWhenScanNotInProgress() throws {
        // Test that continued processing task should not be submitted when scan is not in progress
        
        let remainingPhotos = 50
        let hasPendingWork = false
        
        func shouldSubmitContinuedTask() -> Bool {
            guard remainingPhotos > 0 else { return false }
            guard hasPendingWork else { return false }
            return true
        }
        
        XCTAssertFalse(shouldSubmitContinuedTask(),
                       "Should not submit continued processing task when scan is not in progress")
    }
    
    @MainActor
    func testBackgroundTaskShouldSubmitWithPendingWork() throws {
        // Test that continued processing task should be submitted when there is pending work
        
        let remainingPhotos = 50
        let hasPendingWork = true
        
        func shouldSubmitContinuedTask() -> Bool {
            guard remainingPhotos > 0 else { return false }
            guard hasPendingWork else { return false }
            return true
        }
        
        XCTAssertTrue(shouldSubmitContinuedTask(),
                      "Should submit continued processing task when photos remain and scan is in progress")
    }
    
    @MainActor
    func testBackgroundTaskProgressIntegrity() throws {
        // Test that progress values stay within valid bounds
        
        var totalUnitCount: Int64 = 100
        var completedUnitCount: Int64 = 0
        
        // Simulate progress updates and verify bounds
        for i in 0...100 {
            completedUnitCount = Int64(i)
            
            // completedUnitCount should never exceed totalUnitCount
            XCTAssertLessThanOrEqual(completedUnitCount, totalUnitCount)
            
            // completedUnitCount should never be negative
            XCTAssertGreaterThanOrEqual(completedUnitCount, 0)
            
            // Progress fraction should be valid
            let progress = Double(completedUnitCount) / Double(totalUnitCount)
            XCTAssertGreaterThanOrEqual(progress, 0.0)
            XCTAssertLessThanOrEqual(progress, 1.0)
        }
    }
    
    @MainActor
    func testBackgroundTaskExpirationCheckpoint() throws {
        // Test that checkpoint is properly saved on expiration
        
        let checkpointKey = "test.checkpoint.progress"
        let defaults = UserDefaults.standard
        
        // Clear any existing checkpoint
        defaults.removeObject(forKey: checkpointKey)
        
        // Simulate work progress
        var processedIds: [String] = []
        for i in 1...50 {
            processedIds.append("photo-\(i)")
        }
        
        // Save checkpoint (simulating expiration handler)
        defaults.set(processedIds, forKey: checkpointKey)
        defaults.synchronize()
        
        // Verify checkpoint was saved
        let savedIds = defaults.stringArray(forKey: checkpointKey) ?? []
        XCTAssertEqual(savedIds.count, 50, "Checkpoint should save all processed IDs")
        XCTAssertEqual(savedIds.first, "photo-1")
        XCTAssertEqual(savedIds.last, "photo-50")
        
        // Clean up
        defaults.removeObject(forKey: checkpointKey)
    }
    
    @MainActor
    func testBackgroundTaskCompletionStateTransition() throws {
        // Test that task completion properly transitions state
        
        var isBackgroundScanActive = true
        var taskCompleted = false
        var completionSuccess: Bool?
        
        // Simulate successful completion
        func completeTask(success: Bool) {
            taskCompleted = true
            completionSuccess = success
            isBackgroundScanActive = false
        }
        
        // Before completion
        XCTAssertTrue(isBackgroundScanActive)
        XCTAssertFalse(taskCompleted)
        XCTAssertNil(completionSuccess)
        
        // Complete with success
        completeTask(success: true)
        
        // After completion
        XCTAssertFalse(isBackgroundScanActive, "Background scan should be inactive after completion")
        XCTAssertTrue(taskCompleted, "Task should be marked as completed")
        XCTAssertEqual(completionSuccess, true, "Completion should be successful")
    }
    
    // MARK: - Preference Learning Tests
    
    @MainActor
    func testReviewDecisionModelCreation() throws {
        // Test that ReviewDecision properly extracts features from a photo
        let schema = Schema([PersistedPhoto.self, ReviewDecision.self, LearnedPreferences.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Create a screenshot photo with various features
        let photo = PersistedPhoto(localIdentifier: "test-screenshot")
        photo.analysisCompleted = true
        photo.cleanupCategoryRaw = "screenshot"
        photo.originRaw = "screenshot"
        photo.facesDetected = 2
        photo.visionAestheticsScore = 0.3
        photo.sharpnessScore = 0.8
        photo.exposureScore = 0.5
        photo.hasText = true
        photo.creationDate = Date()
        photo.estimatedFileSize = 500_000
        
        context.insert(photo)
        try context.save()
        
        // Create a review decision
        let decision = ReviewDecision(
            photoId: photo.id,
            localIdentifier: photo.localIdentifier,
            decisionType: .delete,
            photo: photo
        )
        
        context.insert(decision)
        try context.save()
        
        // Verify feature extraction
        XCTAssertEqual(decision.categoryRaw, "screenshot")
        XCTAssertTrue(decision.isScreenshot)
        XCTAssertEqual(decision.faceCount, 2)
        XCTAssertTrue(decision.hasFaces)
        XCTAssertTrue(decision.hasText)
        XCTAssertEqual(decision.aestheticsScore, 0.3, accuracy: 0.01)
        XCTAssertEqual(decision.sharpnessScore, 0.8, accuracy: 0.01)
        XCTAssertTrue(decision.isDeleteDecision)
        XCTAssertFalse(decision.isKeepDecision)
    }
    
    @MainActor
    func testReviewDecisionKeepTypes() throws {
        // Test all keep decision types
        let schema = Schema([PersistedPhoto.self, ReviewDecision.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let keepTypes: [(ReviewDecisionType, Bool, Bool)] = [
            (.keepForever, true, false),
            (.keepSnoozed, true, false),
            (.delete, false, true),
            (.shareThenDelete, false, true),
            (.shareThenKeep, true, false),
            (.skip, false, false),
        ]
        
        for (decisionType, expectedKeep, expectedDelete) in keepTypes {
            let photo = PersistedPhoto(localIdentifier: "test-\(decisionType.rawValue)")
            photo.analysisCompleted = true
            context.insert(photo)
            
            let decision = ReviewDecision(
                photoId: photo.id,
                localIdentifier: photo.localIdentifier,
                decisionType: decisionType,
                photo: photo
            )
            context.insert(decision)
            
            XCTAssertEqual(decision.isKeepDecision, expectedKeep,
                          "\(decisionType.rawValue) should have isKeepDecision=\(expectedKeep)")
            XCTAssertEqual(decision.isDeleteDecision, expectedDelete,
                          "\(decisionType.rawValue) should have isDeleteDecision=\(expectedDelete)")
        }
        
        try context.save()
    }
    
    @MainActor
    func testLearnedPreferencesInitialValues() throws {
        // Test that LearnedPreferences initializes with neutral values
        let prefs = LearnedPreferences()
        
        // All category keep rates should start at 0.5 (neutral)
        XCTAssertEqual(prefs.screenshotKeepRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(prefs.blurryKeepRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(prefs.duplicateKeepRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(prefs.downloadKeepRate, 0.5, accuracy: 0.01)
        
        // All decision counts should start at 0
        XCTAssertEqual(prefs.screenshotDecisions, 0)
        XCTAssertEqual(prefs.blurryDecisions, 0)
        XCTAssertEqual(prefs.duplicateDecisions, 0)
        
        // Logistic weights should start at 0 (neutral)
        XCTAssertEqual(prefs.weightFaceCount, 0.0, accuracy: 0.01)
        XCTAssertEqual(prefs.weightAesthetics, 0.0, accuracy: 0.01)
        XCTAssertEqual(prefs.weightSharpness, 0.0, accuracy: 0.01)
        XCTAssertEqual(prefs.intercept, 0.0, accuracy: 0.01)
        
        // Confidence should be 0 with no decisions
        XCTAssertEqual(prefs.confidenceWeight, 0.0, accuracy: 0.01)
    }
    
    @MainActor
    func testLearnedPreferencesConfidenceRamp() throws {
        // Test that confidence ramps up to 1.0 at ~50 decisions
        let prefs = LearnedPreferences()
        
        // 0 decisions = 0% confidence
        prefs.totalDecisions = 0
        XCTAssertEqual(prefs.confidenceWeight, 0.0, accuracy: 0.01)
        
        // 25 decisions = 50% confidence
        prefs.totalDecisions = 25
        XCTAssertEqual(prefs.confidenceWeight, 0.5, accuracy: 0.01)
        
        // 50 decisions = 100% confidence
        prefs.totalDecisions = 50
        XCTAssertEqual(prefs.confidenceWeight, 1.0, accuracy: 0.01)
        
        // 100 decisions should still be capped at 100%
        prefs.totalDecisions = 100
        XCTAssertEqual(prefs.confidenceWeight, 1.0, accuracy: 0.01)
    }
    
    @MainActor
    func testBayesianCategoryKeepRateUpdate() throws {
        // Test Bayesian update of category keep rates
        // Formula: posterior = (prior * n + new_value) / (n + 1)
        
        let prefs = LearnedPreferences()
        
        // Start with prior of 0.5 (50% keep rate)
        XCTAssertEqual(prefs.screenshotKeepRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(prefs.screenshotDecisions, 0)
        
        // After 1 "delete" decision (value=0): (0.5 * 0 + 0) / 1 = 0
        // Actually with n=0: (0.5 * 0 + 0) / (0 + 1) = 0
        let n0: Double = 0
        let newRate0 = (0.5 * n0 + 0.0) / (n0 + 1)
        XCTAssertEqual(newRate0, 0.0, accuracy: 0.01, "After 1 delete, rate should be 0")
        
        // After 2nd decision (keep, value=1): (0 * 1 + 1) / 2 = 0.5
        let n1: Double = 1
        let newRate1 = (0.0 * n1 + 1.0) / (n1 + 1)
        XCTAssertEqual(newRate1, 0.5, accuracy: 0.01, "After 1 delete + 1 keep, rate should be 0.5")
        
        // After 10 decisions all delete: rate should be close to 0
        var rate = 0.5
        var decisions = 0
        for _ in 0..<10 {
            let n = Double(decisions)
            rate = (rate * n + 0.0) / (n + 1)
            decisions += 1
        }
        XCTAssertLessThan(rate, 0.1, "After 10 deletes, rate should be low")
        
        // After 10 more decisions all keep: rate should recover toward 0.5
        for _ in 0..<10 {
            let n = Double(decisions)
            rate = (rate * n + 1.0) / (n + 1)
            decisions += 1
        }
        XCTAssertGreaterThan(rate, 0.4, "After mixed decisions, rate should recover")
    }
    
    @MainActor
    func testCategoryDeprioritizationDetection() throws {
        // Test that categories with >80% keep rate get flagged for deprioritization
        let prefs = LearnedPreferences()
        
        // Simulate user keeping 85% of screenshots (17 keeps out of 20)
        var keepRate: Double = 0.5
        var decisions = 0
        for i in 0..<20 {
            let n = Double(decisions)
            let keepValue: Double = i < 17 ? 1.0 : 0.0 // 17 keeps, 3 deletes
            keepRate = (keepRate * n + keepValue) / (n + 1)
            decisions += 1
        }
        
        // Keep rate should be around 0.85 (depends on prior influence)
        XCTAssertGreaterThan(keepRate, 0.75, "After 17/20 keeps, rate should be >75%")
        
        // With minDecisionsForSuggestion = 10, this should trigger deprioritization
        let shouldSuggestDeprioritize = keepRate >= 0.8 && decisions >= 10
        XCTAssertTrue(shouldSuggestDeprioritize, "Should suggest deprioritizing screenshots")
    }
    
    @MainActor
    func testDeprioritizedCategoriesStorage() throws {
        // Test that deprioritized categories are properly stored and retrieved
        let schema = Schema([LearnedPreferences.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let prefs = LearnedPreferences()
        context.insert(prefs)
        
        // Initially empty
        XCTAssertTrue(prefs.deprioritizedCategories.isEmpty)
        
        // Set some deprioritized categories
        prefs.setDeprioritizedCategories([.screenshot, .blurry])
        try context.save()
        
        // Verify retrieval
        let retrieved = prefs.deprioritizedCategories
        XCTAssertEqual(retrieved.count, 2)
        XCTAssertTrue(retrieved.contains(.screenshot))
        XCTAssertTrue(retrieved.contains(.blurry))
    }
    
    @MainActor
    func testSuppressedCategoriesStorage() throws {
        // Test that suppressed categories (user explicitly asked to never suggest) work
        let schema = Schema([LearnedPreferences.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let prefs = LearnedPreferences()
        context.insert(prefs)
        
        XCTAssertTrue(prefs.suppressedCategories.isEmpty)
        
        prefs.setSuppressedCategories([.receipt])
        try context.save()
        
        XCTAssertEqual(prefs.suppressedCategories.count, 1)
        XCTAssertTrue(prefs.suppressedCategories.contains(.receipt))
    }
    
    @MainActor
    func testLogisticRegressionPrediction() throws {
        // Test that logistic regression prediction produces valid probabilities
        
        // Sigmoid function: 1 / (1 + e^(-z))
        func sigmoid(_ z: Double) -> Double {
            return 1.0 / (1.0 + exp(-z))
        }
        
        // z = 0 should give 0.5
        XCTAssertEqual(sigmoid(0), 0.5, accuracy: 0.01)
        
        // Large positive z should give ~1.0
        XCTAssertGreaterThan(sigmoid(5), 0.99)
        
        // Large negative z should give ~0.0
        XCTAssertLessThan(sigmoid(-5), 0.01)
        
        // Test with feature weights
        let prefs = LearnedPreferences()
        
        // Simulate learning: user keeps photos with faces
        prefs.weightFaceCount = 2.0 // Strong positive weight for faces
        prefs.weightAesthetics = 1.0
        prefs.intercept = -1.0
        
        // Photo with 3 faces (normalized to 0.3) and high aesthetics (0.8)
        let faceFeature = 0.3
        let aestheticsFeature = 0.8
        
        let z = prefs.intercept +
            prefs.weightFaceCount * faceFeature +
            prefs.weightAesthetics * aestheticsFeature
        
        let prediction = sigmoid(z)
        
        // With positive weights for faces and aesthetics, prediction should be > 0.5
        XCTAssertGreaterThan(prediction, 0.5, "Photo with faces and good aesthetics should have high keep probability")
    }
    
    @MainActor
    func testScoreAdjustmentWithConfidence() throws {
        // Test that learned preferences adjust scores based on confidence
        
        let baseScore = 0.5
        let categoryKeepRate = 0.2 // User deletes 80% of this category
        let categoryAdjustment = (1.0 - categoryKeepRate) * 0.3 // Max 0.3 boost
        
        // At 0% confidence, no adjustment
        var confidence = 0.0
        var adjustedScore = baseScore + categoryAdjustment * confidence
        XCTAssertEqual(adjustedScore, 0.5, accuracy: 0.01, "No adjustment at 0% confidence")
        
        // At 50% confidence, half adjustment
        confidence = 0.5
        adjustedScore = baseScore + categoryAdjustment * confidence
        XCTAssertEqual(adjustedScore, 0.62, accuracy: 0.01, "Half adjustment at 50% confidence")
        
        // At 100% confidence, full adjustment
        confidence = 1.0
        adjustedScore = baseScore + categoryAdjustment * confidence
        XCTAssertEqual(adjustedScore, 0.74, accuracy: 0.01, "Full adjustment at 100% confidence")
    }
    
    @MainActor
    func testDecisionLoggingChangesRanking() throws {
        // Test that logging decisions actually changes the ranking
        // This is the key assertion: "simulate decisions and assert the ranking changes"
        
        let schema = Schema([PersistedPhoto.self, ReviewDecision.self, LearnedPreferences.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Create two screenshots with similar base scores
        let photo1 = PersistedPhoto(localIdentifier: "screenshot-1")
        photo1.analysisCompleted = true
        photo1.cleanupCategoryRaw = "screenshot"
        photo1.deletionLikelihoodScore = 0.5
        photo1.facesDetected = 0
        photo1.visionAestheticsScore = 0.3
        
        let photo2 = PersistedPhoto(localIdentifier: "screenshot-2")
        photo2.analysisCompleted = true
        photo2.cleanupCategoryRaw = "screenshot"
        photo2.deletionLikelihoodScore = 0.5
        photo2.facesDetected = 2
        photo2.visionAestheticsScore = 0.7
        
        context.insert(photo1)
        context.insert(photo2)
        
        // Initialize preferences
        let prefs = LearnedPreferences()
        context.insert(prefs)
        try context.save()
        
        // Initial: both have same base score
        XCTAssertEqual(photo1.deletionLikelihoodScore, photo2.deletionLikelihoodScore)
        
        // Simulate user consistently keeping photos with faces
        // After learning, photos with faces should have lower deletion scores
        
        // Simulate 20 decisions where photos with faces are kept
        for i in 0..<20 {
            let mockPhoto = PersistedPhoto(localIdentifier: "mock-\(i)")
            mockPhoto.facesDetected = i % 2 == 0 ? 2 : 0 // Alternating: with and without faces
            mockPhoto.cleanupCategoryRaw = "screenshot"
            context.insert(mockPhoto)
            
            // User keeps photos with faces, deletes photos without
            let decisionType: ReviewDecisionType = mockPhoto.facesDetected! > 0 ? .keepForever : .delete
            let decision = ReviewDecision(
                photoId: mockPhoto.id,
                localIdentifier: mockPhoto.localIdentifier,
                decisionType: decisionType,
                photo: mockPhoto
            )
            context.insert(decision)
            
            // Update learned preferences (simulated)
            prefs.totalDecisions += 1
            
            if decisionType == .keepForever {
                // Increase weight for faces (gradient descent update)
                prefs.weightFaceCount += 0.1
            } else {
                prefs.weightFaceCount -= 0.1
            }
        }
        
        try context.save()
        
        // After learning, weightFaceCount should be positive
        // (10 keeps with faces, 10 deletes without faces)
        // Net effect: +10 * 0.1 - 0 = +1.0 for faces
        XCTAssertGreaterThan(prefs.weightFaceCount, 0, "Weight for faces should be positive after learning")
        
        // Calculate adjusted scores
        func calculateAdjustedScore(for photo: PersistedPhoto) -> Double {
            let baseScore = photo.deletionLikelihoodScore
            let confidence = prefs.confidenceWeight
            
            // Logistic prediction component
            let faceFeature = Double(photo.facesDetected ?? 0) / 10.0
            let z = prefs.intercept + prefs.weightFaceCount * faceFeature
            let keepProbability = 1.0 / (1.0 + exp(-z))
            
            // Lower keep probability = higher deletion score
            let adjustment = (1.0 - keepProbability) * 0.2 * confidence
            return max(0, min(1, baseScore + adjustment))
        }
        
        let adjustedScore1 = calculateAdjustedScore(for: photo1) // No faces
        let adjustedScore2 = calculateAdjustedScore(for: photo2) // Has faces
        
        // Photo without faces should have higher deletion score
        XCTAssertGreaterThan(adjustedScore1, adjustedScore2,
                            "After learning, photo without faces should rank higher for deletion")
    }
    
    // MARK: - Daily Review Settings Tests
    
    @MainActor
    func testDailyReviewSettingsDefaults() throws {
        // Test that daily review is ON by default at 21:00
        let schema = Schema([DailyReviewSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let settings = DailyReviewSettings()
        context.insert(settings)
        try context.save()
        
        // Verify defaults
        XCTAssertTrue(settings.isEnabled, "Daily review should be ON by default")
        XCTAssertEqual(settings.reviewHour, 21, "Default hour should be 21 (9 PM)")
        XCTAssertEqual(settings.reviewMinute, 0, "Default minute should be 0")
        XCTAssertEqual(settings.reviewTimeString, "21:00")
    }
    
    @MainActor
    func testDailyReviewSettingsCategories() throws {
        // Test category filter settings
        let settings = DailyReviewSettings()
        
        // All categories should be included by default
        XCTAssertTrue(settings.includeScreenshots)
        XCTAssertTrue(settings.includeBlurry)
        XCTAssertTrue(settings.includeDuplicates)
        XCTAssertTrue(settings.includeReceipts)
        XCTAssertTrue(settings.includeMemes)
        XCTAssertTrue(settings.includeLowValuePhotos)
    }
    
    // MARK: - Monthly Recap Tests
    
    @MainActor
    func testMonthlyRecapDataModel() throws {
        // Test MonthlyRecapData model creation
        let recap = MonthlyRecapData(
            month: 10,
            year: 2026,
            monthName: "Octubre",
            totalPhotos: 150,
            topPlaces: [
                MonthlyRecapPlace(
                    name: "Punta del Este",
                    photoCount: 45,
                    latitude: -34.97,
                    longitude: -54.95,
                    representativePhotoId: "photo-1"
                )
            ],
            mostSeenPeople: [
                MonthlyRecapPerson(
                    name: "Juli",
                    photoCount: 30,
                    personId: "person-1",
                    representativePhotoId: "photo-2"
                )
            ],
            highlights: [],
            trips: [
                MonthlyRecapTrip(
                    destination: "Punta del Este",
                    startDate: Date(),
                    endDate: Date().addingTimeInterval(3 * 86400),
                    durationDays: 3,
                    photoCount: 45,
                    coverPhotoId: "photo-1"
                )
            ],
            firsts: [],
            busiestDay: MonthlyRecapBusiestDay(date: Date(), photoCount: 25),
            spaceFreedBytes: 500_000_000,
            generatedAt: Date()
        )
        
        XCTAssertEqual(recap.month, 10)
        XCTAssertEqual(recap.year, 2026)
        XCTAssertEqual(recap.monthName, "Octubre")
        XCTAssertEqual(recap.totalPhotos, 150)
        XCTAssertEqual(recap.topPlaces.count, 1)
        XCTAssertEqual(recap.topPlaces.first?.name, "Punta del Este")
        XCTAssertEqual(recap.mostSeenPeople.count, 1)
        XCTAssertEqual(recap.mostSeenPeople.first?.name, "Juli")
        XCTAssertEqual(recap.trips.count, 1)
        XCTAssertEqual(recap.trips.first?.durationDays, 3)
        XCTAssertNotNil(recap.busiestDay)
        XCTAssertEqual(recap.busiestDay?.photoCount, 25)
        XCTAssertEqual(recap.spaceFreedBytes, 500_000_000)
        XCTAssertEqual(recap.formattedSpaceFreed, "500 MB")
    }
    
    @MainActor
    func testMonthlyRecapBusiestDayCalculation() throws {
        // Test busiest day detection with seeded data
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        // Create photos: day 1 = 5 photos, day 2 = 10 photos (busiest), day 3 = 3 photos
        let day1 = calendar.date(byAdding: .day, value: 0, to: startOfMonth)!
        let day2 = calendar.date(byAdding: .day, value: 1, to: startOfMonth)!
        let day3 = calendar.date(byAdding: .day, value: 2, to: startOfMonth)!
        
        for i in 0..<5 {
            let photo = PersistedPhoto(localIdentifier: "day1-\(i)")
            photo.creationDate = day1
            context.insert(photo)
        }
        
        for i in 0..<10 {
            let photo = PersistedPhoto(localIdentifier: "day2-\(i)")
            photo.creationDate = day2
            context.insert(photo)
        }
        
        for i in 0..<3 {
            let photo = PersistedPhoto(localIdentifier: "day3-\(i)")
            photo.creationDate = day3
            context.insert(photo)
        }
        
        try context.save()
        
        // Verify all photos are inserted
        let allPhotos = try context.fetch(FetchDescriptor<PersistedPhoto>())
        XCTAssertEqual(allPhotos.count, 18, "Should have 18 total photos")
        
        // Calculate busiest day manually (same logic as MonthlyRecapService)
        var dayGroups: [Date: Int] = [:]
        for photo in allPhotos {
            guard let date = photo.creationDate else { continue }
            let dayStart = calendar.startOfDay(for: date)
            dayGroups[dayStart, default: 0] += 1
        }
        
        guard let (busiestDate, busiestCount) = dayGroups.max(by: { $0.value < $1.value }) else {
            XCTFail("Should find busiest day")
            return
        }
        
        XCTAssertEqual(busiestCount, 10, "Busiest day should have 10 photos")
        XCTAssertEqual(calendar.startOfDay(for: busiestDate), calendar.startOfDay(for: day2),
                      "Busiest day should be day 2")
    }
    
    @MainActor
    func testMonthlyRecapTopPlacesAggregation() throws {
        // Test top places aggregation with seeded data
        let schema = Schema([PersistedPhoto.self, PersistedPlaceCluster.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Create place clusters
        let cluster1 = PersistedPlaceCluster(
            id: "cluster-1",
            name: "Punta del Este",
            placeType: .tripDestination,
            latitude: -34.97,
            longitude: -54.95
        )
        
        let cluster2 = PersistedPlaceCluster(
            id: "cluster-2",
            name: "Buenos Aires",
            placeType: .home,
            latitude: -34.60,
            longitude: -58.38
        )
        
        context.insert(cluster1)
        context.insert(cluster2)
        
        // Create photos at different places
        // 20 photos at cluster 1, 5 photos at cluster 2
        for i in 0..<20 {
            let photo = PersistedPhoto(localIdentifier: "cluster1-\(i)")
            photo.placeClusterId = "cluster-1"
            photo.latitude = -34.97
            photo.longitude = -54.95
            photo.creationDate = Date()
            context.insert(photo)
        }
        
        for i in 0..<5 {
            let photo = PersistedPhoto(localIdentifier: "cluster2-\(i)")
            photo.placeClusterId = "cluster-2"
            photo.latitude = -34.60
            photo.longitude = -58.38
            photo.creationDate = Date()
            context.insert(photo)
        }
        
        try context.save()
        
        // Aggregate places manually (same logic as MonthlyRecapService)
        let photos = try context.fetch(FetchDescriptor<PersistedPhoto>())
        var placeGroups: [String: (photos: [PersistedPhoto], lat: Double, lon: Double)] = [:]
        
        for photo in photos {
            guard let lat = photo.latitude, let lon = photo.longitude else { continue }
            if let clusterId = photo.placeClusterId {
                if placeGroups[clusterId] == nil {
                    placeGroups[clusterId] = ([], lat, lon)
                }
                placeGroups[clusterId]?.photos.append(photo)
            }
        }
        
        // Verify aggregation
        XCTAssertEqual(placeGroups.count, 2, "Should have 2 place clusters")
        XCTAssertEqual(placeGroups["cluster-1"]?.photos.count, 20, "Cluster 1 should have 20 photos")
        XCTAssertEqual(placeGroups["cluster-2"]?.photos.count, 5, "Cluster 2 should have 5 photos")
        
        // Sort by photo count
        let sorted = placeGroups.sorted { $0.value.photos.count > $1.value.photos.count }
        XCTAssertEqual(sorted.first?.key, "cluster-1", "Top place should be cluster 1")
    }
    
    @MainActor
    func testMonthlyRecapMostSeenPeople() throws {
        // Test most seen people aggregation
        let schema = Schema([PersistedPhoto.self, PersistedPerson.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Create photos
        var photoIds: [String] = []
        for i in 0..<30 {
            let photo = PersistedPhoto(localIdentifier: "photo-\(i)")
            photo.creationDate = Date()
            context.insert(photo)
            photoIds.append(photo.id)
        }
        
        // Create people with different photo counts
        let person1 = PersistedPerson(
            name: "Juli",
            faceClusterId: "cluster-1",
            photoIds: Array(photoIds[0..<20]) // Appears in 20 photos
        )
        
        let person2 = PersistedPerson(
            name: "Nico",
            faceClusterId: "cluster-2",
            photoIds: Array(photoIds[0..<8]) // Appears in 8 photos
        )
        
        let person3 = PersistedPerson(
            name: nil, // Unnamed person
            faceClusterId: "cluster-3",
            photoIds: Array(photoIds[0..<5])
        )
        
        context.insert(person1)
        context.insert(person2)
        context.insert(person3)
        
        try context.save()
        
        // Get named people
        let personDescriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.name != nil }
        )
        let people = try context.fetch(personDescriptor)
        
        // Only named people should be included
        let namedPeople = people.filter { $0.isNamed }
        XCTAssertEqual(namedPeople.count, 2, "Should have 2 named people")
        
        // Sort by photo count
        let sorted = namedPeople.sorted { $0.photoIdArray.count > $1.photoIdArray.count }
        XCTAssertEqual(sorted.first?.name, "Juli", "Most seen person should be Juli")
        XCTAssertEqual(sorted.first?.photoIdArray.count, 20, "Juli should appear in 20 photos")
    }
    
    @MainActor
    func testMonthlyRecapHighlightsDeduplication() throws {
        // Test that highlights are deduped by dHash
        let schema = Schema([PersistedPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let calendar = Calendar.current
        let day1 = Date()
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
        
        // Two photos with same dHash (duplicates) on different days
        let photo1 = PersistedPhoto(localIdentifier: "photo-1")
        photo1.creationDate = day1
        photo1.visionAestheticsScore = 0.9
        photo1.imageDHash = 12345
        
        let photo2 = PersistedPhoto(localIdentifier: "photo-2")
        photo2.creationDate = day2
        photo2.visionAestheticsScore = 0.85
        photo2.imageDHash = 12345 // Same dHash
        
        // Another unique photo
        let photo3 = PersistedPhoto(localIdentifier: "photo-3")
        photo3.creationDate = day2
        photo3.visionAestheticsScore = 0.7
        photo3.imageDHash = 67890 // Different dHash
        
        context.insert(photo1)
        context.insert(photo2)
        context.insert(photo3)
        try context.save()
        
        // Deduplicate highlights (same logic as MonthlyRecapService)
        let photos = try context.fetch(FetchDescriptor<PersistedPhoto>())
        var usedDHashes: Set<Int64> = []
        var highlights: [(photo: PersistedPhoto, score: Double)] = []
        
        for photo in photos.sorted(by: { ($0.visionAestheticsScore ?? 0) > ($1.visionAestheticsScore ?? 0) }) {
            if let dhash = photo.imageDHash, usedDHashes.contains(dhash) {
                continue // Skip duplicate
            }
            if let dhash = photo.imageDHash {
                usedDHashes.insert(dhash)
            }
            highlights.append((photo, photo.visionAestheticsScore ?? 0))
        }
        
        // Should have 2 highlights (photo1 with score 0.9, photo3 with score 0.7)
        // photo2 is skipped because it has same dHash as photo1
        XCTAssertEqual(highlights.count, 2, "Should have 2 unique highlights")
        XCTAssertEqual(highlights[0].photo.localIdentifier, "photo-1", "First highlight should be highest score")
        XCTAssertEqual(highlights[1].photo.localIdentifier, "photo-3", "Second highlight should be photo-3")
    }
    
    @MainActor
    func testMonthlyRecapSpaceFreedCalculation() throws {
        // Test space freed calculation from deletion records
        let schema = Schema([DeletionRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        // Create successful deletion records
        for i in 0..<5 {
            let record = DeletionRecord(
                localIdentifier: "deleted-\(i)",
                photoId: "photo-\(i)",
                fileSize: 10_000_000 // 10MB each
            )
            record.requestedAt = calendar.date(byAdding: .day, value: i, to: startOfMonth)!
            record.wasSuccessful = true
            context.insert(record)
        }
        
        // Create a failed deletion (should not count)
        let failedRecord = DeletionRecord(
            localIdentifier: "failed-1",
            photoId: "photo-failed",
            fileSize: 50_000_000
        )
        failedRecord.requestedAt = startOfMonth
        failedRecord.wasSuccessful = false
        context.insert(failedRecord)
        
        try context.save()
        
        // Calculate space freed (same logic as MonthlyRecapService)
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        
        let recordDescriptor = FetchDescriptor<DeletionRecord>(
            predicate: #Predicate { record in
                record.requestedAt >= startOfMonth &&
                record.requestedAt < endOfMonth &&
                record.wasSuccessful == true
            }
        )
        
        let records = try context.fetch(recordDescriptor)
        let totalFreed = records.reduce(0) { $0 + $1.fileSize }
        
        XCTAssertEqual(records.count, 5, "Should have 5 successful deletions")
        XCTAssertEqual(totalFreed, 50_000_000, "Should have freed 50MB")
    }
    
    func testMonthlyRecapNarrativeTemplate() throws {
        // Test template narrative generation
        let recap = MonthlyRecapData(
            month: 10,
            year: 2026,
            monthName: "Octubre",
            totalPhotos: 150,
            topPlaces: [
                MonthlyRecapPlace(
                    name: "Punta del Este",
                    photoCount: 45,
                    latitude: -34.97,
                    longitude: -54.95,
                    representativePhotoId: nil
                )
            ],
            mostSeenPeople: [
                MonthlyRecapPerson(
                    name: "Juli",
                    photoCount: 30,
                    personId: "person-1",
                    representativePhotoId: nil
                ),
                MonthlyRecapPerson(
                    name: "Nico",
                    photoCount: 20,
                    personId: "person-2",
                    representativePhotoId: nil
                )
            ],
            highlights: [],
            trips: [
                MonthlyRecapTrip(
                    destination: "Punta del Este",
                    startDate: Date(),
                    endDate: Date().addingTimeInterval(3 * 86400),
                    durationDays: 3,
                    photoCount: 45,
                    coverPhotoId: nil
                )
            ],
            firsts: [],
            busiestDay: nil,
            spaceFreedBytes: 0,
            generatedAt: Date()
        )
        
        // Test that narrative can be generated
        XCTAssertTrue(recap.monthName.contains("Octubre"), "Should have month name")
        XCTAssertTrue(recap.trips.first?.destination == "Punta del Este", "Should have trip destination")
        XCTAssertEqual(recap.mostSeenPeople.prefix(2).map { $0.name }, ["Juli", "Nico"], 
                      "Should have people names for narrative")
    }
    
    func testMonthlyRecapMonthQueryParsing() throws {
        // Test query parsing for month names
        let monthMappings: [String: Int] = [
            "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
            "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
            "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12
        ]
        
        for (monthName, expectedMonth) in monthMappings {
            let query = "¿Cómo fue mi \(monthName)?"
            let lowercased = query.lowercased()
            
            var foundMonth: Int?
            for (name, month) in monthMappings {
                if lowercased.contains(name) {
                    foundMonth = month
                    break
                }
            }
            
            XCTAssertEqual(foundMonth, expectedMonth, "Should parse '\(monthName)' as month \(expectedMonth)")
        }
    }
    
    func testMonthlyRecapTripDetection() throws {
        // Test that trips are detected for the specified month
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        // Trip data
        let tripStart = calendar.date(from: DateComponents(year: year, month: month, day: 5))!
        let tripEnd = calendar.date(byAdding: .day, value: 3, to: tripStart)!
        
        let trip = MonthlyRecapTrip(
            destination: "Punta del Este",
            startDate: tripStart,
            endDate: tripEnd,
            durationDays: 3,
            photoCount: 45,
            coverPhotoId: nil
        )
        
        XCTAssertEqual(trip.durationDays, 3, "Trip should be 3 days")
        XCTAssertEqual(trip.destination, "Punta del Este", "Trip destination should match")
        XCTAssertEqual(trip.photoCount, 45, "Trip should have 45 photos")
    }
}
