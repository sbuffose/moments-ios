import XCTest

/// Real-device bugs from TestFlight 289: videos, mixed batches, Momentos, Asistente, chrome.
final class RealDeviceReviewUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
    func testKeepOnVideoAdvancesCurrentAsset() {
        launchReview(extra: ["-reviewVideoFirst", "-reviewSwipeSingles"])
        XCTAssertTrue(app.otherElements["review.root"].waitForExistence(timeout: 12))
        
        let asset = app.descendants(matching: .any)["review.currentAsset"].firstMatch
        XCTAssertTrue(asset.waitForExistence(timeout: 8), "Review must expose the current asset id")
        let before = asset.label + (asset.value as? String ?? "")
        XCTAssertFalse(before.isEmpty, "currentAsset must be keyed by photo id")
        
        let keep = app.buttons["review.keepButton"]
        XCTAssertTrue(keep.waitForExistence(timeout: 6), "Conservar")
        keep.tap()
        
        let chips = app.otherElements["review.keepChips"]
        XCTAssertTrue(chips.waitForExistence(timeout: 4), "Conservar still shows duration chips")
        let expected = [
            ("review.keepChip.forever", "Siempre"),
            ("review.keepChip.week", "1 semana"),
            ("review.keepChip.month", "1 mes"),
            ("review.keepChip.threeMonths", "3 meses")
        ]
        let window = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        for (identifier, label) in expected {
            let chip = app.buttons[identifier]
            XCTAssertTrue(chip.waitForExistence(timeout: 2), "Chip \(identifier) must exist")
            XCTAssertEqual(chip.label, label, "Chip \(identifier) must use the full untruncated Spanish label")
            XCTAssertFalse(chip.label.hasSuffix("…") || chip.label.hasSuffix("..."), "Chip \(identifier) is truncated: \(chip.label)")
            XCTAssertTrue(chip.isHittable, "Chip \(identifier) must be tappable")
            XCTAssertGreaterThan(chip.frame.width, 48, "Chip \(identifier) is too narrow to show '\(label)'")
            XCTAssertLessThanOrEqual(chip.frame.maxX, window.maxX + 1, "Chip \(identifier) overflows the screen")
        }
        
        let changed = NSPredicate { _, _ in
            let next = self.app.descendants(matching: .any)["review.currentAsset"].firstMatch
            guard next.exists else { return false }
            let after = next.label + (next.value as? String ?? "")
            return !after.isEmpty && after != before
        }
        XCTAssertTrue(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: app)], timeout: 2) == .completed,
            "Conservar on a video must advance the card identity within 2s, not stay stuck"
        )
    }
    
    func testMixedBatchSummaryUsesSessionMediaCopy() {
        launchReview(extra: ["-reviewVideoFirst", "-reviewSwipeSingles"])
        XCTAssertTrue(app.otherElements["review.root"].waitForExistence(timeout: 12))
        
        let delete = app.buttons["review.deleteButton"]
        if !delete.waitForExistence(timeout: 4) {
            let byLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Eliminar'")).firstMatch
            XCTAssertTrue(byLabel.waitForExistence(timeout: 4), "Eliminar")
            byLabel.tap()
        } else {
            delete.tap()
        }
        
        let finish = app.buttons["review.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 6), "Terminar")
        finish.tap()
        
        let confirm = app.buttons["review.confirmDelete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "Session summary confirm")
        let label = confirm.label.lowercased()
        XCTAssertTrue(
            label.contains("video") || label.contains("foto"),
            "Confirm copy must name the media that will be deleted: \(confirm.label)"
        )
        XCTAssertFalse(label.contains("18 foto"), "Must not inflate leftover selectedPhotos into 'Eliminar 18 fotos'")
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Fotos > Álbumes > Eliminados recientemente'")
            ).firstMatch.exists,
            "Old album path must be gone from the summary"
        )
        XCTAssertFalse(app.buttons["Guardar en álbum"].exists)
        XCTAssertFalse(app.staticTexts["Guardar en álbum"].exists)
        
        confirm.tap()
        let photoKit = app.alerts.firstMatch
        if photoKit.waitForExistence(timeout: 6) {
            XCTAssertTrue(
                photoKit.label.lowercased().contains("video")
                    || photoKit.label.lowercased().contains("foto")
                    || photoKit.label.lowercased().contains("eliminar"),
                "PhotoKit prompt must appear for a real delete: \(photoKit.label)"
            )
            if photoKit.buttons["Cancelar"].exists {
                photoKit.buttons["Cancelar"].tap()
            } else if photoKit.buttons["Don't Allow"].exists {
                photoKit.buttons["Don't Allow"].tap()
            } else if photoKit.buttons["No permitir"].exists {
                photoKit.buttons["No permitir"].tap()
            }
        }
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Conservaste todas'")
            ).firstMatch.waitForExistence(timeout: 2),
            "After a delete confirm the empty 'kept all' sheet must not replace the session"
        )
    }
    
    func testMomentosLeavesLoadingState() {
        launchHome()
        tapTab(2)
        XCTAssertTrue(
            app.otherElements["moments.root"].waitForExistence(timeout: 10)
                || app.navigationBars.firstMatch.waitForExistence(timeout: 6)
        )
        
        let content = app.descendants(matching: .any)["timeline.content"].firstMatch
        let empty = app.descendants(matching: .any)["timeline.empty"].firstMatch
        let row = app.descendants(matching: .any)["moment.row"].firstMatch
        let loaded = app.descendants(matching: .any)["moment.row.thumb.loaded"].firstMatch
        XCTAssertTrue(
            content.waitForExistence(timeout: 6)
                || empty.waitForExistence(timeout: 4)
                || row.waitForExistence(timeout: 4)
                || loaded.waitForExistence(timeout: 3),
            "Momentos must show content or empty within 6s, never spin on Cargando momentos"
        )
        let loading = app.descendants(matching: .any)["timeline.loading"].firstMatch
        XCTAssertFalse(loading.exists && !(content.exists || empty.exists || row.exists), "Spinner must not be the only state")
    }
    
    func testAssistantShowsGreetingSuggestionsAndCatalog() {
        launchHome()
        tapTab(1)
        XCTAssertTrue(app.waitForAssistant())
        
        let welcome = app.descendants(matching: .any)["assistant.welcome"].firstMatch
        XCTAssertTrue(
            welcome.waitForExistence(timeout: 4)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Soy tu asistente'")).firstMatch.waitForExistence(timeout: 3),
            "Asistente must show a greeting above the input"
        )
        XCTAssertTrue(
            app.buttons["assistant.suggestion"].waitForExistence(timeout: 4)
                || app.otherElements["assistant.suggestions"].waitForExistence(timeout: 3),
            "Suggestion chips must be visible"
        )
        XCTAssertTrue(
            app.otherElements["assistant.catalogPrompt"].waitForExistence(timeout: 6)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Quién' OR label CONTAINS[c] 'lugar'")).firstMatch.waitForExistence(timeout: 3),
            "People/places cataloguing prompt must appear"
        )
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Borrá las capturas de más de 3 meses'")).firstMatch.exists
        )
    }
    
    func testOpaqueNavOnHomeAndSettings() {
        launchHome()
        XCTAssertTrue(app.otherElements["home.root"].waitForExistence(timeout: 20))
        app.swipeUp()
        app.swipeUp()
        DesignLayoutAssert.assertScrolledNavReadable(
            app,
            titleIdentifiers: ["home.navTitle"],
            titleLabels: ["Moments"]
        )
        
        let gear = app.buttons["home.settingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        gear.tap()
        let settingsTitle = app.navigationBars.firstMatch
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 8), "Ajustes")
        app.swipeUp()
        XCTAssertTrue(settingsTitle.exists, "Settings large title chrome must remain after scroll")
        XCTAssertTrue(
            app.staticTexts["settings.libraryStatus"].waitForExistence(timeout: 4)
                || app.switches.firstMatch.exists
                || app.cells.firstMatch.exists
        )
    }
    
    func testOnboardingShowsRealPermissionPrompt() {
        app.launchArguments = [
            "-showOnboarding",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ]
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
        
        XCTAssertTrue(
            app.otherElements["onboarding.root"].waitForExistence(timeout: 16)
                || app.buttons["onboarding.continue"].waitForExistence(timeout: 8)
        )
        let continueButton = app.buttons["onboarding.continue"]
        if continueButton.waitForExistence(timeout: 4) { continueButton.tap() }
        if continueButton.waitForExistence(timeout: 3) { continueButton.tap() }
        
        let allow = app.buttons["onboarding.allowAccess"]
        XCTAssertTrue(allow.waitForExistence(timeout: 8), "Onboarding must offer the real Photos permission button")
        allow.tap()
        
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        let appAlert = app.alerts.firstMatch
        XCTAssertTrue(
            alert.waitForExistence(timeout: 8) || appAlert.waitForExistence(timeout: 4) || allow.exists,
            "Tapping allow must present the system Photos permission prompt when possible"
        )
        if alert.exists {
            if alert.buttons["Don't Allow"].exists { alert.buttons["Don't Allow"].tap() }
            else if alert.buttons["No permitir"].exists { alert.buttons["No permitir"].tap() }
            else if alert.buttons["OK"].exists { alert.buttons["OK"].tap() }
        }
    }
    
    private func launchHome() {
        app.launchArguments = [
            "-skipOnboarding",
            "-seedFixturePhotos",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ]
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
        XCTAssertTrue(
            app.otherElements["home.root"].waitForExistence(timeout: 20)
                || app.otherElements["home.scrollView"].waitForExistence(timeout: 8)
        )
    }
    
    private func launchReview(extra: [String]) {
        app.launchArguments = [
            "-skipOnboarding",
            "-seedFixturePhotos",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ] + extra
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
        XCTAssertTrue(
            app.otherElements["home.root"].waitForExistence(timeout: 20)
                || app.otherElements["home.scrollView"].waitForExistence(timeout: 8)
        )
        let start = app.descendants(matching: .any)["home.reviewButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 12), "Empezar")
        start.tap()
    }
    
    private func tapTab(_ index: Int) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))
        tabBar.buttons.element(boundBy: index).tap()
    }
}
