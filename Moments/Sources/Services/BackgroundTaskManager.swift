// BackgroundTaskManager.swift
// Manages background processing for photo scanning and analysis

import Foundation
import BackgroundTasks
import UIKit
import Photos
import SwiftData
import UserNotifications

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
    private var modelContainer: ModelContainer?
    
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
    
    func configure(photoLibraryService: PhotoLibraryService, analysisService: PhotoAnalysisService, container: ModelContainer) {
        self.photoLibraryService = photoLibraryService
        self.analysisService = analysisService
        self.modelContainer = container
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
        ScanCheckpointStore.shared.isInProgress
    }
    
    var hasAnalysisPending: Bool {
        let snap = ScanCheckpointStore.shared.snapshot()
        return snap.indexed > snap.analyzed
    }
    
    func startScan(totalPhotos: Int) {
        ScanCheckpointStore.shared.start(totalPhotos: totalPhotos)
    }
    
    func markIndexed(assetId: String) {
        ScanCheckpointStore.shared.markIndexed(assetId)
    }
    
    func markAnalyzed(photoId: String) {
        ScanCheckpointStore.shared.markAnalyzed(photoId)
    }
    
    func isAlreadyIndexed(_ assetId: String) -> Bool {
        ScanCheckpointStore.shared.isIndexed(assetId)
    }
    
    func isAlreadyAnalyzed(_ photoId: String) -> Bool {
        ScanCheckpointStore.shared.isAnalyzed(photoId)
    }
    
    func getCheckpointProgress() -> (indexed: Int, analyzed: Int, total: Int) {
        let snap = ScanCheckpointStore.shared.snapshot()
        return (snap.indexed, snap.analyzed, snap.total)
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
        ScanCheckpointStore.shared.persist()
        print("[BackgroundTaskManager] Checkpoint saved")
    }
    
    func completeScan() {
        ScanCheckpointStore.shared.complete()
        print("[BackgroundTaskManager] Scan marked complete")
    }
    
    func clearCheckpoint() {
        ScanCheckpointStore.shared.clear()
    }
    
    // MARK: - Background Work
    
    private func performBackgroundScan() async -> Bool {
        await performSharedPipeline()
    }
    
    private func performBackgroundAnalysis() async -> Bool {
        await performSharedPipeline()
    }
    
    private func performSharedPipeline() async -> Bool {
        guard let container = modelContainer else { return false }
        return await ScanPipelineCoordinator.shared.run(
            container: container,
            shouldStop: { Task.isCancelled }
        ) { [weak self] snapshot in
            await MainActor.run {
                self?.backgroundProgress = snapshot.overallProgress
            }
        }
    }
    
    // MARK: - Notifications
    
    private func sendScanCompleteNotification() {
        let content = UNMutableNotificationContent()
        content.title = ScanCompletionNotificationCopy.title
        content.body = ScanCompletionNotificationCopy.body
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
    private static let continuedTaskIdentifierWildcard = ContinuedProcessingRequest.identifierWildcard
    private static let continuedTaskIdentifierPrefix = ContinuedProcessingRequest.identifierPrefix
    
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
    
    /// Submit a continued processing task. Only call from a foreground user action
    /// (first-run Empezar). Scene-phase `.background` must not call this.
    func submitContinuedProcessingTask(remainingPhotos: Int) {
        let request = FirstRunScanStart.submitContinuedProcessingOnEmpezar(remainingPhotos: remainingPhotos)
        submitRecordedContinuedRequest(request)
    }
    
    /// Submit a request already recorded on the Empezar call stack.
    func submitRecordedContinuedRequest(_ request: ContinuedProcessingRequest) {
        guard Self.isContinuedProcessingRegistered else {
            print("[BackgroundTaskManager] Skipping continued task - handler not registered")
            scheduleScanTaskIfNeeded()
            return
        }
        
        guard request.remainingPhotos > 0 else {
            print("[BackgroundTaskManager] Skipping continued task - no photos remaining")
            return
        }
        
        let bgRequest = BGContinuedProcessingTaskRequest(
            identifier: request.identifier,
            title: request.title,
            subtitle: request.subtitle
        )
        
        do {
            try BGTaskScheduler.shared.submit(bgRequest)
            print("[BackgroundTaskManager] Submitted continued processing task: \(request.identifier)")
        } catch BGTaskScheduler.Error.unavailable {
            print("[BackgroundTaskManager] Continued processing unavailable, falling back to BGProcessingTask")
            scheduleScanTaskIfNeeded()
        } catch {
            print("[BackgroundTaskManager] Failed to submit continued processing task: \(error)")
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
                // Do not cancel the shared detached pipeline — checkpoint and
                // let BGProcessingTask pick up after iOS suspends us.
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
        guard let container = modelContainer else { return false }
        
        let totalCount = task.progress.totalUnitCount
        var lastTitleUpdate = Date()
        let titleUpdateInterval: TimeInterval = 5.0
        
        let success = await ScanPipelineCoordinator.shared.run(
            container: container,
            shouldStop: { Task.isCancelled }
        ) { [weak self] snapshot in
            await MainActor.run {
                guard let self = self, Self.activeContinuedTask === task else { return }
                let processedCount = Int64(Double(totalCount) * snapshot.overallProgress)
                task.progress.completedUnitCount = processedCount
                self.backgroundProgress = snapshot.overallProgress
                
                let now = Date()
                if now.timeIntervalSince(lastTitleUpdate) >= titleUpdateInterval {
                    lastTitleUpdate = now
                    let remaining = max(0, snapshot.total - snapshot.analyzed)
                    if remaining > 0 {
                        task.updateTitle(
                            ContinuedProcessingRequest.progressTitle,
                            subtitle: "Faltan \(remaining)"
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
