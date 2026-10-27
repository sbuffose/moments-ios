// BackgroundTaskManager.swift
// Manages background processing for photo scanning and analysis

import Foundation
import BackgroundTasks
import UIKit
import Photos

@MainActor
final class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()
    
    // MARK: - Task Identifiers
    
    private let scanTaskIdentifier = "com.sbuffose.moments.scan"
    private let analysisTaskIdentifier = "com.sbuffose.moments.analysis"
    
    // MARK: - Checkpoint Keys
    
    private let checkpointLastIndexedIdKey = "com.moments.checkpoint.lastIndexedId"
    private let checkpointLastAnalyzedIdKey = "com.moments.checkpoint.lastAnalyzedId"
    private let checkpointIndexedIdsKey = "com.moments.checkpoint.indexedIds"
    private let checkpointAnalyzedIdsKey = "com.moments.checkpoint.analyzedIds"
    private let checkpointTotalPhotosKey = "com.moments.checkpoint.totalPhotos"
    private let checkpointScanInProgressKey = "com.moments.checkpoint.scanInProgress"
    
    // MARK: - Published State
    
    @Published var isBackgroundScanActive = false
    @Published var backgroundProgress: Double = 0
    
    // MARK: - Private Properties
    
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var scanTask: BGTask?
    private var analysisTask: BGTask?
    private var scanExpired = false
    private var analysisExpired = false
    private var completedTaskIds = Set<ObjectIdentifier>()
    private weak var photoLibraryService: PhotoLibraryService?
    private weak var analysisService: PhotoAnalysisService?
    
    // In-memory checkpoint sets (O(1) lookups instead of O(n) UserDefaults reads)
    private var indexedIdsCache: Set<String>?
    private var analyzedIdsCache: Set<String>?
    private var pendingIndexedBatch: Set<String> = []
    private var pendingAnalyzedBatch: Set<String> = []
    private let batchPersistThreshold = 50
    private var lastPersistTime: Date = .distantPast
    private let minPersistInterval: TimeInterval = 5.0
    
    private init() {}
    
    // MARK: - Setup
    
    func configure(photoLibraryService: PhotoLibraryService, analysisService: PhotoAnalysisService) {
        self.photoLibraryService = photoLibraryService
        self.analysisService = analysisService
    }
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: scanTaskIdentifier,
            using: nil
        ) { [weak self] task in
            Task { @MainActor in
                self?.handleScanTask(task)
            }
        }
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: analysisTaskIdentifier,
            using: nil
        ) { [weak self] task in
            Task { @MainActor in
                self?.handleAnalysisTask(task)
            }
        }
        
        // Register iOS 26+ continued processing task handler
        if #available(iOS 26.0, *) {
            registerContinuedProcessingTaskHandler()
        }
    }
    
    // MARK: - Task Scheduling
    
    func scheduleScanTaskIfNeeded() {
        guard hasPendingWork else { return }
        
        let request = BGProcessingTaskRequest(identifier: scanTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskManager] Scheduled scan task")
        } catch {
            print("[BackgroundTaskManager] Failed to schedule scan task: \(error)")
        }
    }
    
    func scheduleAnalysisTaskIfNeeded() {
        guard hasAnalysisPending else { return }
        
        let request = BGProcessingTaskRequest(identifier: analysisTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskManager] Scheduled analysis task")
        } catch {
            print("[BackgroundTaskManager] Failed to schedule analysis task: \(error)")
        }
    }
    
    // MARK: - Task Handling
    
    private func handleScanTask(_ task: BGTask) {
        isBackgroundScanActive = true
        scanTask = task
        scanExpired = false
        
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleTaskExpiration(task: task, kind: .scan)
            }
        }
        
        Task {
            let success = await performBackgroundScan()
            await MainActor.run {
                self.finishSystemTask(task, success: success && !self.scanExpired, kind: .scan)
                if self.hasPendingWork {
                    self.scheduleScanTaskIfNeeded()
                } else if !self.scanExpired {
                    self.sendScanCompleteNotification()
                }
            }
        }
    }
    
    private func handleAnalysisTask(_ task: BGTask) {
        isBackgroundScanActive = true
        analysisTask = task
        analysisExpired = false
        
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleTaskExpiration(task: task, kind: .analysis)
            }
        }
        
        Task {
            let success = await performBackgroundAnalysis()
            await MainActor.run {
                self.finishSystemTask(task, success: success && !self.analysisExpired, kind: .analysis)
                if self.hasAnalysisPending {
                    self.scheduleAnalysisTaskIfNeeded()
                } else if !self.hasPendingWork && !self.analysisExpired {
                    self.sendScanCompleteNotification()
                }
            }
        }
    }
    
    enum BackgroundWorkKind {
        case scan
        case analysis
    }
    
    /// Expiration MUST call setTaskCompleted(false) exactly once. iOS kills apps that ignore it.
    private func handleTaskExpiration(task: BGTask, kind: BackgroundWorkKind) {
        print("[BackgroundTaskManager] Task expiring, checkpointing...")
        saveCheckpoint()
        isBackgroundScanActive = false
        switch kind {
        case .scan:
            scanExpired = true
        case .analysis:
            analysisExpired = true
        }
        finishSystemTask(task, success: false, kind: kind)
        scheduleScanTaskIfNeeded()
        scheduleAnalysisTaskIfNeeded()
    }
    
    /// Completes a BGTask at most once. Expiration and the work Task race; only the first wins.
    private func finishSystemTask(_ task: BGTask, success: Bool, kind: BackgroundWorkKind) {
        let id = ObjectIdentifier(task)
        guard BackgroundTaskCompletion.shouldComplete(previouslyCompleted: completedTaskIds.contains(id)) else {
            return
        }
        completedTaskIds.insert(id)
        task.setTaskCompleted(success: success)
        isBackgroundScanActive = false
        switch kind {
        case .scan:
            if scanTask === task { scanTask = nil }
        case .analysis:
            if analysisTask === task { analysisTask = nil }
        }
    }
    
    // MARK: - App Lifecycle Background Task
    
    func beginBackgroundTaskForAppExit() {
        guard backgroundTask == .invalid else { return }
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "moments.scan.grace") { [weak self] in
            self?.endBackgroundTask()
        }
        
        print("[BackgroundTaskManager] Started background task for app exit")
    }
    
    func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        
        saveCheckpoint()
        scheduleScanTaskIfNeeded()
        scheduleAnalysisTaskIfNeeded()
        
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        
        print("[BackgroundTaskManager] Ended background task")
    }
    
    // MARK: - Checkpoint Management
    
    var hasPendingWork: Bool {
        UserDefaults.standard.bool(forKey: checkpointScanInProgressKey)
    }
    
    var hasAnalysisPending: Bool {
        let analyzedIds = Set(UserDefaults.standard.stringArray(forKey: checkpointAnalyzedIdsKey) ?? [])
        let indexedIds = Set(UserDefaults.standard.stringArray(forKey: checkpointIndexedIdsKey) ?? [])
        return indexedIds.count > analyzedIds.count
    }
    
    func startScan(totalPhotos: Int) {
        UserDefaults.standard.set(true, forKey: checkpointScanInProgressKey)
        UserDefaults.standard.set(totalPhotos, forKey: checkpointTotalPhotosKey)
    }
    
    func markIndexed(assetId: String) {
        loadCachesIfNeeded()
        indexedIdsCache?.insert(assetId)
        pendingIndexedBatch.insert(assetId)
        
        // Batch persist: only write to UserDefaults when batch is full or interval elapsed
        if shouldPersistBatch() {
            persistBatchedCheckpoints()
        }
    }
    
    func markAnalyzed(photoId: String) {
        loadCachesIfNeeded()
        analyzedIdsCache?.insert(photoId)
        pendingAnalyzedBatch.insert(photoId)
        
        // Batch persist: only write to UserDefaults when batch is full or interval elapsed
        if shouldPersistBatch() {
            persistBatchedCheckpoints()
        }
    }
    
    func isAlreadyIndexed(_ assetId: String) -> Bool {
        loadCachesIfNeeded()
        return indexedIdsCache?.contains(assetId) ?? false
    }
    
    func isAlreadyAnalyzed(_ photoId: String) -> Bool {
        loadCachesIfNeeded()
        return analyzedIdsCache?.contains(photoId) ?? false
    }
    
    func getCheckpointProgress() -> (indexed: Int, analyzed: Int, total: Int) {
        loadCachesIfNeeded()
        let total = UserDefaults.standard.integer(forKey: checkpointTotalPhotosKey)
        return (indexedIdsCache?.count ?? 0, analyzedIdsCache?.count ?? 0, total)
    }
    
    private func loadCachesIfNeeded() {
        if indexedIdsCache == nil {
            indexedIdsCache = Set(UserDefaults.standard.stringArray(forKey: checkpointIndexedIdsKey) ?? [])
        }
        if analyzedIdsCache == nil {
            analyzedIdsCache = Set(UserDefaults.standard.stringArray(forKey: checkpointAnalyzedIdsKey) ?? [])
        }
    }
    
    private func shouldPersistBatch() -> Bool {
        let batchSize = pendingIndexedBatch.count + pendingAnalyzedBatch.count
        let timeSinceLastPersist = Date().timeIntervalSince(lastPersistTime)
        return batchSize >= batchPersistThreshold || timeSinceLastPersist >= minPersistInterval
    }
    
    private func persistBatchedCheckpoints() {
        guard !pendingIndexedBatch.isEmpty || !pendingAnalyzedBatch.isEmpty else { return }
        
        if let indexedIds = indexedIdsCache {
            UserDefaults.standard.set(Array(indexedIds), forKey: checkpointIndexedIdsKey)
            if let lastIndexed = pendingIndexedBatch.first {
                UserDefaults.standard.set(lastIndexed, forKey: checkpointLastIndexedIdKey)
            }
        }
        
        if let analyzedIds = analyzedIdsCache {
            UserDefaults.standard.set(Array(analyzedIds), forKey: checkpointAnalyzedIdsKey)
            if let lastAnalyzed = pendingAnalyzedBatch.first {
                UserDefaults.standard.set(lastAnalyzed, forKey: checkpointLastAnalyzedIdKey)
            }
        }
        
        pendingIndexedBatch.removeAll()
        pendingAnalyzedBatch.removeAll()
        lastPersistTime = Date()
        
        print("[BackgroundTaskManager] Batch checkpoint persisted")
    }
    
    private func saveCheckpoint() {
        // Force persist any pending batches
        persistBatchedCheckpoints()
        UserDefaults.standard.synchronize()
        print("[BackgroundTaskManager] Checkpoint saved")
    }
    
    func completeScan() {
        UserDefaults.standard.set(false, forKey: checkpointScanInProgressKey)
        print("[BackgroundTaskManager] Scan marked complete")
    }
    
    func clearCheckpoint() {
        // Clear in-memory caches
        indexedIdsCache = nil
        analyzedIdsCache = nil
        pendingIndexedBatch.removeAll()
        pendingAnalyzedBatch.removeAll()
        
        // Clear persisted data
        UserDefaults.standard.removeObject(forKey: checkpointLastIndexedIdKey)
        UserDefaults.standard.removeObject(forKey: checkpointLastAnalyzedIdKey)
        UserDefaults.standard.removeObject(forKey: checkpointIndexedIdsKey)
        UserDefaults.standard.removeObject(forKey: checkpointAnalyzedIdsKey)
        UserDefaults.standard.removeObject(forKey: checkpointTotalPhotosKey)
        UserDefaults.standard.removeObject(forKey: checkpointScanInProgressKey)
    }
    
    // MARK: - Background Work
    
    private func performBackgroundScan() async -> Bool {
        guard let service = photoLibraryService else { return false }
        
        let status = await service.checkAuthorizationStatus()
        guard status == .authorized || status == .limited else { return false }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        var pending: [PHAsset] = []
        pending.reserveCapacity(min(assets.count, 512))
        assets.enumerateObjects { [weak self] asset, _, stop in
            guard let self else {
                stop.pointee = true
                return
            }
            if self.scanExpired {
                stop.pointee = true
                return
            }
            if !self.isAlreadyIndexed(asset.localIdentifier) {
                pending.append(asset)
            }
        }
        
        let totalCount = max(1, assets.count)
        var processedCount = assets.count - pending.count
        
        // Await each asset. Fire-and-forget Tasks used to return true before work finished.
        for asset in pending {
            if scanExpired || Task.isCancelled {
                saveCheckpoint()
                return false
            }
            await service.indexSingleAsset(asset)
            autoreleasepool {
                self.markIndexed(assetId: asset.localIdentifier)
                processedCount += 1
                self.backgroundProgress = Double(processedCount) / Double(totalCount)
            }
        }
        
        persistBatchedCheckpoints()
        return !scanExpired
    }
    
    private func performBackgroundAnalysis() async -> Bool {
        guard let service = analysisService else { return false }
        
        let success = await service.analyzeUnprocessedPhotosInBackground { [weak self] progress in
            Task { @MainActor in
                self?.backgroundProgress = progress
            }
        }
        
        return success
    }
    
    // MARK: - Notifications
    
    private func sendScanCompleteNotification() {
        let content = UNMutableNotificationContent()
        content.title = "¡Análisis completado!"
        content.body = "Tu biblioteca de fotos está lista. Abrí Moments para ver las sugerencias de limpieza."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "scan.complete",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[BackgroundTaskManager] Failed to send notification: \(error)")
            }
        }
    }
}

// MARK: - iOS 26+ BGContinuedProcessingTask Support

@available(iOS 26.0, *)
extension BackgroundTaskManager {
    
    // Continued processing tasks use a wildcard identifier pattern
    // Must register with the EXACT identifier from Info.plist including the asterisk
    private static let continuedTaskIdentifierWildcard = "com.sbuffose.moments.continued.*"
    private static let continuedTaskIdentifierPrefix = "com.sbuffose.moments.continued."
    
    // Track the active continued processing task
    private static var activeContinuedTask: BGContinuedProcessingTask?
    private static var continuedTaskWorkItem: Task<Void, Never>?
    private static var continuedTaskDidComplete = false
    
    // Track whether registration succeeded - Swift do/catch cannot catch NSException,
    // so we must guard submissions against this flag
    private static var isContinuedProcessingRegistered = false
    
    /// Register the continued processing task handler. Call once at app launch.
    /// Returns true if registration succeeded, false otherwise.
    @discardableResult
    func registerContinuedProcessingTaskHandler() -> Bool {
        // Register with the EXACT wildcard identifier from BGTaskSchedulerPermittedIdentifiers
        // Must match "com.sbuffose.moments.continued.*" exactly
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.continuedTaskIdentifierWildcard,
            using: nil
        ) { [weak self] task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self?.handleContinuedProcessingTask(continuedTask)
            }
        }
        Self.isContinuedProcessingRegistered = registered
        if !registered {
            print("[BackgroundTaskManager] WARNING: Failed to register continued processing task handler")
        }
        return registered
    }
    
    /// Submit a continued processing task. Only call while a user-initiated scan is actively running.
    /// - Parameter remainingPhotos: Number of photos remaining to process (must be > 0)
    func submitContinuedProcessingTask(remainingPhotos: Int) {
        // Guard against registration not having succeeded - NSException from submit
        // cannot be caught by Swift do/catch, so we must check this flag
        guard Self.isContinuedProcessingRegistered else {
            print("[BackgroundTaskManager] Skipping continued task - handler not registered")
            scheduleScanTaskIfNeeded()
            return
        }
        
        // Don't submit if no work remains
        guard remainingPhotos > 0 else {
            print("[BackgroundTaskManager] Skipping continued task - no photos remaining")
            return
        }
        
        // Don't submit if scan isn't in progress
        guard hasPendingWork else {
            print("[BackgroundTaskManager] Skipping continued task - no scan in progress")
            return
        }
        
        // Generate unique identifier for this task: prefix + UUID
        // The wildcard registration "com.sbuffose.moments.continued.*" matches this
        let taskId = Self.continuedTaskIdentifierPrefix + UUID().uuidString
        
        let request = BGContinuedProcessingTaskRequest(
            identifier: taskId,
            title: NSLocalizedString("bg_task_title", comment: "Analizando fotos"),
            subtitle: NSLocalizedString("bg_task_subtitle_remaining", comment: "") + " \(remainingPhotos)"
        )
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskManager] Submitted continued processing task: \(taskId)")
        } catch BGTaskScheduler.Error.unavailable {
            print("[BackgroundTaskManager] Continued processing unavailable, falling back to BGProcessingTask")
            scheduleScanTaskIfNeeded()
        } catch {
            print("[BackgroundTaskManager] Failed to submit continued processing task: \(error)")
            // Silent fallback - don't surface error to user
            scheduleScanTaskIfNeeded()
        }
    }
    
    /// Handle a continued processing task with proper progress reporting
    private func handleContinuedProcessingTask(_ task: BGContinuedProcessingTask) {
        Self.activeContinuedTask = task
        Self.continuedTaskDidComplete = false
        isBackgroundScanActive = true
        
        // Get current progress state
        let checkpoint = getCheckpointProgress()
        let totalRemaining = max(1, checkpoint.total - checkpoint.analyzed)
        
        // Initialize progress - system displays this in the banner
        task.progress.totalUnitCount = Int64(totalRemaining)
        task.progress.completedUnitCount = 0
        
        // Set expiration handler - must checkpoint and complete exactly once
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                print("[BackgroundTaskManager] Continued task expiring, checkpointing...")
                Self.continuedTaskWorkItem?.cancel()
                self?.completeContinuedTaskOnce(task, success: false)
                self?.scheduleScanTaskIfNeeded()
                self?.scheduleAnalysisTaskIfNeeded()
            }
        }
        
        // Start the actual work
        Self.continuedTaskWorkItem = Task { [weak self] in
            guard let self = self else {
                task.setTaskCompleted(success: false)
                return
            }
            
            let success = await self.performContinuedProcessing(task: task)
            
            await MainActor.run {
                self.completeContinuedTaskOnce(task, success: success)
                if success && !self.hasPendingWork && !self.hasAnalysisPending {
                    self.sendScanCompleteNotification()
                } else if self.hasPendingWork || self.hasAnalysisPending {
                    self.scheduleScanTaskIfNeeded()
                    self.scheduleAnalysisTaskIfNeeded()
                }
            }
        }
    }
    
    /// Completes the continued task exactly once (expiration and work race).
    private func completeContinuedTaskOnce(_ task: BGContinuedProcessingTask, success: Bool) {
        guard BackgroundTaskCompletion.shouldComplete(previouslyCompleted: Self.continuedTaskDidComplete) else {
            return
        }
        Self.continuedTaskDidComplete = true
        Self.continuedTaskWorkItem = nil
        saveCheckpoint()
        Self.activeContinuedTask = nil
        isBackgroundScanActive = false
        task.setTaskCompleted(success: success)
    }
    
    /// Perform the continued processing work with progress updates
    private func performContinuedProcessing(task: BGContinuedProcessingTask) async -> Bool {
        guard let analysisService = self.analysisService else { return false }
        
        var processedCount: Int64 = 0
        let totalCount = task.progress.totalUnitCount
        var lastTitleUpdate = Date()
        let titleUpdateInterval: TimeInterval = 5.0 // Update subtitle every 5 seconds
        
        let success = await analysisService.analyzeUnprocessedPhotosInBackground { [weak self] progress in
            Task { @MainActor in
                guard let self = self, Self.activeContinuedTask === task else { return }
                
                // Update completed count
                processedCount = Int64(Double(totalCount) * progress)
                task.progress.completedUnitCount = processedCount
                self.backgroundProgress = progress
                
                // Periodically update the subtitle with remaining count
                let now = Date()
                if now.timeIntervalSince(lastTitleUpdate) >= titleUpdateInterval {
                    lastTitleUpdate = now
                    let remaining = Int(totalCount - processedCount)
                    if remaining > 0 {
                        task.updateTitle(
                            NSLocalizedString("bg_task_title", comment: "Analizando fotos"),
                            subtitle: NSLocalizedString("bg_task_subtitle_remaining", comment: "Faltan") + " \(remaining)"
                        )
                    } else {
                        task.updateTitle(
                            NSLocalizedString("bg_task_title_finishing", comment: "Finalizando"),
                            subtitle: NSLocalizedString("bg_task_subtitle_almost_done", comment: "Casi listo")
                        )
                    }
                }
            }
        }
        
        // Ensure progress shows completion
        await MainActor.run {
            task.progress.completedUnitCount = totalCount
            self.backgroundProgress = 1.0
        }
        
        return success
    }
    
    /// Check if there's an active continued processing task
    var hasContinuedProcessingTask: Bool {
        Self.activeContinuedTask != nil
    }
    
    /// Cancel any active continued processing task
    func cancelContinuedProcessingTask() {
        Self.continuedTaskWorkItem?.cancel()
        if let task = Self.activeContinuedTask {
            completeContinuedTaskOnce(task, success: false)
        } else {
            Self.continuedTaskWorkItem = nil
            isBackgroundScanActive = false
        }
    }
}

/// Testable completion gate: a BGTask / BGContinuedProcessingTask must complete exactly once.
enum BackgroundTaskCompletion {
    static func shouldComplete(previouslyCompleted: Bool) -> Bool {
        !previouslyCompleted
    }
    
    static func expirationSuccess() -> Bool {
        false
    }
}
