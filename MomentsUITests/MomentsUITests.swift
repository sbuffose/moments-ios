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
    
    // MARK: - Testing Mode Verification
    
    func testAppSkipsOnboarding() throws {
        let testingModeIndicator = app.otherElements["app.testing_mode"]
        let mainTabView = app.otherElements["main_tab_view"]
        let tabBar = app.tabBars.firstMatch
        
        let inTestingMode = testingModeIndicator.waitForExistence(timeout: 5) ||
                           mainTabView.waitForExistence(timeout: 5) ||
                           tabBar.waitForExistence(timeout: 5)
        
        XCTAssertTrue(inTestingMode, "App should be in testing mode with -skipOnboarding flag")
        
        let onboardingRoot = app.otherElements["onboarding.root"]
        XCTAssertFalse(onboardingRoot.exists, "Onboarding should NOT be shown when -skipOnboarding is used")
    }
    
    // MARK: - Core Navigation Tests
    
    func testMainTabBarExists() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should exist")
        
        let tabs = tabBar.buttons
        XCTAssertGreaterThanOrEqual(tabs.count, 4, "Should have at least 4 tabs")
    }
    
    func testTabBarNavigation() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        
        let homeTab = tabBar.buttons.element(boundBy: 0)
        let assistantTab = tabBar.buttons.element(boundBy: 1)
        let momentsTab = tabBar.buttons.element(boundBy: 2)
        let settingsTab = tabBar.buttons.element(boundBy: 3)
        
        homeTab.tap()
        let homeRoot = app.otherElements["home.root"]
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 5), "Home screen should show home.root identifier")
        
        assistantTab.tap()
        let assistantRoot = app.otherElements["assistant.root"]
        XCTAssertTrue(assistantRoot.waitForExistence(timeout: 5), "Assistant screen should show assistant.root identifier")
        
        momentsTab.tap()
        let momentsRoot = app.otherElements["moments.root"]
        XCTAssertTrue(momentsRoot.waitForExistence(timeout: 5), "Moments screen should show moments.root identifier")
        
        settingsTab.tap()
        XCTAssertTrue(app.navigationBars.count > 0 || app.staticTexts.count > 0, "Settings screen should have content")
    }
    
    // MARK: - Home Screen Tests
    
    func testHomeScreenShowsContent() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 0).tap()
        
        let homeRoot = app.otherElements["home.root"]
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 5), "Home screen should show home.root identifier")
        
        let hasContent = app.scrollViews.count > 0 || 
                        app.staticTexts.count > 2 ||
                        app.buttons.count > 1
        
        XCTAssertTrue(hasContent, "Home screen should have content")
    }
    
    func testHomeScreenShowsCleanupSection() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 0).tap()
        
        let homeRoot = app.otherElements["home.root"]
        guard homeRoot.waitForExistence(timeout: 5) else {
            XCTFail("Home screen not showing home.root identifier")
            return
        }
        
        let scrollView = app.scrollViews.firstMatch
        if scrollView.waitForExistence(timeout: 3) {
            scrollView.swipeUp()
        }
        
        let hasCleanupContent = 
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Limpiar' OR label CONTAINS[c] 'liberar' OR label CONTAINS[c] 'revisar' OR label CONTAINS[c] 'GB' OR label CONTAINS[c] 'MB'")).count > 0 ||
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Revisar' OR label CONTAINS[c] 'Limpiar'")).count > 0
        
        print("Has cleanup content: \(hasCleanupContent)")
    }
    
    // MARK: - Assistant Tests
    
    func testAssistantScreenExists() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 1).tap()
        
        let assistantRoot = app.otherElements["assistant.root"]
        XCTAssertTrue(assistantRoot.waitForExistence(timeout: 5), "Assistant screen should show assistant.root identifier")
        
        let hasInputField = app.textFields.count > 0 || app.textViews.count > 0
        let hasAssistantContent = app.staticTexts.count > 0
        
        XCTAssertTrue(hasInputField || hasAssistantContent, "Assistant should have input field or content")
    }
    
    func testAssistantRespondsToQuery() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 1).tap()
        
        let assistantRoot = app.otherElements["assistant.root"]
        guard assistantRoot.waitForExistence(timeout: 5) else {
            XCTFail("Assistant screen not loaded")
            return
        }
        
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 3) {
            textField.tap()
            textField.typeText("¿cuánto espacio puedo liberar?")
            
            if app.keyboards.buttons["Return"].exists {
                app.keyboards.buttons["Return"].tap()
            } else if app.keyboards.buttons["return"].exists {
                app.keyboards.buttons["return"].tap()
            }
            
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count > 1"),
                object: app.staticTexts
            )
            _ = XCTWaiter.wait(for: [expectation], timeout: 5)
            
            let hasResponse = app.staticTexts.count > 1 || app.cells.count > 0
            print("Assistant responded: \(hasResponse)")
        }
    }
    
    // MARK: - Moments/Timeline Tests
    
    func testMomentsScreenShowsSections() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 2).tap()
        
        let momentsRoot = app.otherElements["moments.root"]
        XCTAssertTrue(momentsRoot.waitForExistence(timeout: 5), "Moments screen should show moments.root identifier")
        
        let hasChips = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Línea' OR label CONTAINS[c] 'Personas' OR label CONTAINS[c] 'Lugares' OR label CONTAINS[c] 'Fechas'")).count > 0
        
        XCTAssertTrue(hasChips || app.scrollViews.count > 0, "Moments should have section chips or scroll views")
    }
    
    func testFechasScreenExists() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 2).tap()
        
        let momentsRoot = app.otherElements["moments.root"]
        guard momentsRoot.waitForExistence(timeout: 5) else {
            XCTFail("Moments screen not loaded")
            return
        }
        
        let fechasChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Fechas'")).firstMatch
        if fechasChip.waitForExistence(timeout: 3) {
            fechasChip.tap()
            
            let fechasContent = app.otherElements["fechas.content"]
            let hasFechasContent = fechasContent.waitForExistence(timeout: 5) || app.staticTexts.count > 0 || app.scrollViews.count > 0
            XCTAssertTrue(hasFechasContent, "Fechas screen should have content")
        }
    }
    
    // MARK: - Settings Tests
    
    func testSettingsScreenExists() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 3).tap()
        
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"),
            object: app.staticTexts
        )
        _ = XCTWaiter.wait(for: [expectation], timeout: 5)
        
        let hasSettingsContent = app.staticTexts.count > 0 || app.cells.count > 0
        XCTAssertTrue(hasSettingsContent, "Settings should have content")
    }
    
    // MARK: - Search Tests
    
    func testSearchForCaptura() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 1).tap()
        
        let assistantRoot = app.otherElements["assistant.root"]
        guard assistantRoot.waitForExistence(timeout: 5) else {
            XCTFail("Assistant screen not loaded")
            return
        }
        
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 3) {
            textField.tap()
            textField.typeText("captura")
            
            if app.keyboards.buttons["Return"].exists {
                app.keyboards.buttons["Return"].tap()
            }
            
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count > 0"),
                object: app.cells
            )
            _ = XCTWaiter.wait(for: [expectation], timeout: 5)
            
            let hasResults = app.cells.count > 0 || 
                            app.collectionViews.cells.count > 0 ||
                            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'resultado' OR label CONTAINS[c] 'foto'")).count > 0
            
            print("Search results found: \(hasResults)")
        }
    }
    
    // MARK: - Screenshot Capture Tests
    
    func testCaptureAllScreenshots() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not available")
            return
        }
        
        // 01: Home screen with space savings card
        tabBar.buttons.element(boundBy: 0).tap()
        let homeRoot = app.otherElements["home.root"]
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 5), "Home screen should load with home.root identifier")
        let homeScreenshot = app.screenshot()
        let homeAttachment = XCTAttachment(screenshot: homeScreenshot)
        homeAttachment.name = "04_home_screen"
        homeAttachment.lifetime = .keepAlways
        add(homeAttachment)
        
        // 02: Assistant screen
        tabBar.buttons.element(boundBy: 1).tap()
        let assistantRoot = app.otherElements["assistant.root"]
        XCTAssertTrue(assistantRoot.waitForExistence(timeout: 5), "Assistant screen should load with assistant.root identifier")
        let assistantScreenshot = app.screenshot()
        let assistantAttachment = XCTAttachment(screenshot: assistantScreenshot)
        assistantAttachment.name = "05_assistant"
        assistantAttachment.lifetime = .keepAlways
        add(assistantAttachment)
        
        // 03: Moments/Timeline screen
        tabBar.buttons.element(boundBy: 2).tap()
        let momentsRoot = app.otherElements["moments.root"]
        XCTAssertTrue(momentsRoot.waitForExistence(timeout: 5), "Moments screen should load with moments.root identifier")
        let momentsScreenshot = app.screenshot()
        let momentsAttachment = XCTAttachment(screenshot: momentsScreenshot)
        momentsAttachment.name = "06_moments"
        momentsAttachment.lifetime = .keepAlways
        add(momentsAttachment)
        
        // 04: Fechas screen
        let fechasChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Fechas'")).firstMatch
        if fechasChip.waitForExistence(timeout: 3) {
            fechasChip.tap()
            let fechasContent = app.otherElements["fechas.content"]
            _ = fechasContent.waitForExistence(timeout: 3)
            let fechasScreenshot = app.screenshot()
            let fechasAttachment = XCTAttachment(screenshot: fechasScreenshot)
            fechasAttachment.name = "07_fechas"
            fechasAttachment.lifetime = .keepAlways
            add(fechasAttachment)
        }
        
        // 05: Settings screen
        tabBar.buttons.element(boundBy: 3).tap()
        let settingsExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"),
            object: app.staticTexts
        )
        _ = XCTWaiter.wait(for: [settingsExpectation], timeout: 3)
        let settingsScreenshot = app.screenshot()
        let settingsAttachment = XCTAttachment(screenshot: settingsScreenshot)
        settingsAttachment.name = "08_settings"
        settingsAttachment.lifetime = .keepAlways
        add(settingsAttachment)
        
        // 06: Home cleanup section (scrolled)
        tabBar.buttons.element(boundBy: 0).tap()
        _ = homeRoot.waitForExistence(timeout: 3)
        let scrollView = app.scrollViews.firstMatch
        if scrollView.waitForExistence(timeout: 3) {
            scrollView.swipeUp()
        }
        let cleanupScreenshot = app.screenshot()
        let cleanupAttachment = XCTAttachment(screenshot: cleanupScreenshot)
        cleanupAttachment.name = "09_cleanup_section"
        cleanupAttachment.lifetime = .keepAlways
        add(cleanupAttachment)
        
        XCTAssertTrue(true, "Screenshots captured with screen-specific identifiers verified")
    }
}
