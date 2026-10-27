import XCTest

extension XCUIApplication {
    /// Finds an accessibility identifier regardless of XCUIElement type.
    /// SwiftUI often exposes identifiers as Other, but TabView/NavigationStack
    /// can remap them; `otherElements[id]` then times out even when the view is up.
    func identified(_ id: String) -> XCUIElement {
        descendants(matching: .any)[id]
    }

    func waitForIdentifier(_ id: String, timeout: TimeInterval = 10) -> Bool {
        identified(id).waitForExistence(timeout: timeout)
    }

    /// Simulator keyboards localize the submit key; "Return" is not always present.
    func submitKeyboard() {
        let keys = ["Return", "return", "Intro", "intro", "Buscar", "Go", "Done", "done"]
        for key in keys {
            let button = keyboards.buttons[key]
            if button.exists {
                button.tap()
                return
            }
        }
        typeText("\n")
    }
}
