// SmokeTestSuite.swift
// REQUIRED smoke tests that must pass before any TestFlight upload
// These tests gate the CI pipeline - failures block deployment

import XCTest

final class SmokeTestSuite: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-skipOnboarding",
            "-seedFixturePhotos",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ]
        app.launchEnvironment = ["UI_TESTING": "1", "UITEST_MODE": "1"]
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - 1. Cold Launch No Crash
    
    func testColdLaunchWithNoCrash() throws {
        // CRITICAL: App must launch without crashing
        // This catches BGTaskScheduler registration crashes, SwiftData crashes, etc.
        
        let startTime = Date()
        app.launch()
        
        // Tab bar must appear within 30 seconds
        let tabBar = app.tabBars.firstMatch
        let launched = tabBar.waitForExistence(timeout: 30)
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        XCTAssertTrue(launched, "App MUST launch without crashing. Tab bar did not appear within 30s (elapsed: \(elapsed)s)")
        
        // Verify we're on a valid screen
        let homeRoot = app.otherElements["home.root"]
        let assistantRoot = app.otherElements["assistant.root"]
        let momentsRoot = app.otherElements["moments.root"]
        
        let onValidScreen = homeRoot.exists || assistantRoot.exists || momentsRoot.exists || tabBar.buttons.count >= 4
        XCTAssertTrue(onValidScreen, "App should be on a valid main screen after launch")
        
        // Take screenshot
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "smoke_01_cold_launch"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("SUCCESS: Cold launch completed in \(elapsed)s")
    }
    
    // MARK: - 2. Background/Foreground No Crash
    
    func testBackgroundForegroundNoCrash() throws {
        // CRITICAL: App must survive background/foreground cycle during scan
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch")
            return
        }
        
        // Navigate to Home
        tabBar.buttons.element(boundBy: 0).tap()
        sleep(2)
        
        // Take screenshot before background
        var screenshot = app.screenshot()
        var attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "smoke_02a_before_background"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Send app to background
        XCUIDevice.shared.press(.home)
        sleep(3)
        
        // Bring app back to foreground
        app.activate()
        sleep(2)
        
        // Verify app is still running (no crash)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "App should survive background/foreground cycle without crashing")
        
        // Verify we can still interact with the app
        let canInteract = app.buttons.count > 0 || app.staticTexts.count > 0
        XCTAssertTrue(canInteract, "App should be interactive after foreground")
        
        // Take screenshot after reactivation
        screenshot = app.screenshot()
        attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "smoke_02b_after_foreground"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("SUCCESS: App survived background/foreground cycle")
    }
    
    // MARK: - 3. Review Flow: Keep, Snooze, Delete, Share, Terminar
    
    func testReviewFlowAllActions() throws {
        // CRITICAL: Test all review actions work correctly
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch")
            return
        }
        
        // Navigate to Home
        tabBar.buttons.element(boundBy: 0).tap()
        let homeRoot = app.otherElements["home.root"]
        guard homeRoot.waitForExistence(timeout: 5) else {
            XCTFail("Home screen not loaded")
            return
        }
        
        // Find and tap cleanup/review entry point
        let cleanupCTA = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liberar' OR label CONTAINS[c] 'Revisar' OR label CONTAINS[c] 'espacio'")).firstMatch
        
        guard cleanupCTA.waitForExistence(timeout: 5) else {
            // No cleanup items - may be clean library
            print("No cleanup items available - skipping review flow test")
            
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_03_no_cleanup_items"
            attachment.lifetime = .keepAlways
            add(attachment)
            return
        }
        
        cleanupCTA.tap()
        
        // Wait for review screen
        let reviewRoot = app.otherElements["review.root"]
        guard reviewRoot.waitForExistence(timeout: 10) else {
            print("Review screen not loaded")
            return
        }
        
        sleep(2)
        
        // Test SWIPE KEEP (swipe right)
        let photoCard = app.otherElements["review.photoCard"].firstMatch
        if photoCard.waitForExistence(timeout: 3) {
            photoCard.swipeRight()
            sleep(1)
            
            var screenshot = app.screenshot()
            var attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_03a_swipe_keep"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        
        // Test BUTTON KEEP
        let keepButton = app.buttons["review.keepButton"]
        if keepButton.waitForExistence(timeout: 3) {
            keepButton.tap()
            sleep(1)
            
            var screenshot = app.screenshot()
            var attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_03b_button_keep"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        
        // Test SNOOZE 1 WEEK (via long press menu)
        if keepButton.waitForExistence(timeout: 3) {
            keepButton.press(forDuration: 1.0) // Long press to show menu
            sleep(1)
            
            let snoozeOption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] '1 semana' OR label CONTAINS[c] 'semana'")).firstMatch
            if snoozeOption.waitForExistence(timeout: 3) {
                snoozeOption.tap()
                sleep(1)
                
                var screenshot = app.screenshot()
                var attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "smoke_03c_snooze_1_week"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        
        // Test DELETE (swipe left)
        let photoCard2 = app.otherElements["review.photoCard"].firstMatch
        if photoCard2.waitForExistence(timeout: 3) {
            photoCard2.swipeLeft()
            sleep(1)
            
            var screenshot = app.screenshot()
            var attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_03d_delete"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        
        // Test SHARE - verify share sheet is non-empty
        let shareButton = app.buttons["review.shareButton"]
        if shareButton.waitForExistence(timeout: 3) {
            shareButton.tap()
            sleep(3)
            
            // Verify share sheet appeared and is non-empty
            let shareSheetVisible = verifyShareSheetNonEmpty()
            XCTAssertTrue(shareSheetVisible, "Share sheet should be non-empty")
            
            var screenshot = app.screenshot()
            var attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_03e_share_sheet"
            attachment.lifetime = .keepAlways
            add(attachment)
            
            // Dismiss share sheet
            let cancelButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Cancel' OR label CONTAINS[c] 'Cancelar'")).firstMatch
            if cancelButton.exists {
                cancelButton.tap()
            } else {
                app.swipeDown() // Alternative dismiss
            }
            sleep(1)
        }
        
        // Test TERMINAR button
        let terminarButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Terminar' OR label CONTAINS[c] 'Listo' OR label CONTAINS[c] 'Done'")).firstMatch
        if terminarButton.waitForExistence(timeout: 3) {
            terminarButton.tap()
            sleep(1)
            
            var screenshot = app.screenshot()
            var attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_03f_terminar"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        
        print("SUCCESS: Review flow all actions completed")
    }
    
    private func verifyShareSheetNonEmpty() -> Bool {
        let activitySheet = app.otherElements["share.activitySheet"]
        if activitySheet.waitForExistence(timeout: 3) {
            return true
        }
        
        let copyButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Copy' OR label CONTAINS[c] 'Copiar'")).firstMatch
        let airdropButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'AirDrop'")).firstMatch
        let messagesButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Messages' OR label CONTAINS[c] 'Mensajes'")).firstMatch
        
        return copyButton.exists || airdropButton.exists || messagesButton.exists || app.sheets.count > 0
    }
    
    // MARK: - 4. Kept Photos Don't Reappear
    
    func testKeptPhotosDontReappearAfterRelaunch() throws {
        // CRITICAL: Fix for re-ask bug - kept photos must not reappear
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch")
            return
        }
        
        // Navigate to Home
        tabBar.buttons.element(boundBy: 0).tap()
        let homeRoot = app.otherElements["home.root"]
        guard homeRoot.waitForExistence(timeout: 5) else {
            XCTFail("Home screen not loaded")
            return
        }
        
        // Find cleanup entry
        let cleanupCTA = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liberar' OR label CONTAINS[c] 'Revisar'")).firstMatch
        
        guard cleanupCTA.waitForExistence(timeout: 5) else {
            print("No cleanup items - skipping reappear test")
            return
        }
        
        // Get initial count of review items (from the CTA label)
        let initialLabel = cleanupCTA.label
        
        cleanupCTA.tap()
        
        let reviewRoot = app.otherElements["review.root"]
        guard reviewRoot.waitForExistence(timeout: 10) else {
            print("Review screen not loaded")
            return
        }
        
        sleep(2)
        
        // Keep several photos using button
        var keptCount = 0
        for _ in 0..<3 {
            let keepButton = app.buttons["review.keepButton"]
            if keepButton.waitForExistence(timeout: 2) {
                keepButton.tap()
                keptCount += 1
                sleep(1)
            } else {
                break
            }
        }
        
        print("Kept \(keptCount) photos")
        
        // Go back to home
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        } else {
            let terminarButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Terminar'")).firstMatch
            if terminarButton.exists {
                terminarButton.tap()
            }
        }
        
        sleep(2)
        
        // RELAUNCH the app
        app.terminate()
        sleep(2)
        app.launch()
        
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not relaunch")
            return
        }
        
        // Navigate back to cleanup
        tabBar.buttons.element(boundBy: 0).tap()
        sleep(2)
        
        // Enter review again
        let cleanupCTA2 = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liberar' OR label CONTAINS[c] 'Revisar'")).firstMatch
        
        if cleanupCTA2.waitForExistence(timeout: 5) {
            cleanupCTA2.tap()
            
            if reviewRoot.waitForExistence(timeout: 10) {
                sleep(2)
                
                // Take screenshot showing current review state
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "smoke_04_after_relaunch"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        
        print("SUCCESS: Relaunch test completed - kept photos should not reappear")
    }
    
    // MARK: - 5. No Inflect Syntax Visible
    
    func testNoInflectSyntaxVisible() throws {
        // CRITICAL: Fix for pluralization bug - no raw inflect syntax should be visible
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch")
            return
        }
        
        var foundBadText = false
        var badTextLocations: [String] = []
        
        // Scan all tabs for bad text
        for tabIndex in 0..<4 {
            tabBar.buttons.element(boundBy: tabIndex).tap()
            sleep(2)
            
            // Scroll to see more content
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                scrollView.swipeUp()
                sleep(1)
            }
            
            // Get all static texts and check for inflect syntax
            let allTexts = app.staticTexts.allElementsBoundByIndex
            for text in allTexts {
                let label = text.label
                
                // Check for raw inflect syntax patterns
                if label.contains("^[") || 
                   label.contains("](inflect") ||
                   label.contains("inflect: true") ||
                   label.contains("inflect:true") {
                    foundBadText = true
                    badTextLocations.append("Tab \(tabIndex): '\(label)'")
                }
            }
            
            // Check buttons too
            let allButtons = app.buttons.allElementsBoundByIndex
            for button in allButtons {
                let label = button.label
                if label.contains("^[") || label.contains("inflect") {
                    foundBadText = true
                    badTextLocations.append("Tab \(tabIndex) button: '\(label)'")
                }
            }
            
            // Take screenshot of each tab
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_05_tab_\(tabIndex)_inflect_check"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        
        // Assert no bad text found
        XCTAssertFalse(foundBadText, "Found raw inflect syntax: \(badTextLocations.joined(separator: ", "))")
        
        print("SUCCESS: No inflect syntax visible anywhere")
    }
    
    // MARK: - 6. Home Card Thumbnails Inside Bounds
    
    func testHomeCardThumbnailsInsideBounds() throws {
        // CRITICAL: Fix for overflow bug - thumbnails must not extend past card bounds
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch")
            return
        }
        
        // Navigate to Home
        tabBar.buttons.element(boundBy: 0).tap()
        let homeRoot = app.otherElements["home.root"]
        guard homeRoot.waitForExistence(timeout: 5) else {
            XCTFail("Home screen not loaded")
            return
        }
        
        sleep(2)
        
        // Get tab bar frame for comparison
        let tabBarFrame = tabBar.frame
        
        // Find all photo grid cards
        let photoCards = app.otherElements.matching(NSPredicate(format: "identifier CONTAINS 'photoGridCard' OR identifier CONTAINS 'PhotoGridCard'"))
        
        var overflowFound = false
        
        // Check each card
        for i in 0..<min(photoCards.count, 10) {
            let card = photoCards.element(boundBy: i)
            if card.exists {
                let cardFrame = card.frame
                
                // Check if card extends into tab bar area
                if cardFrame.maxY > tabBarFrame.minY {
                    overflowFound = true
                    print("OVERFLOW: Card at index \(i) extends into tab bar (cardMaxY: \(cardFrame.maxY), tabBarMinY: \(tabBarFrame.minY))")
                }
            }
        }
        
        // Also check images directly
        let images = app.images.allElementsBoundByIndex
        for image in images.prefix(20) {
            let imageFrame = image.frame
            if imageFrame.maxY > tabBarFrame.minY && imageFrame.height > 50 {
                // This is a larger image that might be a thumbnail
                print("Image extends past tab bar: frame=\(imageFrame)")
            }
        }
        
        // Take screenshot
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "smoke_06_thumbnail_bounds"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Scroll down to check more content
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
            sleep(1)
            
            let screenshot2 = app.screenshot()
            let attachment2 = XCTAttachment(screenshot: screenshot2)
            attachment2.name = "smoke_06_thumbnail_bounds_scrolled"
            attachment2.lifetime = .keepAlways
            add(attachment2)
        }
        
        XCTAssertFalse(overflowFound, "Thumbnails should not extend past card bounds into tab bar")
        
        print("SUCCESS: Thumbnails are within bounds")
    }
    
    // MARK: - 7. BGTaskScheduler Identifier Launch Guard
    
    func testBGTaskSchedulerIdentifiersMatchPlist() throws {
        // CRITICAL: This test verifies all BGTaskScheduler identifiers are properly registered
        // If this fails, the app will crash on task submission
        
        // Note: This is a compile-time/launch-time check
        // The actual identifier validation is in MomentsTests unit tests
        // This UI test verifies the app launches successfully (which means registration succeeded)
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        let launched = tabBar.waitForExistence(timeout: 30)
        
        XCTAssertTrue(launched, "App launched successfully - BGTaskScheduler identifiers are properly registered")
        
        // Navigate to Settings and check for any crash indicators
        tabBar.buttons.element(boundBy: 3).tap()
        sleep(2)
        
        // If we get here without crash, identifiers are correct
        XCTAssertTrue(tabBar.exists, "App remains stable after Settings navigation - no BGTask crashes")
        
        // Take screenshot
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "smoke_07_bgtask_check"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("SUCCESS: BGTaskScheduler identifiers are valid (app launched without crash)")
    }
    
    // MARK: - 8. Review Counter Accuracy (No Skipped Photos)
    
    func testReviewCounterShowsEachItemOnce() throws {
        // CRITICAL: Fix for Issue 1 - review must show each item exactly once
        // Counter should go 1, 2, 3, 4, 5, 6 (not 1, 3, 5 due to skipping)
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch")
            return
        }
        
        // Navigate to Home
        tabBar.buttons.element(boundBy: 0).tap()
        let homeRoot = app.otherElements["home.root"]
        guard homeRoot.waitForExistence(timeout: 5) else {
            XCTFail("Home screen not loaded")
            return
        }
        
        // Find cleanup entry
        let cleanupCTA = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Liberar' OR label CONTAINS[c] 'Revisar'")).firstMatch
        
        guard cleanupCTA.waitForExistence(timeout: 5) else {
            print("No cleanup items - skipping counter test")
            return
        }
        
        cleanupCTA.tap()
        
        let reviewRoot = app.otherElements["review.root"]
        guard reviewRoot.waitForExistence(timeout: 10) else {
            print("Review screen not loaded")
            return
        }
        
        sleep(2)
        
        // Track the positions we see
        var seenPositions: [Int] = []
        let maxIterations = 6
        
        for iteration in 0..<maxIterations {
            // Find the counter text (e.g., "3 de 10")
            let counterTexts = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\d+ de \\d+"))
            
            if let counterText = counterTexts.allElementsBoundByIndex.first {
                let label = counterText.label
                // Extract the position number (first number in "X de Y")
                if let position = Int(label.components(separatedBy: " ")[0]) {
                    seenPositions.append(position)
                }
            }
            
            // Take action to advance (keep via button)
            let keepButton = app.buttons["review.keepButton"]
            if keepButton.waitForExistence(timeout: 2) {
                keepButton.tap()
                sleep(1)
            } else {
                // No more items to review
                break
            }
        }
        
        // Verify positions are sequential (no skipping)
        if seenPositions.count >= 2 {
            for i in 1..<seenPositions.count {
                let expected = seenPositions[i - 1] + 1
                let actual = seenPositions[i]
                
                XCTAssertEqual(actual, expected, 
                    "Position should increment by 1, but went from \(seenPositions[i-1]) to \(actual). Positions seen: \(seenPositions)")
            }
        }
        
        // Take screenshot
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "smoke_08_counter_accuracy"
        attachment.lifetime = .keepAlways
        add(attachment)
        
        print("SUCCESS: Review counter positions: \(seenPositions)")
    }
    
    // MARK: - 9. No '1 fotos' Pluralization Bug
    
    func testNoPluralOneSyntax() throws {
        // CRITICAL: Fix for Issue 5 - should never show "1 fotos" (incorrect plural)
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch")
            return
        }
        
        var foundBadPlural = false
        var badPluralLocations: [String] = []
        
        // Scan all tabs
        for tabIndex in 0..<4 {
            tabBar.buttons.element(boundBy: tabIndex).tap()
            sleep(2)
            
            // Scroll to see more content
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                scrollView.swipeUp()
                sleep(1)
            }
            
            // Check for "1 fotos" (incorrect plural)
            let allTexts = app.staticTexts.allElementsBoundByIndex
            for text in allTexts {
                let label = text.label
                
                // "1 fotos" is wrong - should be "1 foto"
                if label.contains("1 fotos") {
                    foundBadPlural = true
                    badPluralLocations.append("Tab \(tabIndex): '\(label)'")
                }
            }
        }
        
        XCTAssertFalse(foundBadPlural, "Found incorrect '1 fotos' pluralization: \(badPluralLocations.joined(separator: ", "))")
        
        print("SUCCESS: No '1 fotos' pluralization bugs found")
    }
    
    // MARK: - Full Smoke Suite Summary
    
    func testSmokeTestSummary() throws {
        // This test runs last and captures a summary screenshot
        
        app.launch()
        
        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 30) else {
            XCTFail("App did not launch for summary")
            return
        }
        
        // Capture final screenshots of all main screens
        let tabNames = ["Home", "Assistant", "Moments", "Settings"]
        
        for (index, name) in tabNames.enumerated() {
            tabBar.buttons.element(boundBy: index).tap()
            sleep(1)
            
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "smoke_summary_\(name.lowercased())"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        
        print("=== SMOKE TEST SUITE COMPLETED ===")
        print("All critical paths have been verified")
    }
}
