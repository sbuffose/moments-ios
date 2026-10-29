// PhotoLuminance.swift
// Classifies measured mean luminance so a black frame is never a silent void.

import Foundation
import UIKit

enum PhotoLuminanceClass: String, Equatable, Sendable {
    case blackFrame
    case dark
    case normal
    
    /// Near-black / pocket-or-covered shutter. Below this the image is a black rectangle.
    static let blackFrameThreshold = 0.04
    /// Underexposed but still has visible detail.
    static let darkThreshold = 0.15
    
    static func classify(meanLuminance: Double) -> PhotoLuminanceClass {
        if meanLuminance <= blackFrameThreshold { return .blackFrame }
        if meanLuminance < darkThreshold { return .dark }
        return .normal
    }
    
    static let blackFrameTitle = "Foto casi toda negra"
    static let blackFrameSubtitle = "Probablemente sacada sin querer (bolsillo o tapada)"
    static let darkBadgeTitle = "Muy oscura"
    static let loadFailureTitle = "No pudimos cargar esta foto"
    static let loadFailureRetryTitle = "Reintentar"
}

enum ThumbnailLoadFailureSimulation {
    static let launchArgument = "-simulateThumbnailLoadFailure"
    
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum FirstRunCompletionSimulation {
    static let launchArgument = "-simulateFirstScanThenComplete"
    
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

enum HomeRevealPolicy {
    /// Completing first-run while the scene is not active must not start a spring
    /// that can freeze mid-fade (the 266 Home-at-15% bug).
    static func disablesAnimations(applicationState: UIApplication.State) -> Bool {
        applicationState != .active
    }
}
