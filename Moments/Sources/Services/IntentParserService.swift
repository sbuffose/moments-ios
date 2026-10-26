// IntentParserService.swift
// Parse natural language requests into structured intents using on-device AI

import Foundation
import NaturalLanguage
import SwiftData

// MARK: - Intent Types

enum MomentsIntent: Sendable {
    case search(query: String, filters: SearchFilters)
    case cleanup(category: CleanupCategoryType?, olderThan: Date?)
    case showDate(personName: String?)
    case showUpcomingDates
    case checkSpace
    case createMemory(query: String)
    case showPhotos(location: String?, date: DateInterval?, people: [String]?)
    case showPerson(name: String)
    case unknown(text: String)
    
    struct SearchFilters: Sendable {
        var dateRange: DateInterval?
        var location: String?
        var people: [String]?
        var mediaType: String?
    }
}

// MARK: - Intent Parser Service

@MainActor
class IntentParserService: ObservableObject {
    static let shared = IntentParserService()
    
    private var modelContext: ModelContext?
    private var useFoundationModels = false
    
    @Published var isProcessing = false
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        checkFoundationModelsAvailability()
    }
    
    // MARK: - Foundation Models Availability
    
    private func checkFoundationModelsAvailability() {
        // Check for iOS 26+ and Apple Intelligence availability
        // Foundation Models framework with SystemLanguageModel
        if #available(iOS 26, *) {
            // Would use: SystemLanguageModel.default.availability
            // For now, we'll use a runtime check
            useFoundationModels = checkAppleIntelligenceAvailable()
        } else {
            useFoundationModels = false
        }
    }
    
    private func checkAppleIntelligenceAvailable() -> Bool {
        // Runtime check for Apple Intelligence availability
        // This would be: SystemLanguageModel.default.availability != .unavailable
        // For iOS 17-25 compatibility, return false
        return false
    }
    
    // MARK: - Parse Intent
    
    func parseIntent(_ text: String) async -> MomentsIntent {
        isProcessing = true
        defer { isProcessing = false }
        
        let normalizedText = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
        
        // Try Foundation Models first if available
        if useFoundationModels {
            if let intent = await parseWithFoundationModels(text) {
                return intent
            }
        }
        
        // Fallback to rule-based parsing
        return parseWithRules(normalizedText, originalText: text)
    }
    
    // MARK: - Foundation Models Parsing (iOS 26+)
    
    @available(iOS 26, *)
    private func parseWithFoundationModels(_ text: String) async -> MomentsIntent? {
        // This would use @Generable and tool calling:
        // let session = SystemLanguageModel.default.session
        // let result = try await session.generate(prompt, tools: [searchTool, cleanupTool, ...])
        
        // For now, return nil to fall back to rule-based
        return nil
    }
    
    // MARK: - Rule-Based Parsing (iOS 17+)
    
    private func parseWithRules(_ text: String, originalText: String) -> MomentsIntent {
        // Cleanup patterns
        if matchesCleanupIntent(text) {
            return parseCleanupIntent(text)
        }
        
        // Date/birthday patterns
        if matchesDateIntent(text) {
            return parseDateIntent(text, originalText: originalText)
        }
        
        // Space check patterns
        if matchesSpaceIntent(text) {
            return .checkSpace
        }
        
        // Memory creation patterns
        if matchesMemoryIntent(text) {
            return parseMemoryIntent(text, originalText: originalText)
        }
        
        // Photo search patterns
        if matchesSearchIntent(text) {
            return parseSearchIntent(text, originalText: originalText)
        }
        
        // Person search
        if matchesPersonIntent(text) {
            return parsePersonIntent(text, originalText: originalText)
        }
        
        // Default to search
        return .search(query: originalText, filters: MomentsIntent.SearchFilters())
    }
    
    // MARK: - Pattern Matchers
    
    private func matchesCleanupIntent(_ text: String) -> Bool {
        let patterns = [
            "borra", "elimina", "limpia", "delete", "clean",
            "capturas", "screenshots", "duplicados", "borrosas",
            "libera", "liberar", "espacio"
        ]
        return patterns.contains { text.contains($0) }
    }
    
    private func matchesDateIntent(_ text: String) -> Bool {
        let patterns = [
            "cumple", "cumpleanos", "birthday", "aniversario",
            "cuando es", "fecha", "proximas fechas", "fechas"
        ]
        return patterns.contains { text.contains($0) }
    }
    
    private func matchesSpaceIntent(_ text: String) -> Bool {
        let patterns = [
            "cuanto espacio", "espacio puedo liberar", "cuantos gb",
            "cuanta memoria", "how much space"
        ]
        return patterns.contains { text.contains($0) }
    }
    
    private func matchesMemoryIntent(_ text: String) -> Bool {
        let patterns = [
            "armame", "creame", "hazme", "genera", "armar",
            "recuerdo", "memoria", "memory", "resumen"
        ]
        return patterns.contains { text.contains($0) }
    }
    
    private func matchesSearchIntent(_ text: String) -> Bool {
        let patterns = [
            "mostrame", "busca", "encuentra", "fotos de",
            "show me", "search", "find", "donde esta"
        ]
        return patterns.contains { text.contains($0) }
    }
    
    private func matchesPersonIntent(_ text: String) -> Bool {
        let patterns = [
            "quien es", "fotos de", "fotos con"
        ]
        return patterns.contains { text.contains($0) }
    }
    
    // MARK: - Intent Parsers
    
    private func parseCleanupIntent(_ text: String) -> MomentsIntent {
        var category: CleanupCategoryType?
        var olderThan: Date?
        
        // Category detection
        if text.contains("captura") || text.contains("screenshot") {
            category = .screenshot
        } else if text.contains("duplicad") {
            category = .duplicate
        } else if text.contains("borrosa") || text.contains("blurry") {
            category = .blurry
        } else if text.contains("video") {
            category = .largeVideo
        } else if text.contains("documento") || text.contains("recibo") {
            category = .document
        }
        
        // Time detection
        if let months = extractMonths(from: text) {
            olderThan = Calendar.current.date(byAdding: .month, value: -months, to: Date())
        } else if let days = extractDays(from: text) {
            olderThan = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        }
        
        return .cleanup(category: category, olderThan: olderThan)
    }
    
    private func parseDateIntent(_ text: String, originalText: String) -> MomentsIntent {
        // Check if asking about upcoming dates
        if text.contains("proximas") || text.contains("upcoming") || text.contains("proximos") {
            return .showUpcomingDates
        }
        
        // Extract person name
        let personName = extractPersonName(from: originalText)
        return .showDate(personName: personName)
    }
    
    private func parseMemoryIntent(_ text: String, originalText: String) -> MomentsIntent {
        // Extract the query part
        let query = extractMemoryQuery(from: originalText)
        return .createMemory(query: query)
    }
    
    private func parseSearchIntent(_ text: String, originalText: String) -> MomentsIntent {
        var filters = MomentsIntent.SearchFilters()
        var query = originalText
        
        // Extract location
        if let location = extractLocation(from: originalText) {
            filters.location = location
            query = query.replacingOccurrences(of: location, with: "").trimmingCharacters(in: .whitespaces)
        }
        
        // Extract year
        if let year = extractYear(from: text) {
            let calendar = Calendar.current
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
            filters.dateRange = DateInterval(start: start, end: end)
        }
        
        // Extract people
        if let people = extractPeopleNames(from: originalText) {
            filters.people = people
        }
        
        return .search(query: query, filters: filters)
    }
    
    private func parsePersonIntent(_ text: String, originalText: String) -> MomentsIntent {
        if let name = extractPersonName(from: originalText) {
            return .showPerson(name: name)
        }
        return .unknown(text: originalText)
    }
    
    // MARK: - Extraction Helpers
    
    private func extractMonths(from text: String) -> Int? {
        let patterns = [
            "\\d+\\s*mes(es)?",
            "(un|dos|tres|cuatro|cinco|seis)\\s*mes(es)?"
        ]
        
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                if let number = Int(match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    return number
                }
                // Handle Spanish words
                let wordToNum = ["un": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6]
                for (word, num) in wordToNum {
                    if match.contains(word) { return num }
                }
            }
        }
        return nil
    }
    
    private func extractDays(from text: String) -> Int? {
        let pattern = "\\d+\\s*dia(s)?"
        if let range = text.range(of: pattern, options: .regularExpression) {
            let match = String(text[range])
            return Int(match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
        }
        return nil
    }
    
    private func extractYear(from text: String) -> Int? {
        let pattern = "20\\d{2}"
        if let range = text.range(of: pattern, options: .regularExpression) {
            return Int(String(text[range]))
        }
        return nil
    }
    
    private func extractLocation(from text: String) -> String? {
        // Common Argentine locations and patterns
        let locationPatterns = [
            "bariloche", "mendoza", "cordoba", "rosario", "mar del plata",
            "buenos aires", "ushuaia", "salta", "iguazu", "calafate"
        ]
        
        let normalized = text.lowercased()
        for location in locationPatterns {
            if normalized.contains(location) {
                return location.capitalized
            }
        }
        
        // Try to extract "en [Location]" or "de [Location]"
        let patterns = ["en\\s+([A-Z][a-záéíóúñ]+)", "de\\s+([A-Z][a-záéíóúñ]+)"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        
        return nil
    }
    
    private func extractPersonName(from text: String) -> String? {
        // Remove common prefixes
        var cleaned = text
        let prefixes = [
            "cuando es el cumple de", "cuando cumple", "cumpleaños de",
            "cumple de", "fotos de", "fotos con", "quien es"
        ]
        
        for prefix in prefixes {
            if let range = cleaned.lowercased().range(of: prefix) {
                cleaned = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Extract capitalized name
        let words = cleaned.split(separator: " ")
        for word in words {
            let str = String(word)
            if str.first?.isUppercase == true && str.count > 1 {
                return str
            }
        }
        
        // Return first word if nothing else
        return words.first.map(String.init)
    }
    
    private func extractPeopleNames(from text: String) -> [String]? {
        // Look for "con [Name] y [Name]" patterns
        let pattern = "con\\s+([A-Z][a-záéíóúñ]+)(?:\\s+y\\s+([A-Z][a-záéíóúñ]+))?"
        
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            var names: [String] = []
            
            for i in 1..<match.numberOfRanges {
                if let range = Range(match.range(at: i), in: text) {
                    names.append(String(text[range]))
                }
            }
            
            return names.isEmpty ? nil : names
        }
        
        return nil
    }
    
    private func extractMemoryQuery(from text: String) -> String {
        let prefixes = [
            "armame un recuerdo de", "creame un recuerdo de",
            "hazme un resumen de", "genera un recuerdo de",
            "armame", "creame", "hazme"
        ]
        
        var cleaned = text
        for prefix in prefixes {
            if let range = cleaned.lowercased().range(of: prefix) {
                cleaned = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        return cleaned
    }
}

// MARK: - Memory Title Generator

@MainActor
class MemoryTitleGenerator {
    static let shared = MemoryTitleGenerator()
    
    func generateTitle(for photos: [PersistedPhoto]) async -> String {
        guard !photos.isEmpty else { return "Recuerdos" }
        
        // Collect context
        var locations: [String] = []
        var dates: [Date] = []
        var people: Set<String> = []
        
        for photo in photos {
            if let city = photo.placeCity { locations.append(city) }
            if let date = photo.creationDate { dates.append(date) }
        }
        
        // Build title
        var parts: [String] = []
        
        // Time context
        if let firstDate = dates.min(), let lastDate = dates.max() {
            let calendar = Calendar.current
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_AR")
            
            if calendar.isDate(firstDate, equalTo: lastDate, toGranularity: .day) {
                formatter.dateFormat = "d 'de' MMMM"
                parts.append(formatter.string(from: firstDate))
            } else if calendar.isDate(firstDate, equalTo: lastDate, toGranularity: .month) {
                formatter.dateFormat = "MMMM yyyy"
                parts.append(formatter.string(from: firstDate))
            } else {
                formatter.dateFormat = "MMMM"
                parts.append("Desde \(formatter.string(from: firstDate))")
            }
        }
        
        // Location
        if let mostCommon = locations.mostFrequent() {
            parts.insert("en \(mostCommon)", at: 0)
        }
        
        return parts.isEmpty ? "Recuerdos" : parts.joined(separator: " ")
    }
    
    func generateSummary(for photos: [PersistedPhoto]) async -> String {
        guard !photos.isEmpty else { return "" }
        
        let photoCount = photos.count
        let videoCount = photos.filter { $0.mediaTypeRaw == "video" }.count
        let peopleCount = Set(photos.compactMap { $0.faceDetections?.first?.clusterId }).count
        
        var parts: [String] = []
        
        if photoCount > 0 {
            parts.append("\(photoCount) foto\(photoCount == 1 ? "" : "s")")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) video\(videoCount == 1 ? "" : "s")")
        }
        if peopleCount > 0 {
            parts.append("\(peopleCount) persona\(peopleCount == 1 ? "" : "s")")
        }
        
        return parts.joined(separator: " · ")
    }
}

// MARK: - Array Extension

extension Array where Element: Hashable {
    func mostFrequent() -> Element? {
        let counts = self.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
