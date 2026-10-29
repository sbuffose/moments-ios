import XCTest

final class ReviewSwipeUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-seedFixturePhotos", "UI_TESTING=1"]
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
        XCTAssertTrue(app.otherElements["review.photoCard"].waitForExistence(timeout: 8))
    }
    
    private func swipeAndAssert(direction: Swipe, expected: String) {
        let card = app.otherElements["review.photoCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        switch direction {
        case .left: card.swipeLeft()
        case .right: card.swipeRight()
        case .up: card.swipeUp()
        }
        
        let decision = app.staticTexts["review.lastDecision"]
        let toast = app.staticTexts["review.decisionToast"]
        let stamp = app.staticTexts["review.swipeStamp"]
        let sawDecision = decision.waitForExistence(timeout: 1) || toast.waitForExistence(timeout: 1) || stamp.waitForExistence(timeout: 1)
        XCTAssertTrue(sawDecision, "Stamp or toast should appear after swipe \(expected)")
        if decision.exists {
            XCTAssertTrue(
                (decision.label + (decision.value as? String ?? "")).contains(expected),
                "Expected decision \(expected), got \(decision.label)"
            )
        }
        if toast.exists {
            XCTAssertFalse(toast.label.isEmpty, "Stamp/toast label must not be empty")
        }
        
        let next = app.otherElements["review.photoCard"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 1), "Next card must appear within 1s")
        XCTAssertTrue(next.isHittable, "Next card must be tappable")
    }
}
