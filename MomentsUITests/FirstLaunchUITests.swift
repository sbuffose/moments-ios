import XCTest

/// Fresh-install first-launch bugs from TestFlight 316.
final class FirstLaunchUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
    // MARK: - 1. Onboarding titles / subtitles fully visible
    
    func testOnboardingPageTextIsFullyVisible() {
        launchOnboarding(extra: ["-uiAppearanceLight"])
        assertOnboardingPage(
            title: "Liberá espacio sin perder lo importante",
            subtitle: "Tu teléfono lleno no es un problema, es una oportunidad."
        )
        
        tapContinue()
        assertOnboardingPage(
            title: "Reviví tus mejores momentos",
            subtitle: "Tus fotos cuentan historias. Dejá que las encuentres."
        )
        
        app.terminate()
        app = XCUIApplication()
        launchOnboarding(extra: ["-uiAppearanceDark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"])
        assertOnboardingPage(
            title: "Liberá espacio sin perder lo importante",
            subtitle: "Tu teléfono lleno no es un problema, es una oportunidad."
        )
        tapContinue()
        assertOnboardingPage(
            title: "Reviví tus mejores momentos",
            subtitle: "Tus fotos cuentan historias. Dejá que las encuentres."
        )
    }
    
    // MARK: - 2. Explanation sheet last row above Empezar
    
    func testExplanationSheetKeepsLastRowAboveEmpezar() {
        launchFresh(extra: ["-showFirstRunExplanation", "-skipOnboarding"])
        XCTAssertTrue(
            app.otherElements["firstRun.explanation"].waitForExistence(timeout: 12)
                || app.buttons["firstRun.startButton"].waitForExistence(timeout: 6),
            "First-run explanation sheet must appear"
        )
        
        let start = app.buttons["firstRun.startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "Empezar must be pinned")
        XCTAssertTrue(start.isHittable, "Empezar must stay tappable")
        
        let lastRow = app.descendants(matching: .any)["firstRun.explanation.lastRow"].firstMatch
        let lastByLabel = app.staticTexts["Vos decidís qué borrar"]
        XCTAssertTrue(
            lastRow.waitForExistence(timeout: 6) || lastByLabel.waitForExistence(timeout: 4),
            "Last explanation row must exist in the tree"
        )
        
        let row = lastRow.exists ? lastRow : lastByLabel
        if !row.isHittable || row.frame.maxY > start.frame.minY - 4 {
            if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        
        XCTAssertTrue(
            lastRow.exists || lastByLabel.exists,
            "Last row must remain after scrolling"
        )
        let visibleRow = lastRow.exists ? lastRow : lastByLabel
        XCTAssertTrue(visibleRow.isHittable || visibleRow.frame.maxY <= start.frame.minY + 2,
                      "Last row must sit above Empezar or be scrollable there. row=\(visibleRow.frame) button=\(start.frame)")
        XCTAssertLessThan(
            visibleRow.frame.maxY,
            start.frame.maxY,
            "Last row must not be buried under the button"
        )
        XCTAssertFalse(start.frame.contains(visibleRow.frame.insetBy(dx: 8, dy: 8)),
                       "Empezar must not cover the last row")
    }
    
    // MARK: - 3. Progress bar advances
    
    func testFirstRunProgressBarAdvances() {
        launchFresh(extra: ["-simulateFirstScan", "-simulateActiveScan", "-skipOnboarding"])
        XCTAssertTrue(
            app.otherElements["firstRun.screen"].waitForExistence(timeout: 15)
                || app.otherElements["firstRun.root"].waitForExistence(timeout: 6)
                || app.staticTexts["firstRun.title"].waitForExistence(timeout: 4),
            "First-run analyzing screen"
        )
        
        let bar = app.descendants(matching: .any)["firstRun.softProgress"].firstMatch
        let valueEl = app.descendants(matching: .any)["firstRun.softProgressValue"].firstMatch
        XCTAssertTrue(
            bar.waitForExistence(timeout: 8) || valueEl.waitForExistence(timeout: 4),
            "Progress bar must be visible"
        )
        
        let before = progressValue()
        XCTAssertGreaterThan(before, 0, "Bar must not sit at 0")
        
        let moved = NSPredicate { _, _ in
            self.progressValue() > before + 0.002
        }
        XCTAssertTrue(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: app)], timeout: 8) == .completed,
            "Bar must visibly advance. before=\(before) after=\(progressValue())"
        )
    }
    
    // MARK: - 4. Momentos warm in-progress, not spinner
    
    func testMomentosShowsWarmInProgressNotSpinner() {
        launchFresh(extra: ["-simulateFirstScan", "-skipOnboarding"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 16))
        app.tabBars.firstMatch.buttons.element(boundBy: 2).tap()
        
        XCTAssertTrue(
            app.otherElements["moments.root"].waitForExistence(timeout: 10)
                || app.navigationBars.firstMatch.waitForExistence(timeout: 6)
        )
        
        let analyzing = app.descendants(matching: .any)["timeline.analyzing"].firstMatch
        let title = app.staticTexts["timeline.analyzing.title"]
        let titleByLabel = app.staticTexts["Tus momentos se están acomodando"]
        XCTAssertTrue(
            analyzing.waitForExistence(timeout: 8)
                || title.waitForExistence(timeout: 4)
                || titleByLabel.waitForExistence(timeout: 4),
            "Momentos must show the warm in-progress state while analysis runs"
        )
        
        let loading = app.descendants(matching: .any)["timeline.loading"].firstMatch
        XCTAssertFalse(
            loading.exists && !(analyzing.exists || title.exists || titleByLabel.exists),
            "Must not stay on Cargando momentos while analysis is running"
        )
        XCTAssertFalse(
            app.staticTexts["Cargando momentos..."].exists
                && !(analyzing.exists || title.exists || titleByLabel.exists),
            "Spinner copy must not be the only Momentos state"
        )
    }
    
    // MARK: - 5. Photos permission, not notifications
    
    func testAllowAccessRequestsPhotosNotNotifications() {
        launchOnboarding(extra: ["-recordPermissionRequests", "-grantPhotosAccess"])
        tapContinue()
        tapContinue()
        
        let allow = app.buttons["onboarding.allowAccess"]
        XCTAssertTrue(allow.waitForExistence(timeout: 8), "Permitir acceso a Fotos")
        allow.tap()
        
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let text = (alert.label + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")).lowercased()
            XCTAssertFalse(
                text.contains("notif") || text.contains("avis"),
                "Allow Access must not present the notifications prompt: \(text)"
            )
            XCTAssertTrue(
                text.contains("foto") || text.contains("photo") || text.contains("biblioteca"),
                "System prompt must be Photos: \(text)"
            )
            if alert.buttons["Don't Allow"].exists { alert.buttons["Don't Allow"].tap() }
            else if alert.buttons["No permitir"].exists { alert.buttons["No permitir"].tap() }
            else if alert.buttons["OK"].exists { alert.buttons["OK"].tap() }
        }
        
        let last = app.descendants(matching: .any)["permission.lastRequest"].firstMatch
        if last.waitForExistence(timeout: 4) {
            let value = ((last.value as? String) ?? last.label).lowercased()
            XCTAssertEqual(value, "photos", "Onboarding allow must record Photos, got \(value)")
            XCTAssertNotEqual(value, "notifications")
        }
        
        XCTAssertTrue(
            app.otherElements["firstRun.explanation"].waitForExistence(timeout: 10)
                || app.buttons["firstRun.startButton"].waitForExistence(timeout: 6)
                || app.otherElements["firstRun.screen"].waitForExistence(timeout: 6)
                || app.tabBars.firstMatch.waitForExistence(timeout: 6),
            "After Photos grant, onboarding must continue without a notifications prompt"
        )
        XCTAssertFalse(
            springboard.alerts.firstMatch.exists
                && springboard.alerts.firstMatch.label.lowercased().contains("notif"),
            "Notifications must not appear as the next prompt after Permitir acceso a Fotos"
        )
    }
    
    // MARK: - Combined fresh-install flow
    
    func testFreshInstallFlowReachesAnalyzingWithoutTruncationOrCoveredRows() {
        launchOnboarding(extra: ["-grantPhotosAccess", "-recordPermissionRequests"])
        assertOnboardingPage(
            title: "Liberá espacio sin perder lo importante",
            subtitle: "Tu teléfono lleno no es un problema, es una oportunidad."
        )
        tapContinue()
        assertOnboardingPage(
            title: "Reviví tus mejores momentos",
            subtitle: "Tus fotos cuentan historias. Dejá que las encuentres."
        )
        tapContinue()
        
        let allow = app.buttons["onboarding.allowAccess"]
        XCTAssertTrue(allow.waitForExistence(timeout: 8))
        allow.tap()
        
        XCTAssertTrue(
            app.otherElements["firstRun.explanation"].waitForExistence(timeout: 12)
                || app.buttons["firstRun.startButton"].waitForExistence(timeout: 8),
            "Explanation sheet follows Photos grant"
        )
        let lastByLabel = app.staticTexts["Vos decidís qué borrar"]
        if !lastByLabel.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lastByLabel.waitForExistence(timeout: 6) || app.descendants(matching: .any)["firstRun.explanation.lastRow"].firstMatch.exists)
        
        let start = app.buttons["firstRun.startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 6))
        start.tap()
        
        XCTAssertTrue(
            app.otherElements["firstRun.screen"].waitForExistence(timeout: 12)
                || app.staticTexts["Estamos conociendo tus fotos"].waitForExistence(timeout: 8)
                || app.tabBars.firstMatch.waitForExistence(timeout: 8),
            "Empezar must leave the sheet and continue the first-run flow"
        )
    }
    
    // MARK: - Helpers
    
    private func launchOnboarding(extra: [String] = []) {
        app.launchArguments = [
            "-showOnboarding",
            "-resetFirstLaunch",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ] + extra
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
        XCTAssertTrue(
            app.otherElements["onboarding.root"].waitForExistence(timeout: 16)
                || app.buttons["onboarding.continue"].waitForExistence(timeout: 8)
        )
    }
    
    private func launchFresh(extra: [String]) {
        app.launchArguments = [
            "-resetFirstLaunch",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ] + extra
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
    }
    
    private func tapContinue() {
        let button = app.buttons["onboarding.continue"]
        if button.waitForExistence(timeout: 4) {
            button.tap()
        } else if app.buttons["Continuar"].waitForExistence(timeout: 2) {
            app.buttons["Continuar"].tap()
        }
    }
    
    private func assertOnboardingPage(title: String, subtitle: String) {
        let titleEl = app.staticTexts[title]
        let subtitleEl = app.staticTexts[subtitle]
        XCTAssertTrue(titleEl.waitForExistence(timeout: 8), "Full title must be in the tree: \(title)")
        XCTAssertTrue(subtitleEl.waitForExistence(timeout: 6), "Full subtitle must be in the tree: \(subtitle)")
        XCTAssertFalse(titleEl.label.hasSuffix("…") || titleEl.label.hasSuffix("..."), "Title truncated: \(titleEl.label)")
        XCTAssertFalse(subtitleEl.label.hasSuffix("…") || subtitleEl.label.hasSuffix("..."), "Subtitle truncated: \(subtitleEl.label)")
        XCTAssertEqual(titleEl.label, title)
        XCTAssertEqual(subtitleEl.label, subtitle)
        
        let window = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        XCTAssertGreaterThan(titleEl.frame.height, 16, "Title has no height")
        XCTAssertLessThanOrEqual(titleEl.frame.maxX, window.maxX + 2, "Title overflows trailing edge")
        XCTAssertGreaterThanOrEqual(titleEl.frame.minX, window.minX - 2, "Title overflows leading edge")
        XCTAssertLessThanOrEqual(subtitleEl.frame.maxX, window.maxX + 2, "Subtitle overflows trailing edge")
        XCTAssertGreaterThan(subtitleEl.frame.height, 12, "Subtitle has no height")
    }
    
    private func progressValue() -> Double {
        for id in ["firstRun.softProgressValue", "firstRun.softProgress", "scan.progress"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists else { continue }
            let raw = ((element.value as? String) ?? element.label)
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Double(raw) { return parsed }
            if raw.hasSuffix("%"), let parsed = Double(raw.dropLast()) {
                return parsed / 100
            }
        }
        return 0
    }
}
