// Lightweight layout checks used by DesignTourTests.

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
}
