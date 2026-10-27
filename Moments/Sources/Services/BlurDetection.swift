// BlurDetection.swift
// True Laplacian variance (not signed-mean + 0.5) plus Vision aesthetics agreement.

import Foundation

enum BlurDetection {
    /// Population variance of Laplacian samples. Do not average the signed kernel.
    static func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }
    
    static func sharpness(fromTileVariances variances: [Double], exposure: Double) -> Double {
        guard !variances.isEmpty else { return 0 }
        let sorted = variances.sorted(by: >)
        let topCount = max(1, Int(Double(sorted.count) * 0.10))
        let average = sorted.prefix(topCount).reduce(0, +) / Double(topCount)
        let boost: Double
        if exposure < 0.15 {
            boost = 2.5
        } else if exposure < 0.3 {
            boost = 1.5 + (0.3 - exposure) * 3.0
        } else {
            boost = 1.0
        }
        return min((average * boost) / 500.0, 1.0)
    }
    
    /// Requires a low Laplacian score AND a low Vision aesthetics score when available.
    static func isBlurry(
        sharpness: Double,
        aesthetics: Double?,
        isUtility: Bool?,
        hasFaces: Bool
    ) -> Bool {
        let threshold = hasFaces ? 0.05 : 0.10
        guard sharpness < threshold else { return false }
        if let aesthetics {
            let aestheticLimit = hasFaces ? 0.20 : 0.35
            return aesthetics < aestheticLimit && (isUtility ?? true)
        }
        return sharpness < (hasFaces ? 0.03 : 0.08)
    }
    
    static func syntheticBlurTiles() -> [Double] {
        Array(repeating: 2.0, count: 64)
    }
    
    static func syntheticSharpNightTiles() -> [Double] {
        var tiles = Array(repeating: 8.0, count: 58)
        tiles.append(contentsOf: [180, 220, 200, 190, 210, 175])
        return tiles
    }
}
