// DailyReviewService.swift
// Daily review notification scheduling and management

import Foundation
import SwiftData
import UserNotifications
import BackgroundTasks
import Photos

@MainActor
final class DailyReviewService: ObservableObject {
    static let shared = DailyReviewService()
    
    private var modelContext: ModelContext?
    
    static let dailyReviewTaskIdentifier = "com.sbuffose.moments.dailyReview"
    static let notificationCategoryIdentifier = "DAILY_REVIEW"
    static let reviewDeepLinkAction = "REVIEW_TODAY"
    static let notificationIdentifier = "daily-review"
    static let legacyNotificationIdentifiers = ["daily-review-21-0", "daily-review"]
    
    @Published var isNotificationPermissionGranted = false
    @Published var todayCandidateCount = 0
    @Published var todayCandidateSize: Int64 = 0
    
    private init() {}
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await checkNotificationPermission()
            await scheduleNotificationIfEnabled()
            await updateTodayCandidates()
        }
    }
    
    // MARK: - Permission
    
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                self.isNotificationPermissionGranted = granted
            }
            
            if granted {
                await registerNotificationCategory()
            }
            
            return granted
        } catch {
            print("[DailyReviewService] Failed to request permission: \(error)")
            return false
        }
    }
    
    private func checkNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        await MainActor.run {
            self.isNotificationPermissionGranted = settings.authorizationStatus == .authorized
        }
    }
    
    private func registerNotificationCategory() async {
        let reviewAction = UNNotificationAction(
            identifier: Self.reviewDeepLinkAction,
            title: NSLocalizedString("daily_review_action_review", comment: "Revisar fotos"),
            options: [.foreground]
        )
        
        let category = UNNotificationCategory(
            identifier: Self.notificationCategoryIdentifier,
            actions: [reviewAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
    
    // MARK: - Settings
    
    func getSettings() async -> DailyReviewSettings {
        guard let context = modelContext else {
            return DailyReviewSettings()
        }
        
        let descriptor = FetchDescriptor<DailyReviewSettings>(
            predicate: #Predicate<DailyReviewSettings> { $0.id == "main" }
        )
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        let newSettings = DailyReviewSettings()
        context.insert(newSettings)
        try? context.save()
        return newSettings
    }
    
    func updateSettings(
        isEnabled: Bool? = nil,
        hour: Int? = nil,
        minute: Int? = nil
    ) async {
        let settings = await getSettings()
        
        if let enabled = isEnabled {
            settings.isEnabled = enabled
        }
        if let h = hour {
            settings.reviewHour = h
        }
        if let m = minute {
            settings.reviewMinute = m
        }
        
        try? modelContext?.save()
        
        if settings.isEnabled {
            await scheduleNotification(at: settings.reviewHour, minute: settings.reviewMinute)
        } else {
            await cancelNotification()
        }
    }
    
    // MARK: - Notification Scheduling
    
    func scheduleNotificationIfEnabled() async {
        let settings = await getSettings()
        
        guard settings.isEnabled else {
            await cancelNotification()
            return
        }
        
        await scheduleNotification(at: settings.reviewHour, minute: settings.reviewMinute)
    }
    
    private func scheduleNotification(at hour: Int, minute: Int) async {
        guard isNotificationPermissionGranted else { return }
        
        // Cancel any existing notification
        await cancelNotification()
        
        // Update candidates count first
        await updateTodayCandidates()
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("daily_review_notification_title", comment: "Repaso del día")
        
        if todayCandidateCount > 0 {
            let sizeFormatted = ByteCountFormatter.string(fromByteCount: todayCandidateSize, countStyle: .file)
            content.body = String(
                format: NSLocalizedString("daily_review_notification_body", comment: ""),
                todayCandidateCount,
                sizeFormatted
            )
        } else {
            content.body = "Revisá las fotos de hoy y organizá tu biblioteca"
        }
        
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategoryIdentifier
        content.userInfo = ["type": "dailyReview", "deepLink": "review"]
        
        // Calendar trigger for the specified time
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[DailyReviewService] Scheduled daily review at \(hour):\(minute)")
            
            // Store notification ID in settings
            let settings = await getSettings()
            settings.notificationId = request.identifier
            try? modelContext?.save()
        } catch {
            print("[DailyReviewService] Failed to schedule notification: \(error)")
        }
    }
    
    private func cancelNotification() async {
        let settings = await getSettings()
        
        var ids = Self.legacyNotificationIdentifiers
        if let notificationId = settings.notificationId {
            ids.append(notificationId)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        settings.notificationId = nil
        try? modelContext?.save()
    }
    
    // MARK: - Today's Candidates
    
    func updateTodayCandidates() async {
        guard let context = modelContext else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Fetch analyzed photos that are cleanup candidates
        let noneValue = "none"
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate<PersistedPhoto> { photo in
                photo.analysisCompleted &&
                photo.cleanupCategoryRaw != noneValue
            }
        )
        
        guard let photos = try? context.fetch(descriptor) else { return }
        
        // Filter to today's photos that are not kept
        let todayPhotos = photos.filter { photo in
            guard let date = photo.creationDate,
                  date >= startOfDay && date < endOfDay else { return false }
            let keepDecision = photo.keepDecisionRaw
            return keepDecision == nil || keepDecision == "none"
        }
        
        await MainActor.run {
            self.todayCandidateCount = todayPhotos.count
            self.todayCandidateSize = todayPhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
        }
    }
    
    func getTodayCandidates() async -> [PersistedPhoto] {
        guard let context = modelContext else { return [] }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let noneValue = "none"
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate<PersistedPhoto> { photo in
                photo.analysisCompleted &&
                photo.cleanupCategoryRaw != noneValue
            },
            sortBy: [SortDescriptor(\.deletionLikelihoodScore, order: .reverse)]
        )
        
        guard let photos = try? context.fetch(descriptor) else { return [] }
        
        // Filter to today's photos that are not kept
        return photos.filter { photo in
            guard let date = photo.creationDate,
                  date >= startOfDay && date < endOfDay else { return false }
            let keepDecision = photo.keepDecisionRaw
            return keepDecision == nil || keepDecision == "none"
        }
    }
    
    // MARK: - Background Refresh
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dailyReviewTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self?.handleBackgroundRefresh(refresh)
            }
        }
    }
    
    func scheduleBackgroundRefresh() {
        let settings = Task { await getSettings() }
        
        Task {
            let s = await settings.value
            guard s.isEnabled else { return }
            
            // Schedule refresh 1 hour before notification time
            var components = DateComponents()
            components.hour = (s.reviewHour - 1 + 24) % 24
            components.minute = s.reviewMinute
            
            let calendar = Calendar.current
            guard let nextDate = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else {
                return
            }
            
            let request = BGAppRefreshTaskRequest(identifier: Self.dailyReviewTaskIdentifier)
            request.earliestBeginDate = nextDate
            
            do {
                try BGTaskScheduler.shared.submit(request)
                print("[DailyReviewService] Scheduled background refresh for \(nextDate)")
            } catch {
                print("[DailyReviewService] Failed to schedule background refresh: \(error)")
            }
        }
    }
    
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await updateTodayCandidates()
            
            // Reschedule the notification with updated count
            await scheduleNotificationIfEnabled()
            
            // Schedule next background refresh
            scheduleBackgroundRefresh()
            
            task.setTaskCompleted(success: true)
        }
    }
    
    // MARK: - Handle Notification Response
    
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard response.notification.request.content.userInfo["type"] as? String == "dailyReview" else {
            return
        }
        
        // Post notification to open daily review
        NotificationCenter.default.post(
            name: .openDailyReview,
            object: nil
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openDailyReview = Notification.Name("openDailyReview")
}

final class MomentsNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MomentsNotificationDelegate()
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            DailyReviewService.shared.handleNotificationResponse(response)
            let info = response.notification.request.content.userInfo
            if info["type"] as? String == "newPhotoCheck" {
                NotificationCenter.default.post(name: .openNewPhotoCheck, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let openNewPhotoCheck = Notification.Name("openNewPhotoCheck")
}
