import XCTest
@testable import Moments

final class ReviewSwipeHumorTests: XCTestCase {
    func testSwipeThresholdKeepDeleteSnooze() {
        XCTAssertEqual(ReviewSwipePhysics.direction(translation: CGSize(width: 101, height: 10)), .keep)
        XCTAssertEqual(ReviewSwipePhysics.direction(translation: CGSize(width: -101, height: 8)), .delete)
        XCTAssertEqual(ReviewSwipePhysics.direction(translation: CGSize(width: 12, height: -101)), .snooze)
        XCTAssertEqual(ReviewSwipePhysics.direction(translation: CGSize(width: 40, height: -20)), .none)
    }
    
    func testSwipePreviewGrowsTowardCommit() {
        let early = ReviewSwipePhysics.preview(translation: CGSize(width: 50, height: 0))
        let late = ReviewSwipePhysics.preview(translation: CGSize(width: 100, height: 0))
        XCTAssertEqual(early.direction, .keep)
        XCTAssertLessThan(early.progress, late.progress)
        XCTAssertEqual(late.progress, 1, accuracy: 0.001)
    }
    
    func testStampAppearsBeforeCommit() {
        XCTAssertTrue(ReviewSwipePhysics.pastStampThreshold(CGSize(width: 60, height: 0)))
        XCTAssertFalse(ReviewSwipePhysics.pastStampThreshold(CGSize(width: 20, height: 0)))
    }
    
    func testHumorOptionsRotateBySeed() {
        let first = ReviewHumorCopy.pick(for: .keep, seed: 0)
        let second = ReviewHumorCopy.pick(for: .keep, seed: 1)
        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(ReviewHumorCopy.pick(for: .keep, seed: 0), first)
    }
    
    func testHumorDeleteIncludesScreenshotLine() {
        let options = ReviewHumorCopy.options(for: .delete, category: .screenshot)
        XCTAssertTrue(options.contains(.screenshotNever))
        XCTAssertTrue(options.contains(.deleteBlurry))
        XCTAssertTrue(options.contains(.deleteButterfly))
    }
    
    func testHumorSnoozeAndBatchLines() {
        XCTAssertEqual(ReviewHumorCopy.options(for: .snooze), [.snoozeWeek])
        XCTAssertEqual(ReviewHumorCopy.batchDoneLine(deletedCount: 0), ReviewHumorLine.batchKeptAll.localized)
        XCTAssertEqual(ReviewHumorCopy.batchDoneLine(deletedCount: 3), ReviewHumorLine.batchDone.localized)
        let freed = ReviewHumorCopy.liberatedLine(formattedBytes: "12 MB")
        XCTAssertTrue(freed.contains("12 MB"), freed)
        let kept = ReviewHumorCopy.keptCountLine(count: 16)
        XCTAssertTrue(kept.contains("16"), kept)
        XCTAssertNotEqual(kept, ReviewHumorLine.batchKeptAll.localized)
    }
    
    func testReviewActionColorsMatchThemedButtons() {
        XCTAssertEqual(ReviewActionKind.keep.paletteName, "freshGreen")
        XCTAssertEqual(ReviewActionKind.share.paletteName, "skyBlue")
        XCTAssertEqual(ReviewActionKind.delete.paletteName, "coral")
        XCTAssertEqual(ReviewActionKind.keep.label, "Conservar")
        XCTAssertEqual(ReviewActionKind.share.label, "Compartir")
        XCTAssertEqual(ReviewActionKind.delete.label, "Eliminar")
        XCTAssertNotEqual(ReviewActionKind.keep.paletteName, ReviewActionKind.share.paletteName)
        XCTAssertNotEqual(ReviewActionKind.share.paletteName, ReviewActionKind.delete.paletteName)
        XCTAssertNotEqual(ReviewActionKind.keep.paletteName, ReviewActionKind.delete.paletteName)
    }
    
    func testReviewCardFitsIPhone16ProAndSE() {
        let proScreen = CGSize(width: 402, height: 874)
        let seScreen = CGSize(width: 375, height: 667)
        
        let pro = ReviewCardLayout.size(in: CGSize(width: 402, height: 515), screenWidth: proScreen.width)
        XCTAssertEqual(pro.width, 370, accuracy: 0.01)
        XCTAssertEqual(pro.width / pro.height, ReviewCardLayout.aspectRatio, accuracy: 0.001)
        XCTAssertLessThanOrEqual(pro.width, proScreen.width - ReviewCardLayout.horizontalPadding * 2)
        XCTAssertGreaterThan(pro.width, 40)
        
        let se = ReviewCardLayout.size(in: CGSize(width: 375, height: 420), screenWidth: seScreen.width)
        XCTAssertLessThanOrEqual(se.width, seScreen.width - ReviewCardLayout.horizontalPadding * 2)
        XCTAssertEqual(se.width / se.height, ReviewCardLayout.aspectRatio, accuracy: 0.001)
        XCTAssertGreaterThan(se.width, 40)
        
        let tall = ReviewCardLayout.size(in: CGSize(width: 402, height: 800), screenWidth: 402)
        XCTAssertEqual(tall.width, 370, accuracy: 0.01)
        XCTAssertEqual(tall.height, 370 / ReviewCardLayout.aspectRatio, accuracy: 0.01)
        
        let short = ReviewCardLayout.size(in: CGSize(width: 402, height: 400), screenWidth: 402)
        XCTAssertEqual(short.height, 400, accuracy: 0.01)
        XCTAssertEqual(short.width, 300, accuracy: 0.01)
        
        let overflowingImageProposal = ReviewCardLayout.size(in: CGSize(width: 515.33, height: 515.33), screenWidth: 402)
        XCTAssertEqual(overflowingImageProposal.width, 370, accuracy: 0.01)
        XCTAssertLessThanOrEqual(overflowingImageProposal.width, 402 - 32)
    }
    
    func testHumorKeysExistInBothLanguages() {
        for line in ReviewHumorLine.allCases {
            XCTAssertFalse(line.localized.isEmpty, line.localizationKey)
            XCTAssertNotEqual(line.localized, line.localizationKey)
        }
    }
}
