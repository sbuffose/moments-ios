// MonthlyRecapService.swift
// Recap mensual "Tu mes en fotos"

import Foundation
import SwiftData
import UserNotifications

struct MonthlyRecap: Sendable {
    let month: Int
    let year: Int
    let monthName: String
    let photoCount: Int
    let placeCount: Int
    let narrative: String
    let photoIds: [String]
    
    var title: String { "Tu mes en fotos" }
    var subtitle: String { "Así fue tu \(monthName)" }
}

enum MonthlyRecapService {
    static let monthsES = [
        1: "enero", 2: "febrero", 3: "marzo", 4: "abril", 5: "mayo", 6: "junio",
        7: "julio", 8: "agosto", 9: "septiembre", 10: "octubre", 11: "noviembre", 12: "diciembre"
    ]
    static let notificationIdentifier = "monthly-recap"
    
    static func monthName(_ month: Int) -> String {
        monthsES[month] ?? "este mes"
    }
    
    static func photos(month: Int, year: Int, context: ModelContext) -> [PersistedPhoto] {
        let all = (try? context.fetch(FetchDescriptor<PersistedPhoto>())) ?? []
        return all.filter { photo in
            guard let date = photo.creationDate else { return false }
            let comps = Calendar.current.dateComponents([.month, .year], from: date)
            return comps.month == month && comps.year == year
        }
    }
    
    static func statsSummary(month: Int, year: Int, context: ModelContext?) -> String {
        guard let context else { return "sin datos" }
        let inMonth = photos(month: month, year: year, context: context)
        let places = Set(inMonth.compactMap { $0.placeCity })
        return "\(MomentsPluralization.photos(inMonth.count)), \(places.count) lugares"
    }
    
    static func fallbackNarrative(monthName: String, stats: String) -> String {
        "Así fue tu \(monthName): \(stats). Un mes para recordar."
    }
    
    static func generateRecap(month: Int, year: Int, context: ModelContext) async -> MonthlyRecap {
        let inMonth = photos(month: month, year: year, context: context)
        let stats = statsSummary(month: month, year: year, context: context)
        let name = monthName(month)
        let narrative = await FoundationModelsClient.recapNarrative(monthName: name, stats: stats)
            ?? fallbackNarrative(monthName: name, stats: stats)
        return MonthlyRecap(
            month: month,
            year: year,
            monthName: name,
            photoCount: inMonth.count,
            placeCount: Set(inMonth.compactMap { $0.placeCity }).count,
            narrative: narrative,
            photoIds: inMonth.prefix(12).map(\.localIdentifier)
        )
    }
    
    static func previousMonth(from date: Date = Date()) -> (month: Int, year: Int) {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.month, .year], from: date)
        var month = (comps.month ?? 1) - 1
        var year = comps.year ?? 2026
        if month <= 0 {
            month = 12
            year -= 1
        }
        return (month, year)
    }
    
    static func scheduleFirstOfMonthNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        let content = UNMutableNotificationContent()
        content.title = "Tu mes en fotos"
        content.body = "Ya está listo el recap del mes pasado"
        content.sound = .default
        content.userInfo = ["type": "monthlyRecap"]
        var components = DateComponents()
        components.day = 1
        components.hour = 10
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
