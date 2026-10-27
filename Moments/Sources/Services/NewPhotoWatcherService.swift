// NewPhotoWatcherService.swift
// Watches for new photos and alerts user about potentially bad ones

import Foundation
import Photos
import SwiftData
import UserNotifications
import BackgroundTasks

@MainActor
class NewPhotoWatcherService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = NewPhotoWatcherService()
    
    @Published var hasNewBadPhotos = false
    @Published var newBadPhotos: [PHAsset] = []
    @Published var showBadPhotoSheet = false
    
    private var modelContext: ModelContext?
    private var photoAnalysisService: PhotoAnalysisService?
    private var lastCheckedDate: Date?
    private var dailyPopupCount = 0
    private var lastPopupResetDate: Date?
    
    private let maxPopupsPerDay = 3
    private let photoAgeThreshold: TimeInterval = 5 * 60 // 5 minutes
    private let userDefaultsKey = "newPhotoWatcher.enabled"
    private let lastCheckedKey = "newPhotoWatcher.lastChecked"
    private let popupCountKey = "newPhotoWatcher.popupCount"
    private let popupResetDateKey = "newPhotoWatcher.popupResetDate"
    
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKey) }
    }
    
    private override init() {
        super.init()
        loadState()
    }
    
    func initialize(modelContext: ModelContext, analysisService: PhotoAnalysisService) {
        self.modelContext = modelContext
        self.photoAnalysisService = analysisService
        
        // Register for photo library changes
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    // MARK: - State Persistence
    
    private func loadState() {
        lastCheckedDate = UserDefaults.standard.object(forKey: lastCheckedKey) as? Date
        dailyPopupCount = UserDefaults.standard.integer(forKey: popupCountKey)
        lastPopupResetDate = UserDefaults.standard.object(forKey: popupResetDateKey) as? Date
        
        // Reset popup count if new day
        if let resetDate = lastPopupResetDate, !Calendar.current.isDateInToday(resetDate) {
            dailyPopupCount = 0
            lastPopupResetDate = Date()
            saveState()
        }
    }
    
    private func saveState() {
        UserDefaults.standard.set(lastCheckedDate, forKey: lastCheckedKey)
        UserDefaults.standard.set(dailyPopupCount, forKey: popupCountKey)
        UserDefaults.standard.set(lastPopupResetDate, forKey: popupResetDateKey)
    }
    
    // MARK: - PHPhotoLibraryChangeObserver
    
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.checkForNewPhotos()
        }
    }
    
    // MARK: - Check for New Photos
    
    func checkForNewPhotos() {
        guard isEnabled else { return }
        
        // Check daily popup limit
        resetDailyCountIfNeeded()
        guard dailyPopupCount < maxPopupsPerDay else { return }
        
        let now = Date()
        let fiveMinutesAgo = now.addingTimeInterval(-photoAgeThreshold)
        
        // Fetch recent photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate > %@ AND creationDate < %@",
            fiveMinutesAgo as NSDate,
            now as NSDate
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let recentPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var badPhotos: [PHAsset] = []
        
        recentPhotos.enumerateObjects { asset, _, _ in
            // Quick check for obvious issues
            if self.isLikelyBadPhoto(asset) {
                badPhotos.append(asset)
            }
        }
        
        if !badPhotos.isEmpty {
            newBadPhotos = badPhotos
            hasNewBadPhotos = true
            
            // Show sheet or notification based on app state
            if UIApplication.shared.applicationState == .active {
                showBadPhotoSheet = true
                dailyPopupCount += 1
                saveState()
            } else {
                sendBadPhotoNotification(count: badPhotos.count)
            }
        }
        
        lastCheckedDate = now
        saveState()
    }
    
    private func resetDailyCountIfNeeded() {
        if let resetDate = lastPopupResetDate, !Calendar.current.isDateInToday(resetDate) {
            dailyPopupCount = 0
            lastPopupResetDate = Date()
            saveState()
        } else if lastPopupResetDate == nil {
            lastPopupResetDate = Date()
            saveState()
        }
    }
    
    // MARK: - Quick Bad Photo Detection
    
    private func isLikelyBadPhoto(_ asset: PHAsset) -> Bool {
        // Check for screenshots
        if asset.mediaSubtypes.contains(.screenshot) {
            return false // Screenshots aren't "bad", just clutter
        }
        
        // Check for very short burst (might be accidental)
        if asset.burstIdentifier != nil && !asset.representsBurst {
            return false // Non-representative burst photos
        }
        
        // Check pixel dimensions - very small images might be accidental
        if asset.pixelWidth < 500 || asset.pixelHeight < 500 {
            return true // Likely accidental or corrupted
        }
        
        // Check for duplicate detection would require more processing
        // For now, return false for normal photos
        return false
    }
    
    // MARK: - Background Notification
    
    private func sendBadPhotoNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Foto recién tomada"
        content.body = count == 1 
            ? "¿Querés revisar tu última foto?"
            : "Tenés \(count) fotos nuevas para revisar"
        content.sound = .default
        content.categoryIdentifier = "NEW_PHOTO_CHECK"
        content.userInfo = ["type": "newPhotoCheck"]
        
        let request = UNNotificationRequest(
            identifier: "new-photo-check-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request)
        dailyPopupCount += 1
        saveState()
    }
    
    // MARK: - Clear State
    
    func dismissBadPhotos() {
        hasNewBadPhotos = false
        newBadPhotos = []
        showBadPhotoSheet = false
    }
    
    // MARK: - Foreground Check
    
    func checkOnForeground() {
        guard isEnabled else { return }
        
        // Only check if we haven't checked recently
        if let lastCheck = lastCheckedDate, Date().timeIntervalSince(lastCheck) < 60 {
            return
        }
        
        checkForNewPhotos()
    }
    
    // MARK: - Background Task
    
    static let backgroundTaskIdentifier = "com.sbuffose.moments.newPhotoCheck"
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            Task { @MainActor in
                self?.handleBackgroundTask(task as! BGAppRefreshTask)
            }
        }
    }
    
    func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[NewPhotoWatcherService] Failed to schedule background task: \(error)")
        }
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        checkForNewPhotos()
        scheduleBackgroundTask()
        task.setTaskCompleted(success: true)
    }
}
