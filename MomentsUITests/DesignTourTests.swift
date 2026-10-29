// Walks main screens/states and keeps a screenshot per stop.
// Light and dark; device slug comes from UITEST_DEVICE_SLUG.

import XCTest

final class DesignTourTests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    
    override func tearDownWithError() throws {
        if app.state != .notRunning {
            app.terminate()
        }
        app = nil
    }
    
    func testDesignTourLight() throws {
        try runTour(appearance: "-uiAppearanceLight", scheme: "light")
    }
    
    func testDesignTourDark() throws {
        try runTour(appearance: "-uiAppearanceDark", scheme: "dark")
    }
    
    private func runTour(appearance: String, scheme: String) throws {
        let device = resolvedDeviceSlug()
        
        launch(["-showOnboarding", appearance], seed: false, skipOnboarding: false)
        let onboardingVisible = existsId("onboarding.root", timeout: 16)
            || existsId("onboarding.page1", timeout: 4)
            || app.buttons["onboarding.continue"].waitForExistence(timeout: 4)
            || app.buttons["Continuar"].waitForExistence(timeout: 4)
            || app.staticTexts["Liberá espacio sin perder lo importante"].waitForExistence(timeout: 4)
            || app.staticTexts["onboarding.root"].waitForExistence(timeout: 2)
        capture("onboarding_page1", scheme: scheme, device: device)
        XCTAssertTrue(onboardingVisible, "Onboarding page 1")
        assertScreen(.onboarding)
        assertChrome([app.otherElements["onboarding.page1"], app.buttons["onboarding.continue"]])
        let continueButton = app.buttons["onboarding.continue"].exists
            ? app.buttons["onboarding.continue"]
            : app.buttons["Continuar"]
        if continueButton.exists {
            continueButton.tap()
            _ = existsId("onboarding.page2", timeout: 4)
            capture("onboarding_page2", scheme: scheme, device: device)
            if continueButton.exists { continueButton.tap() }
            _ = existsId("onboarding.page3", timeout: 4)
            capture("onboarding_page3", scheme: scheme, device: device)
        }
        
        launch(["-simulateFirstScan", appearance], seed: false)
        XCTAssertTrue(
            app.otherElements["firstRun.screen"].waitForExistence(timeout: 15)
                || app.otherElements["firstRun.root"].waitForExistence(timeout: 4),
            "First-run analyzing"
        )
        capture("home_scanning", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", appearance])
        openHome()
        XCTAssertTrue(app.otherElements["home.scrollView"].waitForExistence(timeout: 12)
                      || app.otherElements["home.root"].waitForExistence(timeout: 4), "Ready home")
        capture("home_ready", scheme: scheme, device: device)
        assertScreen(.home)
        assertChrome([app.buttons["home.reviewButton"]])
        
        launch(["-simulateEmptyHome", appearance], seed: false)
        openHome()
        _ = app.otherElements["home.emptyState"].waitForExistence(timeout: 8)
        capture("home_empty", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", "-simulateSpaceSaved", appearance])
        openHome()
        capture("home_savings", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", appearance])
        openReview()
        capture("review_card", scheme: scheme, device: device)
        assertScreen(.review)
        
        launch(["-seedFixturePhotos", "-simulateMidSwipeKeep", appearance])
        openReview()
        _ = app.staticTexts["review.swipeStamp"].waitForExistence(timeout: 4)
        capture("review_midswipe_keep", scheme: scheme, device: device)
        assertScreen(.review)
        
        launch(["-seedFixturePhotos", "-simulateMidSwipeDelete", appearance])
        openReview()
        _ = app.staticTexts["review.swipeStamp"].waitForExistence(timeout: 4)
        capture("review_midswipe_delete", scheme: scheme, device: device)
        assertScreen(.review)
        
        launch(["-seedFixturePhotos", "-simulateMidSwipeSnooze", appearance])
        openReview()
        _ = app.staticTexts["review.swipeStamp"].waitForExistence(timeout: 4)
        capture("review_midswipe_snooze", scheme: scheme, device: device)
        assertScreen(.review)
        
        launch(["-seedFixturePhotos", "-simulateKeptAllSummary", appearance])
        openReview()
        XCTAssertTrue(existsId("review.batchSummary", timeout: 12), "Kept-all summary")
        capture("summary_kept_all", scheme: scheme, device: device)
        assertScreen(.summaryKept)
        
        launch(["-seedFixturePhotos", "-simulateDeletedSummary", appearance])
        openReview()
        XCTAssertTrue(existsId("review.batchSummary", timeout: 12), "Deleted summary")
        capture("summary_deleted", scheme: scheme, device: device)
        assertScreen(.summaryDeleted)
        
        launch(["-seedFixturePhotos", appearance])
        openTab(2)
        capture("momentos_list", scheme: scheme, device: device)
        openTab(1)
        capture("asistente_empty", scheme: scheme, device: device)
        openTab(3)
        capture("settings", scheme: scheme, device: device)
    }
    
    private func resolvedDeviceSlug() -> String {
        let env = ProcessInfo.processInfo.environment
        for key in ["UITEST_DEVICE_SLUG", "TEST_RUNNER_UITEST_DEVICE_SLUG"] {
            if let value = env[key], !value.isEmpty {
                return value
            }
        }
        return "iphone16pro"
    }
    
    private func launch(_ extras: [String], seed: Bool = true, skipOnboarding: Bool = true) {
        if app.state != .notRunning {
            app.terminate()
        }
        app = XCUIApplication()
        var args = ["-AppleLanguages", "(es-AR)", "-AppleLocale", "es_AR"]
        if skipOnboarding {
            args.append("-skipOnboarding")
        }
        if seed {
            args.append("-seedFixturePhotos")
        }
        args.append(contentsOf: extras)
        app.launchArguments = args
        app.launchEnvironment = [
            "UI_TESTING": "1",
            "UITEST_MODE": "1",
            "UITEST_DEVICE_SLUG": resolvedDeviceSlug(),
            "UITEST_SCREENSHOT_DIR": ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_DIR"] ?? ""
        ]
        app.launch()
        if extras.contains("-showOnboarding") {
            _ = existsId("onboarding.root", timeout: 10)
                || app.buttons["onboarding.continue"].waitForExistence(timeout: 6)
        } else {
            _ = app.tabBars.firstMatch.waitForExistence(timeout: 16)
                || existsId("firstRun.screen", timeout: 4)
                || existsId("home.root", timeout: 4)
        }
    }
    
    private func existsId(_ id: String, timeout: TimeInterval) -> Bool {
        if app.otherElements[id].waitForExistence(timeout: timeout) { return true }
        if app.buttons[id].waitForExistence(timeout: 1) { return true }
        if app.staticTexts[id].waitForExistence(timeout: 1) { return true }
        if app.images[id].waitForExistence(timeout: 1) { return true }
        return app.descendants(matching: .any)[id].waitForExistence(timeout: 1)
    }
    
    private func openHome() {
        if app.tabBars.firstMatch.exists {
            app.tabBars.firstMatch.buttons.element(boundBy: 0).tap()
        }
        _ = app.otherElements["home.root"].waitForExistence(timeout: 8)
    }
    
    private func openTab(_ index: Int) {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 12) else { return }
        let button = tabBar.buttons.element(boundBy: index)
        if button.exists { button.tap() }
    }
    
    private func openReview() {
        openHome()
        let review = app.buttons["home.reviewButton"]
        let start = app.buttons["Empezar"]
        if review.waitForExistence(timeout: 10) {
            review.tap()
        } else if start.waitForExistence(timeout: 4) {
            start.tap()
        }
        _ = app.otherElements["review.root"].waitForExistence(timeout: 10)
    }
    
    private func capture(_ stem: String, scheme: String, device: String) {
        let name = "\(stem)_\(scheme)_\(device)"
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        
        let env = ProcessInfo.processInfo.environment
        if let dir = env["UITEST_SCREENSHOT_DIR"] ?? env["TEST_RUNNER_UITEST_SCREENSHOT_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        }
        print("DESIGN_TOUR \(name)")
    }
    
    private func assertChrome(_ elements: [XCUIElement]) {
        DesignLayoutAssert.assertVisibleChrome(app, elements: elements.filter(\.exists))
    }
    
    private func assertScreen(_ screen: DesignTourScreen) {
        DesignLayoutAssert.assertScreen(app, screen)
    }
}
