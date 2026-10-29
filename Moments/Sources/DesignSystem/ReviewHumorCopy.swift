// ReviewHumorCopy.swift
// Short, warm es-AR humor. Never mean, never about people's looks.

import Foundation

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
        String(format: String(localized: "humor_liberaste %1$@"), formattedBytes)
    }
    
    static func seed(from identifier: String) -> Int {
        identifier.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
    }
}
