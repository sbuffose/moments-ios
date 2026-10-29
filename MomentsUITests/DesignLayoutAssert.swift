// Lightweight layout checks used by DesignTourTests.
// Titles/buttons must not overlap, sit inside 16pt margins, and not truncate.

import XCTest

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
            XCTAssertGreaterThanOrEqual(
                frame.minY,
                window.minY - 1,
                "\(label) is above the window",
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                frame.maxY,
                window.maxY + 1,
                "\(label) is below the window",
                file: file,
                line: line
            )
            
            let spoken = element.label + " " + (element.value as? String ?? "")
            XCTAssertFalse(
                spoken.contains("Eliminar t") || spoken.contains("Fotos > Álbumes > Eliminados recientemente > Eliminar t"),
                "\(label) looks truncated: \(spoken)",
                file: file,
                line: line
            )
            if let value = element.value as? String, !value.isEmpty, !element.label.isEmpty {
                let clipped = element.label.hasSuffix("…") || element.label.hasSuffix("...")
                XCTAssertFalse(
                    clipped && value.count > element.label.count + 2,
                    "\(label) accessibility value is longer than the visible label (truncated)",
                    file: file,
                    line: line
                )
            }
            frames.append((label, frame))
        }
        
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                let a = frames[i].1
                let b = frames[j].1
                let hit = a.intersection(b)
                XCTAssertFalse(
                    hit.width > 4 && hit.height > 4,
                    "Overlapping chrome: \(frames[i].0) vs \(frames[j].0) \(hit)",
                    file: file,
                    line: line
                )
            }
        }
    }
}
