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
    private weak var photoLibraryService: PhotoLibraryService?
    private weak var analysisService: PhotoAnalysisService?
    
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
        
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleTaskExpiration()
            }
        }
        
        Task {
            let success = await performBackgroundScan()
            
            await MainActor.run {
                task.setTaskCompleted(success: success)
                self.isBackgroundScanActive = false
                self.scanTask = nil
                
                if self.hasPendingWork {
                    self.scheduleScanTaskIfNeeded()
                } else {
                    self.sendScanCompleteNotification()
                }
            }
        }
    }
    
    private func handleAnalysisTask(_ task: BGTask) {
        isBackgroundScanActive = true
        
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleTaskExpiration()
            }
        }
        
        Task {
            let success = await performBackgroundAnalysis()
            
            await MainActor.run {
                task.setTaskCompleted(success: success)
                self.isBackgroundScanActive = false
                
                if self.hasAnalysisPending {
                    self.scheduleAnalysisTaskIfNeeded()
                } else if !self.hasPendingWork {
                    self.sendScanCompleteNotification()
                }
            }
        }
    }
    
    private func handleTaskExpiration() {
        print("[BackgroundTaskManager] Task expiring, checkpointing...")
        saveCheckpoint()
        isBackgroundScanActive = false
        
        scheduleScanTaskIfNeeded()
        scheduleAnalysisTaskIfNeeded()
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
        var indexedIds = Set(UserDefaults.standard.stringArray(forKey: checkpointIndexedIdsKey) ?? [])
        indexedIds.insert(assetId)
        UserDefaults.standard.set(Array(indexedIds), forKey: checkpointIndexedIdsKey)
        UserDefaults.standard.set(assetId, forKey: checkpointLastIndexedIdKey)
    }
    
    func markAnalyzed(photoId: String) {
        var analyzedIds = Set(UserDefaults.standard.stringArray(forKey: checkpointAnalyzedIdsKey) ?? [])
        analyzedIds.insert(photoId)
        UserDefaults.standard.set(Array(analyzedIds), forKey: checkpointAnalyzedIdsKey)
        UserDefaults.standard.set(photoId, forKey: checkpointLastAnalyzedIdKey)
    }
    
    func isAlreadyIndexed(_ assetId: String) -> Bool {
        let indexedIds = Set(UserDefaults.standard.stringArray(forKey: checkpointIndexedIdsKey) ?? [])
        return indexedIds.contains(assetId)
    }
    
    func isAlreadyAnalyzed(_ photoId: String) -> Bool {
        let analyzedIds = Set(UserDefaults.standard.stringArray(forKey: checkpointAnalyzedIdsKey) ?? [])
        return analyzedIds.contains(photoId)
    }
    
    func getCheckpointProgress() -> (indexed: Int, analyzed: Int, total: Int) {
        let indexedIds = UserDefaults.standard.stringArray(forKey: checkpointIndexedIdsKey) ?? []
        let analyzedIds = UserDefaults.standard.stringArray(forKey: checkpointAnalyzedIdsKey) ?? []
        let total = UserDefaults.standard.integer(forKey: checkpointTotalPhotosKey)
        return (indexedIds.count, analyzedIds.count, total)
    }
    
    private func saveCheckpoint() {
        UserDefaults.standard.synchronize()
        print("[BackgroundTaskManager] Checkpoint saved")
    }
    
    func completeScan() {
        UserDefaults.standard.set(false, forKey: checkpointScanInProgressKey)
        print("[BackgroundTaskManager] Scan marked complete")
    }
    
    func clearCheckpoint() {
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
        
        do {
            let status = await service.checkAuthorizationStatus()
            guard status == .authorized || status == .limited else { return false }
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            
            var processedCount = 0
            let totalCount = assets.count
            
            assets.enumerateObjects { [weak self] asset, index, stop in
                guard let self = self else {
                    stop.pointee = true
                    return
                }
                
                if self.isAlreadyIndexed(asset.localIdentifier) {
                    return
                }
                
                Task {
                    await service.indexSingleAsset(asset)
                    await MainActor.run {
                        self.markIndexed(assetId: asset.localIdentifier)
                        processedCount += 1
                        self.backgroundProgress = Double(processedCount) / Double(totalCount)
                    }
                }
            }
            
            return true
        } catch {
            print("[BackgroundTaskManager] Background scan failed: \(error)")
            return false
        }
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
    func submitContinuedProcessingTask() {
        // iOS 26+ allows BGContinuedProcessingTask with progress UI
        // This shows a system UI when the app is backgrounded during processing
        
        let request = BGContinuedProcessingTaskRequest(identifier: scanTaskIdentifier)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskManager] Submitted continued processing task (iOS 26+)")
        } catch {
            print("[BackgroundTaskManager] Failed to submit continued processing task: \(error)")
            scheduleScanTaskIfNeeded()
        }
    }
}
