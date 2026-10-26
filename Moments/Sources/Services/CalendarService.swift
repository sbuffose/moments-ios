// CalendarService.swift
// Servicio para integración con Calendario (EventKit)

import Foundation
import EventKit
import SwiftData

@MainActor
class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    private var modelContext: ModelContext?
    private let eventStore = EKEventStore()
    
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isAddingEvent = false
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    func requestAuthorization() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                checkAuthorizationStatus()
                return granted
            } catch {
                return false
            }
        } else {
            do {
                let granted = try await eventStore.requestAccess(to: .event)
                checkAuthorizationStatus()
                return granted
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Add Event
    
    func addToCalendar(importantDate: PersistedImportantDate) async -> Bool {
        let hasAccess: Bool
        if #available(iOS 17.0, *) {
            hasAccess = authorizationStatus == .fullAccess || authorizationStatus == .writeOnly
        } else {
            hasAccess = authorizationStatus == .authorized
        }
        if !hasAccess {
            let granted = await requestAuthorization()
            if !granted { return false }
        }
        
        isAddingEvent = true
        defer { isAddingEvent = false }
        
        let event = EKEvent(eventStore: eventStore)
        
        event.title = createEventTitle(for: importantDate)
        
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        var dateComponents = DateComponents()
        dateComponents.year = currentYear
        dateComponents.month = importantDate.month
        dateComponents.day = importantDate.day
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        guard var eventDate = calendar.date(from: dateComponents) else { return false }
        
        if eventDate < Date() {
            dateComponents.year = currentYear + 1
            guard let nextYearDate = calendar.date(from: dateComponents) else { return false }
            eventDate = nextYearDate
        }
        
        event.startDate = eventDate
        event.endDate = calendar.date(byAdding: .hour, value: 1, to: eventDate)
        event.isAllDay = true
        
        event.notes = createEventNotes(for: importantDate)
        
        let recurrenceRule = EKRecurrenceRule(
            recurrenceWith: .yearly,
            interval: 1,
            end: nil
        )
        event.addRecurrenceRule(recurrenceRule)
        
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        let leadDays = importantDate.notificationLeadDays > 0 ? importantDate.notificationLeadDays : 3
        let alarm = EKAlarm(relativeOffset: -Double(leadDays * 24 * 60 * 60))
        event.addAlarm(alarm)
        
        let dayOfAlarm = EKAlarm(relativeOffset: 0)
        event.addAlarm(dayOfAlarm)
        
        do {
            try eventStore.save(event, span: .futureEvents)
            
            await updateImportantDateWithEventId(dateId: importantDate.id, eventId: event.eventIdentifier)
            
            return true
        } catch {
            return false
        }
    }
    
    private func createEventTitle(for importantDate: PersistedImportantDate) -> String {
        let emoji = importantDate.dateType.notificationEmoji
        
        switch importantDate.dateType {
        case .birthday:
            let name = importantDate.personName ?? "Cumpleaños"
            return "\(emoji) Cumple de \(name)"
            
        case .wedding, .anniversary:
            let names = importantDate.displayName
            return "\(emoji) Aniversario de \(names)"
            
        case .childBirthday:
            let name = importantDate.personName ?? "Cumpleaños"
            return "\(emoji) Cumple de \(name)"
            
        case .other:
            return "\(emoji) \(importantDate.displayName)"
        }
    }
    
    private func createEventNotes(for importantDate: PersistedImportantDate) -> String {
        var notes: [String] = []
        
        notes.append("Agregado desde Moments")
        
        if let year = importantDate.year {
            switch importantDate.dateType {
            case .birthday, .childBirthday:
                notes.append("Año de nacimiento: \(year)")
            case .wedding, .anniversary:
                notes.append("Fecha de la boda: \(importantDate.displayDate)/\(year)")
            default:
                break
            }
        }
        
        return notes.joined(separator: "\n")
    }
    
    private func updateImportantDateWithEventId(dateId: String, eventId: String) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate<PersistedImportantDate> { $0.id == dateId }
        )
        
        if let date = try? context.fetch(descriptor).first {
            date.calendarEventId = eventId
            date.lastUpdatedAt = Date()
            try? context.save()
        }
    }
    
    // MARK: - Check if Event Exists
    
    func hasCalendarEvent(for importantDate: PersistedImportantDate) -> Bool {
        guard let eventId = importantDate.calendarEventId else { return false }
        return eventStore.event(withIdentifier: eventId) != nil
    }
    
    // MARK: - Remove Event
    
    func removeFromCalendar(importantDate: PersistedImportantDate) async -> Bool {
        guard let eventId = importantDate.calendarEventId,
              let event = eventStore.event(withIdentifier: eventId) else { return false }
        
        do {
            try eventStore.remove(event, span: .futureEvents)
            
            await updateImportantDateWithEventId(dateId: importantDate.id, eventId: "")
            
            return true
        } catch {
            return false
        }
    }
}

