// ReviewSwipePhysics.swift
// Pure swipe-threshold math. Unit-tested; the card view only renders it.

import CoreGraphics
import Foundation

enum ReviewSwipeDirection: String, Sendable, Equatable {
    case keep
    case delete
    case snooze
    case none
}

enum ReviewSwipePhysics {
    static let commitThreshold: CGFloat = 100
    static let stampThreshold: CGFloat = 56
    static let flyOffDistance: CGFloat = 640
    
    static func preview(translation: CGSize) -> (direction: ReviewSwipeDirection, progress: CGFloat) {
        let ax = abs(translation.width)
        let ay = abs(translation.height)
        if ay > ax && translation.height < 0 {
            return (.snooze, min(1, ay / commitThreshold))
        }
        if translation.width > 0 {
            return (.keep, min(1, ax / commitThreshold))
        }
        if translation.width < 0 {
            return (.delete, min(1, ax / commitThreshold))
        }
        return (.none, 0)
    }
    
    static func direction(translation: CGSize) -> ReviewSwipeDirection {
        let preview = preview(translation: translation)
        return preview.progress >= 1 ? preview.direction : .none
    }
    
    static func pastStampThreshold(_ translation: CGSize) -> Bool {
        let preview = preview(translation: translation)
        return preview.direction != .none && preview.progress >= stampThreshold / commitThreshold
    }
    
    static func rotationDegrees(translation: CGSize) -> Double {
        Double(translation.width / 18)
    }
    
    static func flyOffOffset(for direction: ReviewSwipeDirection) -> CGSize {
        switch direction {
        case .keep: return CGSize(width: flyOffDistance, height: -40)
        case .delete: return CGSize(width: -flyOffDistance, height: 40)
        case .snooze: return CGSize(width: 0, height: -flyOffDistance)
        case .none: return .zero
        }
    }
}
