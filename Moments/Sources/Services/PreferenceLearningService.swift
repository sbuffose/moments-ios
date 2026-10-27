// PreferenceLearningService.swift
// On-device preference learning for review decisions

import Foundation
import SwiftData
import Vision

@MainActor
final class PreferenceLearningService: ObservableObject {
    static let shared = PreferenceLearningService()
    
    private var modelContext: ModelContext?
    
    // Cached feature prints for nearest-neighbor matching
    private var keptFeaturePrints: [(id: String, data: Data)] = []
    private var deletedFeaturePrints: [(id: String, data: Data)] = []
    private let maxCachedPrints = 100
    
    // Learning rate for online logistic regression
    private let learningRate: Double = 0.01
    
    // Threshold for suggesting category suppression
    private let highKeepRateThreshold: Double = 0.8
    private let minDecisionsForSuggestion: Int = 10
    
    private init() {}
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await loadCachedFeaturePrints()
        }
    }
    
    // MARK: - Log Review Decision
    
    func logDecision(
        for photo: PersistedPhoto,
        decision: ReviewDecisionType
    ) async {
        guard let context = modelContext else { return }
        
        let reviewDecision = ReviewDecision(
            photoId: photo.id,
            localIdentifier: photo.localIdentifier,
            decisionType: decision,
            photo: photo
        )
        
        context.insert(reviewDecision)
        
        // Update learned preferences
        await updatePreferences(with: reviewDecision)
        
        // Update feature print cache for nearest-neighbor
        if let featureData = photo.imageFeaturePrintData {
            if reviewDecision.isKeepDecision {
                addToKeptPrints(id: photo.id, data: featureData)
            } else if reviewDecision.isDeleteDecision {
                addToDeletedPrints(id: photo.id, data: featureData)
            }
        }
        
        try? context.save()
    }
    
    // MARK: - Update Preferences
    
    private func updatePreferences(with decision: ReviewDecision) async {
        guard let context = modelContext else { return }
        
        let preferences = await getOrCreatePreferences()
        
        preferences.totalDecisions += 1
        preferences.lastUpdated = Date()
        
        // Update Bayesian category keep rate
        if let categoryRaw = decision.categoryRaw,
           let category = CleanupCategoryType(rawValue: categoryRaw) {
            updateCategoryKeepRate(preferences: preferences, category: category, kept: decision.isKeepDecision)
        }
        
        // Update logistic regression weights
        updateLogisticWeights(preferences: preferences, decision: decision)
        
        // Check if any category should be deprioritized
        await checkForDeprioritization(preferences: preferences)
        
        // Update learning summary
        await updateLearningSummary(preferences: preferences)
        
        try? context.save()
    }
    
    private func updateCategoryKeepRate(preferences: LearnedPreferences, category: CleanupCategoryType, kept: Bool) {
        let keepValue: Double = kept ? 1.0 : 0.0
        
        // Bayesian update: posterior = (prior * n + new_value) / (n + 1)
        switch category {
        case .screenshot:
            let n = Double(preferences.screenshotDecisions)
            preferences.screenshotKeepRate = (preferences.screenshotKeepRate * n + keepValue) / (n + 1)
            preferences.screenshotDecisions += 1
        case .blurry:
            let n = Double(preferences.blurryDecisions)
            preferences.blurryKeepRate = (preferences.blurryKeepRate * n + keepValue) / (n + 1)
            preferences.blurryDecisions += 1
        case .underexposed:
            let n = Double(preferences.darkDecisions)
            preferences.darkKeepRate = (preferences.darkKeepRate * n + keepValue) / (n + 1)
            preferences.darkDecisions += 1
        case .overexposed:
            let n = Double(preferences.overexposedDecisions)
            preferences.overexposedKeepRate = (preferences.overexposedKeepRate * n + keepValue) / (n + 1)
            preferences.overexposedDecisions += 1
        case .burst:
            let n = Double(preferences.burstDecisions)
            preferences.burstKeepRate = (preferences.burstKeepRate * n + keepValue) / (n + 1)
            preferences.burstDecisions += 1
        case .duplicate, .nearDuplicate:
            let n = Double(preferences.duplicateDecisions)
            preferences.duplicateKeepRate = (preferences.duplicateKeepRate * n + keepValue) / (n + 1)
            preferences.duplicateDecisions += 1
        case .downloadedMeme:
            let n = Double(preferences.downloadDecisions)
            preferences.downloadKeepRate = (preferences.downloadKeepRate * n + keepValue) / (n + 1)
            preferences.downloadDecisions += 1
        case .forwardedImage:
            let n = Double(preferences.forwardedDecisions)
            preferences.forwardedKeepRate = (preferences.forwardedKeepRate * n + keepValue) / (n + 1)
            preferences.forwardedDecisions += 1
        case .receipt:
            let n = Double(preferences.receiptDecisions)
            preferences.receiptKeepRate = (preferences.receiptKeepRate * n + keepValue) / (n + 1)
            preferences.receiptDecisions += 1
        case .document:
            let n = Double(preferences.documentDecisions)
            preferences.documentKeepRate = (preferences.documentKeepRate * n + keepValue) / (n + 1)
            preferences.documentDecisions += 1
        default:
            break
        }
    }
    
    private func updateLogisticWeights(preferences: LearnedPreferences, decision: ReviewDecision) {
        // Online logistic regression update using gradient descent
        // y = 1 for keep, 0 for delete
        let y = decision.isKeepDecision ? 1.0 : 0.0
        
        // Feature vector
        let faceFeature = Double(decision.faceCount) / 10.0  // Normalized
        let aestheticsFeature = decision.aestheticsScore ?? 0.5
        let sharpnessFeature = decision.sharpnessScore ?? 0.5
        let ageFeature = min(1.0, Double(decision.photoAgeInDays) / 365.0)  // Normalized to 1 year
        let sizeFeature = min(1.0, Double(decision.photoSizeBytes) / 10_000_000.0)  // Normalized to 10MB
        let textFeature = decision.hasText ? 1.0 : 0.0
        
        // Compute prediction
        let z = preferences.intercept +
            preferences.weightFaceCount * faceFeature +
            preferences.weightAesthetics * aestheticsFeature +
            preferences.weightSharpness * sharpnessFeature +
            preferences.weightPhotoAge * ageFeature +
            preferences.weightPhotoSize * sizeFeature +
            preferences.weightHasText * textFeature
        
        let prediction = 1.0 / (1.0 + exp(-z))  // Sigmoid
        
        // Gradient descent update
        let error = y - prediction
        
        preferences.intercept += learningRate * error
        preferences.weightFaceCount += learningRate * error * faceFeature
        preferences.weightAesthetics += learningRate * error * aestheticsFeature
        preferences.weightSharpness += learningRate * error * sharpnessFeature
        preferences.weightPhotoAge += learningRate * error * ageFeature
        preferences.weightPhotoSize += learningRate * error * sizeFeature
        preferences.weightHasText += learningRate * error * textFeature
    }
    
    // MARK: - Deprioritization Check
    
    private func checkForDeprioritization(preferences: LearnedPreferences) async {
        var newDeprioritized: [CleanupCategoryType] = []
        
        let categoriesToCheck: [CleanupCategoryType] = [
            .screenshot, .blurry, .underexposed, .overexposed,
            .burst, .duplicate, .downloadedMeme, .forwardedImage,
            .receipt, .document
        ]
        
        for category in categoriesToCheck {
            let keepRate = preferences.keepRate(for: category)
            let decisionCount = preferences.decisionCount(for: category)
            
            if keepRate >= highKeepRateThreshold && decisionCount >= minDecisionsForSuggestion {
                if !preferences.deprioritizedCategories.contains(category) &&
                   !preferences.suppressedCategories.contains(category) {
                    newDeprioritized.append(category)
                }
            }
        }
        
        if !newDeprioritized.isEmpty {
            var current = preferences.deprioritizedCategories
            current.append(contentsOf: newDeprioritized)
            preferences.setDeprioritizedCategories(current)
        }
    }
    
    // MARK: - Calculate Adjusted Score
    
    func calculateAdjustedScore(for photo: PersistedPhoto, baseScore: Double) async -> Double {
        guard let context = modelContext else { return baseScore }
        
        let preferences = await getOrCreatePreferences()
        let confidence = preferences.confidenceWeight
        
        // Start with base score
        var adjustedScore = baseScore
        
        // Apply learned category weight
        let category = photo.cleanupCategory
        if category != .none {
            let keepRate = preferences.keepRate(for: category)
            // Lower keep rate = higher deletion score
            let categoryAdjustment = (1.0 - keepRate) * 0.3 * confidence
            adjustedScore += categoryAdjustment
        }
        
        // Apply logistic regression prediction
        let logisticPrediction = calculateLogisticPrediction(preferences: preferences, photo: photo)
        // Lower prediction (less likely to keep) = higher deletion score
        let logisticAdjustment = (1.0 - logisticPrediction) * 0.2 * confidence
        adjustedScore += logisticAdjustment
        
        // Apply nearest-neighbor boost
        let nnBoost = await calculateNearestNeighborBoost(for: photo)
        adjustedScore += nnBoost * confidence
        
        // Clamp to [0, 1]
        return max(0, min(1, adjustedScore))
    }
    
    private func calculateLogisticPrediction(preferences: LearnedPreferences, photo: PersistedPhoto) -> Double {
        let faceFeature = Double(photo.facesDetected ?? 0) / 10.0
        let aestheticsFeature = photo.visionAestheticsScore ?? 0.5
        let sharpnessFeature = photo.sharpnessScore ?? 0.5
        
        var ageFeature = 0.5
        if let creationDate = photo.creationDate {
            let days = Date().timeIntervalSince(creationDate) / 86400
            ageFeature = min(1.0, days / 365.0)
        }
        
        let sizeFeature = min(1.0, Double(photo.estimatedFileSize ?? 0) / 10_000_000.0)
        let textFeature = (photo.hasText ?? false) ? 1.0 : 0.0
        
        let z = preferences.intercept +
            preferences.weightFaceCount * faceFeature +
            preferences.weightAesthetics * aestheticsFeature +
            preferences.weightSharpness * sharpnessFeature +
            preferences.weightPhotoAge * ageFeature +
            preferences.weightPhotoSize * sizeFeature +
            preferences.weightHasText * textFeature
        
        return 1.0 / (1.0 + exp(-z))
    }
    
    // MARK: - Nearest-Neighbor Boost
    
    private func calculateNearestNeighborBoost(for photo: PersistedPhoto) async -> Double {
        guard let featureData = photo.imageFeaturePrintData else { return 0 }
        
        var keptSimilarity: Float = 0
        var deletedSimilarity: Float = 0
        
        // Compare with kept photos
        for (_, keptData) in keptFeaturePrints.prefix(50) {
            if let similarity = computeFeaturePrintSimilarity(featureData, keptData) {
                keptSimilarity = max(keptSimilarity, similarity)
            }
        }
        
        // Compare with deleted photos
        for (_, deletedData) in deletedFeaturePrints.prefix(50) {
            if let similarity = computeFeaturePrintSimilarity(featureData, deletedData) {
                deletedSimilarity = max(deletedSimilarity, similarity)
            }
        }
        
        // Boost: similar to deleted = higher score, similar to kept = lower score
        let boost = Double(deletedSimilarity - keptSimilarity) * 0.15
        return boost
    }
    
    private func computeFeaturePrintSimilarity(_ data1: Data, _ data2: Data) -> Float? {
        guard let print1 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data1),
              let print2 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data2) else {
            return nil
        }
        
        var distance: Float = 0
        try? print1.computeDistance(&distance, to: print2)
        
        // Convert distance to similarity (lower distance = higher similarity)
        return max(0, 1 - distance)
    }
    
    // MARK: - Feature Print Cache
    
    private func addToKeptPrints(id: String, data: Data) {
        keptFeaturePrints.insert((id: id, data: data), at: 0)
        if keptFeaturePrints.count > maxCachedPrints {
            keptFeaturePrints.removeLast()
        }
    }
    
    private func addToDeletedPrints(id: String, data: Data) {
        deletedFeaturePrints.insert((id: id, data: data), at: 0)
        if deletedFeaturePrints.count > maxCachedPrints {
            deletedFeaturePrints.removeLast()
        }
    }
    
    private func loadCachedFeaturePrints() async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<ReviewDecision>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        guard let decisions = try? context.fetch(descriptor) else { return }
        
        for decision in decisions.prefix(maxCachedPrints * 2) {
            guard let featureData = decision.featurePrintData else { continue }
            
            if decision.isKeepDecision && keptFeaturePrints.count < maxCachedPrints {
                keptFeaturePrints.append((id: decision.photoId, data: featureData))
            } else if decision.isDeleteDecision && deletedFeaturePrints.count < maxCachedPrints {
                deletedFeaturePrints.append((id: decision.photoId, data: featureData))
            }
        }
    }
    
    // MARK: - Category Suppression
    
    func shouldShowCategory(_ category: CleanupCategoryType) async -> Bool {
        let preferences = await getOrCreatePreferences()
        return !preferences.suppressedCategories.contains(category)
    }
    
    func suppressCategory(_ category: CleanupCategoryType) async {
        let preferences = await getOrCreatePreferences()
        var suppressed = preferences.suppressedCategories
        if !suppressed.contains(category) {
            suppressed.append(category)
            preferences.setSuppressedCategories(suppressed)
            try? modelContext?.save()
        }
    }
    
    func unsuppressCategory(_ category: CleanupCategoryType) async {
        let preferences = await getOrCreatePreferences()
        var suppressed = preferences.suppressedCategories
        suppressed.removeAll { $0 == category }
        preferences.setSuppressedCategories(suppressed)
        try? modelContext?.save()
    }
    
    // MARK: - Learning Summary
    
    private func updateLearningSummary(preferences: LearnedPreferences) async {
        var summaryItems: [[String: Any]] = []
        
        // Find notable patterns
        if preferences.weightFaceCount > 0.5 {
            summaryItems.append([
                "key": "faces_positive",
                "text": "Solés conservar fotos con personas"
            ])
        }
        
        if preferences.weightAesthetics > 0.3 {
            summaryItems.append([
                "key": "aesthetics_positive",
                "text": "Preferís fotos de alta calidad"
            ])
        }
        
        // Category-specific patterns
        if preferences.screenshotKeepRate < 0.3 && preferences.screenshotDecisions >= 5 {
            summaryItems.append([
                "key": "screenshot_delete",
                "text": "Solés borrar capturas de pantalla"
            ])
        }
        
        if preferences.blurryKeepRate > 0.7 && preferences.blurryDecisions >= 5 {
            summaryItems.append([
                "key": "blurry_keep",
                "text": "Conservás muchas fotos que parecen borrosas"
            ])
        }
        
        if preferences.duplicateKeepRate < 0.2 && preferences.duplicateDecisions >= 5 {
            summaryItems.append([
                "key": "duplicate_delete",
                "text": "Solés eliminar duplicados"
            ])
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: summaryItems) {
            preferences.learningSummaryJson = String(data: data, encoding: .utf8)
        }
    }
    
    func getLearningSummary() async -> [String] {
        let preferences = await getOrCreatePreferences()
        
        guard let jsonString = preferences.learningSummaryJson,
              let data = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { $0["text"] as? String }
    }
    
    // MARK: - Reset
    
    func resetLearning() async {
        guard let context = modelContext else { return }
        
        // Delete all review decisions
        let decisionDescriptor = FetchDescriptor<ReviewDecision>()
        if let decisions = try? context.fetch(decisionDescriptor) {
            for decision in decisions {
                context.delete(decision)
            }
        }
        
        // Reset preferences
        let preferences = await getOrCreatePreferences()
        preferences.totalDecisions = 0
        preferences.lastUpdated = Date()
        
        preferences.screenshotKeepRate = 0.5
        preferences.blurryKeepRate = 0.5
        preferences.darkKeepRate = 0.5
        preferences.overexposedKeepRate = 0.5
        preferences.burstKeepRate = 0.5
        preferences.duplicateKeepRate = 0.5
        preferences.downloadKeepRate = 0.5
        preferences.forwardedKeepRate = 0.5
        preferences.receiptKeepRate = 0.5
        preferences.documentKeepRate = 0.5
        
        preferences.screenshotDecisions = 0
        preferences.blurryDecisions = 0
        preferences.darkDecisions = 0
        preferences.overexposedDecisions = 0
        preferences.burstDecisions = 0
        preferences.duplicateDecisions = 0
        preferences.downloadDecisions = 0
        preferences.forwardedDecisions = 0
        preferences.receiptDecisions = 0
        preferences.documentDecisions = 0
        
        preferences.weightFaceCount = 0.0
        preferences.weightAesthetics = 0.0
        preferences.weightSharpness = 0.0
        preferences.weightPhotoAge = 0.0
        preferences.weightPhotoSize = 0.0
        preferences.weightHasText = 0.0
        preferences.intercept = 0.0
        
        preferences.deprioritizedCategoriesRaw = nil
        preferences.suppressedCategoriesRaw = nil
        preferences.learningSummaryJson = nil
        
        // Clear caches
        keptFeaturePrints.removeAll()
        deletedFeaturePrints.removeAll()
        
        try? context.save()
    }
    
    // MARK: - Helpers
    
    private func getOrCreatePreferences() async -> LearnedPreferences {
        guard let context = modelContext else {
            return LearnedPreferences()
        }
        
        let descriptor = FetchDescriptor<LearnedPreferences>(
            predicate: #Predicate<LearnedPreferences> { $0.id == "main" }
        )
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        let newPrefs = LearnedPreferences()
        context.insert(newPrefs)
        try? context.save()
        return newPrefs
    }
    
    func getPreferences() async -> LearnedPreferences {
        return await getOrCreatePreferences()
    }
}
