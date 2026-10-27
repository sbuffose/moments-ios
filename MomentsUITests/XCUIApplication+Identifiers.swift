import XCTest

extension XCUIApplication {
    /// Prefer typed queries. `descendants(matching: .any)` times out on CI
    /// (minutes) because it walks the whole accessibility tree.
    func identified(_ id: String) -> XCUIElement {
        otherElements[id]
    }

    func waitForIdentifier(_ id: String, timeout: TimeInterval = 8) -> Bool {
        otherElements[id].waitForExistence(timeout: timeout)
    }

    func waitForHome(timeout: TimeInterval = 10) -> Bool {
        if otherElements["home.root"].waitForExistence(timeout: timeout) { return true }
        if otherElements["home.scrollView"].waitForExistence(timeout: 3) { return true }
        return tabBars.firstMatch.exists
    }

    func waitForAssistant(timeout: TimeInterval = 10) -> Bool {
        if otherElements["assistant.root"].waitForExistence(timeout: min(timeout, 4)) { return true }
        if textFields["assistant.input"].waitForExistence(timeout: 4) { return true }
        if textFields["Preguntame algo..."].waitForExistence(timeout: 3) { return true }
        return textFields.firstMatch.waitForExistence(timeout: 2)
    }

    func waitForMoments(timeout: TimeInterval = 10) -> Bool {
        if otherElements["moments.root"].waitForExistence(timeout: timeout) { return true }
        return buttons["chip.timeline"].waitForExistence(timeout: 3)
    }

    /// Simulator keyboards localize the submit key; "Return" is not always present.
    func submitKeyboard() {
        let keys = ["Return", "return", "Intro", "intro", "Buscar", "Go", "Done", "done", "Enviar"]
        for key in keys {
            let button = keyboards.buttons[key]
            if button.exists {
                button.tap()
                return
            }
        }
        if keyboards.buttons["assistant.input"].exists { return }
        // Avoid typeText("\n") when the keyboard is gone — that can hang XCUITest.
        if keyboards.firstMatch.exists {
            typeText("\n")
        }
    }
}
