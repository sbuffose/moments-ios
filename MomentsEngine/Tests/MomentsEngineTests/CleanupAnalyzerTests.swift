// CleanupAnalyzerTests.swift
// Tests para el analizador de limpieza

import XCTest
@testable import MomentsEngine

final class CleanupAnalyzerTests: XCTestCase {
    
    var analyzer: CleanupAnalyzer!
    
    override func setUp() {
        super.setUp()
        analyzer = CleanupAnalyzer()
    }
    
    // MARK: - Screenshot Detection Tests
    
    func testDetectScreenshots() {
        let photos = [
            createPhoto(id: "1", mediaSubtypes: [.screenshot]),
            createPhoto(id: "2", mediaSubtypes: []),
            createPhoto(id: "3", mediaSubtypes: [.screenshot]),
        ]
        
        let screenshots = analyzer.detectScreenshots(in: photos)
        
        XCTAssertEqual(screenshots.count, 2)
        XCTAssertTrue(screenshots.allSatisfy { $0.mediaSubtypes.contains(.screenshot) })
    }
    
    func testDetectScreenRecordings() {
        let photos = [
            createPhoto(id: "1", mediaType: .video, mediaSubtypes: [.screenRecording]),
            createPhoto(id: "2", mediaType: .video, mediaSubtypes: []),
            createPhoto(id: "3", mediaType: .image, mediaSubtypes: [.screenshot]),
        ]
        
        let recordings = analyzer.detectScreenRecordings(in: photos)
        
        XCTAssertEqual(recordings.count, 1)
        XCTAssertEqual(recordings.first?.id, "1")
    }
    
    // MARK: - Blurry Photo Detection Tests
    
    func testDetectBlurryPhotos() {
        let photos = [
            createPhoto(id: "1", sharpnessScore: 0.1),
            createPhoto(id: "2", sharpnessScore: 0.5),
            createPhoto(id: "3", sharpnessScore: 0.2),
            createPhoto(id: "4", sharpnessScore: 0.8),
        ]
        
        let blurry = analyzer.detectBlurryPhotos(in: photos)
        
        XCTAssertEqual(blurry.count, 2)
        XCTAssertTrue(blurry.allSatisfy { ($0.sharpnessScore ?? 1.0) < 0.3 })
    }
    
    func testBlurryPhotosAreSortedBySharpness() {
        let photos = [
            createPhoto(id: "1", sharpnessScore: 0.2),
            createPhoto(id: "2", sharpnessScore: 0.05),
            createPhoto(id: "3", sharpnessScore: 0.15),
        ]
        
        let blurry = analyzer.detectBlurryPhotos(in: photos)
        
        XCTAssertEqual(blurry.map { $0.id }, ["2", "3", "1"])
    }
    
    // MARK: - Exposure Detection Tests
    
    func testDetectOverexposedPhotos() {
        let photos = [
            createPhoto(id: "1", exposureScore: 0.9),
            createPhoto(id: "2", exposureScore: 0.5),
            createPhoto(id: "3", exposureScore: 0.95),
        ]
        
        let overexposed = analyzer.detectOverexposedPhotos(in: photos)
        
        XCTAssertEqual(overexposed.count, 2)
        XCTAssertTrue(overexposed.allSatisfy { ($0.exposureScore ?? 0) > 0.85 })
    }
    
    func testDetectUnderexposedPhotos() {
        let photos = [
            createPhoto(id: "1", exposureScore: 0.1),
            createPhoto(id: "2", exposureScore: 0.5),
            createPhoto(id: "3", exposureScore: 0.05),
        ]
        
        let underexposed = analyzer.detectUnderexposedPhotos(in: photos)
        
        XCTAssertEqual(underexposed.count, 2)
        XCTAssertTrue(underexposed.allSatisfy { ($0.exposureScore ?? 1) < 0.15 })
    }
    
    // MARK: - Burst Detection Tests
    
    func testDetectBursts() {
        let photos = [
            createPhoto(id: "1", burstIdentifier: "burst1", representsBurst: true),
            createPhoto(id: "2", burstIdentifier: "burst1"),
            createPhoto(id: "3", burstIdentifier: "burst1"),
            createPhoto(id: "4", burstIdentifier: nil),
            createPhoto(id: "5", burstIdentifier: "burst2"),
            createPhoto(id: "6", burstIdentifier: "burst2"),
        ]
        
        let bursts = analyzer.detectBursts(in: photos)
        
        XCTAssertEqual(bursts.count, 2)
        
        let burst1 = bursts.first { $0.burstIdentifier == "burst1" }
        XCTAssertNotNil(burst1)
        XCTAssertEqual(burst1?.all.count, 3)
    }
    
    func testBurstBestSelectionPrefersRepresentative() {
        let photos = [
            createPhoto(id: "1", burstIdentifier: "burst1", representsBurst: true, sharpnessScore: 0.5),
            createPhoto(id: "2", burstIdentifier: "burst1", sharpnessScore: 0.6),
            createPhoto(id: "3", burstIdentifier: "burst1", sharpnessScore: 0.7),
        ]
        
        let bursts = analyzer.detectBursts(in: photos)
        
        // La foto representativa tiene bonus, pero la más nítida debería ganar
        XCTAssertEqual(bursts.first?.best.id, "3")
    }
    
    // MARK: - Large Videos Detection Tests
    
    func testDetectLargeVideos() {
        let photos = [
            createPhoto(id: "1", mediaType: .video, estimatedFileSize: 50_000_000),
            createPhoto(id: "2", mediaType: .video, estimatedFileSize: 150_000_000),
            createPhoto(id: "3", mediaType: .video, estimatedFileSize: 200_000_000),
            createPhoto(id: "4", mediaType: .image, estimatedFileSize: 500_000_000),
        ]
        
        let largeVideos = analyzer.detectLargeVideos(in: photos)
        
        XCTAssertEqual(largeVideos.count, 2)
        XCTAssertEqual(largeVideos.first?.id, "3") // Más grande primero
    }
    
    // MARK: - Accidental Shots Detection Tests
    
    func testDetectVeryDarkAccidentalShots() {
        let photos = [
            createPhoto(id: "1", exposureScore: 0.03), // Muy oscura
            createPhoto(id: "2", exposureScore: 0.5),
        ]
        
        let accidental = analyzer.detectAccidentalShots(in: photos)
        
        XCTAssertEqual(accidental.count, 1)
        XCTAssertEqual(accidental.first?.id, "1")
    }
    
    func testDetectExtremeAspectRatioAccidentalShots() {
        let photos = [
            createPhoto(id: "1", pixelWidth: 100, pixelHeight: 1000), // Muy vertical
            createPhoto(id: "2", pixelWidth: 1000, pixelHeight: 100), // Muy horizontal
            createPhoto(id: "3", pixelWidth: 1000, pixelHeight: 800), // Normal
        ]
        
        let accidental = analyzer.detectAccidentalShots(in: photos)
        
        XCTAssertEqual(accidental.count, 2)
    }
    
    // MARK: - Quality Score Tests
    
    func testQualityScoreCalculation() {
        let sharpPhoto = createPhoto(id: "1", sharpnessScore: 0.9, exposureScore: 0.5, isFavorite: true)
        let blurryPhoto = createPhoto(id: "2", sharpnessScore: 0.2, exposureScore: 0.9)
        
        let sharpScore = analyzer.qualityScore(for: sharpPhoto)
        let blurryScore = analyzer.qualityScore(for: blurryPhoto)
        
        XCTAssertGreaterThan(sharpScore, blurryScore)
    }
    
    func testSelectBestPhotoFromGroup() {
        let photos = [
            createPhoto(id: "1", sharpnessScore: 0.3, exposureScore: 0.5),
            createPhoto(id: "2", sharpnessScore: 0.9, exposureScore: 0.5),
            createPhoto(id: "3", sharpnessScore: 0.6, exposureScore: 0.5),
        ]
        
        let best = analyzer.selectBestPhoto(from: photos)
        
        XCTAssertEqual(best.id, "2")
    }
    
    // MARK: - Full Analysis Tests
    
    func testFullAnalysis() {
        let photos = [
            createPhoto(id: "1", mediaSubtypes: [.screenshot]),
            createPhoto(id: "2", sharpnessScore: 0.1),
            createPhoto(id: "3", mediaType: .video, estimatedFileSize: 200_000_000),
        ]
        
        let suggestions = analyzer.analyze(photos: photos)
        
        XCTAssertEqual(suggestions.screenshots.count, 1)
        XCTAssertEqual(suggestions.blurryPhotos.count, 1)
        XCTAssertEqual(suggestions.largeVideos.count, 1)
        XCTAssertEqual(suggestions.totalSuggestedForDeletion, 3)
    }
    
    // MARK: - Helpers
    
    private func createPhoto(
        id: String,
        mediaType: MediaType = .image,
        mediaSubtypes: Set<MediaSubtype> = [],
        pixelWidth: Int = 4032,
        pixelHeight: Int = 3024,
        sharpnessScore: Double? = nil,
        exposureScore: Double? = nil,
        burstIdentifier: String? = nil,
        representsBurst: Bool = false,
        estimatedFileSize: Int64? = nil,
        isFavorite: Bool = false
    ) -> PhotoMetadata {
        PhotoMetadata(
            id: id,
            creationDate: Date(),
            modificationDate: nil,
            mediaType: mediaType,
            mediaSubtypes: mediaSubtypes,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            burstIdentifier: burstIdentifier,
            representsBurst: representsBurst,
            sharpnessScore: sharpnessScore,
            exposureScore: exposureScore,
            estimatedFileSize: estimatedFileSize
        )
    }
}
