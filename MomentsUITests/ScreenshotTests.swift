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
        
        // 1. Home Screen
        captureScreenshot(name: "01_home_screen")
        
        // 2. Home with Space Card
        let homeTab = app.tabBars.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
            sleep(2)
            captureScreenshot(name: "02_home_space_card")
        }
        
        // 3. Assistant Tab
        let assistantTab = app.tabBars.buttons["Asistente"]
        if assistantTab.exists {
            assistantTab.tap()
            sleep(1)
            captureScreenshot(name: "03_assistant_empty")
            
            // Do not type + submit here: the keyboard snapshot walk times out on CI.
        }
        
        // 4. Moments Tab - Timeline
        let momentsTab = app.tabBars.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
            sleep(1)
            captureScreenshot(name: "06_moments_timeline")
            
            // Try different views
            let peopleChip = app.buttons["Personas"]
            if peopleChip.exists {
                peopleChip.tap()
                sleep(1)
                captureScreenshot(name: "07_moments_people")
            }
            
            let placesChip = app.buttons["Lugares"]
            if placesChip.exists {
                placesChip.tap()
                sleep(1)
                captureScreenshot(name: "08_moments_places")
            }
            
            let datesChip = app.buttons["Fechas"]
            if datesChip.exists {
                datesChip.tap()
                sleep(1)
                captureScreenshot(name: "09_moments_dates")
            }
        }
        
        // 5. Settings Tab
        let settingsTab = app.tabBars.buttons["Ajustes"]
        if settingsTab.exists {
            settingsTab.tap()
            sleep(1)
            captureScreenshot(name: "10_settings")
            
            // Notifications settings if available
            let notifRow = app.cells["Notificaciones"]
            if notifRow.exists {
                notifRow.tap()
                sleep(1)
                captureScreenshot(name: "11_settings_notifications")
                app.navigationBars.buttons.firstMatch.tap()
            }
            
            // Storage settings
            let storageRow = app.cells["Almacenamiento"]
            if storageRow.exists {
                storageRow.tap()
                sleep(1)
                captureScreenshot(name: "12_settings_storage")
                app.navigationBars.buttons.firstMatch.tap()
            }
        }
        
        // 6. Cleanup Flow
        navigateToCleanup()
        sleep(2)
        captureScreenshot(name: "13_cleanup_categories")
        
        // Tap first category
        let firstCategory = app.cells.firstMatch
        if firstCategory.exists {
            firstCategory.tap()
            sleep(1)
            captureScreenshot(name: "14_cleanup_review")
            
            // Select a photo
            let photoGrid = app.collectionViews.firstMatch
            if photoGrid.exists && photoGrid.cells.count > 0 {
                photoGrid.cells.firstMatch.tap()
                sleep(1)
                captureScreenshot(name: "15_cleanup_photo_selected")
            }
        }
        
        // 7. Search Results
        if assistantTab.exists {
            assistantTab.tap()
            let input = app.textFields.firstMatch
            if input.exists {
                input.tap()
                captureScreenshot(name: "16_search_results")
            }
        }
        
        // 8. Cataloging Card (if available)
        if homeTab.exists {
            homeTab.tap()
            sleep(1)
            
            let catalogingCard = app.cells.matching(identifier: "cataloging").firstMatch
            if catalogingCard.exists {
                captureScreenshot(name: "17_cataloging_card")
                catalogingCard.tap()
                sleep(1)
                captureScreenshot(name: "18_cataloging_detail")
            }
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
        
        for (index, tabName) in tabs.enumerated() {
            let tab = app.tabBars.buttons[tabName]
            if tab.exists {
                tab.tap()
                sleep(1)
                captureScreenshot(name: "dark_\(String(format: "%02d", index))_\(tabName.lowercased())")
            }
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
        
        let momentsTab = app.tabBars.buttons["Momentos"]
        guard momentsTab.waitForExistence(timeout: 10) else { return }
        momentsTab.tap()
        captureScreenshot(name: "empty_or_content_moments")
        
        let placesChip = app.buttons["Lugares"]
        if placesChip.waitForExistence(timeout: 3) {
            placesChip.tap()
            sleep(1)
            captureScreenshot(name: "empty_or_content_places")
        }
        
        let datesChip = app.buttons["Fechas"]
        if datesChip.waitForExistence(timeout: 3) {
            datesChip.tap()
            sleep(1)
            captureScreenshot(name: "empty_or_content_dates")
        }
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
