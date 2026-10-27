// FixturePhotoSeeder.swift
// Seeds a deterministic review library when launched with -seedFixturePhotos.
// Used by UI tests so Review/Home have real categorized items without waiting for Vision.

import Foundation
import SwiftData

enum FixturePhotoSeeder {
    static let launchArgument = "-seedFixturePhotos"
    static let seededFlagKey = "com.moments.fixturesSeeded.v1"
    
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
    
    struct SeedSummary: Equatable {
        var photos: Int
        var exactGroups: Int
        var similarGroups: Int
        var videos: Int
        var screenshots: Int
        var blurry: Int
    }
    
    @discardableResult
    @MainActor
    static func seedIfNeeded(into context: ModelContext, force: Bool = false) throws -> SeedSummary {
        if !force {
            let existing = try context.fetch(FetchDescriptor<PersistedPhoto>()).filter {
                $0.localIdentifier.hasPrefix("fixture-")
            }
            if !existing.isEmpty {
                return summarize(existing, groups: (try? context.fetch(FetchDescriptor<SimilarGroup>())) ?? [])
            }
        }
        
        let now = Date()
        var photos: [PersistedPhoto] = []
        
        func makePhoto(
            identifier: String,
            category: CleanupCategoryType,
            score: Double,
            size: Int64,
            date: Date = now,
            mediaType: String = "image",
            extra: ((PersistedPhoto) -> Void)? = nil
        ) -> PersistedPhoto {
            let photo = PersistedPhoto(localIdentifier: identifier, creationDate: date)
            photo.analysisCompleted = true
            photo.lastAnalyzedAt = now
            photo.cleanupCategory = category
            photo.deletionLikelihoodScore = score
            photo.estimatedFileSize = size
            photo.pixelWidth = 1200
            photo.pixelHeight = 900
            photo.mediaTypeRaw = mediaType
            extra?(photo)
            context.insert(photo)
            photos.append(photo)
            return photo
        }
        
        // Screenshots
        for index in 1...5 {
            makePhoto(
                identifier: "fixture-screenshot-\(index)",
                category: .screenshot,
                score: 0.72 + Double(index) * 0.01,
                size: 1_200_000 + Int64(index) * 10_000,
                extra: { photo in
                    photo.mediaSubtypesRaw = "screenshot"
                    photo.origin = .screenshot
                }
            )
        }
        
        // Exact duplicates (3 pairs). Best copy stays .none so groups must be built from the group, not category.
        for index in 1...3 {
            let best = makePhoto(
                identifier: "fixture-dup-\(index)-best",
                category: .duplicate,
                score: 0.20,
                size: 3_400_000,
                extra: { photo in
                    photo.isBestInGroup = true
                    photo.duplicateGroupId = "fixture-dup-\(index)"
                    photo.sharpnessScore = 0.92
                }
            )
            let copy = makePhoto(
                identifier: "fixture-dup-\(index)-copy",
                category: .duplicate,
                score: 0.88,
                size: 3_400_000,
                extra: { photo in
                    photo.isBestInGroup = false
                    photo.duplicateGroupId = "fixture-dup-\(index)"
                    photo.sharpnessScore = 0.88
                }
            )
            let group = SimilarGroup(
                id: "fixture-dup-group-\(index)",
                photoIds: [best.id, copy.id],
                bestPhotoId: best.id
            )
            group.isExactDuplicate = true
            group.averageSimilarity = 1.0
            context.insert(group)
        }
        
        // Similar (near-duplicate) group with a best photo that has no cleanup category
        let similarBest = makePhoto(
            identifier: "fixture-similar-best",
            category: .none,
            score: 0.18,
            size: 2_800_000,
            extra: { photo in
                photo.isBestInGroup = true
                photo.duplicateGroupId = "fixture-similar-1"
                photo.sharpnessScore = 0.9
                photo.visionAestheticsScore = 0.7
            }
        )
        let similarA = makePhoto(
            identifier: "fixture-similar-a",
            category: .nearDuplicate,
            score: 0.64,
            size: 2_600_000,
            extra: { photo in
                photo.duplicateGroupId = "fixture-similar-1"
                photo.sharpnessScore = 0.55
            }
        )
        let similarB = makePhoto(
            identifier: "fixture-similar-b",
            category: .nearDuplicate,
            score: 0.61,
            size: 2_500_000,
            extra: { photo in
                photo.duplicateGroupId = "fixture-similar-1"
                photo.sharpnessScore = 0.5
            }
        )
        let similarGroup = SimilarGroup(
            id: "fixture-similar-group-1",
            photoIds: [similarBest.id, similarA.id, similarB.id],
            bestPhotoId: similarBest.id
        )
        similarGroup.isExactDuplicate = false
        similarGroup.averageSimilarity = 0.86
        context.insert(similarGroup)
        
        // Blurry
        for index in 1...3 {
            makePhoto(
                identifier: "fixture-blurry-\(index)",
                category: .blurry,
                score: 0.81,
                size: 900_000,
                extra: { photo in
                    photo.sharpnessScore = 0.08
                    photo.visionAestheticsScore = 0.2
                }
            )
        }
        
        // Sharp night photo — NOT a cleanup candidate
        makePhoto(
            identifier: "fixture-night-sharp",
            category: .none,
            score: 0.05,
            size: 4_200_000,
            extra: { photo in
                photo.sharpnessScore = 0.86
                photo.exposureScore = 0.22
                photo.visionAestheticsScore = 0.55
                photo.visionLabels = "night|sky|stars"
            }
        )
        
        // Short video
        makePhoto(
            identifier: "fixture-video-1",
            category: .largeVideo,
            score: 0.58,
            size: 28_000_000,
            mediaType: "video",
            extra: { photo in
                photo.duration = 12
            }
        )
        
        // Live Photo candidate
        makePhoto(
            identifier: "fixture-live-1",
            category: .accidental,
            score: 0.54,
            size: 5_100_000,
            extra: { photo in
                photo.isLivePhoto = true
                photo.mediaSubtypesRaw = "photoLive"
            }
        )
        
        // Normal photos so Home/Momentos have content
        for index in 1...8 {
            makePhoto(
                identifier: "fixture-normal-\(index)",
                category: .none,
                score: 0.04,
                size: 2_000_000 + Int64(index) * 50_000,
                date: now.addingTimeInterval(Double(-index) * 86_400),
                extra: { photo in
                    photo.sharpnessScore = 0.8
                    photo.visionLabels = index % 2 == 0 ? "person|outdoor" : "food|indoor"
                    photo.placeCity = index % 2 == 0 ? "Buenos Aires" : "Córdoba"
                }
            )
        }
        
        try context.save()
        UserDefaults.standard.set(true, forKey: seededFlagKey)
        return summarize(photos, groups: (try? context.fetch(FetchDescriptor<SimilarGroup>())) ?? [])
    }
    
    private static func summarize(_ photos: [PersistedPhoto], groups: [SimilarGroup]) -> SeedSummary {
        SeedSummary(
            photos: photos.count,
            exactGroups: groups.filter(\.isExactDuplicate).count,
            similarGroups: groups.filter { !$0.isExactDuplicate }.count,
            videos: photos.filter { $0.mediaTypeRaw == "video" }.count,
            screenshots: photos.filter { $0.cleanupCategory == .screenshot }.count,
            blurry: photos.filter { $0.cleanupCategory == .blurry }.count
        )
    }
}
