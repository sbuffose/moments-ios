// Walks every main screen/state and keeps a screenshot per stop.
// Light and dark; device slug comes from UITEST_DEVICE_SLUG or the simulator name.

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
    
    private var deviceSlug: String {
        if let env = ProcessInfo.processInfo.environment["UITEST_DEVICE_SLUG"], !env.isEmpty {
            return env
        }
        let name = app.identifier.lowercased()
        if name.contains("se") { return "iphonese" }
        return "iphone16pro"
    }
    
    private func runTour(appearance: String, scheme: String) throws {
        let device = resolvedDeviceSlug()
        
        launch(["-showOnboarding", appearance], seed: false, skipOnboarding: false)
        XCTAssertTrue(
            existsId("onboarding.root", timeout: 16)
                || existsId("onboarding.page1", timeout: 4)
                || app.buttons["onboarding.continue"].waitForExistence(timeout: 4),
            "Onboarding page 1"
        )
        capture("onboarding_page1", scheme: scheme, device: device)
        assertChrome([app.otherElements["onboarding.page1"], app.buttons["onboarding.continue"]])
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.otherElements["onboarding.page2"].waitForExistence(timeout: 4))
        capture("onboarding_page2", scheme: scheme, device: device)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.otherElements["onboarding.page3"].waitForExistence(timeout: 4))
        capture("onboarding_permission", scheme: scheme, device: device)
        
        launch(["-showOnboarding", "-simulatePhotosDenied", appearance], seed: false, skipOnboarding: false)
        XCTAssertTrue(
            existsId("onboarding.photosDenied", timeout: 12)
                || existsId("onboarding.photosDeniedTitle", timeout: 4)
                || app.staticTexts["Sin acceso a Fotos"].waitForExistence(timeout: 4),
            "Photos-denied onboarding"
        )
        capture("permission_denied", scheme: scheme, device: device)
        
        launch(["-simulateFirstScan", appearance], seed: false)
        XCTAssertTrue(app.otherElements["firstRun.screen"].waitForExistence(timeout: 15)
                      || app.otherElements["firstRun.root"].waitForExistence(timeout: 4),
                      "First-run analyzing")
        capture("home_scanning", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", appearance])
        openHome()
        XCTAssertTrue(app.otherElements["home.scrollView"].waitForExistence(timeout: 12), "Ready home")
        capture("home_ready", scheme: scheme, device: device)
        assertChrome([app.buttons["home.reviewButton"], app.staticTexts["home.heroHeadline"]])
        
        launch(["-seedFixturePhotos", "-simulateActiveScan", appearance])
        openHome()
        capture("home_scanning_ready", scheme: scheme, device: device)
        
        launch(["-simulateEmptyHome", appearance], seed: false)
        openHome()
        XCTAssertTrue(app.otherElements["home.emptyState"].waitForExistence(timeout: 12), "Empty home")
        capture("home_empty", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", "-simulateSpaceSaved", appearance])
        openHome()
        XCTAssertTrue(app.staticTexts["home.freedTotal"].waitForExistence(timeout: 10)
                      || app.otherElements["home.freedTotal"].waitForExistence(timeout: 3),
                      "Home with savings total")
        capture("home_savings", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", appearance])
        openReview()
        XCTAssertTrue(app.otherElements["review.root"].waitForExistence(timeout: 12), "Review")
        capture("review_card", scheme: scheme, device: device)
        if app.otherElements["review.blackFrameLabel"].exists || app.staticTexts["Foto casi toda negra"].exists {
            capture("review_black", scheme: scheme, device: device)
        }
        if app.buttons["review.keepButton"].waitForExistence(timeout: 4) {
            app.buttons["review.keepButton"].press(forDuration: 1.0)
            sleep(1)
            capture("review_snooze", scheme: scheme, device: device)
            if app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'semana'")).firstMatch.exists {
                app.tap()
            }
        }
        if app.buttons["review.tagButton"].waitForExistence(timeout: 3)
            || app.buttons["Etiquetar"].waitForExistence(timeout: 2) {
            let tag = app.buttons["review.tagButton"].exists ? app.buttons["review.tagButton"] : app.buttons["Etiquetar"]
            tag.tap()
            XCTAssertTrue(app.otherElements["review.tagSheet"].waitForExistence(timeout: 8)
                          || app.navigationBars["Etiquetar"].waitForExistence(timeout: 4),
                          "Etiquetar sheet")
            capture("review_etiquetar", scheme: scheme, device: device)
            if app.buttons["Cancelar"].exists { app.buttons["Cancelar"].tap() }
        }
        if app.buttons["review.keepButton"].exists {
            app.buttons["review.keepButton"].tap()
            sleep(1)
            capture("review_keep", scheme: scheme, device: device)
        }
        if app.buttons["review.deleteButton"].exists {
            app.buttons["review.deleteButton"].tap()
            sleep(1)
            capture("review_delete", scheme: scheme, device: device)
        }
        
        launch(["-seedFixturePhotos", "-simulateReviewSimilar", appearance])
        openReview()
        _ = app.otherElements["review.similarGroup"].waitForExistence(timeout: 8)
        capture("review_similar", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", "-simulateReviewVideo", appearance])
        openReview()
        capture("review_video", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", "-simulateKeptAllSummary", appearance])
        openReview()
        XCTAssertTrue(app.otherElements["review.batchSummary"].waitForExistence(timeout: 12), "Kept-all summary")
        capture("summary_kept_all", scheme: scheme, device: device)
        assertChrome([app.buttons["review.moreBatch"], app.buttons["review.doneForToday"]])
        
        launch(["-seedFixturePhotos", "-simulateDeletedSummary", appearance])
        openReview()
        XCTAssertTrue(app.otherElements["review.batchSummary"].waitForExistence(timeout: 12), "Deleted summary")
        capture("summary_deleted", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", "-simulateNewPhotoCheck", appearance])
        XCTAssertTrue(app.otherElements["newPhotoCheck.sheet"].waitForExistence(timeout: 15), "New-photo popup")
        capture("new_photo_popup", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", appearance])
        openTab(2)
        XCTAssertTrue(app.otherElements["moments.root"].waitForExistence(timeout: 10)
                      || app.buttons["chip.timeline"].waitForExistence(timeout: 4),
                      "Momentos list")
        capture("momentos_list", scheme: scheme, device: device)
        let row = app.otherElements["moment.row.thumb.loaded"].firstMatch
        if row.waitForExistence(timeout: 6) {
            row.tap()
            _ = app.otherElements["moments.detail"].waitForExistence(timeout: 6)
            capture("momentos_detail", scheme: scheme, device: device)
            app.navigationBars.buttons.firstMatch.tap()
        }
        
        openTab(1)
        XCTAssertTrue(app.waitForAssistant(timeout: 10), "Asistente empty")
        capture("asistente_empty", scheme: scheme, device: device)
        let field = app.textFields["assistant.input"].exists ? app.textFields["assistant.input"] : app.textFields.firstMatch
        if field.waitForExistence(timeout: 6) {
            field.tap()
            field.typeText("como fue mi octubre")
            app.submitKeyboard()
            _ = app.otherElements["assistant.answerCard"].waitForExistence(timeout: 8)
            capture("asistente_recap", scheme: scheme, device: device)
            if field.exists {
                field.tap()
                field.typeText("fotos de Familia")
                app.submitKeyboard()
                sleep(1)
                capture("asistente_search", scheme: scheme, device: device)
            }
        }
        if app.buttons["assistant.suggestion"].firstMatch.exists {
            capture("asistente_catalog", scheme: scheme, device: device)
        }
        
        openTab(3)
        XCTAssertTrue(app.otherElements["settings.root"].waitForExistence(timeout: 10)
                      || app.buttons["settings.newPhotoCheck"].waitForExistence(timeout: 4),
                      "Settings")
        capture("settings", scheme: scheme, device: device)
        
        launch(["-seedFixturePhotos", "-simulateNotificationsDenied", appearance])
        openTab(3)
        let notif = app.buttons["settings.notifications"]
        if notif.waitForExistence(timeout: 8) || app.buttons["Notificaciones"].waitForExistence(timeout: 3) {
            (notif.exists ? notif : app.buttons["Notificaciones"]).tap()
            _ = app.otherElements["settings.notificationsDenied"].waitForExistence(timeout: 6)
            capture("notifications_denied", scheme: scheme, device: device)
        }
    }
    
    private func resolvedDeviceSlug() -> String {
        if let env = ProcessInfo.processInfo.environment["UITEST_DEVICE_SLUG"], !env.isEmpty {
            return env
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
        return false
    }
    
    private func openHome() {
        if app.tabBars.firstMatch.exists {
            app.tabBars.firstMatch.buttons.element(boundBy: 0).tap()
        }
        _ = app.otherElements["home.root"].waitForExistence(timeout: 8)
    }
    
    private func openTab(_ index: Int) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 12), "Tab bar")
        tabBar.buttons.element(boundBy: index).tap()
    }
    
    private func openReview() {
        openHome()
        let review = app.buttons["home.reviewButton"]
        let start = app.buttons["Empezar"]
        XCTAssertTrue(review.waitForExistence(timeout: 10) || start.waitForExistence(timeout: 4), "Empezar")
        if review.exists { review.tap() } else { start.tap() }
        XCTAssertTrue(app.otherElements["review.root"].waitForExistence(timeout: 10), "Review opened")
    }
    
    private func capture(_ stem: String, scheme: String, device: String) {
        let name = "\(stem)_\(scheme)_\(device)"
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        
        if let dir = ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(name).png")
            try? shot.pngRepresentation.write(to: url)
        }
        print("DESIGN_TOUR \(name)")
    }
    
    private func assertChrome(_ elements: [XCUIElement]) {
        DesignLayoutAssert.assertVisibleChrome(app, elements: elements.filter(\.exists))
    }
}
