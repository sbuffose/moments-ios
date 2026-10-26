// ScreenshotTests.swift
// Capture screenshots of every main screen for visual review
// Waits for scan to complete before capturing

import XCTest

final class ScreenshotTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-skipOnboarding", "-AppleLanguages", "(es-AR)", "-AppleLocale", "es_AR"]
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Helpers
    
    private func waitForScanToComplete(timeout: TimeInterval = 90) -> Bool {
        let tabBar = app.tabBars.firstMatch
        return tabBar.waitForExistence(timeout: timeout)
    }
    
    private func waitForHomeContent(timeout: TimeInterval = 30) -> Bool {
        let gbText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'GB' OR label CONTAINS[c] 'MB' OR label CONTAINS[c] 'KB'")).firstMatch
        let reviewButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Revisar'")).firstMatch
        let spaceCard = app.otherElements["home.spaceCard"]
        let emptyState = app.otherElements["home.emptyState"]
        
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if gbText.exists || reviewButton.exists || spaceCard.exists || emptyState.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }
    
    private func captureScreenshot(name: String, targetApp: XCUIApplication? = nil) {
        let application = targetApp ?? app!
        let screenshot = application.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Captured screenshot: \(name)")
    }
    
    // MARK: - Main Screenshot Capture Test
    
    func testCaptureAllScreenshots() throws {
        // Wait for scan to complete
        print("⏳ Waiting for scan to complete...")
        XCTAssertTrue(waitForScanToComplete(timeout: 90), "Scan should complete and show tab bar")
        
        let tabBar = app.tabBars.firstMatch
        
        // 1. Home Screen with Space Card
        print("📱 Capturing Home Screen...")
        tabBar.buttons.element(boundBy: 0).tap()
        _ = waitForHomeContent(timeout: 30)
        Thread.sleep(forTimeInterval: 2)
        
        let gbText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'GB' OR label CONTAINS[c] 'MB'")).firstMatch
        print("📊 Home has space data: \(gbText.exists)")
        captureScreenshot(name: "01_home_screen")
        
        // 2. Cleanup Categories
        print("📱 Capturing Cleanup Categories...")
        let reviewButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Revisar'")).firstMatch
        if reviewButton.waitForExistence(timeout: 5) {
            reviewButton.tap()
            Thread.sleep(forTimeInterval: 2)
            captureScreenshot(name: "02_cleanup_categories")
            
            // 3. Cleanup Review Grid
            print("📱 Capturing Cleanup Review Grid...")
            let firstCategory = app.cells.firstMatch
            if firstCategory.waitForExistence(timeout: 3) {
                firstCategory.tap()
                Thread.sleep(forTimeInterval: 2)
                captureScreenshot(name: "03_cleanup_review_grid")
                
                // Go back to categories
                if app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            
            // 4. Trash view (if available)
            let trashButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Papelera' OR label CONTAINS[c] 'Trash' OR label CONTAINS[c] 'Eliminados'")).firstMatch
            if trashButton.waitForExistence(timeout: 2) {
                trashButton.tap()
                Thread.sleep(forTimeInterval: 2)
                captureScreenshot(name: "04_trash")
                if app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                }
            }
            
            // Go back to home
            if app.navigationBars.buttons.firstMatch.exists {
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        } else {
            print("⚠️ No review button found - capturing home with empty state")
            captureScreenshot(name: "02_home_empty_state")
        }
        
        // 5. Assistant with Query and Answer Card
        print("📱 Capturing Assistant...")
        tabBar.buttons.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 2)
        captureScreenshot(name: "05_assistant_empty")
        
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 5) {
            textField.tap()
            Thread.sleep(forTimeInterval: 0.5)
            textField.typeText("¿Cuánto espacio puedo liberar?")
            
            // Submit the query
            let returnKey = app.keyboards.buttons["Return"]
            let enviarKey = app.keyboards.buttons["enviar"]
            if enviarKey.exists {
                enviarKey.tap()
            } else if returnKey.exists {
                returnKey.tap()
            }
            
            // Wait for response
            Thread.sleep(forTimeInterval: 4)
            
            // Check for answer card
            let responseFound = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'GB' OR label CONTAINS[c] 'MB' OR label CONTAINS[c] 'liberar' OR label CONTAINS[c] 'encontré'")).count > 0
            print("📊 Assistant response found: \(responseFound)")
            captureScreenshot(name: "06_assistant_answer_card")
        }
        
        // 6. Search Results
        print("📱 Capturing Search Results...")
        if textField.waitForExistence(timeout: 3) {
            textField.tap()
            
            // Clear existing text
            if let currentText = textField.value as? String, !currentText.isEmpty {
                textField.clearText()
            }
            
            textField.typeText("captura")
            
            let returnKey = app.keyboards.buttons["Return"]
            let enviarKey = app.keyboards.buttons["enviar"]
            if enviarKey.exists {
                enviarKey.tap()
            } else if returnKey.exists {
                returnKey.tap()
            }
            
            Thread.sleep(forTimeInterval: 3)
            captureScreenshot(name: "07_search_results")
        }
        
        // 7. Moments Timeline
        print("📱 Capturing Moments...")
        tabBar.buttons.element(boundBy: 2).tap()
        Thread.sleep(forTimeInterval: 2)
        captureScreenshot(name: "08_moments_timeline")
        
        // 8. Fechas Section
        print("📱 Capturing Fechas...")
        let fechasChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Fechas'")).firstMatch
        if fechasChip.waitForExistence(timeout: 3) {
            fechasChip.tap()
            Thread.sleep(forTimeInterval: 2)
            captureScreenshot(name: "09_fechas")
        }
        
        // 9. People
        let peopleChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Personas'")).firstMatch
        if peopleChip.waitForExistence(timeout: 2) {
            peopleChip.tap()
            Thread.sleep(forTimeInterval: 1)
            captureScreenshot(name: "10_moments_people")
        }
        
        // 10. Places
        let placesChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Lugares'")).firstMatch
        if placesChip.waitForExistence(timeout: 2) {
            placesChip.tap()
            Thread.sleep(forTimeInterval: 1)
            captureScreenshot(name: "11_moments_places")
        }
        
        // 11. Settings
        print("📱 Capturing Settings...")
        tabBar.buttons.element(boundBy: 3).tap()
        Thread.sleep(forTimeInterval: 1)
        captureScreenshot(name: "12_settings")
        
        print("✅ All screenshots captured successfully")
    }
    
    // MARK: - Onboarding Screenshots (Separate Test)
    
    func testCaptureOnboardingScreenshots() throws {
        let freshApp = XCUIApplication()
        freshApp.launchArguments = ["--reset-onboarding", "-AppleLanguages", "(es-AR)", "-AppleLocale", "es_AR"]
        freshApp.launch()
        
        Thread.sleep(forTimeInterval: 2)
        
        let continueButton = freshApp.buttons["Continuar"]
        let pageIndicator = freshApp.pageIndicators.firstMatch
        
        if pageIndicator.exists || continueButton.exists {
            captureScreenshot(name: "00_onboarding_1", targetApp: freshApp)
            
            if continueButton.exists {
                continueButton.tap()
                Thread.sleep(forTimeInterval: 1)
                captureScreenshot(name: "00_onboarding_2", targetApp: freshApp)
            }
            
            if continueButton.exists {
                continueButton.tap()
                Thread.sleep(forTimeInterval: 1)
                captureScreenshot(name: "00_onboarding_3", targetApp: freshApp)
            }
        }
    }
    
    // MARK: - Dark Mode Screenshots (Default Theme)
    
    func testCaptureDarkModeScreenshots() throws {
        XCTAssertTrue(waitForScanToComplete(timeout: 90), "Scan should complete")
        _ = waitForHomeContent(timeout: 30)
        
        let tabBar = app.tabBars.firstMatch
        let tabs = ["Inicio", "Asistente", "Momentos", "Ajustes"]
        
        for (index, tabName) in tabs.enumerated() {
            let tab = tabBar.buttons[tabName]
            if tab.exists {
                tab.tap()
                Thread.sleep(forTimeInterval: 1)
                captureScreenshot(name: "dark_\(String(format: "%02d", index))_\(tabName.lowercased())")
            }
        }
    }
}

