// ScreenshotTests.swift
// Capture screenshots of every main screen for visual review

import XCTest

final class ScreenshotTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-seedFixturePhotos", "-AppleLanguages", "(es-AR)", "-AppleLocale", "es_AR"]
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Screenshot Capture
    
    func testCaptureAllScreenshots() throws {
        skipOnboardingIfNeeded()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else { return }
        
        // Index-only tab hops. Named Momentos chips time out on CI snapshots.
        let names = ["01_home_screen", "03_assistant_empty", "06_moments_timeline", "10_settings"]
        for (index, name) in names.enumerated() {
            tabBar.buttons.element(boundBy: index).tap()
            sleep(1)
            captureScreenshot(name: name)
        }
    }
    
    func testCaptureOnboardingScreenshots() throws {
        // Launch with fresh state to see onboarding
        let freshApp = XCUIApplication()
        freshApp.launchArguments = ["--uitesting", "--reset-onboarding"]
        freshApp.launch()
        
        sleep(2)
        
        // Check if onboarding is visible
        let onboardingIndicator = freshApp.pageIndicators.firstMatch
        let continueButton = freshApp.buttons["Continuar"]
        
        if onboardingIndicator.exists || continueButton.exists {
            // Screen 1
            captureScreenshot(name: "00_onboarding_1", app: freshApp)
            
            if continueButton.exists {
                continueButton.tap()
                sleep(1)
                captureScreenshot(name: "00_onboarding_2", app: freshApp)
            }
            
            if continueButton.exists {
                continueButton.tap()
                sleep(1)
                captureScreenshot(name: "00_onboarding_3", app: freshApp)
            }
        }
    }
    
    func testCaptureDarkModeScreenshots() throws {
        // Dark mode is default, these are the main screenshots
        skipOnboardingIfNeeded()
        
        // Capture each tab in dark mode
        let tabs = ["Inicio", "Asistente", "Momentos", "Ajustes"]
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else { return }
        for (index, tabName) in tabs.enumerated() {
            tabBar.buttons.element(boundBy: index).tap()
            sleep(1)
            captureScreenshot(name: "dark_\(String(format: "%02d", index))_\(tabName.lowercased())")
        }
    }
    
    func testCaptureLoadingStates() throws {
        // Launch app and capture loading states before content loads
        let freshApp = XCUIApplication()
        freshApp.launchArguments = ["--uitesting", "--slow-scan"]
        freshApp.launch()
        
        skipOnboardingIfNeeded()
        
        // Capture loading state
        captureScreenshot(name: "loading_01_initial", app: freshApp)
        
        sleep(2)
        captureScreenshot(name: "loading_02_scanning", app: freshApp)
    }
    
    func testCaptureEmptyStates() throws {
        // Seeded fixtures mean empty-state copy is not guaranteed. Capture the
        // screens without CONTAINS queries — 'sin' matches most Spanish labels
        // and times out evaluating the accessibility tree (~160s on CI).
        skipOnboardingIfNeeded()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else { return }
        tabBar.buttons.element(boundBy: 2).tap()
        sleep(1)
        captureScreenshot(name: "empty_or_content_moments")
    }
    
    // MARK: - Helpers
    
    private func captureScreenshot(name: String, app: XCUIApplication? = nil) {
        // XCUIScreen does not walk the app accessibility tree; app.screenshot()
        // timed out for ~280s on CI after visiting Momentos / Asistente.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("📸 Captured screenshot: \(name)")
    }
    
    private func skipOnboardingIfNeeded() {
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 3) {
            return
        }
        
        let skipButton = app.buttons["Saltar"]
        if skipButton.exists {
            skipButton.tap()
        }
        
        let continueButton = app.buttons["Continuar"]
        while continueButton.waitForExistence(timeout: 1) {
            continueButton.tap()
        }
        
        let startButton = app.buttons["Comenzar"]
        if startButton.waitForExistence(timeout: 1) {
            startButton.tap()
        }
        
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow Full Access"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }
        
        _ = tabBar.waitForExistence(timeout: 10)
    }
    
    private func navigateToCleanup() {
        let homeTab = app.tabBars.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
        }
        
        sleep(1)
        
        let cleanupButton = app.buttons["Limpiar"]
        let cleanupCell = app.cells.matching(identifier: "cleanup").firstMatch
        
        if cleanupButton.exists {
            cleanupButton.tap()
        } else if cleanupCell.exists {
            cleanupCell.tap()
        }
    }
}
