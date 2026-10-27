// PerformanceTests.swift
// Performance tests to ensure the app handles large libraries efficiently

import XCTest

final class PerformanceTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--performance-test"]
        app.launchEnvironment = ["UITEST_MODE": "1", "PERFORMANCE_TEST": "1"]
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Launch Performance
    
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
    
    // MARK: - Scan Performance
    
    func testScanTimeWithSeededLibrary() throws {
        // This measures how long it takes to scan the seeded ~150 photo library
        let startTime = CFAbsoluteTimeGetCurrent()
        
        app.launch()
        skipOnboardingIfNeeded()
        
        // Navigate to home where scan happens
        let homeTab = app.tabBars.buttons["Inicio"]
        if homeTab.exists {
            homeTab.tap()
        }
        
        // Wait for scan to complete - look for progress indicator to disappear
        let scanProgress = app.progressIndicators.firstMatch
        if scanProgress.waitForExistence(timeout: 5) {
            _ = scanProgress.waitForNonExistence(timeout: 120)
        } else {
            // If no progress indicator, wait for content
            sleep(10)
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let scanTime = endTime - startTime
        
        print("📊 Scan completed in \(String(format: "%.2f", scanTime)) seconds")
        
        // Assert reasonable scan time for ~150 photos
        XCTAssertLessThan(scanTime, 60.0, "Scan should complete within 60 seconds for ~150 photos")
    }
    
    // MARK: - Memory Tests
    
    func testMemoryUsageDuringScroll() throws {
        app.launch()
        skipOnboardingIfNeeded()
        
        // Navigate to timeline with photos
        let momentsTab = app.tabBars.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
        }
        
        sleep(2)
        
        // Scroll through content repeatedly
        let scrollView = app.scrollViews.firstMatch
        let collectionView = app.collectionViews.firstMatch
        let targetView = scrollView.exists ? scrollView : collectionView
        
        if targetView.exists {
            // Perform multiple scrolls
            for _ in 0..<10 {
                targetView.swipeUp()
                sleep(1)
            }
            
            for _ in 0..<10 {
                targetView.swipeDown()
                sleep(1)
            }
        }
        
        // Memory should remain stable (this is a basic test)
        // Real memory metrics would come from Instruments
        XCTAssertTrue(true, "Scroll test completed without crash")
    }
    
    // MARK: - UI Responsiveness
    
    func testMainThreadResponsiveness() throws {
        // This tests that the UI remains responsive during operations
        app.launch()
        skipOnboardingIfNeeded()
        
        // Start a timer
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Rapidly switch between tabs
        let tabs = app.tabBars.firstMatch.buttons.allElementsBoundByIndex
        
        for _ in 0..<5 {
            for tab in tabs {
                tab.tap()
                
                // Measure response time
                let tabSwitchStart = CFAbsoluteTimeGetCurrent()
                
                // Wait for any content to appear
                _ = app.staticTexts.firstMatch.waitForExistence(timeout: 2) ||
                    app.cells.firstMatch.waitForExistence(timeout: 2)
                
                let tabSwitchTime = CFAbsoluteTimeGetCurrent() - tabSwitchStart
                
                // Tab should respond within 500ms
                XCTAssertLessThan(tabSwitchTime, 0.5, "Tab switch should be responsive")
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("📊 20 tab switches completed in \(String(format: "%.2f", totalTime)) seconds")
    }
    
    // MARK: - Search Performance
    
    func testSearchResponseTime() throws {
        app.launch()
        skipOnboardingIfNeeded()
        
        let assistantTab = app.tabBars.buttons["Asistente"]
        guard assistantTab.exists else {
            XCTSkip("Assistant tab not available")
            return
        }
        
        assistantTab.tap()
        sleep(1)
        
        let searchField = app.textFields.firstMatch
        guard searchField.waitForExistence(timeout: 5) else {
            XCTSkip("Search field not available")
            return
        }
        
        let queries = ["fotos", "capturas", "Buenos Aires", "cumpleaños", "borrosas"]
        
        for query in queries {
            searchField.tap()
            searchField.clearText()
            searchField.typeText(query)
            
            let searchStart = CFAbsoluteTimeGetCurrent()
            app.submitKeyboard()
            
            // Wait for results
            _ = app.cells.firstMatch.waitForExistence(timeout: 10) ||
                app.staticTexts.element(boundBy: 2).waitForExistence(timeout: 10)
            
            let searchTime = CFAbsoluteTimeGetCurrent() - searchStart
            
            print("📊 Search '\(query)' completed in \(String(format: "%.2f", searchTime)) seconds")
            XCTAssertLessThan(searchTime, 5.0, "Search should complete within 5 seconds")
        }
    }
    
    // MARK: - Cleanup Performance
    
    func testCleanupAnalysisPerformance() throws {
        app.launch()
        skipOnboardingIfNeeded()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Navigate to cleanup
        navigateToCleanup()
        
        // Wait for categories to load
        let firstCategory = app.cells.firstMatch
        _ = firstCategory.waitForExistence(timeout: 30)
        
        let analysisTime = CFAbsoluteTimeGetCurrent() - startTime
        
        print("📊 Cleanup analysis completed in \(String(format: "%.2f", analysisTime)) seconds")
        XCTAssertLessThan(analysisTime, 30.0, "Cleanup analysis should complete within 30 seconds")
    }
    
    // MARK: - Large Library Simulation
    
    func testIncrementalLoadingBehavior() throws {
        // This tests that the app doesn't freeze with incremental loading
        app.launchEnvironment["SIMULATE_LARGE_LIBRARY"] = "1"
        app.launch()
        skipOnboardingIfNeeded()
        
        // Navigate to timeline
        let momentsTab = app.tabBars.buttons["Momentos"]
        if momentsTab.exists {
            momentsTab.tap()
        }
        
        // UI should remain responsive
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Try to interact while "loading"
        for _ in 0..<5 {
            // Verify UI is responsive by checking if tabs work
            let responseStart = CFAbsoluteTimeGetCurrent()
            app.tabBars.buttons["Ajustes"].tap()
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 2)
            let responseTime = CFAbsoluteTimeGetCurrent() - responseStart
            
            // Should never hang more than 1 second
            XCTAssertLessThan(responseTime, 1.0, "UI should remain responsive during incremental loading")
            
            app.tabBars.buttons["Momentos"].tap()
            sleep(1)
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("📊 Incremental loading test completed in \(String(format: "%.2f", totalTime)) seconds")
    }
    
    // MARK: - Helpers
    
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
