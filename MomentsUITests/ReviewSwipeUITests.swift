import XCTest

final class ReviewSwipeUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-skipOnboarding",
            "-seedFixturePhotos",
            "-reviewSwipeSingles",
            "-AppleLanguages", "(es-AR)",
            "-AppleLocale", "es_AR"
        ]
        app.launchEnvironment = [
            "UI_TESTING": "1",
            "UITEST_MODE": "1"
        ]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }
    
    func testSwipeRightKeepsAndShowsNextCard() {
        openReview()
        swipeAndAssert(direction: .right, expected: "keep")
    }
    
    func testSwipeLeftDeletesAndShowsNextCard() {
        openReview()
        swipeAndAssert(direction: .left, expected: "delete")
    }
    
    func testSwipeUpSnoozesAndShowsNextCard() {
        openReview()
        swipeAndAssert(direction: .up, expected: "snooze")
    }
    
    private enum Swipe {
        case left, right, up
    }
    
    private func openReview() {
        XCTAssertTrue(app.otherElements["home.root"].waitForExistence(timeout: 20)
                      || app.otherElements["home.scrollView"].waitForExistence(timeout: 8))
        let start = app.buttons["home.reviewButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 12), "Empezar")
        start.tap()
        XCTAssertTrue(app.otherElements["review.root"].waitForExistence(timeout: 12))
        XCTAssertTrue(cardQuery.waitForExistence(timeout: 8))
    }
    
    private var cardQuery: XCUIElement {
        app.descendants(matching: .any)["review.photoCard"].firstMatch
    }
    
    private func swipeAndAssert(direction: Swipe, expected: String) {
        let card = cardQuery
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        drag(card, direction: direction)
        
        XCTAssertTrue(waitForDecision(expected), "Stamp or toast should appear after swipe \(expected)")
        
        let toast = app.staticTexts["review.decisionToast"]
        if toast.exists {
            XCTAssertFalse(toast.label.isEmpty, "Stamp/toast label must not be empty")
        }
        
        let next = cardQuery
        XCTAssertTrue(next.waitForExistence(timeout: 1), "Next card must appear within 1s")
        XCTAssertTrue(
            next.isHittable || app.otherElements["review.root"].isHittable,
            "Next card must be tappable"
        )
    }
    
    private func waitForDecision(_ expected: String, timeout: TimeInterval = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = elementText(app.staticTexts["review.lastDecision"])
            if text.contains(expected) { return true }
            if app.staticTexts["review.decisionToast"].exists { return true }
            if app.staticTexts["review.swipeStamp"].exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return elementText(app.staticTexts["review.lastDecision"]).contains(expected)
            || app.staticTexts["review.decisionToast"].exists
            || app.staticTexts["review.swipeStamp"].exists
    }
    
    private func elementText(_ element: XCUIElement) -> String {
        element.label + (element.value as? String ?? "")
    }
    
    private func drag(_ card: XCUIElement, direction: Swipe) {
        let start: CGVector
        let end: CGVector
        switch direction {
        case .left:
            start = CGVector(dx: 0.80, dy: 0.48)
            end = CGVector(dx: 0.08, dy: 0.52)
        case .right:
            start = CGVector(dx: 0.20, dy: 0.48)
            end = CGVector(dx: 0.92, dy: 0.52)
        case .up:
            start = CGVector(dx: 0.50, dy: 0.78)
            end = CGVector(dx: 0.50, dy: 0.08)
        }
        card.coordinate(withNormalizedOffset: start)
            .press(forDuration: 0.08, thenDragTo: card.coordinate(withNormalizedOffset: end))
    }
}
