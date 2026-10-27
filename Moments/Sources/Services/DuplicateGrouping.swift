// DuplicateGrouping.swift
// Incremental, bucketed grouping so detectDuplicates is not O(n²) on every run.

import Foundation

enum DuplicateGrouping {
    static let timeWindow: TimeInterval = 6 * 3600
    
    static func bucket(forDHash hash: Int64) -> Int64 {
        hash >> 48
    }
    
    static func areNearInTime(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return true }
        return abs(lhs.timeIntervalSince(rhs)) <= timeWindow
    }
    
    static func shouldCompare(hashA: Int64?, hashB: Int64?, dateA: Date?, dateB: Date?) -> Bool {
        if let hashA, let hashB, bucket(forDHash: hashA) == bucket(forDHash: hashB) {
            return true
        }
        return areNearInTime(dateA, dateB)
    }
    
    static func pairKey(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "_")
    }
    
    /// Replace groups that overlap `photoIds`, keeping user "not similar" feedback.
    static func groupsToDelete<G>(
        existing: [G],
        incomingPhotoIds: Set<String>,
        photoIds: (G) -> [String],
        isNotSimilar: (G) -> Bool
    ) -> [G] {
        existing.filter { group in
            guard !isNotSimilar(group) else { return false }
            return !Set(photoIds(group)).isDisjoint(with: incomingPhotoIds)
        }
    }
}
