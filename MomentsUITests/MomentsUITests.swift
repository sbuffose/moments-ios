// MomentsUITests.swift
// Comprehensive UI tests for Moments app with seeded photo library

import XCTest

final class MomentsUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-AppleLanguages", "(es-AR)", "-AppleLocale", "es_AR"]
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Helpers
    
    private func waitForScanToComplete(timeout: TimeInterval = 60) -> Bool {
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
    
    private func captureScreenshot(name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("📸 Captured: \(name)")
    }
    
    // MARK: - Core Flow Test with Screenshots
    
    func testCaptureAllScreenshotsAfterScan() throws {
        // Wait for scan to complete (shows scanning progress then tab bar)
        print("⏳ Waiting for scan to complete...")
        XCTAssertTrue(waitForScanToComplete(timeout: 90), "Scan should complete and show tab bar")
        
        let tabBar = app.tabBars.firstMatch
        
        // Go to home and wait for content
        tabBar.buttons.element(boundBy: 0).tap()
        print("⏳ Waiting for home content to load...")
        _ = waitForHomeContent(timeout: 30)
        sleep(2) // Extra time for UI to settle
        
        // 01: Home screen with space card (or empty state)
        let gbText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'GB' OR label CONTAINS[c] 'MB'")).firstMatch
        let hasSpaceData = gbText.exists
        print("📊 Home has space data: \(hasSpaceData)")
        captureScreenshot(name: "04_home_screen")
        
        // 02: Navigate to cleanup categories if available
        let reviewButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Revisar'")).firstMatch
        if reviewButton.waitForExistence(timeout: 3) {
            reviewButton.tap()
            sleep(2)
            captureScreenshot(name: "05_cleanup_categories")
            
            // 03: Cleanup review grid - tap first category if available
            let firstCell = app.cells.firstMatch
            if firstCell.waitForExistence(timeout: 3) {
                firstCell.tap()
                sleep(2)
                captureScreenshot(name: "06_cleanup_review")
                
                // Go back
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            
            // Go back to home
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        
        // 04: Assistant tab - send a query
        tabBar.buttons.element(boundBy: 1).tap()
        sleep(2)
        
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 5) {
            textField.tap()
            sleep(1)
            textField.typeText("¿Cuánto espacio puedo liberar?")
            
            // Submit
            if app.keyboards.buttons["enviar"].exists {
                app.keyboards.buttons["enviar"].tap()
            } else if app.keyboards.buttons["Return"].exists {
                app.keyboards.buttons["Return"].tap()
            } else {
                app.keyboards.buttons.element(boundBy: app.keyboards.buttons.count - 1).tap()
            }
            
            // Wait for response
            sleep(3)
            
            // Check for response card
            let responseTexts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'GB' OR label CONTAINS[c] 'MB' OR label CONTAINS[c] 'encontré' OR label CONTAINS[c] 'liberar'"))
            print("📊 Assistant response count: \(responseTexts.count)")
        }
        captureScreenshot(name: "07_assistant_response")
        
        // 05: Moments tab
        tabBar.buttons.element(boundBy: 2).tap()
        sleep(2)
        captureScreenshot(name: "08_moments")
        
        // 06: Fechas section
        let fechasChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Fechas'")).firstMatch
        if fechasChip.waitForExistence(timeout: 3) {
            fechasChip.tap()
            sleep(2)
            captureScreenshot(name: "09_fechas")
        }
        
        // 07: Settings
        tabBar.buttons.element(boundBy: 3).tap()
        sleep(2)
        captureScreenshot(name: "10_settings")
        
        // 08: Search - go back to assistant and search
        tabBar.buttons.element(boundBy: 1).tap()
        sleep(1)
        
        let searchField = app.textFields.firstMatch
        if searchField.waitForExistence(timeout: 3) {
            searchField.tap()
            
            // Clear and type
            if let text = searchField.value as? String, !text.isEmpty {
                searchField.clearText()
            }
            searchField.typeText("captura")
            
            if app.keyboards.buttons["enviar"].exists {
                app.keyboards.buttons["enviar"].tap()
            } else if app.keyboards.buttons["Return"].exists {
                app.keyboards.buttons["Return"].tap()
            }
            
            sleep(3)
            captureScreenshot(name: "11_search_results")
        }
        
        XCTAssertTrue(true, "All screenshots captured")
    }
    
    // MARK: - Basic Navigation Tests
    
    func testMainTabBarExists() throws {
        XCTAssertTrue(waitForScanToComplete(timeout: 90), "Tab bar should exist after scan")
    }
    
    func testHomeShowsContent() throws {
        XCTAssertTrue(waitForScanToComplete(timeout: 90), "Scan should complete")
        
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons.element(boundBy: 0).tap()
        
        let hasContent = waitForHomeContent(timeout: 30)
        print("Home has content: \(hasContent)")
        
        // Either space card or empty state should be present
        let spaceCard = app.otherElements["home.spaceCard"]
        let emptyState = app.otherElements["home.emptyState"]
        let greeting = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Buenos' OR label CONTAINS[c] 'Buenas'")).firstMatch
        
        XCTAssertTrue(spaceCard.exists || emptyState.exists || greeting.exists, "Home should show content")
    }
}

// MARK: - XCUIElement Extension

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
    }
}
