// NotificationService.swift
// Servicio para notificaciones locales de fechas importantes

import Foundation
import UserNotifications
import SwiftData

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    private var modelContext: ModelContext?
    private let notificationCenter = UNUserNotificationCenter.current()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var settings: NotificationSettings = NotificationSettings()
    
    struct NotificationSettings {
        var enabled: Bool = false
        var defaultLeadDays: Int = 3
        var notifyOnDay: Bool = true
        var notifyBirthdays: Bool = true
        var notifyAnniversaries: Bool = true
        var notifyChildBirthdays: Bool = true
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await checkAuthorizationStatus()
            await loadSettings()
        }
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            
            if granted {
                await enableNotifications()
            }
            
            return granted
        } catch {
            return false
        }
    }
    
    // MARK: - Settings Management
    
    func loadSettings() async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedNotificationSettings>(
            predicate: #Predicate { $0.id == "main" }
        )
        
        if let persisted = try? context.fetch(descriptor).first {
            settings = NotificationSettings(
                enabled: persisted.notificationsEnabled,
                defaultLeadDays: persisted.defaultLeadDays,
                notifyOnDay: persisted.notifyOnDay,
                notifyBirthdays: persisted.notifyBirthdays,
                notifyAnniversaries: persisted.notifyAnniversaries,
                notifyChildBirthdays: persisted.notifyChildBirthdays
            )
        }
    }
    
    func saveSettings() async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedNotificationSettings>(
            predicate: #Predicate { $0.id == "main" }
        )
        
        let persisted: PersistedNotificationSettings
        if let existing = try? context.fetch(descriptor).first {
            persisted = existing
        } else {
            persisted = PersistedNotificationSettings()
            context.insert(persisted)
        }
        
        persisted.notificationsEnabled = settings.enabled
        persisted.defaultLeadDays = settings.defaultLeadDays
        persisted.notifyOnDay = settings.notifyOnDay
        persisted.notifyBirthdays = settings.notifyBirthdays
        persisted.notifyAnniversaries = settings.notifyAnniversaries
        persisted.notifyChildBirthdays = settings.notifyChildBirthdays
        
        try? context.save()
        
        if settings.enabled {
            await scheduleAllNotifications()
        } else {
            await cancelAllNotifications()
        }
    }
    
    func enableNotifications() async {
        settings.enabled = true
        await saveSettings()
    }
    
    func disableNotifications() async {
        settings.enabled = false
        await saveSettings()
    }
    
    func updateLeadDays(_ days: Int) async {
        settings.defaultLeadDays = max(0, min(days, 30))
        await saveSettings()
    }
    
    // MARK: - Schedule Notifications
    
    func scheduleAllNotifications() async {
        guard authorizationStatus == .authorized && settings.enabled else { return }
        guard let context = modelContext else { return }
        
        await cancelAllNotifications()
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate { $0.isUserConfirmed && !$0.isDismissed && $0.notificationEnabled }
        )
        
        let dates = (try? context.fetch(descriptor)) ?? []
        
        for date in dates {
            await scheduleNotifications(for: date)
        }
    }
    
    func scheduleNotifications(for importantDate: PersistedImportantDate) async {
        guard authorizationStatus == .authorized && settings.enabled else { return }
        
        let shouldNotify: Bool
        switch importantDate.dateType {
        case .birthday:
            shouldNotify = settings.notifyBirthdays
        case .anniversary, .wedding:
            shouldNotify = settings.notifyAnniversaries
        case .childBirthday:
            shouldNotify = settings.notifyChildBirthdays
        case .other:
            shouldNotify = true
        }
        
        guard shouldNotify else { return }
        
        let leadDays = importantDate.notificationLeadDays > 0 ? importantDate.notificationLeadDays : settings.defaultLeadDays
        
        if leadDays > 0 {
            await scheduleLeadNotification(for: importantDate, daysBefore: leadDays)
        }
        
        if settings.notifyOnDay {
            await scheduleOnDayNotification(for: importantDate)
        }
    }
    
    private func scheduleLeadNotification(for importantDate: PersistedImportantDate, daysBefore: Int) async {
        let identifier = "lead_\(importantDate.id)"
        
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        var dateComponents = DateComponents()
        dateComponents.month = importantDate.month
        dateComponents.day = importantDate.day
        dateComponents.year = currentYear
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        guard var eventDate = calendar.date(from: dateComponents) else { return }
        
        if eventDate < Date() {
            dateComponents.year = currentYear + 1
            guard let nextYearDate = calendar.date(from: dateComponents) else { return }
            eventDate = nextYearDate
        }
        
        guard let notificationDate = calendar.date(byAdding: .day, value: -daysBefore, to: eventDate) else { return }
        
        if notificationDate < Date() { return }
        
        let content = createLeadNotificationContent(for: importantDate, daysBefore: daysBefore)
        
        var triggerComponents = calendar.dateComponents([.month, .day, .hour, .minute], from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        try? await notificationCenter.add(request)
    }
    
    private func scheduleOnDayNotification(for importantDate: PersistedImportantDate) async {
        let identifier = "day_\(importantDate.id)"
        
        var dateComponents = DateComponents()
        dateComponents.month = importantDate.month
        dateComponents.day = importantDate.day
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        let content = createOnDayNotificationContent(for: importantDate)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        try? await notificationCenter.add(request)
    }
    
    // MARK: - Notification Content
    
    private func createLeadNotificationContent(for importantDate: PersistedImportantDate, daysBefore: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let emoji = importantDate.dateType.notificationEmoji
        
        let daysText = daysBefore == 1 ? "mañana" : "en \(daysBefore) días"
        
        switch importantDate.dateType {
        case .birthday, .friendBirthday:
            let name = importantDate.personName ?? "Alguien"
            if let age = calculateUpcomingAge(for: importantDate) {
                content.title = "\(emoji) Cumple \(daysText)"
                content.body = "\(name) cumple \(age) años el \(importantDate.displayDate)"
            } else {
                content.title = "\(emoji) Cumple \(daysText)"
                content.body = "Cumpleaños de \(name) el \(importantDate.displayDate)"
            }
            
        case .wedding, .anniversary:
            let names = importantDate.displayName
            if let years = importantDate.anniversaryYear {
                let nextYears = years + 1
                content.title = "\(emoji) Aniversario \(daysText)"
                content.body = "\(nextYears)º aniversario de \(names) el \(importantDate.displayDate)"
            } else {
                content.title = "\(emoji) Aniversario \(daysText)"
                content.body = "Aniversario de \(names) el \(importantDate.displayDate)"
            }
            
        case .childBirthday:
            let name = importantDate.personName ?? "Alguien"
            if let age = calculateUpcomingAge(for: importantDate) {
                content.title = "\(emoji) Cumple \(daysText)"
                content.body = "\(name) cumple \(age) años el \(importantDate.displayDate)"
            } else {
                content.title = "\(emoji) Cumple \(daysText)"
                content.body = "Cumpleaños de \(name) el \(importantDate.displayDate)"
            }
            
        case .other:
            content.title = "\(emoji) Evento \(daysText)"
            content.body = "\(importantDate.displayName) el \(importantDate.displayDate)"
        }
        
        content.sound = .default
        content.categoryIdentifier = "IMPORTANT_DATE"
        content.userInfo = ["dateId": importantDate.id]
        
        return content
    }
    
    private func createOnDayNotificationContent(for importantDate: PersistedImportantDate) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let emoji = importantDate.dateType.notificationEmoji
        
        switch importantDate.dateType {
        case .birthday, .friendBirthday:
            let name = importantDate.personName ?? "Alguien"
            if let age = calculateUpcomingAge(for: importantDate) {
                content.title = "\(emoji) ¡Feliz cumple!"
                content.body = "¡Hoy \(name) cumple \(age) años! 🎉"
            } else {
                content.title = "\(emoji) ¡Feliz cumple!"
                content.body = "¡Hoy es el cumpleaños de \(name)! 🎉"
            }
            
        case .wedding, .anniversary:
            let names = importantDate.displayName
            if let years = importantDate.anniversaryYear {
                let currentYears = years + 1
                content.title = "\(emoji) ¡Feliz aniversario!"
                content.body = "¡Hoy \(names) celebran \(currentYears) años! 💕"
            } else {
                content.title = "\(emoji) ¡Feliz aniversario!"
                content.body = "¡Hoy es el aniversario de \(names)! 💕"
            }
            
        case .childBirthday:
            let name = importantDate.personName ?? "Alguien"
            if let age = calculateUpcomingAge(for: importantDate) {
                content.title = "\(emoji) ¡Feliz cumple!"
                content.body = "¡Hoy \(name) cumple \(age) años! 🎈"
            } else {
                content.title = "\(emoji) ¡Feliz cumple!"
                content.body = "¡Hoy es el cumpleaños de \(name)! 🎈"
            }
            
        case .other:
            content.title = "\(emoji) Evento de hoy"
            content.body = importantDate.displayName
        }
        
        content.sound = .default
        content.categoryIdentifier = "IMPORTANT_DATE_TODAY"
        content.userInfo = ["dateId": importantDate.id]
        
        return content
    }
    
    private func calculateUpcomingAge(for importantDate: PersistedImportantDate) -> Int? {
        guard let birthYear = importantDate.year else { return nil }
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        var ageThisYear = currentYear - birthYear
        
        let currentMonth = calendar.component(.month, from: Date())
        let currentDay = calendar.component(.day, from: Date())
        
        if importantDate.month < currentMonth ||
           (importantDate.month == currentMonth && importantDate.day < currentDay) {
            ageThisYear += 1
        }
        
        return ageThisYear
    }
    
    // MARK: - Cancel Notifications
    
    func cancelAllNotifications() async {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    func cancelNotifications(for dateId: String) {
        let identifiers = ["lead_\(dateId)", "day_\(dateId)"]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    // MARK: - Enable/Disable for Specific Date
    
    func enableNotification(for dateId: String) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate<PersistedImportantDate> { $0.id == dateId }
        )
        
        if let date = try? context.fetch(descriptor).first {
            date.notificationEnabled = true
            date.lastUpdatedAt = Date()
            try? context.save()
            
            await scheduleNotifications(for: date)
        }
    }
    
    func disableNotification(for dateId: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate<PersistedImportantDate> { $0.id == dateId }
        )
        
        if let date = try? context.fetch(descriptor).first {
            date.notificationEnabled = false
            date.lastUpdatedAt = Date()
            try? context.save()
            
            cancelNotifications(for: dateId)
        }
    }
    
    func updateLeadDays(for dateId: String, days: Int) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate<PersistedImportantDate> { $0.id == dateId }
        )
        
        if let date = try? context.fetch(descriptor).first {
            date.notificationLeadDays = days
            date.lastUpdatedAt = Date()
            try? context.save()
            
            cancelNotifications(for: dateId)
            await scheduleNotifications(for: date)
        }
    }
}
