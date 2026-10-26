// ScreenshotTests.swift
// Capture screenshots of every main screen for visual review

import XCTest

final class ScreenshotTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
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
            
            // Type a query
            let input = app.textFields.firstMatch
            if input.exists {
                input.tap()
                input.typeText("mostrame fotos de viajes")
                captureScreenshot(name: "04_assistant_typing")
                
                app.keyboards.buttons["Return"].tap()
                sleep(2)
                captureScreenshot(name: "05_assistant_response")
            }
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
                input.clearAndTypeText("Buenos Aires")
                app.keyboards.buttons["Return"].tap()
                sleep(2)
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
        // Would need a truly empty library to test this properly
        // For now, capture what we can
        skipOnboardingIfNeeded()
        
        // Navigate to places with no places
        let momentsTab = app.tabBars.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
            
            let placesChip = app.buttons["Lugares"]
            if placesChip.exists {
                placesChip.tap()
                sleep(1)
                
                // Check for empty state
                if app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'no hay' OR label CONTAINS[c] 'sin' OR label CONTAINS[c] 'vacío'")).count > 0 {
                    captureScreenshot(name: "empty_state_places")
                }
            }
            
            let datesChip = app.buttons["Fechas"]
            if datesChip.exists {
                datesChip.tap()
                sleep(1)
                
                if app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'no hay' OR label CONTAINS[c] 'sin' OR label CONTAINS[c] 'vacío'")).count > 0 {
                    captureScreenshot(name: "empty_state_dates")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func captureScreenshot(name: String, app: XCUIApplication? = nil) {
        let targetApp = app ?? self.app!
        let screenshot = targetApp.screenshot()
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
