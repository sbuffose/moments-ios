// ScanPipeline.swift
// Detached, low-priority photo scan: Vision/feature-print off MainActor,
// batched SwiftData writes on a background ModelContext, resumable checkpoints.

import Foundation
import Photos
import SwiftData
import UIKit
import Vision

// MARK: - Checkpoint (thread-safe, process-kill durable)

enum ScanCheckpointKeys {
    static let lastIndexedId = "com.moments.checkpoint.lastIndexedId"
    static let lastAnalyzedId = "com.moments.checkpoint.lastAnalyzedId"
    static let indexedIds = "com.moments.checkpoint.indexedIds"
    static let analyzedIds = "com.moments.checkpoint.analyzedIds"
    static let totalPhotos = "com.moments.checkpoint.totalPhotos"
    static let scanInProgress = "com.moments.checkpoint.scanInProgress"
}

struct ScanProgressSnapshot: Sendable, Equatable {
    var indexed: Int
    var analyzed: Int
    var total: Int
    var phase: Phase
    
    enum Phase: String, Sendable {
        case indexing
        case analyzing
        case done
    }
    
    var indexProgress: Double {
        Double(indexed) / Double(max(total, 1))
    }
    
    var analysisProgress: Double {
        Double(analyzed) / Double(max(max(indexed, total), 1))
    }
    
    var overallProgress: Double {
        switch phase {
        case .indexing: return indexProgress * 0.45
        case .analyzing: return 0.45 + analysisProgress * 0.55
        case .done: return 1
        }
    }
}

final class ScanCheckpointStore: @unchecked Sendable {
    static let shared = ScanCheckpointStore(defaults: .standard)
    
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var indexedCache: Set<String>?
    private var analyzedCache: Set<String>?
    private var pendingIndexed: Set<String> = []
    private var pendingAnalyzed: Set<String> = []
    private var lastPersist = Date.distantPast
    private let batchThreshold = 50
    private let persistInterval: TimeInterval = 5
    
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    convenience init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        self.init(defaults: defaults)
    }
    
    var isInProgress: Bool {
        lock.lock(); defer { lock.unlock() }
        return defaults.bool(forKey: ScanCheckpointKeys.scanInProgress)
    }
    
    var processedCount: Int {
        lock.lock(); defer { lock.unlock() }
        loadCachesLocked()
        return analyzedCache?.count ?? 0
    }
    
    var indexedCount: Int {
        lock.lock(); defer { lock.unlock() }
        loadCachesLocked()
        return indexedCache?.count ?? 0
    }
    
    var isComplete: Bool {
        let snap = snapshot()
        return snap.total > 0 && snap.analyzed >= max(snap.indexed, snap.total) && snap.phase == .done
    }
    
    func start(totalPhotos: Int) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(true, forKey: ScanCheckpointKeys.scanInProgress)
        defaults.set(totalPhotos, forKey: ScanCheckpointKeys.totalPhotos)
    }
    
    func markIndexed(_ assetId: String) {
        lock.lock(); defer { lock.unlock() }
        loadCachesLocked()
        indexedCache?.insert(assetId)
        pendingIndexed.insert(assetId)
        persistIfNeededLocked()
    }
    
    func markAnalyzed(_ photoId: String) {
        lock.lock(); defer { lock.unlock() }
        loadCachesLocked()
        analyzedCache?.insert(photoId)
        pendingAnalyzed.insert(photoId)
        persistIfNeededLocked()
    }
    
    func markProcessed(_ id: String) {
        markIndexed(id)
        markAnalyzed(id)
    }
    
    func isIndexed(_ assetId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        loadCachesLocked()
        return indexedCache?.contains(assetId) ?? false
    }
    
    func isAnalyzed(_ photoId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        loadCachesLocked()
        return analyzedCache?.contains(photoId) ?? false
    }
    
    func isProcessed(_ id: String) -> Bool {
        isAnalyzed(id)
    }
    
    func snapshot() -> ScanProgressSnapshot {
        lock.lock(); defer { lock.unlock() }
        loadCachesLocked()
        let indexed = indexedCache?.count ?? 0
        let analyzed = analyzedCache?.count ?? 0
        let total = defaults.integer(forKey: ScanCheckpointKeys.totalPhotos)
        let inProgress = defaults.bool(forKey: ScanCheckpointKeys.scanInProgress)
        let phase: ScanProgressSnapshot.Phase
        if !inProgress && total > 0 && analyzed >= max(indexed, total) {
            phase = .done
        } else if indexed < max(total, 1) {
            phase = .indexing
        } else {
            phase = .analyzing
        }
        return ScanProgressSnapshot(indexed: indexed, analyzed: analyzed, total: total, phase: phase)
    }
    
    func persist() {
        lock.lock(); defer { lock.unlock() }
        persistLocked()
        defaults.synchronize()
    }
    
    func complete() {
        lock.lock(); defer { lock.unlock() }
        persistLocked()
        defaults.set(false, forKey: ScanCheckpointKeys.scanInProgress)
        defaults.synchronize()
    }
    
    func clear() {
        lock.lock(); defer { lock.unlock() }
        indexedCache = nil
        analyzedCache = nil
        pendingIndexed.removeAll()
        pendingAnalyzed.removeAll()
        defaults.removeObject(forKey: ScanCheckpointKeys.lastIndexedId)
        defaults.removeObject(forKey: ScanCheckpointKeys.lastAnalyzedId)
        defaults.removeObject(forKey: ScanCheckpointKeys.indexedIds)
        defaults.removeObject(forKey: ScanCheckpointKeys.analyzedIds)
        defaults.removeObject(forKey: ScanCheckpointKeys.totalPhotos)
        defaults.removeObject(forKey: ScanCheckpointKeys.scanInProgress)
    }
    
    private func loadCachesLocked() {
        if indexedCache == nil {
            indexedCache = Set(defaults.stringArray(forKey: ScanCheckpointKeys.indexedIds) ?? [])
        }
        if analyzedCache == nil {
            analyzedCache = Set(defaults.stringArray(forKey: ScanCheckpointKeys.analyzedIds) ?? [])
        }
    }
    
    private func persistIfNeededLocked() {
        let batch = pendingIndexed.count + pendingAnalyzed.count
        let elapsed = Date().timeIntervalSince(lastPersist)
        if batch >= batchThreshold || elapsed >= persistInterval {
            persistLocked()
        }
    }
    
    private func persistLocked() {
        if let indexed = indexedCache {
            defaults.set(Array(indexed), forKey: ScanCheckpointKeys.indexedIds)
            if let last = pendingIndexed.first {
                defaults.set(last, forKey: ScanCheckpointKeys.lastIndexedId)
            }
        }
        if let analyzed = analyzedCache {
            defaults.set(Array(analyzed), forKey: ScanCheckpointKeys.analyzedIds)
            if let last = pendingAnalyzed.first {
                defaults.set(last, forKey: ScanCheckpointKeys.lastAnalyzedId)
            }
        }
        pendingIndexed.removeAll()
        pendingAnalyzed.removeAll()
        lastPersist = Date()
    }
}

// MARK: - Continued processing request (testable without BGTaskScheduler)

struct ContinuedProcessingRequest: Sendable, Equatable {
    static let identifierPrefix = "com.sbuffose.moments.continued."
    static let identifierWildcard = "com.sbuffose.moments.continued.*"
    static let progressTitle = "Analizando tus fotos"
    
    let identifier: String
    let title: String
    let subtitle: String
    let remainingPhotos: Int
    let submittedFromUserAction: Bool
    
    var matchesPermittedWildcard: Bool {
        identifier.hasPrefix(Self.identifierPrefix)
            && identifier != Self.identifierPrefix
            && identifier != Self.identifierWildcard
            && !identifier.hasSuffix(".*")
    }
    
    static func make(remainingPhotos: Int, fromUserAction: Bool) -> ContinuedProcessingRequest {
        ContinuedProcessingRequest(
            identifier: identifierPrefix + UUID().uuidString,
            title: progressTitle,
            subtitle: "Faltan \(remainingPhotos)",
            remainingPhotos: remainingPhotos,
            submittedFromUserAction: fromUserAction
        )
    }
}

enum ContinuedProcessingSubmissionRecorder {
    private static let lock = NSLock()
    private static var last: ContinuedProcessingRequest?
    
    static var lastUserInitiatedSubmission: ContinuedProcessingRequest? {
        lock.lock(); defer { lock.unlock() }
        return last
    }
    
    static func record(_ request: ContinuedProcessingRequest) {
        lock.lock(); defer { lock.unlock() }
        last = request
    }
    
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        last = nil
    }
}

enum ScanCompletionNotificationCopy {
    static let title = "Tus fotos están listas para limpiar y etiquetar"
    static let body = "Ya podés limpiar y etiquetar tus fotos."
}

/// First-run Empezar: iOS 26 requires the continued task to be submitted
/// from a user action while the app is in the foreground.
enum FirstRunScanStart {
    @discardableResult
    static func submitContinuedProcessingOnEmpezar(remainingPhotos: Int) -> ContinuedProcessingRequest {
        let request = ContinuedProcessingRequest.make(
            remainingPhotos: remainingPhotos,
            fromUserAction: true
        )
        ContinuedProcessingSubmissionRecorder.record(request)
        return request
    }
}

struct ScanWorkItem: Sendable, Equatable {
    let id: String
}

final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}

// MARK: - Pipeline actor (never MainActor)

actor ScanPipeline {
    /// Vision / CIContext live only on the library path. `processBatch` is
    /// synthetic so unit tests never construct those types.
    
    /// One synthetic item. Actor hops off MainActor; used by the unit test.
    @discardableResult
    func processNext(item: ScanWorkItem, store: ScanCheckpointStore) async -> Bool {
        if store.isProcessed(item.id) { return false }
        var hash: UInt64 = 14695981039346656037
        for byte in item.id.utf8 {
            hash = hash &* 1099511628211 ^ UInt64(byte)
        }
        for i in 0..<64 {
            hash ^= hash << 13
            hash ^= hash >> 7
            hash &+= UInt64(i)
        }
        _ = hash
        store.markProcessed(item.id)
        return true
    }
    
    func processBatch(
        _ items: [ScanWorkItem],
        store: ScanCheckpointStore,
        onItem: @escaping @Sendable (String) -> Void
    ) async {
        for item in items {
            if Task.isCancelled { break }
            if store.isProcessed(item.id) { continue }
            _ = await processNext(item: item, store: store)
            onItem(item.id)
        }
        store.persist()
    }
    
    func runLibrary(
        container: ModelContainer,
        store: ScanCheckpointStore,
        shouldStop: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (ScanProgressSnapshot) async -> Void
    ) async -> Bool {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        
        let indexed = await indexPendingAssets(
            context: context,
            store: store,
            shouldStop: shouldStop,
            onProgress: onProgress
        )
        if shouldStop() { store.persist(); return false }
        
        let analyzed = await analyzePendingPhotos(
            context: context,
            store: store,
            shouldStop: shouldStop,
            onProgress: onProgress
        )
        
        store.persist()
        if indexed && analyzed && !shouldStop() {
            store.complete()
            await onProgress(store.snapshot())
            return true
        }
        return false
    }
    
    private func indexPendingAssets(
        context: ModelContext,
        store: ScanCheckpointStore,
        shouldStop: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (ScanProgressSnapshot) async -> Void
    ) async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            await onProgress(store.snapshot())
            return true
        }
        
        let existingIds = Self.fetchExistingIds(context: context)
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        if assets.count == 0 {
            await onProgress(store.snapshot())
            return true
        }
        
        if store.snapshot().total == 0 {
            store.start(totalPhotos: assets.count)
        }
        
        var pending: [PHAsset] = []
        pending.reserveCapacity(min(assets.count, 512))
        assets.enumerateObjects { asset, _, stop in
            if shouldStop() {
                stop.pointee = true
                return
            }
            let id = asset.localIdentifier
            if existingIds.contains(id) || store.isIndexed(id) {
                store.markIndexed(id)
                return
            }
            pending.append(asset)
        }
        
        var inserted = 0
        for asset in pending {
            if shouldStop() || Task.isCancelled {
                try? context.save()
                store.persist()
                return false
            }
            let photo = PhotoLibraryService.persistedPhoto(from: asset)
            context.insert(photo)
            store.markIndexed(asset.localIdentifier)
            inserted += 1
            if inserted % 50 == 0 {
                try? context.save()
                store.persist()
                await onProgress(store.snapshot())
            }
        }
        
        try? context.save()
        store.persist()
        await onProgress(store.snapshot())
        return true
    }
    
    private func analyzePendingPhotos(
        context: ModelContext,
        store: ScanCheckpointStore,
        shouldStop: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (ScanProgressSnapshot) async -> Void
    ) async -> Bool {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { !$0.analysisCompleted }
        )
        let photos: [PersistedPhoto]
        do {
            photos = try context.fetch(descriptor)
        } catch {
            return false
        }
        
        if photos.isEmpty {
            await onProgress(store.snapshot())
            return true
        }
        
        var analyzed = 0
        for photo in photos {
            if shouldStop() || Task.isCancelled {
                try? context.save()
                store.persist()
                return false
            }
            if store.isAnalyzed(photo.id) {
                continue
            }
            await analyzeOne(photo, context: context)
            store.markAnalyzed(photo.id)
            analyzed += 1
            if analyzed % 10 == 0 {
                try? context.save()
                store.persist()
                await onProgress(store.snapshot())
            }
        }
        
        try? context.save()
        store.persist()
        await onProgress(store.snapshot())
        return true
    }
    
    private func analyzeOne(_ photo: PersistedPhoto, context: ModelContext) async {
        if MomentsTestRuntime.shouldSkipLiveScan {
            photo.analysisCompleted = true
            return
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
        guard let asset = result.firstObject else {
            photo.analysisCompleted = true
            return
        }
        
        photo.isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        if photo.isLivePhoto {
            let resources = PHAssetResource.assetResources(for: asset)
            photo.livePhotoVideoIdentifier = resources.first { $0.type == .pairedVideo }?.assetLocalIdentifier
        }
        let resources = PHAssetResource.assetResources(for: asset)
        photo.isEdited = resources.contains { $0.type == .adjustmentData }
        photo.isSharedOrReceived = asset.sourceType.contains(.typeCloudShared)
            || asset.sourceType.contains(.typeiTunesSynced)
        
        guard let image = await Self.loadThumbnail(for: asset) else {
            photo.isPendingICloud = true
            photo.analysisCompleted = false
            return
        }
        
        let analyzer = ImageAnalyzer()
        let quality = await analyzer.analyzeQuality(image: image)
        let text = await analyzer.analyzeText(image: image)
        let labels = await analyzer.classifyImage(image: image)
        let barcode = await analyzer.detectBarcodes(image: image)
        let featurePrint = await analyzer.generateFeaturePrint(image: image)
        let dHash: UInt64? = autoreleasepool { analyzer.generateDHash(image: image) }
        let faces = await FaceAnalyzer().detectFaces(in: image, photoId: photo.id)
        
        let metadata = await MetadataExtractionService.shared.extractMetadata(for: asset)
        let originResult = await MetadataExtractionService.shared.detectOrigin(for: asset, metadata: metadata)
        
        photo.sharpnessScore = quality.sharpness
        photo.exposureScore = quality.exposure
        photo.detailScore = quality.detail
        photo.deviceTilt = quality.tilt
        photo.visionAestheticsScore = quality.visionAestheticsScore
        photo.visionIsUtility = quality.visionIsUtility
        photo.hasText = text.hasText
        photo.isDocument = text.isDocument
        photo.ocrText = text.detectedText
        
        if !labels.isEmpty {
            let labelStrings = labels.map(\.label)
            let confidences = labels.map { String(format: "%.2f", $0.confidence) }
            photo.visionLabels = SpanishSynonyms.addSpanishSynonyms(to: labelStrings.joined(separator: "|"))
            photo.visionLabelsConfidence = confidences.joined(separator: "|")
        }
        
        photo.hasBarcode = barcode.hasBarcode
        if barcode.hasQR {
            photo.cleanupCategory = .qrCode
        }
        if let fp = featurePrint {
            photo.imageFeaturePrintData = fp
        }
        if let hash = dHash {
            photo.imageDHash = Int64(bitPattern: hash)
        }
        photo.facesDetected = faces.count
        if !faces.isEmpty {
            photo.facesOpenScore = faces.reduce(0.0) { $0 + $1.quality } / Double(faces.count)
        }
        
        photo.origin = originResult.origin
        photo.hasExifData = metadata?.hasExifData ?? false
        photo.cameraMake = metadata?.cameraMake
        photo.cameraModel = metadata?.cameraModel
        photo.lensMake = metadata?.lensMake
        photo.lensModel = metadata?.lensModel
        photo.software = metadata?.software
        photo.originalFilename = metadata?.originalFilename
        
        if let lat = photo.latitude, let lon = photo.longitude {
            if let cached = await GeocodingService.shared.cachedLocationName(latitude: lat, longitude: lon) {
                photo.placeName = cached.name
                photo.placeCity = cached.city
                photo.placeCountry = cached.country
            }
        }
        
        Self.applyCleanupCategory(photo: photo, text: text, quality: quality)
        
        photo.isPendingICloud = false
        photo.analysisCompleted = true
        photo.lastAnalyzedAt = Date()
        
        for face in faces {
            let detection = PersistedFaceDetection(
                photoId: photo.id,
                boundingBoxX: face.boundingBox.origin.x,
                boundingBoxY: face.boundingBox.origin.y,
                boundingBoxWidth: face.boundingBox.size.width,
                boundingBoxHeight: face.boundingBox.size.height,
                featurePrintData: face.featurePrint,
                quality: face.quality
            )
            detection.photo = photo
            context.insert(detection)
        }
    }
    
    private static func applyCleanupCategory(
        photo: PersistedPhoto,
        text: ImageAnalyzer.TextAnalysis,
        quality: ImageAnalyzer.QualityMetrics
    ) {
        if photo.cleanupCategory != .none { return }
        if photo.mediaSubtypesRaw.contains("screenshot") {
            photo.cleanupCategory = .screenshot
            return
        }
        if photo.mediaTypeRaw == "video" && photo.mediaSubtypesRaw.contains("screenRecording") {
            photo.cleanupCategory = .screenRecording
            return
        }
        if photo.mediaTypeRaw == "video" && (photo.estimatedFileSize ?? 0) > 100_000_000 {
            photo.cleanupCategory = .largeVideo
            return
        }
        if photo.burstIdentifier != nil && !photo.representsBurst {
            photo.cleanupCategory = .burst
            return
        }
        if text.isReceipt {
            photo.cleanupCategory = .receipt
            return
        }
        if text.isDocument {
            photo.cleanupCategory = .document
            return
        }
        if photo.mediaTypeRaw == "image" {
            let shouldFlag = BlurDetection.isBlurry(
                sharpness: photo.sharpnessScore ?? 1,
                aesthetics: quality.visionAestheticsScore,
                isUtility: quality.visionIsUtility,
                hasFaces: (photo.facesDetected ?? 0) > 0
            )
            if shouldFlag {
                photo.cleanupCategory = .blurry
                return
            }
        }
        if let exposure = photo.exposureScore, exposure > 0.85, photo.mediaTypeRaw == "image" {
            photo.cleanupCategory = .overexposed
            return
        }
        if let exposure = photo.exposureScore, exposure < 0.15, photo.mediaTypeRaw == "image" {
            photo.cleanupCategory = .underexposed
            return
        }
        if photo.isLivePhoto {
            photo.cleanupCategory = .livePhoto
        }
    }
    
    private static func fetchExistingIds(context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<PersistedPhoto>()
        let existing = (try? context.fetch(descriptor)) ?? []
        return Set(existing.map(\.localIdentifier))
    }
    
    private static func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            options.resizeMode = .fast
            
            var resumed = false
            let resumeOnce: (UIImage?) -> Void = { image in
                if !resumed {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 300, height: 300),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] != nil
                if cancelled || error {
                    resumeOnce(nil)
                    return
                }
                if let image, !degraded {
                    resumeOnce(image)
                } else if image == nil {
                    resumeOnce(nil)
                }
            }
            
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                resumeOnce(nil)
            }
        }
    }
}

// MARK: - Single-flight coordinator (AppState + BG tasks share one run)

actor ScanPipelineCoordinator {
    static let shared = ScanPipelineCoordinator()
    
    private var running: Task<Bool, Never>?
    
    func run(
        container: ModelContainer,
        store: ScanCheckpointStore = .shared,
        shouldStop: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (ScanProgressSnapshot) async -> Void
    ) async -> Bool {
        if MomentsTestRuntime.shouldSkipLiveScan {
            await onProgress(store.snapshot())
            return true
        }
        if let running {
            return await running.value
        }
        let task = Task.detached(priority: .utility) {
            let pipeline = ScanPipeline()
            return await pipeline.runLibrary(
                container: container,
                store: store,
                shouldStop: shouldStop,
                onProgress: onProgress
            )
        }
        running = task
        let result = await task.value
        running = nil
        return result
    }
}

// MARK: - UI-test active-scan simulation

enum ActiveScanSimulation {
    static let launchArgument = "-simulateActiveScan"
    
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
    
    private static let lock = NSLock()
    private static var processed = 10
    private static let total = 100
    private static var ticker: Task<Void, Never>?
    
    @MainActor
    static func bootstrapAppState(_ appState: AppState) {
        appState.hasCompletedOnboarding = true
        appState.isLibraryAuthorized = true
        appState.hasCompletedInitialAnalysis = true
        appState.isAnalyzing = true
        appState.isIndexing = false
        appState.analysisProgress = 0.10
        appState.totalPhotosAnalyzed = 10
        appState.totalPhotosToAnalyze = total
    }
    
    @MainActor
    static func start(appState: AppState) {
        let store = ScanCheckpointStore.shared
        store.start(totalPhotos: total)
        lock.lock()
        processed = max(store.processedCount, 10)
        lock.unlock()
        for i in 1...10 {
            store.markProcessed("sim-\(i)")
        }
        store.persist()
        apply(to: appState)
        
        ticker?.cancel()
        ticker = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                advance(by: 1)
                await MainActor.run {
                    apply(to: appState)
                }
            }
        }
    }
    
    static func handleDidEnterBackground() {
        guard isRequested else { return }
        advance(by: 5)
    }
    
    @MainActor
    static func handleDidBecomeActive(appState: AppState) {
        guard isRequested else { return }
        apply(to: appState)
    }
    
    static func advance(by count: Int) {
        lock.lock()
        processed = min(total - 1, processed + count)
        let current = processed
        lock.unlock()
        let store = ScanCheckpointStore.shared
        if !store.isInProgress {
            store.start(totalPhotos: total)
        }
        for i in 1...current {
            store.markProcessed("sim-\(i)")
        }
        store.persist()
    }
    
    @MainActor
    private static func apply(to appState: AppState) {
        let store = ScanCheckpointStore.shared
        let snap = store.snapshot()
        let count = max(snap.analyzed, {
            lock.lock(); defer { lock.unlock() }
            return processed
        }())
        let progress = Double(count) / Double(total)
        if appState.isAnalyzing != true { appState.isAnalyzing = true }
        if appState.isIndexing { appState.isIndexing = false }
        if appState.totalPhotosAnalyzed != count { appState.totalPhotosAnalyzed = count }
        if appState.totalPhotosToAnalyze != total { appState.totalPhotosToAnalyze = total }
        if abs(appState.analysisProgress - progress) > 0.0001 {
            appState.analysisProgress = progress
        }
    }
}
