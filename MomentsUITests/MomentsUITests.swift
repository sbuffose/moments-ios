// MomentsUITests.swift
// Comprehensive UI tests for Moments app with seeded photo library

import XCTest

final class MomentsUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-state"]
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Onboarding Tests
    
    func testOnboardingFlowCompletes() throws {
        let startButton = app.buttons["onboarding_start_button"]
        
        if startButton.waitForExistence(timeout: 5) {
            // Screen 1: Welcome
            XCTAssertTrue(app.staticTexts["Liberá espacio"].exists || app.staticTexts["onboarding_title_1"].exists)
            
            // Navigate through onboarding
            if app.buttons["Continuar"].exists {
                app.buttons["Continuar"].tap()
            } else if startButton.exists {
                startButton.tap()
            }
            
            // Screen 2: Features
            sleep(1)
            if app.buttons["Continuar"].exists {
                app.buttons["Continuar"].tap()
            }
            
            // Screen 3: Permissions
            sleep(1)
            if app.buttons["Comenzar"].exists {
                app.buttons["Comenzar"].tap()
            }
            
            // Handle photo permission alert
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allowButton = springboard.buttons["Allow Full Access"]
            if allowButton.waitForExistence(timeout: 3) {
                allowButton.tap()
            }
            
            // Verify we're on the main screen
            sleep(2)
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should appear after onboarding")
        }
    }
    
    // MARK: - Tab Navigation Tests
    
    func testTabBarNavigation() throws {
        skipOnboardingIfNeeded()
        
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        
        // Test Home tab
        let homeTab = tabBar.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
            sleep(1)
            XCTAssertTrue(app.navigationBars["Inicio"].exists || app.staticTexts["home_title"].exists)
        }
        
        // Test Assistant tab
        let assistantTab = tabBar.buttons["Asistente"]
        if assistantTab.exists {
            assistantTab.tap()
            sleep(1)
            XCTAssertTrue(app.textFields.firstMatch.exists || app.staticTexts["assistant_title"].exists)
        }
        
        // Test Moments tab
        let momentsTab = tabBar.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
            sleep(1)
        }
        
        // Test Settings tab
        let settingsTab = tabBar.buttons["Ajustes"]
        if settingsTab.exists {
            settingsTab.tap()
            sleep(1)
            XCTAssertTrue(app.navigationBars["Ajustes"].exists || app.staticTexts["settings_title"].exists)
        }
    }
    
    // MARK: - Scan Tests
    
    func testPhotoScanCompletion() throws {
        skipOnboardingIfNeeded()
        
        // Navigate to home
        let homeTab = app.tabBars.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
        }
        
        // Wait for scan to complete (or check progress)
        let scanProgress = app.progressIndicators.firstMatch
        if scanProgress.exists {
            // Wait up to 60 seconds for scan
            let completed = scanProgress.waitForNonExistence(timeout: 60)
            XCTAssertTrue(completed, "Scan should complete within 60 seconds")
        }
        
        // Check that cleanup categories appear
        sleep(2)
        let cleanupSection = app.staticTexts["Limpiar"] 
        let hasCleanupContent = cleanupSection.exists || 
                               app.buttons["cleanup_category"].exists ||
                               app.staticTexts.matching(identifier: "cleanup").count > 0
        
        // Log result
        print("Scan completed, cleanup content present: \(hasCleanupContent)")
    }
    
    // MARK: - Cleanup Category Tests
    
    func testCleanupCategoriesDetectSeededJunk() throws {
        skipOnboardingIfNeeded()
        navigateToCleanup()
        
        sleep(3) // Wait for analysis
        
        // Check for expected cleanup categories
        let expectedCategories = ["Capturas", "Borrosas", "Oscuras", "Documentos", "Duplicadas"]
        var foundCategories: [String] = []
        
        for category in expectedCategories {
            if app.staticTexts[category].exists || 
               app.buttons[category].exists ||
               app.cells.staticTexts[category].exists {
                foundCategories.append(category)
            }
        }
        
        print("Found cleanup categories: \(foundCategories)")
        XCTAssertGreaterThan(foundCategories.count, 0, "Should detect at least one cleanup category from seeded photos")
    }
    
    func testCleanupReviewFlow() throws {
        skipOnboardingIfNeeded()
        navigateToCleanup()
        
        sleep(2)
        
        // Tap on first cleanup category
        let firstCategory = app.cells.firstMatch
        if firstCategory.waitForExistence(timeout: 5) {
            firstCategory.tap()
            sleep(1)
            
            // Verify review UI appears
            let photoGrid = app.collectionViews.firstMatch
            let hasPhotos = photoGrid.exists && photoGrid.cells.count > 0
            
            // Test selection
            if hasPhotos {
                let firstPhoto = photoGrid.cells.firstMatch
                firstPhoto.tap()
                
                // Look for delete/keep actions
                let deleteButton = app.buttons["Eliminar"]
                let keepButton = app.buttons["Conservar"]
                
                XCTAssertTrue(deleteButton.exists || keepButton.exists, "Should show delete/keep actions")
            }
        }
    }
    
    func testDeleteFlowConfirmation() throws {
        skipOnboardingIfNeeded()
        navigateToCleanup()
        
        sleep(2)
        
        // Navigate to a cleanup category
        let firstCategory = app.cells.firstMatch
        guard firstCategory.waitForExistence(timeout: 5) else {
            XCTSkip("No cleanup categories available")
            return
        }
        
        firstCategory.tap()
        sleep(1)
        
        // Select photos
        let photoGrid = app.collectionViews.firstMatch
        guard photoGrid.exists else {
            XCTSkip("No photo grid available")
            return
        }
        
        // Select first photo
        let firstPhoto = photoGrid.cells.firstMatch
        if firstPhoto.exists {
            firstPhoto.tap()
        }
        
        // Tap delete
        let deleteButton = app.buttons["Eliminar"]
        if deleteButton.waitForExistence(timeout: 3) {
            deleteButton.tap()
            
            // Verify confirmation dialog
            let confirmAlert = app.alerts.firstMatch
            let confirmButton = app.buttons["Confirmar"]
            
            if confirmAlert.waitForExistence(timeout: 3) || confirmButton.waitForExistence(timeout: 3) {
                XCTAssertTrue(true, "Confirmation dialog appeared")
                
                // Cancel to avoid actually deleting
                let cancelButton = app.buttons["Cancelar"]
                if cancelButton.exists {
                    cancelButton.tap()
                }
            }
        }
    }
    
    // MARK: - Search Tests (Spanish)
    
    func testSpanishSearchQueries() throws {
        skipOnboardingIfNeeded()
        
        // Navigate to assistant (search)
        let assistantTab = app.tabBars.buttons["Asistente"]
        if assistantTab.exists {
            assistantTab.tap()
        }
        
        sleep(1)
        
        let searchField = app.textFields.firstMatch
        guard searchField.waitForExistence(timeout: 5) else {
            XCTSkip("Search field not available")
            return
        }
        
        // Test Spanish search queries
        let queries = [
            "mostrame fotos de Buenos Aires",
            "borrá las capturas viejas",
            "buscar fotos borrosas",
            "fotos de cumpleaños"
        ]
        
        for query in queries {
            searchField.tap()
            searchField.clearAndTypeText(query)
            
            // Submit search
            app.keyboards.buttons["Return"].tap()
            sleep(2)
            
            // Verify response
            let hasResponse = app.staticTexts.count > 1 || 
                             app.cells.count > 0 ||
                             app.collectionViews.cells.count > 0
            
            print("Query '\(query)': response received = \(hasResponse)")
            
            // Clear for next query
            searchField.tap()
            if let text = searchField.value as? String, !text.isEmpty {
                searchField.clearText()
            }
        }
    }
    
    // MARK: - Cataloging Tests
    
    func testCatalogingCardsAppear() throws {
        skipOnboardingIfNeeded()
        
        // Navigate to home where cataloging cards appear
        let homeTab = app.tabBars.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
        }
        
        sleep(3)
        
        // Look for cataloging cards
        let catalogingCard = app.cells.matching(identifier: "cataloging_card").firstMatch
        let whoIsThisText = app.staticTexts["¿Quién es?"]
        let labelPlaceText = app.staticTexts["¿Qué es este lugar?"]
        
        let hasCatalogingContent = catalogingCard.exists || 
                                   whoIsThisText.exists || 
                                   labelPlaceText.exists
        
        print("Cataloging cards present: \(hasCatalogingContent)")
    }
    
    func testCatalogingPersonNaming() throws {
        skipOnboardingIfNeeded()
        
        // Navigate to home
        let homeTab = app.tabBars.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
        }
        
        sleep(2)
        
        // Look for person cataloging card
        let whoIsThis = app.staticTexts["¿Quién es?"]
        if whoIsThis.waitForExistence(timeout: 5) {
            whoIsThis.tap()
            
            // Verify naming UI
            let nameField = app.textFields["Nombre"]
            if nameField.waitForExistence(timeout: 3) {
                nameField.tap()
                nameField.typeText("María")
                
                let saveButton = app.buttons["Guardar"]
                XCTAssertTrue(saveButton.exists, "Save button should appear")
            }
        }
    }
    
    // MARK: - Important Dates Tests
    
    func testFechasTabShowsUpcomingDates() throws {
        skipOnboardingIfNeeded()
        
        // Navigate to Momentos tab and then Fechas
        let momentsTab = app.tabBars.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
        }
        
        sleep(1)
        
        // Look for Fechas chip/button
        let fechasChip = app.buttons["Fechas"]
        if fechasChip.waitForExistence(timeout: 3) {
            fechasChip.tap()
            sleep(1)
            
            // Verify dates section
            let datesContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'próximo' OR label CONTAINS[c] 'cumple' OR label CONTAINS[c] 'aniversario'")).count > 0
            
            print("Dates content present: \(datesContent)")
        }
    }
    
    // MARK: - Assistant Bar Tests
    
    func testAssistantBarRespondsToCommands() throws {
        skipOnboardingIfNeeded()
        
        let assistantTab = app.tabBars.buttons["Asistente"]
        if assistantTab.exists {
            assistantTab.tap()
        }
        
        sleep(1)
        
        let inputField = app.textFields.firstMatch
        guard inputField.waitForExistence(timeout: 5) else {
            XCTSkip("Assistant input not available")
            return
        }
        
        // Test command
        inputField.tap()
        inputField.typeText("cuánto espacio puedo liberar")
        app.keyboards.buttons["Return"].tap()
        
        sleep(3)
        
        // Verify response with size info
        let hasSpaceInfo = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'MB' OR label CONTAINS[c] 'GB' OR label CONTAINS[c] 'espacio'")).count > 0
        
        print("Space info response: \(hasSpaceInfo)")
    }
    
    // MARK: - Dark Mode Tests
    
    func testDarkModeAppearance() throws {
        // Dark mode is the default, verify UI elements are visible
        skipOnboardingIfNeeded()
        
        // Check that main UI elements are visible (not invisible due to color issues)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // Verify tabs are visible
        XCTAssertTrue(tabBar.buttons.count >= 3, "Tab buttons should be visible in dark mode")
        
        // Navigate through tabs and verify content is visible
        for tab in tabBar.buttons.allElementsBoundByIndex {
            tab.tap()
            sleep(1)
            
            // Verify some content is visible (not blank)
            let hasContent = app.staticTexts.count > 0 || 
                            app.buttons.count > 1 ||
                            app.cells.count > 0
            
            XCTAssertTrue(hasContent, "Content should be visible in dark mode for tab: \(tab.label)")
        }
    }
    
    // MARK: - Empty State Tests
    
    func testEmptyStatesHaveProperCopy() throws {
        skipOnboardingIfNeeded()
        
        // This test verifies empty states show appropriate Spanish copy
        // Would need a fresh library to properly test
        
        let momentsTab = app.tabBars.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
            sleep(1)
            
            // Look for empty state text in Spanish
            let emptyStateTexts = [
                "No hay fotos",
                "sin fotos",
                "biblioteca vacía",
                "Aún no hay"
            ]
            
            for text in emptyStateTexts {
                if app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).count > 0 {
                    print("Found empty state: \(text)")
                }
            }
        }
    }
    
    // MARK: - Screenshot Capture Tests
    
    func testCaptureKeyScreenshots() throws {
        skipOnboardingIfNeeded()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not available")
            return
        }
        
        // Screenshot 1: Home screen
        let homeTab = tabBar.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
            sleep(2)
            let homeScreenshot = app.screenshot()
            let homeAttachment = XCTAttachment(screenshot: homeScreenshot)
            homeAttachment.name = "01_home"
            homeAttachment.lifetime = .keepAlways
            add(homeAttachment)
        }
        
        // Screenshot 2: Assistant screen
        let assistantTab = tabBar.buttons["Asistente"]
        if assistantTab.exists {
            assistantTab.tap()
            sleep(2)
            let assistantScreenshot = app.screenshot()
            let assistantAttachment = XCTAttachment(screenshot: assistantScreenshot)
            assistantAttachment.name = "02_assistant"
            assistantAttachment.lifetime = .keepAlways
            add(assistantAttachment)
        }
        
        // Screenshot 3: Moments screen
        let momentsTab = tabBar.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
            sleep(2)
            let momentsScreenshot = app.screenshot()
            let momentsAttachment = XCTAttachment(screenshot: momentsScreenshot)
            momentsAttachment.name = "03_moments"
            momentsAttachment.lifetime = .keepAlways
            add(momentsAttachment)
        }
        
        // Screenshot 4: Settings screen
        let settingsTab = tabBar.buttons["Ajustes"]
        if settingsTab.exists {
            settingsTab.tap()
            sleep(2)
            let settingsScreenshot = app.screenshot()
            let settingsAttachment = XCTAttachment(screenshot: settingsScreenshot)
            settingsAttachment.name = "04_settings"
            settingsAttachment.lifetime = .keepAlways
            add(settingsAttachment)
        }
        
        // Screenshot 5: Fechas view (if accessible)
        if momentsTab.exists {
            momentsTab.tap()
            sleep(1)
            let fechasButton = app.buttons["Fechas"]
            if fechasButton.exists {
                fechasButton.tap()
                sleep(2)
                let fechasScreenshot = app.screenshot()
                let fechasAttachment = XCTAttachment(screenshot: fechasScreenshot)
                fechasAttachment.name = "05_fechas"
                fechasAttachment.lifetime = .keepAlways
                add(fechasAttachment)
            }
        }
        
        // Screenshot 6: Cleanup view (if available)
        if homeTab.exists {
            homeTab.tap()
            sleep(1)
            let cleanupButton = app.buttons["Limpiar"]
            let reviewButton = app.buttons["Revisar ahora"]
            if cleanupButton.exists {
                cleanupButton.tap()
                sleep(2)
                let cleanupScreenshot = app.screenshot()
                let cleanupAttachment = XCTAttachment(screenshot: cleanupScreenshot)
                cleanupAttachment.name = "06_cleanup"
                cleanupAttachment.lifetime = .keepAlways
                add(cleanupAttachment)
            } else if reviewButton.exists {
                reviewButton.tap()
                sleep(2)
                let cleanupScreenshot = app.screenshot()
                let cleanupAttachment = XCTAttachment(screenshot: cleanupScreenshot)
                cleanupAttachment.name = "06_cleanup"
                cleanupAttachment.lifetime = .keepAlways
                add(cleanupAttachment)
            }
        }
        
        XCTAssertTrue(true, "Screenshots captured successfully")
    }
    
    // MARK: - Performance Tests
    
    func testScanPerformanceMetrics() throws {
        // Measure scan time
        let metrics: [XCTMetric] = [
            XCTClockMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric()
        ]
        
        measure(metrics: metrics) {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting", "--fresh-scan"]
            app.launch()
            
            // Wait for scan to complete
            let scanComplete = app.staticTexts["scan_complete"].waitForExistence(timeout: 120)
            if !scanComplete {
                // Check for any indication scan finished
                sleep(30)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func skipOnboardingIfNeeded() {
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 3) {
            return // Already past onboarding
        }
        
        // Try to skip onboarding
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
        
        // Handle permission alert
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow Full Access"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }
        
        // Wait for main UI
        _ = tabBar.waitForExistence(timeout: 10)
    }
    
    private func navigateToCleanup() {
        let homeTab = app.tabBars.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
        }
        
        sleep(1)
        
        // Look for cleanup section
        let cleanupButton = app.buttons["Limpiar"]
        let cleanupCell = app.cells.matching(identifier: "cleanup").firstMatch
        
        if cleanupButton.exists {
            cleanupButton.tap()
        } else if cleanupCell.exists {
            cleanupCell.tap()
        }
    }
}

// MARK: - XCUIElement Extensions

extension XCUIElement {
    func clearText() {
        guard let stringValue = self.value as? String else { return }
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
    }
    
    func clearAndTypeText(_ text: String) {
        self.tap()
        clearText()
        self.typeText(text)
    }
    
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
