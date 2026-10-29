// Build266RegressionTests.swift
// Device-recording regressions: raw keys, thumbnails that survive 20s,
// screenshots of every main tab.

import XCTest

final class Build266RegressionTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-skipOnboarding",
            "-seedFixturePhotos",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ]
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        if app.state != .notRunning {
            app.terminate()
        }
        app = nil
    }
    
    func testAsistenteHasNoRawCleanupKeysAndThumbsStayLoaded() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "App must launch")
        
        attachScreenshot(name: "266_home")
        XCTAssertFalse(
            app.otherElements["tab.selectionPill"].exists,
            "No leftover selection pill overlay"
        )
        
        tabBar.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.waitForAssistant(), "Asistente must open")
        attachScreenshot(name: "266_asistente")
        
        assertNoRawLocalizationKeys(on: "Asistente")
        
        let hyphenated = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Revi-sar' OR label CONTAINS 'Elimi-nar'")
        )
        XCTAssertEqual(hyphenated.count, 0, "Card buttons must not hyphenate words")
        XCTAssertFalse(app.buttons["Eliminar todo"].exists, "Must not offer Eliminar todo for the whole library")
        
        let review = app.buttons["assistant.reviewButton"]
        if review.waitForExistence(timeout: 6) {
            XCTAssertEqual(review.label.replacingOccurrences(of: "eye", with: "").trimmingCharacters(in: .whitespaces), "Revisar")
            XCTAssertFalse(review.label.contains("-"))
        }
        
        let loadedBefore = loadedThumbnailCount()
        XCTAssertGreaterThan(loadedBefore, 0, "Asistente cards must show real thumbnails")
        
        let expired = Date().addingTimeInterval(20)
        while Date() < expired {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        
        let failed = app.descendants(matching: .any)["photo.thumb.failed"]
        let loading = app.descendants(matching: .any)["photo.thumb.loading"]
        let stillLoaded = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'photo.thumb.loaded' AND value == 'image'")
        )
        XCTAssertGreaterThan(
            stillLoaded.count,
            0,
            "Thumbnails must still be images after 20s, not grey placeholders"
        )
        XCTAssertFalse(failed.exists, "No failed thumbs after 20s on Asistente")
        XCTAssertFalse(loading.exists, "Thumbs must not revert to the loading placeholder after 20s")
        
        tabBar.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.waitForMoments(), "Momentos must open")
        attachScreenshot(name: "266_momentos")
        
        tabBar.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(
            app.otherElements["settings.libraryStatus"].waitForExistence(timeout: 10)
                || app.staticTexts["settings_library_status"].waitForExistence(timeout: 4)
                || app.navigationBars.firstMatch.waitForExistence(timeout: 6),
            "Settings must open"
        )
        attachScreenshot(name: "266_settings")
        if app.otherElements["settings.indexedCount"].exists {
            let value = app.otherElements["settings.indexedCount"].value as? String ?? ""
            XCTAssertFalse(value == "0", "Settings indexed count must be the real library size, not 0")
        }
        
        tabBar.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.waitForHome(), "Home must stay fully opaque after a tab switch")
        attachScreenshot(name: "266_home_after_tabs")
        let hero = app.staticTexts["home.heroHeadline"]
        if hero.waitForExistence(timeout: 6) {
            XCTAssertTrue(
                hero.label.contains("lote de hoy") || hero.label.contains("liberar"),
                "Home headline must describe today's batch: \(hero.label)"
            )
        }
        XCTAssertTrue(app.buttons["home.settingsButton"].exists, "Gear stays in the Home toolbar")
    }
    
    private func loadedThumbnailCount() -> Int {
        let loaded = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'photo.thumb.loaded'")
        )
        if loaded.firstMatch.waitForExistence(timeout: 10) {
            return loaded.count
        }
        return 0
    }
    
    private func assertNoRawLocalizationKeys(on screen: String) {
        let raw = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'cleanup_category_' OR value CONTAINS 'cleanup_category_'")
        )
        XCTAssertEqual(raw.count, 0, "\(screen) shows raw cleanup_category_ keys: \(raw.allElementsBoundByIndex.map(\.label))")
        
        let snake = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '^[a-z]+_[a-zA-Z0-9_]+$'")
        )
        XCTAssertEqual(snake.count, 0, "\(screen) shows raw snake_case keys: \(snake.allElementsBoundByIndex.map(\.label))")
    }
    
    private func attachScreenshot(name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
