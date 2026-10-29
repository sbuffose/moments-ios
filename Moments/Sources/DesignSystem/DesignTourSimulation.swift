// Launch flags that pin a screen/state for DesignTourTests.

import Foundation

enum DesignTourSimulation {
    static let showOnboardingArgument = "-showOnboarding"
    static let resetOnboardingArgument = "--reset-onboarding"
    static let emptyHomeArgument = "-simulateEmptyHome"
    static let spaceSavedArgument = "-simulateSpaceSaved"
    static let keptAllSummaryArgument = "-simulateKeptAllSummary"
    static let deletedSummaryArgument = "-simulateDeletedSummary"
    static let midSwipeKeepArgument = "-simulateMidSwipeKeep"
    static let midSwipeDeleteArgument = "-simulateMidSwipeDelete"
    static let midSwipeSnoozeArgument = "-simulateMidSwipeSnooze"
    static let reviewSwipeSinglesArgument = "-reviewSwipeSingles"
    static let previewSavedBytes: Int64 = 48_000_000
    static let previewDeletedBytes: Int64 = 18_000_000
    
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    
    static var showOnboarding: Bool {
        args.contains(showOnboardingArgument) || args.contains(resetOnboardingArgument)
    }
    
    static var emptyHome: Bool { args.contains(emptyHomeArgument) }
    static var spaceSaved: Bool { args.contains(spaceSavedArgument) }
    static var keptAllSummary: Bool { args.contains(keptAllSummaryArgument) }
    static var deletedSummary: Bool { args.contains(deletedSummaryArgument) }
    
    static var reviewSwipeSingles: Bool { args.contains(reviewSwipeSinglesArgument) }
    
    static var midSwipeDirection: ReviewSwipeDirection {
        if args.contains(midSwipeKeepArgument) { return .keep }
        if args.contains(midSwipeDeleteArgument) { return .delete }
        if args.contains(midSwipeSnoozeArgument) { return .snooze }
        return .none
    }
    
    static var forcesReviewSummary: Bool { keptAllSummary || deletedSummary }
    
    static func applyUserDefaultsIfNeeded() {
        if spaceSaved {
            UserDefaults.standard.set(Int(previewSavedBytes), forKey: "totalSpaceSaved")
        }
        if showOnboarding {
            UserDefaults.standard.set(false, forKey: "com.moments.hasCompletedOnboarding")
        }
        if reviewSwipeSingles {
            UserDefaults.standard.removeObject(forKey: "com.moments.cleanup.selectedPhotos")
            UserDefaults.standard.removeObject(forKey: "com.moments.cleanup.reviewedPhotos")
            UserDefaults.standard.removeObject(forKey: "com.moments.cleanup.reviewedGroups")
            UserDefaults.standard.removeObject(forKey: "com.moments.cleanup.keptPhotos")
        }
    }
}

enum ReviewHumorLine: String, CaseIterable, Sendable {
    case deleteBlurry
    case deleteButterfly
    case keepHeart
    case keepGem
    case snoozeWeek
    case screenshotNever
    case batchDone
    case batchKeptAll
    
    var localizationKey: String {
        switch self {
        case .deleteBlurry: return "humor_delete_blurry"
        case .deleteButterfly: return "humor_delete_butterfly"
        case .keepHeart: return "humor_keep_heart"
        case .keepGem: return "humor_keep_gem"
        case .snoozeWeek: return "humor_snooze_week"
        case .screenshotNever: return "humor_screenshot"
        case .batchDone: return "humor_batch_done"
        case .batchKeptAll: return "humor_batch_kept_all"
        }
    }
    
    var localized: String {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

enum ReviewHumorCopy {
    static func options(
        for direction: ReviewSwipeDirection,
        category: CleanupCategoryType? = nil
    ) -> [ReviewHumorLine] {
        switch direction {
        case .delete:
            var lines: [ReviewHumorLine] = [.deleteBlurry, .deleteButterfly]
            if category == .screenshot || category == .screenRecording {
                lines.append(.screenshotNever)
            }
            return lines
        case .keep:
            return [.keepHeart, .keepGem]
        case .snooze:
            return [.snoozeWeek]
        case .none:
            return []
        }
    }
    
    static func pick(
        for direction: ReviewSwipeDirection,
        category: CleanupCategoryType? = nil,
        seed: Int
    ) -> String {
        let lines = options(for: direction, category: category)
        guard !lines.isEmpty else { return "" }
        return lines[abs(seed) % lines.count].localized
    }
    
    static func batchDoneLine(deletedCount: Int) -> String {
        deletedCount == 0 ? ReviewHumorLine.batchKeptAll.localized : ReviewHumorLine.batchDone.localized
    }
    
    static func liberatedLine(formattedBytes: String) -> String {
        String(format: String(localized: String.LocalizationValue("humor_liberaste %1$@")), formattedBytes)
    }
    
    static func keptCountLine(count: Int) -> String {
        String(format: String(localized: String.LocalizationValue("humor_kept_count %1$lld")), Int64(count))
    }
    
    static func seed(from identifier: String) -> Int {
        identifier.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
    }
}
