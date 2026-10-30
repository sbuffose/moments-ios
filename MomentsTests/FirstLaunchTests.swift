import XCTest
@testable import Moments

final class FirstLaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PermissionRequestRecorder.reset()
        FirstLaunchReset.apply()
    }
    
    // MARK: - 1. Onboarding copy is complete (no truncated source strings)
    
    func testOnboardingPageCopyIsCompleteInSpanish() {
        XCTAssertEqual(OnboardingCopy.expectedPage1TitleES, "Liberá espacio sin perder lo importante")
        XCTAssertEqual(OnboardingCopy.expectedPage1SubtitleES, "Tu teléfono lleno no es un problema, es una oportunidad.")
        XCTAssertEqual(OnboardingCopy.expectedPage2TitleES, "Reviví tus mejores momentos")
        XCTAssertEqual(OnboardingCopy.expectedPage2SubtitleES, "Tus fotos cuentan historias. Dejá que las encuentres.")
        
        for text in [
            OnboardingCopy.expectedPage1TitleES,
            OnboardingCopy.expectedPage1SubtitleES,
            OnboardingCopy.expectedPage2TitleES,
            OnboardingCopy.expectedPage2SubtitleES
        ] {
            XCTAssertFalse(text.hasSuffix("…") || text.hasSuffix("..."), "Source copy is truncated: \(text)")
            XCTAssertGreaterThan(text.count, 20, "Onboarding copy is unexpectedly short: \(text)")
            XCTAssertFalse(text.contains("perded"), text)
            XCTAssertFalse(text.contains("momeme"), text)
        }
    }
    
    // MARK: - 2. Explanation sheet keeps last row above the CTA
    
    func testExplanationSheetReservesSpaceForStartButton() {
        XCTAssertEqual(FirstRunExplanationCopy.rows.count, 5)
        XCTAssertEqual(FirstRunExplanationCopy.lastRow.title, "Vos decidís qué borrar")
        XCTAssertGreaterThanOrEqual(
            FirstRunExplanationCopy.startButtonReserve,
            96,
            "Scroll content must clear the pinned Empezar button"
        )
        XCTAssertEqual(FirstRunExplanationCopy.start, "Empezar")
    }
    
    // MARK: - 3. Progress bar reflects real / parallel work and moves
    
    func testFirstRunProgressAdvancesOnSmallIndexIncrements() {
        let library = 7781.0
        let first = FirstRunProgress.displayValue(
            overall: 0,
            indexing: 50 / library,
            analysis: 0,
            isIndexing: true,
            isAnalyzing: false
        )
        let second = FirstRunProgress.displayValue(
            overall: 0,
            indexing: 100 / library,
            analysis: 0,
            isIndexing: true,
            isAnalyzing: false
        )
        XCTAssertGreaterThan(first, 0.04)
        XCTAssertGreaterThan(second, first, "50→100 of 7781 must move the bar, not sit on a 0.12 floor")
        XCTAssertLessThan(second, 0.2)
    }
    
    func testFirstRunProgressCombinesParallelIndexingAndAnalysis() {
        let indexingOnly = FirstRunProgress.rawProgress(
            overall: 0, indexing: 0.4, analysis: 0, isIndexing: true, isAnalyzing: false
        )
        let parallel = FirstRunProgress.rawProgress(
            overall: 0, indexing: 0.4, analysis: 0.2, isIndexing: true, isAnalyzing: true
        )
        XCTAssertEqual(indexingOnly, 0.4 * 0.45, accuracy: 0.0001)
        XCTAssertEqual(parallel, 0.4 * 0.45 + 0.2 * 0.55, accuracy: 0.0001)
        XCTAssertGreaterThan(parallel, indexingOnly)
        
        let snapshot = ScanProgressSnapshot(indexed: 200, analyzed: 40, total: 1000, phase: .analyzing)
        XCTAssertGreaterThan(snapshot.overallProgress, 0.45)
        XCTAssertGreaterThan(snapshot.overallProgress, snapshot.indexProgress * 0.45)
        
        let later = ScanProgressSnapshot(indexed: 400, analyzed: 120, total: 1000, phase: .analyzing)
        XCTAssertGreaterThan(later.overallProgress, snapshot.overallProgress)
    }
    
    func testOverallProgressMovesDuringIndexingPhase() {
        let start = ScanProgressSnapshot(indexed: 0, analyzed: 0, total: 8000, phase: .indexing)
        let mid = ScanProgressSnapshot(indexed: 400, analyzed: 0, total: 8000, phase: .indexing)
        XCTAssertEqual(start.overallProgress, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(mid.overallProgress, start.overallProgress)
        XCTAssertEqual(mid.overallProgress, 400.0 / 8000.0 * 0.45, accuracy: 0.0001)
    }
    
    // MARK: - 4. Momentos presentation
    
    func testTimelineShowsAnalyzingInsteadOfSpinnerDuringScan() {
        XCTAssertEqual(
            TimelineLoadPresentation.resolve(isLoading: true, hasSections: false, analysisInProgress: true),
            .analyzing
        )
        XCTAssertEqual(
            TimelineLoadPresentation.resolve(isLoading: true, hasSections: false, analysisInProgress: false),
            .loading
        )
        XCTAssertEqual(
            TimelineLoadPresentation.resolve(isLoading: false, hasSections: false, analysisInProgress: false),
            .empty
        )
        XCTAssertEqual(
            TimelineLoadPresentation.resolve(isLoading: true, hasSections: true, analysisInProgress: true),
            .content
        )
        XCTAssertEqual(TimelineInProgressCopy.title, "Tus momentos se están acomodando")
        XCTAssertTrue(TimelineInProgressCopy.body.contains("conociendo"))
        XCTAssertFalse(TimelineInProgressCopy.title.contains("Cargando"))
    }
    
    // MARK: - 5. Photos vs notifications
    
    func testOnboardingAllowButtonRequestsPhotosOnly() {
        XCTAssertTrue(FirstLaunchPermissionPolicy.shouldRequestPhotos(fromOnboardingAllowButton: true))
        XCTAssertFalse(FirstLaunchPermissionPolicy.shouldRequestNotifications(fromOnboardingAllowButton: true))
        XCTAssertTrue(FirstLaunchPermissionPolicy.shouldRequestNotifications(fromOnboardingAllowButton: false))
    }
    
    func testPermissionRecorderKeepsPhotosAndNotificationsSeparate() {
        PermissionRequestRecorder.record(.photos)
        XCTAssertEqual(PermissionRequestRecorder.last, .photos)
        XCTAssertFalse(PermissionRequestRecorder.all.contains(.notifications))
        
        PermissionRequestRecorder.record(.notifications)
        XCTAssertEqual(PermissionRequestRecorder.last, .notifications)
        XCTAssertEqual(PermissionRequestRecorder.all, [.photos, .notifications])
    }
    
    func testFirstLaunchResetClearsAllFirstRunKeys() {
        let defaults = UserDefaults(suiteName: "test.firstlaunch.\(UUID().uuidString)")!
        defaults.set(true, forKey: FirstLaunchReset.onboardingCompletedKey)
        defaults.set(true, forKey: FirstLaunchReset.firstRunExplanationShownKey)
        defaults.set(true, forKey: FirstLaunchReset.initialAnalysisCompletedKey)
        defaults.set(true, forKey: FirstLaunchReset.notificationPromptShownKey)
        
        FirstLaunchReset.apply(defaults: defaults)
        
        for key in FirstLaunchReset.allKeys {
            XCTAssertNil(defaults.object(forKey: key), "Reset left \(key)")
        }
    }
}
