// Layout checks used by DesignTourTests. Each rule maps to a screenshot bug.

import XCTest

enum DesignTourScreen {
    case onboarding
    case home
    case review
    case summaryKept
    case summaryDeleted
    case other
}

enum DesignLayoutAssert {
    static let margin: CGFloat = 16
    
    static func assertVisibleChrome(
        _ app: XCUIApplication,
        elements: [XCUIElement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        guard window.width > 0, window.height > 0 else { return }
        
        var frames: [(String, CGRect)] = []
        for element in elements {
            guard element.exists else { continue }
            let frame = element.frame
            guard frame.width > 1, frame.height > 1, !frame.isNull, !frame.isInfinite else { continue }
            
            let label = element.label.isEmpty ? (element.identifier.isEmpty ? "unnamed" : element.identifier) : element.label
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                window.minX + margin - 1,
                "\(label) overflows leading 16pt margin",
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                window.maxX - margin + 1,
                "\(label) overflows trailing 16pt margin",
                file: file,
                line: line
            )
            frames.append((label, frame))
        }
        
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                let hit = frames[i].1.intersection(frames[j].1)
                XCTAssertFalse(
                    hit.width > 4 && hit.height > 4,
                    "Overlapping chrome: \(frames[i].0) vs \(frames[j].0) \(hit)",
                    file: file,
                    line: line
                )
            }
        }
    }
    
    static func assertScreen(
        _ app: XCUIApplication,
        _ screen: DesignTourScreen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertNoAlbumCopy(app, file: file, line: line)
        assertNoTruncatedLabels(app, file: file, line: line)
        switch screen {
        case .review, .summaryKept, .summaryDeleted, .onboarding:
            assertNoDuplicateVisibleStrings(app, file: file, line: line)
        case .home, .other:
            break
        }
        
        switch screen {
        case .review, .summaryKept, .summaryDeleted:
            XCTAssertFalse(
                app.tabBars.firstMatch.exists,
                "Review/summary must hide the tab bar",
                file: file,
                line: line
            )
        case .home, .onboarding, .other:
            break
        }
        
        switch screen {
        case .summaryKept, .summaryDeleted:
            XCTAssertFalse(
                app.buttons["Terminar"].exists || app.navigationBars["Revisar fotos"].exists,
                "Summary must be full-screen without Terminar / Revisar fotos",
                file: file,
                line: line
            )
        default:
            break
        }
        
        if screen == .summaryKept {
            let haystack = visibleLabels(app).joined(separator: "\n")
            XCTAssertFalse(haystack.contains("KB"), "Kept-all summary must not mention KB: \(haystack)", file: file, line: line)
            XCTAssertFalse(haystack.contains("MB"), "Kept-all summary must not mention MB: \(haystack)", file: file, line: line)
            XCTAssertFalse(haystack.contains("Eliminados"), "Kept-all summary must not mention Eliminados: \(haystack)", file: file, line: line)
            XCTAssertFalse(app.buttons["Abrir Fotos"].exists, "Kept-all summary must not offer Abrir Fotos", file: file, line: line)
        }
        
        if screen == .review {
            XCTAssertTrue(
                app.buttons["review.tagButton"].exists || app.buttons["Etiquetar"].exists,
                "Review must offer Etiquetar",
                file: file,
                line: line
            )
        }
    }
    
    static func assertNoAlbumCopy(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            app.staticTexts["Guardar en álbum"].exists || app.buttons["Guardar en álbum"].exists,
            "Guardar en álbum must not appear anywhere",
            file: file,
            line: line
        )
    }
    
    static func assertNoTruncatedLabels(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for label in visibleLabels(app) {
            XCTAssertFalse(
                label.hasSuffix("...") || label.hasSuffix("…"),
                "Truncated visible text: \(label)",
                file: file,
                line: line
            )
        }
    }
    
    static func assertNoDuplicateVisibleStrings(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var counts: [String: Int] = [:]
        for label in visibleLabels(app) {
            counts[label, default: 0] += 1
        }
        for (label, count) in counts where count > 1 {
            XCTFail("Visible string appears \(count) times: \(label)", file: file, line: line)
        }
    }
    
    private static func visibleLabels(_ app: XCUIApplication) -> [String] {
        let window = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        var labels: [String] = []
        let texts = app.staticTexts
        let limit = min(texts.count, 80)
        for index in 0..<limit {
            let element = texts.element(boundBy: index)
            guard element.exists else { continue }
            let frame = element.frame
            guard frame.height > 8, frame.width > 8, window.intersects(frame) else { continue }
            let label = element.label.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard label.count > 1 else { continue }
            if label == element.identifier { continue }
            if label.hasPrefix("review.") || label.hasPrefix("onboarding.") || label.hasPrefix("home.") { continue }
            labels.append(label)
        }
        return labels
    }
}
