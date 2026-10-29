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
    }
}
