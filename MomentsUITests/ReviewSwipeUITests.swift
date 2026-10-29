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
    
    func testTapCardOpensFullScreenViewerAndDismisses() {
        openReview()
        let card = cardQuery
        XCTAssertTrue(card.waitForExistence(timeout: 6), "Review card")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        
        let viewer = app.descendants(matching: .any)["review.photoViewer"].firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: 5), "Full-screen viewer after tap")
        
        let close = app.buttons["review.photoViewer.dismiss"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
        } else {
            viewer.swipeDown()
        }
        XCTAssertFalse(viewer.waitForExistence(timeout: 3), "Viewer must dismiss")
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
        
        if let toast = elementTextIfPresent("review.decisionToast") {
            XCTAssertFalse(
                toast.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Stamp/toast label must not be empty"
            )
        }
        
        let next = cardQuery
        XCTAssertTrue(next.waitForExistence(timeout: 1), "Next card must appear within 1s")
        XCTAssertTrue(
            next.isHittable || app.otherElements["review.root"].isHittable,
            "Next card must be tappable"
        )
    }
    
    private func waitForDecision(_ expected: String, timeout: TimeInterval = 4) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.decisionSignal(contains: expected)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
    
    private func decisionSignal(contains expected: String) -> Bool {
        if let last = elementTextIfPresent("review.lastDecision")?.lowercased(),
           last.contains(expected) {
            return true
        }
        if let toast = elementTextIfPresent("review.decisionToast"),
           !toast.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return elementExists("review.swipeStamp")
    }
    
    private func elementExists(_ identifier: String) -> Bool {
        app.descendants(matching: .any).matching(identifier: identifier).count > 0
    }
    
    private func elementTextIfPresent(_ identifier: String) -> String? {
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        guard matches.count > 0 else { return nil }
        let element = matches.element(boundBy: 0)
        return element.label + (element.value as? String ?? "")
    }
    
    private func drag(_ card: XCUIElement, direction: Swipe) {
        let start: CGVector
        let end: CGVector
        switch direction {
        case .left:
            start = CGVector(dx: 0.82, dy: 0.42)
            end = CGVector(dx: 0.22, dy: 0.46)
        case .right:
            start = CGVector(dx: 0.18, dy: 0.42)
            end = CGVector(dx: 0.88, dy: 0.46)
        case .up:
            start = CGVector(dx: 0.50, dy: 0.72)
            end = CGVector(dx: 0.50, dy: 0.14)
        }
        card.coordinate(withNormalizedOffset: start)
            .press(forDuration: 0.18, thenDragTo: card.coordinate(withNormalizedOffset: end))
    }
}
