// CleanupViewModel.swift
// ViewModel para la funcionalidad de limpieza

import Foundation
import SwiftData
import Photos
import Combine

// Preference learning integration
private let preferenceLearningService = PreferenceLearningService.shared

// MARK: - Review Item (Single photo or Group)

enum ReviewItem: Identifiable {
    case single(PersistedPhoto)
    case exactDuplicateGroup(SimilarGroup, [PersistedPhoto])
    case similarGroup(SimilarGroup, [PersistedPhoto])
    
    var id: String {
        switch self {
        case .single(let photo):
            return "single_\(photo.id)"
        case .exactDuplicateGroup(let group, _):
            return "exact_\(group.id)"
        case .similarGroup(let group, _):
            return "similar_\(group.id)"
        }
    }
    
    var photoIds: [String] {
        switch self {
        case .single(let photo):
            return [photo.id]
        case .exactDuplicateGroup(_, let photos), .similarGroup(_, let photos):
            return photos.map { $0.id }
        }
    }
    
    var maxDeletionScore: Double {
        switch self {
        case .single(let photo):
            return photo.deletionLikelihoodScore
        case .exactDuplicateGroup(_, let photos), .similarGroup(_, let photos):
            return photos.map { $0.deletionLikelihoodScore }.max() ?? 0
        }
    }
    
    var totalSize: Int64 {
        switch self {
        case .single(let photo):
            return photo.estimatedFileSize ?? 0
        case .exactDuplicateGroup(_, let photos), .similarGroup(_, let photos):
            return photos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
        }
    }
    
    var bestPhoto: PersistedPhoto? {
        switch self {
        case .single(let photo):
            return photo
        case .exactDuplicateGroup(let group, let photos), .similarGroup(let group, let photos):
            return photos.first { $0.id == group.bestPhotoId } ?? photos.first
        }
    }
    
    var isGroup: Bool {
        switch self {
        case .single: return false
        case .exactDuplicateGroup, .similarGroup: return true
        }
    }
}

enum DailyReviewBatch {
    static let size = 20
    
    /// A group counts as 1 item. Returns the top `size` items by deletion likelihood.
    static func cap(_ items: [ReviewItem]) -> (batch: [ReviewItem], remaining: Int) {
        let sorted = items.sorted { $0.maxDeletionScore > $1.maxDeletionScore }
        return (Array(sorted.prefix(size)), max(0, sorted.count - size))
    }
    
    static func progressLabel(reviewed: Int, batchCount: Int) -> String {
        let total = min(size, max(batchCount, 0))
        let position = min(max(reviewed, 0) + (total == 0 ? 0 : 1), max(total, 1))
        return "\(position) de \(total)"
    }
}

@MainActor
class CleanupViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isLoading = true
    @Published var selectedCategory: CleanupCategoryItem?
    @Published var selectedPhotos: Set<String> = []
    @Published var reviewedPhotos: Set<String> = []
    @Published var reviewedGroups: Set<String> = []
    @Published var keptPhotos: Set<String> = []
    @Published var isDeleting = false
    @Published var showDeleteConfirmation = false
    @Published var errorMessage: String?
    @Published var spaceFreed: Int64 = 0
    @Published var lastDeletedSize: Int64 = 0
    
    @Published var categories: [CleanupCategoryItem] = []
    @Published var estimatedSpaceFreed: Int64 = 0
    
    // Grouped review queue
    @Published var reviewQueue: [ReviewItem] = []
    @Published var similarGroups: [SimilarGroup] = []
    @Published var remainingAfterBatch: Int = 0
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private var allPhotos: [PersistedPhoto] = []
    
    // MARK: - Persistence Keys
    
    private let selectedPhotosKey = "com.moments.cleanup.selectedPhotos"
    private let reviewedPhotosKey = "com.moments.cleanup.reviewedPhotos"
    private let reviewedGroupsKey = "com.moments.cleanup.reviewedGroups"
    private let keptPhotosKey = "com.moments.cleanup.keptPhotos"
    
    // MARK: - Category Item
    
    struct CleanupCategoryItem: Identifiable {
        let id: String
        let category: CleanupCategoryType
        let count: Int
        let photos: [PersistedPhoto]
        let estimatedSize: Int64
        let confidenceTier: CleanupConfidenceTier
        
        // Photos split by confidence
        var veryLikelyPhotos: [PersistedPhoto] {
            photos.filter { $0.cleanupConfidenceTier == .veryLikely }
        }
        
        var maybePhotos: [PersistedPhoto] {
            photos.filter { $0.cleanupConfidenceTier == .maybe || $0.cleanupConfidenceTier == nil }
        }
        
        var icon: String { category.iconName }
        var localizedKey: String { category.localizedKey }
    }
    
    // Published tiers
    @Published var veryLikelyCategories: [CleanupCategoryItem] = []
    @Published var maybeCategories: [CleanupCategoryItem] = []
    
    // MARK: - Computed Properties
    
    var totalCleanupItems: Int {
        categories.reduce(0) { $0 + $1.count }
    }
    
    // MARK: - Initialization
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadPersistedProgress()
        preferenceLearningService.initialize(modelContext: modelContext)
        Task {
            await loadCleanupSuggestions()
        }
    }
    
    // MARK: - Progress Persistence
    
    private func loadPersistedProgress() {
        if let selectedData = UserDefaults.standard.array(forKey: selectedPhotosKey) as? [String] {
            selectedPhotos = Set(selectedData)
        }
        if let reviewedData = UserDefaults.standard.array(forKey: reviewedPhotosKey) as? [String] {
            reviewedPhotos = Set(reviewedData)
        }
        if let reviewedGroupsData = UserDefaults.standard.array(forKey: reviewedGroupsKey) as? [String] {
            reviewedGroups = Set(reviewedGroupsData)
        }
        if let keptData = UserDefaults.standard.array(forKey: keptPhotosKey) as? [String] {
            keptPhotos = Set(keptData)
        }
        
        // Migration: Convert legacy persisted kept photos to proper keepDecision
        // This ensures past user decisions are not lost
        migrateLegacyKeptPhotosIfNeeded()
    }
    
    private let migrationCompletedKey = "com.moments.cleanup.migrationCompleted.v1"
    
    private func migrateLegacyKeptPhotosIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else { return }
        guard let context = modelContext else { return }
        
        // Get all photo IDs that were previously kept or reviewed (not deleted)
        let legacyKeptIds = keptPhotos.union(reviewedPhotos.subtracting(selectedPhotos))
        guard !legacyKeptIds.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            return
        }
        
        // Fetch photos and set keepDecision .forever for legacy kept photos
        let descriptor = FetchDescriptor<PersistedPhoto>()
        guard let photos = try? context.fetch(descriptor) else { return }
        
        var migratedCount = 0
        for photo in photos {
            if legacyKeptIds.contains(photo.id) && photo.keepDecision == .none {
                photo.keepDecision = .forever
                photo.keepDecisionDate = Date()
                migratedCount += 1
            }
        }
        
        if migratedCount > 0 {
            try? context.save()
            print("[CleanupViewModel] Migrated \(migratedCount) legacy kept photos to keepDecision .forever")
        }
        
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
    }
    
    func persistProgress() {
        UserDefaults.standard.set(Array(selectedPhotos), forKey: selectedPhotosKey)
        UserDefaults.standard.set(Array(reviewedPhotos), forKey: reviewedPhotosKey)
        UserDefaults.standard.set(Array(reviewedGroups), forKey: reviewedGroupsKey)
        UserDefaults.standard.set(Array(keptPhotos), forKey: keptPhotosKey)
    }
    
    func clearPersistedProgress() {
        UserDefaults.standard.removeObject(forKey: selectedPhotosKey)
        UserDefaults.standard.removeObject(forKey: reviewedPhotosKey)
        UserDefaults.standard.removeObject(forKey: reviewedGroupsKey)
        UserDefaults.standard.removeObject(forKey: keptPhotosKey)
        selectedPhotos.removeAll()
        reviewedPhotos.removeAll()
        reviewedGroups.removeAll()
        keptPhotos.removeAll()
    }
    
    // MARK: - Review Actions
    
    func markAsReviewed(_ photoId: String, delete: Bool) {
        reviewedPhotos.insert(photoId)
        if delete {
            selectedPhotos.insert(photoId)
            keptPhotos.remove(photoId)
            
            // Ensure keep decision is cleared when marking for deletion
            if let photo = allPhotos.first(where: { $0.id == photoId }) {
                photo.keepDecision = .none
                photo.keepUntil = nil
                photo.keepDecisionDate = nil
                try? modelContext?.save()
                
                // Log decision for preference learning
                Task {
                    await preferenceLearningService.logDecision(for: photo, decision: .delete)
                }
            }
        } else {
            // CRITICAL FIX: For keep actions, use keepPhoto to persist the decision
            // This was the bug: swipe-right called markAsReviewed but never persisted keepDecision
            keepPhoto(photoId, duration: .forever)
        }
        persistProgress()
    }
    
    func hasReviewProgress(for photos: [PersistedPhoto]) -> Bool {
        let photoIds = Set(photos.map { $0.id })
        return !reviewedPhotos.intersection(photoIds).isEmpty
    }
    
    func unreviewedPhotos(from photos: [PersistedPhoto]) -> [PersistedPhoto] {
        photos.filter { !reviewedPhotos.contains($0.id) }
    }
    
    func reviewedCount(from photos: [PersistedPhoto]) -> Int {
        let photoIds = Set(photos.map { $0.id })
        return reviewedPhotos.intersection(photoIds).count
    }
    
    func photosMarkedForDeletion(from photos: [PersistedPhoto]) -> [PersistedPhoto] {
        photos.filter { selectedPhotos.contains($0.id) }
    }
    
    func deletionSizeForReview(from photos: [PersistedPhoto]) -> Int64 {
        photosMarkedForDeletion(from: photos).reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    // MARK: - Loading
    
    func loadCleanupSuggestions() async {
        guard let context = modelContext else { return }
        
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.analysisCompleted }
            )
            
            var fetchedPhotos = try context.fetch(descriptor)
            fetchedPhotos.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            allPhotos = fetchedPhotos
            
            // Load similar groups
            let groupDescriptor = FetchDescriptor<SimilarGroup>(
                predicate: #Predicate { $0.feedbackRaw != "notSimilar" }
            )
            similarGroups = try context.fetch(groupDescriptor)
            
            await MainActor.run {
                self.buildCategories()
                self.buildReviewQueue()
                self.calculateEstimatedSpace()
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Error al cargar fotos: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Review Queue Building
    
    private func buildReviewQueue() {
        var queue: [ReviewItem] = []
        var photosInGroups: Set<String> = []
        
        // Get cleanable photos (not protected, not kept by user)
        let cleanablePhotos = allPhotos.filter { 
            !$0.isProtected && 
            !$0.isKeptByUser && 
            $0.cleanupCategory != .none 
        }
        let cleanablePhotoIds = Set(cleanablePhotos.map { $0.id })
        let photosById = Dictionary(uniqueKeysWithValues: cleanablePhotos.map { ($0.id, $0) })
        
        // First, add groups where at least one photo is cleanable
        for group in similarGroups {
            let groupPhotoIds = group.photoIds
            let cleanableInGroup = groupPhotoIds.filter { cleanablePhotoIds.contains($0) }
            
            guard cleanableInGroup.count > 1 else { continue }
            
            let photos = cleanableInGroup.compactMap { photosById[$0] }
            guard photos.count > 1 else { continue }
            
            // Mark all photos in group as belonging to a group
            for photoId in cleanableInGroup {
                photosInGroups.insert(photoId)
            }
            
            if group.isExactDuplicate {
                queue.append(.exactDuplicateGroup(group, photos))
            } else {
                queue.append(.similarGroup(group, photos))
            }
        }
        
        // Then add singles that are not in any group
        for photo in cleanablePhotos {
            if !photosInGroups.contains(photo.id) {
                queue.append(.single(photo))
            }
        }
        
        let capped = DailyReviewBatch.cap(queue)
        remainingAfterBatch = capped.remaining
        reviewQueue = capped.batch
    }
    
    func startNextDailyBatch() {
        Task {
            await loadCleanupSuggestions()
        }
    }
    
    // MARK: - Group Review Actions
    
    func markGroupAsReviewed(_ groupId: String, keepPhotoIds: Set<String>, deletePhotoIds: Set<String>) {
        reviewedGroups.insert(groupId)
        
        for photoId in keepPhotoIds {
            keepPhoto(photoId, duration: .forever)
        }
        
        for photoId in deletePhotoIds {
            reviewedPhotos.insert(photoId)
            selectedPhotos.insert(photoId)
            keptPhotos.remove(photoId)
            
            // Log delete decision for preference learning
            if let photo = allPhotos.first(where: { $0.id == photoId }) {
                Task {
                    await preferenceLearningService.logDecision(for: photo, decision: .delete)
                }
            }
        }
        
        persistProgress()
    }
    
    func isReviewItemReviewed(_ item: ReviewItem) -> Bool {
        switch item {
        case .single(let photo):
            return reviewedPhotos.contains(photo.id)
        case .exactDuplicateGroup(let group, _), .similarGroup(let group, _):
            return reviewedGroups.contains(group.id)
        }
    }
    
    func unreviewedItems() -> [ReviewItem] {
        reviewQueue.filter { !isReviewItemReviewed($0) }
    }
    
    func reviewedItemCount() -> Int {
        reviewQueue.count - unreviewedItems().count
    }
    
    // MARK: - Keep Decision Actions
    
    enum KeepDuration {
        case forever
        case oneWeek
        case oneMonth
        case threeMonths
        
        var keepUntilDate: Date? {
            switch self {
            case .forever: return nil
            case .oneWeek: return Calendar.current.date(byAdding: .day, value: 7, to: Date())
            case .oneMonth: return Calendar.current.date(byAdding: .month, value: 1, to: Date())
            case .threeMonths: return Calendar.current.date(byAdding: .month, value: 3, to: Date())
            }
        }
        
        var decision: KeepDecision {
            switch self {
            case .forever: return .forever
            case .oneWeek, .oneMonth, .threeMonths: return .snoozed
            }
        }
    }
    
    func keepPhoto(_ photoId: String, duration: KeepDuration) {
        var photo = allPhotos.first(where: { $0.id == photoId })
        if photo == nil, let context = modelContext {
            photo = (try? context.fetch(FetchDescriptor<PersistedPhoto>()))?.first { $0.id == photoId }
        }
        guard let photo else { return }
        
        photo.keepDecision = duration.decision
        photo.keepUntil = duration.keepUntilDate
        photo.keepDecisionDate = Date()
        
        // Also mark as reviewed and kept
        reviewedPhotos.insert(photoId)
        keptPhotos.insert(photoId)
        selectedPhotos.remove(photoId)
        
        try? modelContext?.save()
        persistProgress()
        
        // Log decision for preference learning
        Task {
            let decisionType: ReviewDecisionType = duration == .forever ? .keepForever : .keepSnoozed
            await preferenceLearningService.logDecision(for: photo, decision: decisionType)
        }
    }
    
    func keepPhotos(_ photoIds: [String], duration: KeepDuration, groupId: String? = nil) {
        let decisionType: ReviewDecisionType = duration == .forever ? .keepForever : .keepSnoozed
        
        for photoId in photoIds {
            guard let photo = allPhotos.first(where: { $0.id == photoId }) else { continue }
            
            photo.keepDecision = duration.decision
            photo.keepUntil = duration.keepUntilDate
            photo.keepDecisionDate = Date()
            photo.keepDecisionGroupId = groupId
            
            reviewedPhotos.insert(photoId)
            keptPhotos.insert(photoId)
            selectedPhotos.remove(photoId)
            
            // Log decision for preference learning
            Task {
                await preferenceLearningService.logDecision(for: photo, decision: decisionType)
            }
        }
        
        if let groupId = groupId {
            reviewedGroups.insert(groupId)
        }
        
        try? modelContext?.save()
        persistProgress()
    }
    
    func undoKeepDecision(_ photoId: String) {
        guard let photo = allPhotos.first(where: { $0.id == photoId }) else { return }
        
        photo.keepDecision = .none
        photo.keepUntil = nil
        photo.keepDecisionDate = nil
        photo.keepDecisionGroupId = nil
        
        // Remove from kept tracking
        keptPhotos.remove(photoId)
        reviewedPhotos.remove(photoId)
        
        try? modelContext?.save()
        persistProgress()
        
        // Rebuild categories and queue to include the photo again
        Task {
            await loadCleanupSuggestions()
        }
    }
    
    func getKeptPhotos() -> [PersistedPhoto] {
        allPhotos.filter { $0.keepDecision != .none }
    }
    
    private func buildCategories() {
        var items: [CleanupCategoryItem] = []
        
        // IMPORTANT: Filter out protected photos AND user-kept photos from cleanup suggestions
        // isKeptByUser handles forever keeps and active snoozes
        let cleanablePhotos = allPhotos.filter { !$0.isProtected && !$0.isKeptByUser }
        
        // Group photos by cleanup category
        let categoryGroups = Dictionary(grouping: cleanablePhotos) { $0.cleanupCategory }
        
        // Create category items for each non-empty category
        for categoryType in CleanupCategoryType.allCases {
            guard categoryType != .none else { continue }
            
            var photosForCategory: [PersistedPhoto]
            var defaultConfidence: CleanupConfidenceTier = .maybe
            
            // For some categories, use the stored cleanupCategory
            // For others, calculate on the fly for backwards compatibility
            switch categoryType {
            case .screenshot:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .screenshot || $0.mediaSubtypesRaw.contains("screenshot") 
                }
                defaultConfidence = .veryLikely // Screenshots are very likely junk
            case .screenRecording:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .screenRecording || 
                    ($0.mediaTypeRaw == "video" && $0.mediaSubtypesRaw.contains("screenRecording"))
                }
                defaultConfidence = .maybe // Screen recordings might be important
            case .blurry:
                // STRICT blur detection - requires BOTH Laplacian AND Vision aesthetics to agree
                // This eliminates false positives like sharp storefronts
                photosForCategory = cleanablePhotos.filter { photo in
                    // First check if already categorized as blurry by analysis
                    if photo.cleanupCategory == .blurry { return true }
                    
                    // Otherwise, re-evaluate with strict criteria
                    guard photo.mediaTypeRaw == "image" else { return false }
                    
                    let laplacian = photo.sharpnessScore ?? 1.0
                    let aesthetics = photo.visionAestheticsScore
                    let isUtility = photo.visionIsUtility
                    
                    if laplacian < 0.10 {
                        if let aScore = aesthetics, let utility = isUtility {
                            // Vision available - require agreement
                            return aScore < 0.3 || utility == true
                        } else {
                            // No Vision - use very strict threshold
                            return laplacian < 0.08
                        }
                    }
                    return false
                }
                // Set confidence tiers
                photosForCategory.forEach { photo in
                    let laplacian = photo.sharpnessScore ?? 1.0
                    let aesthetics = photo.visionAestheticsScore ?? 0.5
                    
                    // Very blurry with Vision confirmation = very likely
                    if laplacian < 0.06 && aesthetics < 0.2 {
                        photo.cleanupConfidenceTier = .veryLikely
                    } else {
                        photo.cleanupConfidenceTier = .maybe
                    }
                }
            case .overexposed:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .overexposed || 
                    ($0.mediaTypeRaw == "image" && ($0.exposureScore ?? 0.5) > 0.85)
                }
                defaultConfidence = .maybe
            case .underexposed:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .underexposed || 
                    ($0.mediaTypeRaw == "image" && ($0.exposureScore ?? 0.5) < 0.15)
                }
                // Very dark (<0.05) is very likely pocket shot
                photosForCategory.forEach { photo in
                    if (photo.exposureScore ?? 0.5) < 0.05 {
                        photo.cleanupConfidenceTier = .veryLikely
                    } else {
                        photo.cleanupConfidenceTier = .maybe
                    }
                }
            case .burst:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .burst || 
                    ($0.burstIdentifier != nil && !$0.representsBurst)
                }
                defaultConfidence = .veryLikely // Non-representative burst photos are safe to delete
            case .nearDuplicate:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .nearDuplicate && $0.isBestInGroup != true
                }
                defaultConfidence = .veryLikely // We've already picked the best
            case .duplicate:
                photosForCategory = categoryGroups[.duplicate] ?? []
                defaultConfidence = .veryLikely // Exact duplicates
            case .accidental:
                photosForCategory = cleanablePhotos.filter { photo in
                    if photo.cleanupCategory == .accidental { return true }
                    guard photo.mediaTypeRaw == "image" else { return false }
                    
                    // Very dark with no faces
                    if let exposure = photo.exposureScore, exposure < 0.05 {
                        if let faces = photo.facesDetected, faces == 0 {
                            return true
                        }
                    }
                    
                    // Very blurry without faces
                    if let sharpness = photo.sharpnessScore, sharpness < 0.1 {
                        if let faces = photo.facesDetected, faces == 0 {
                            return true
                        }
                    }
                    
                    return false
                }
                defaultConfidence = .veryLikely // Pocket shots are safe
            case .document:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .document || ($0.isDocument == true && $0.cleanupCategory != .receipt)
                }
                defaultConfidence = .maybe // Documents might be important
            case .receipt:
                photosForCategory = categoryGroups[.receipt] ?? []
                defaultConfidence = .maybe // Receipts might be needed
            case .qrCode:
                photosForCategory = categoryGroups[.qrCode] ?? []
                defaultConfidence = .veryLikely // QR codes are usually temporary
            case .largeVideo:
                photosForCategory = cleanablePhotos.filter { 
                    $0.cleanupCategory == .largeVideo || 
                    ($0.mediaTypeRaw == "video" && ($0.estimatedFileSize ?? 0) > 100_000_000)
                }.sorted { ($0.estimatedFileSize ?? 0) > ($1.estimatedFileSize ?? 0) }
                defaultConfidence = .maybe // Large videos might be precious
            case .downloadedMeme:
                photosForCategory = cleanablePhotos.filter { $0.cleanupCategory == .downloadedMeme }
                defaultConfidence = .veryLikely // Downloaded memes
            case .forwardedImage:
                photosForCategory = cleanablePhotos.filter { $0.cleanupCategory == .forwardedImage }
                defaultConfidence = .veryLikely // Forwarded images
            case .none:
                continue
            }
            
            // Set default confidence for photos that don't have one yet
            for photo in photosForCategory where photo.cleanupConfidenceTier == nil {
                photo.cleanupConfidenceTier = defaultConfidence
            }
            
            // Deduplicate and sort by deletion likelihood score (highest first)
            let uniquePhotos = Array(Set(photosForCategory.map { $0.id }))
                .compactMap { id in photosForCategory.first { $0.id == id } }
                .sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
            
            if !uniquePhotos.isEmpty {
                items.append(CleanupCategoryItem(
                    id: categoryType.rawValue,
                    category: categoryType,
                    count: uniquePhotos.count,
                    photos: uniquePhotos,
                    estimatedSize: uniquePhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) },
                    confidenceTier: defaultConfidence
                ))
            }
        }
        
        // Split categories into "Muy probable" and "Quizás" tiers
        veryLikelyCategories = items.filter { item in
            item.veryLikelyPhotos.count > 0
        }.map { item in
            let sortedPhotos = item.veryLikelyPhotos.sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
            return CleanupCategoryItem(
                id: "\(item.id)_veryLikely",
                category: item.category,
                count: sortedPhotos.count,
                photos: sortedPhotos,
                estimatedSize: sortedPhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) },
                confidenceTier: .veryLikely
            )
        }.filter { $0.count > 0 }
        
        maybeCategories = items.filter { item in
            item.maybePhotos.count > 0
        }.map { item in
            let sortedPhotos = item.maybePhotos.sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
            return CleanupCategoryItem(
                id: "\(item.id)_maybe",
                category: item.category,
                count: sortedPhotos.count,
                photos: sortedPhotos,
                estimatedSize: sortedPhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) },
                confidenceTier: .maybe
            )
        }.filter { $0.count > 0 }
        
        // Sort categories by average deletion score (highest first), then by space
        categories = items.sorted { item1, item2 in
            let avgScore1 = item1.photos.isEmpty ? 0 : item1.photos.reduce(0) { $0 + $1.deletionLikelihoodScore } / Double(item1.photos.count)
            let avgScore2 = item2.photos.isEmpty ? 0 : item2.photos.reduce(0) { $0 + $1.deletionLikelihoodScore } / Double(item2.photos.count)
            
            // Combine score and space: 60% score, 40% space (normalized)
            let maxSize = max(item1.estimatedSize, item2.estimatedSize, 1)
            let sortScore1 = avgScore1 * 0.6 + (Double(item1.estimatedSize) / Double(maxSize)) * 0.4
            let sortScore2 = avgScore2 * 0.6 + (Double(item2.estimatedSize) / Double(maxSize)) * 0.4
            
            return sortScore1 > sortScore2
        }
    }
    
    private func calculateEstimatedSpace() {
        // Sum sizes but avoid double-counting photos in multiple categories
        var countedPhotoIds: Set<String> = []
        var totalSize: Int64 = 0
        
        for category in categories {
            for photo in category.photos {
                if !countedPhotoIds.contains(photo.id) {
                    countedPhotoIds.insert(photo.id)
                    totalSize += photo.estimatedFileSize ?? 0
                }
            }
        }
        
        estimatedSpaceFreed = totalSize
    }
    
    // MARK: - Selection
    
    func selectAll(in category: CleanupCategoryItem) {
        for photo in category.photos {
            // Don't auto-select the "best" photo in duplicate groups
            if photo.isBestInGroup != true {
                selectedPhotos.insert(photo.id)
            }
        }
    }
    
    func deselectAll(in category: CleanupCategoryItem) {
        for photo in category.photos {
            selectedPhotos.remove(photo.id)
        }
    }
    
    func toggleSelection(for photo: PersistedPhoto) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }
    
    func isSelected(_ photo: PersistedPhoto) -> Bool {
        selectedPhotos.contains(photo.id)
    }
    
    var selectedCount: Int {
        selectedPhotos.count
    }
    
    var selectedSize: Int64 {
        allPhotos
            .filter { selectedPhotos.contains($0.id) }
            .reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    // MARK: - Deletion
    
    func deleteSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        guard let context = modelContext else { return }
        
        isDeleting = true
        
        let photosToDelete = allPhotos.filter { selectedPhotos.contains($0.id) }
        let identifiers = photosToDelete.map { $0.localIdentifier }
        let sizeFreed = selectedSize
        
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            
            // Remove from SwiftData
            for photo in photosToDelete {
                context.delete(photo)
            }
            try context.save()
            
            // Update state
            selectedPhotos.removeAll()
            spaceFreed = sizeFreed
            lastDeletedSize = sizeFreed
            await loadCleanupSuggestions()
            
        } catch {
            errorMessage = "Error al eliminar: \(error.localizedDescription)"
        }
        
        isDeleting = false
    }
}

// MARK: - Formatted Size

extension CleanupViewModel {
    func formattedSize(_ bytes: Int64) -> String {
        SpaceFormatting.string(from: bytes)
    }
}
