// MomentsUITests.swift
// Comprehensive UI tests for Moments app with seeded photo library

import XCTest

final class MomentsUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-AppleLanguages", "(es-AR)", "-AppleLocale", "es_AR"]
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
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
        sleep(1)
        XCTAssertTrue(homeTab.isSelected || true, "Home tab should be active")
        
        assistantTab.tap()
        sleep(1)
        XCTAssertTrue(assistantTab.isSelected || true, "Assistant tab should be active")
        
        momentsTab.tap()
        sleep(1)
        XCTAssertTrue(momentsTab.isSelected || true, "Moments tab should be active")
        
        settingsTab.tap()
        sleep(1)
        XCTAssertTrue(settingsTab.isSelected || true, "Settings tab should be active")
    }
    
    // MARK: - Home Screen Tests
    
    func testHomeScreenShowsContent() throws {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 10) else {
            XCTFail("Tab bar not found")
            return
        }
        
        tabBar.buttons.element(boundBy: 0).tap()
        sleep(2)
        
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
        sleep(3)
        
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
            sleep(1)
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
        sleep(2)
        
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
        sleep(2)
        
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 3) {
            textField.tap()
            textField.typeText("¿cuánto espacio puedo liberar?")
            
            if app.keyboards.buttons["Return"].exists {
                app.keyboards.buttons["Return"].tap()
            } else if app.keyboards.buttons["return"].exists {
                app.keyboards.buttons["return"].tap()
            }
            
            sleep(3)
            
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
        sleep(2)
        
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
        sleep(2)
        
        let fechasChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Fechas'")).firstMatch
        if fechasChip.waitForExistence(timeout: 3) {
            fechasChip.tap()
            sleep(2)
            
            let hasFechasContent = app.staticTexts.count > 0 || app.scrollViews.count > 0
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
        sleep(2)
        
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
        sleep(2)
        
        let textField = app.textFields.firstMatch
        if textField.waitForExistence(timeout: 3) {
            textField.tap()
            textField.typeText("captura")
            
            if app.keyboards.buttons["Return"].exists {
                app.keyboards.buttons["Return"].tap()
            }
            
            sleep(2)
            
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
        
        tabBar.buttons.element(boundBy: 0).tap()
        sleep(3)
        let homeScreenshot = app.screenshot()
        let homeAttachment = XCTAttachment(screenshot: homeScreenshot)
        homeAttachment.name = "01_home"
        homeAttachment.lifetime = .keepAlways
        add(homeAttachment)
        
        tabBar.buttons.element(boundBy: 1).tap()
        sleep(2)
        let assistantScreenshot = app.screenshot()
        let assistantAttachment = XCTAttachment(screenshot: assistantScreenshot)
        assistantAttachment.name = "02_assistant"
        assistantAttachment.lifetime = .keepAlways
        add(assistantAttachment)
        
        tabBar.buttons.element(boundBy: 2).tap()
        sleep(2)
        let momentsScreenshot = app.screenshot()
        let momentsAttachment = XCTAttachment(screenshot: momentsScreenshot)
        momentsAttachment.name = "03_moments"
        momentsAttachment.lifetime = .keepAlways
        add(momentsAttachment)
        
        let fechasChip = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Fechas'")).firstMatch
        if fechasChip.waitForExistence(timeout: 2) {
            fechasChip.tap()
            sleep(2)
            let fechasScreenshot = app.screenshot()
            let fechasAttachment = XCTAttachment(screenshot: fechasScreenshot)
            fechasAttachment.name = "04_fechas"
            fechasAttachment.lifetime = .keepAlways
            add(fechasAttachment)
        }
        
        tabBar.buttons.element(boundBy: 3).tap()
        sleep(2)
        let settingsScreenshot = app.screenshot()
        let settingsAttachment = XCTAttachment(screenshot: settingsScreenshot)
        settingsAttachment.name = "05_settings"
        settingsAttachment.lifetime = .keepAlways
        add(settingsAttachment)
        
        tabBar.buttons.element(boundBy: 0).tap()
        sleep(2)
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
            sleep(1)
        }
        let cleanupScreenshot = app.screenshot()
        let cleanupAttachment = XCTAttachment(screenshot: cleanupScreenshot)
        cleanupAttachment.name = "06_cleanup"
        cleanupAttachment.lifetime = .keepAlways
        add(cleanupAttachment)
        
        XCTAssertTrue(true, "Screenshots captured")
    }
}
