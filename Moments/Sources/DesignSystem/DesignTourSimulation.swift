// Launch flags that pin a screen/state for DesignTourTests.

import Foundation

enum DesignTourSimulation {
    static let showOnboardingArgument = "-showOnboarding"
    static let resetOnboardingArgument = "--reset-onboarding"
    static let emptyHomeArgument = "-simulateEmptyHome"
    static let spaceSavedArgument = "-simulateSpaceSaved"
    static let photosDeniedArgument = "-simulatePhotosDenied"
    static let notificationsDeniedArgument = "-simulateNotificationsDenied"
    static let reviewSimilarArgument = "-simulateReviewSimilar"
    static let reviewVideoArgument = "-simulateReviewVideo"
    static let previewSavedBytes: Int64 = 48_000_000
    
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    
    static var showOnboarding: Bool {
        args.contains(showOnboardingArgument) || args.contains(resetOnboardingArgument)
    }
    
    static var emptyHome: Bool { args.contains(emptyHomeArgument) }
    static var spaceSaved: Bool { args.contains(spaceSavedArgument) }
    static var photosDenied: Bool { args.contains(photosDeniedArgument) }
    static var notificationsDenied: Bool { args.contains(notificationsDeniedArgument) }
    static var reviewSimilar: Bool { args.contains(reviewSimilarArgument) }
    static var reviewVideo: Bool { args.contains(reviewVideoArgument) }
    
    static func applyUserDefaultsIfNeeded() {
        if spaceSaved {
            UserDefaults.standard.set(Int(previewSavedBytes), forKey: "totalSpaceSaved")
        }
    }
}
