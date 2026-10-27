// MonthlyRecapService.swift
// Recap mensual "Tu mes en fotos"

import Foundation
import SwiftData

enum MonthlyRecapService {
    static let monthsES = [
        1: "enero", 2: "febrero", 3: "marzo", 4: "abril", 5: "mayo", 6: "junio",
        7: "julio", 8: "agosto", 9: "septiembre", 10: "octubre", 11: "noviembre", 12: "diciembre"
    ]
    
    static func monthName(_ month: Int) -> String {
        monthsES[month] ?? "este mes"
    }
    
    static func statsSummary(month: Int, year: Int, context: ModelContext?) -> String {
        guard let context else { return "sin datos" }
        let photos = (try? context.fetch(FetchDescriptor<PersistedPhoto>())) ?? []
        let inMonth = photos.filter { photo in
            guard let date = photo.creationDate else { return false }
            let comps = Calendar.current.dateComponents([.month, .year], from: date)
            return comps.month == month && comps.year == year
        }
        let people = Set(inMonth.compactMap { $0.placeCity })
        return "\(inMonth.count) fotos, \(people.count) lugares"
    }
    
    static func fallbackNarrative(monthName: String, stats: String) -> String {
        "Así fue tu \(monthName): \(stats). Un mes para recordar."
    }
}
