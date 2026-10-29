import XCTest
import SwiftData
@testable import Moments

@MainActor
final class ReviewSessionTests: XCTestCase {
    func testKeepPhotoFindsVideoOutsideAllPhotos() {
        let video = PersistedPhoto(localIdentifier: "session-video-keep")
        video.mediaTypeRaw = "video"
        video.cleanupCategory = .largeVideo
        video.deletionLikelihoodScore = 0.9
        video.estimatedFileSize = 12_000_000
        video.analysisCompleted = true
        
        let viewModel = CleanupViewModel()
        viewModel.reviewQueue = [.single(video)]
        
        viewModel.keepPhoto(video.id, duration: .forever)
        
        XCTAssertTrue(viewModel.reviewedPhotos.contains(video.id), "Conservar must mark the video reviewed even when it is not in allPhotos")
        XCTAssertTrue(viewModel.keptPhotos.contains(video.id))
        XCTAssertEqual(video.keepDecision, .forever)
        XCTAssertTrue(viewModel.unreviewedItems().isEmpty, "The card must advance off a kept video")
    }
    
    func testSessionDeleteIgnoresStaleSelectedPhotos() {
        let sessionVideo = PersistedPhoto(localIdentifier: "session-video-delete")
        sessionVideo.mediaTypeRaw = "video"
        sessionVideo.estimatedFileSize = 4_000_000
        sessionVideo.analysisCompleted = true
        
        let stalePhoto = PersistedPhoto(localIdentifier: "stale-selected-photo")
        stalePhoto.mediaTypeRaw = "image"
        stalePhoto.estimatedFileSize = 1_000_000
        stalePhoto.analysisCompleted = true
        
        let viewModel = CleanupViewModel()
        viewModel.reviewQueue = [.single(sessionVideo)]
        viewModel.selectedPhotos = [sessionVideo.id, stalePhoto.id]
        
        let session = viewModel.sessionPhotosMarkedForDeletion()
        XCTAssertEqual(session.map(\.id), [sessionVideo.id], "Summary must only count this session, not leftover selectedPhotos")
        XCTAssertEqual(MomentsPluralization.deleteMedia(photos: 0, videos: session.filter(\.isVideo).count), "Eliminar 1 video")
    }
    
    func testDeleteMediaCopyMatchesPhotoKitKinds() {
        XCTAssertEqual(MomentsPluralization.deleteMedia(photos: 18, videos: 0), "Eliminar 18 fotos")
        XCTAssertEqual(MomentsPluralization.deleteMedia(photos: 0, videos: 4), "Eliminar 4 videos")
        XCTAssertEqual(MomentsPluralization.deleteMedia(photos: 2, videos: 3), "Eliminar 2 fotos y 3 videos")
        XCTAssertEqual(MomentsPluralization.deleteMedia(photos: 0, videos: 0), "Nada para eliminar")
        XCTAssertEqual(MomentsPluralization.deleteMedia(photos: 1, videos: 1), "Eliminar 1 foto y 1 video")
    }
    
    func testRecentlyDeletedHowToHasNoAlbumPath() {
        XCTAssertEqual(SpaceFormatting.recentlyDeletedHowTo, "Se libera al vaciar Eliminados recientemente")
        XCTAssertFalse(SpaceFormatting.recentlyDeletedHowTo.contains("Fotos > Álbumes"))
        XCTAssertFalse(SpaceFormatting.recentlyDeletedHowTo.contains("Eliminar todo"))
        XCTAssertFalse(SpaceFormatting.recentlyDeletedRecovery.contains("Fotos > Álbumes"))
    }
    
    func testDailyBatchCapsManyMixedItems() {
        let items: [ReviewItem] = (0..<80).map { index in
            let photo = PersistedPhoto(localIdentifier: "batch-\(index)")
            photo.mediaTypeRaw = index % 4 == 0 ? "video" : "image"
            photo.deletionLikelihoodScore = Double(80 - index) / 80
            photo.cleanupCategory = index % 4 == 0 ? .largeVideo : .screenshot
            return .single(photo)
        }
        let capped = DailyReviewBatch.cap(items)
        XCTAssertEqual(capped.batch.count, DailyReviewBatch.size)
        XCTAssertEqual(capped.remaining, 60)
        XCTAssertTrue(capped.batch.contains { $0.photos.contains(where: \.isVideo) })
        XCTAssertTrue(capped.batch.contains { $0.photos.contains(where: { !$0.isVideo }) })
    }
    
    func testLargeVideoChipTitleFits() {
        XCTAssertEqual(HomeViewModel.largeVideosChipTitle, "Videos +100 MB")
        XCTAssertLessThan(HomeViewModel.largeVideosChipTitle.count, 18)
        XCTAssertFalse(HomeViewModel.largeVideosChipTitle.contains("grandes"))
    }
    
    func testAssistantWelcomeIsSynchronous() {
        let viewModel = AssistantViewModel()
        XCTAssertTrue(viewModel.messages.isEmpty)
        viewModel.presentWelcomeIfNeeded()
        viewModel.suggestions = AssistantViewModel.defaultSuggestionCopy
        
        XCTAssertTrue(
            viewModel.messages.contains { $0.text == AssistantViewModel.welcomeText },
            "Asistente must show a greeting before async cards load"
        )
        XCTAssertFalse(viewModel.suggestions.isEmpty)
        XCTAssertTrue(
            viewModel.messages.contains { if case .catalogQuestion = $0.card { return true }; return false },
            "Asistente must show a people/places cataloguing prompt"
        )
        XCTAssertFalse(AssistantViewModel.defaultSuggestionCopy.contains { $0.contains("más de 3 meses") })
        XCTAssertTrue(AssistantViewModel.defaultSuggestionCopy.contains("Borrá capturas"))
    }
    
    func testTimelineLeavesLoadingWithoutEndlessSpinner() async {
        let viewModel = TimelineViewModel()
        XCTAssertTrue(viewModel.isLoading)
        await viewModel.loadTimeline()
        XCTAssertFalse(viewModel.isLoading, "Missing context must show empty, never spin forever")
        XCTAssertTrue(viewModel.sections.isEmpty)
    }
    
    func testKeepDurationChipLabelsFit() {
        XCTAssertEqual(CleanupViewModel.KeepDuration.forever.testId, "forever")
        XCTAssertEqual(CleanupViewModel.KeepDuration.oneWeek.testId, "week")
        XCTAssertEqual(CleanupViewModel.KeepDuration.oneMonth.testId, "month")
        XCTAssertEqual(CleanupViewModel.KeepDuration.threeMonths.testId, "threeMonths")
    }
}
