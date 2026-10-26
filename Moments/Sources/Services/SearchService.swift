// SearchService.swift
// Servicio de búsqueda local sobre el índice de fotos

import Foundation
import SwiftData

@MainActor
class SearchService: ObservableObject {
    private var modelContext: ModelContext?
    
    @Published var isSearching = false
    @Published var searchResults: [SearchResult] = []
    @Published var recentSearches: [String] = []
    
    // MARK: - Search Result
    
    struct SearchResult: Identifiable {
        let id: String
        let photo: PersistedPhoto
        let score: Double
        let matchedFields: [MatchedField]
        
        enum MatchedField: Hashable {
            case label(String)
            case ocr(String)
            case place(String)
            case date
            case person(String)
        }
    }
    
    // MARK: - Search Filters
    
    struct SearchFilters: Equatable {
        var dateRange: DateRange?
        var places: [String] = []
        var people: [String] = []
        var types: [PhotoType] = []
        var origins: [PhotoOrigin] = []
        
        enum DateRange: Equatable {
            case today
            case thisWeek
            case thisMonth
            case thisYear
            case year(Int)
            case custom(start: Date, end: Date)
        }
        
        enum PhotoType: String, CaseIterable {
            case photo = "image"
            case video = "video"
            case screenshot = "screenshot"
            case document = "document"
            case livePhoto = "livePhoto"
        }
        
        var isEmpty: Bool {
            dateRange == nil && places.isEmpty && people.isEmpty && types.isEmpty && origins.isEmpty
        }
    }
    
    // MARK: - Initialization
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadRecentSearches()
    }
    
    // MARK: - Search
    
    func search(query: String, filters: SearchFilters = SearchFilters()) async -> [SearchResult] {
        guard let context = modelContext else { return [] }
        guard !query.isEmpty || !filters.isEmpty else { return [] }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            // Fetch all analyzed photos
            let descriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.analysisCompleted }
            )
            
            var photos = try context.fetch(descriptor)
            
            // Apply filters first
            photos = applyFilters(photos, filters: filters)
            
            // If no query, just return filtered results
            if query.isEmpty {
                return photos.map { SearchResult(id: $0.id, photo: $0, score: 1.0, matchedFields: []) }
            }
            
            // Parse query for semantic search
            let searchTerms = parseQuery(query)
            
            // Score and rank results
            var results: [SearchResult] = []
            
            for photo in photos {
                let (score, matchedFields) = calculateMatchScore(photo: photo, searchTerms: searchTerms)
                if score > 0 {
                    results.append(SearchResult(id: photo.id, photo: photo, score: score, matchedFields: matchedFields))
                }
            }
            
            // Sort by score (highest first)
            results.sort { $0.score > $1.score }
            
            // Save to recent searches
            if !query.isEmpty {
                addRecentSearch(query)
            }
            
            return results
            
        } catch {
            print("Search error: \(error)")
            return []
        }
    }
    
    // MARK: - Query Parsing
    
    private func parseQuery(_ query: String) -> SearchTerms {
        var terms = SearchTerms()
        let lowercased = query.lowercased()
        
        // Check for origin patterns first
        let originPatterns: [(pattern: String, origin: PhotoOrigin)] = [
            ("whatsapp", .whatsapp),
            ("telegram", .telegram),
            ("instagram", .instagram),
            ("messenger", .messenger),
            ("snapchat", .snapchat),
            ("twitter", .twitter),
            ("tiktok", .tiktok),
            ("descargadas", .download),
            ("downloaded", .download),
            ("cámara", .camera),
            ("camera", .camera),
            ("captura", .screenshot),
            ("screenshot", .screenshot),
        ]
        
        for (pattern, origin) in originPatterns {
            if lowercased.contains(pattern) {
                terms.origins.append(origin)
            }
        }
        
        // Split by spaces but keep phrases in quotes
        let words = lowercased.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        for word in words {
            // Skip origin words already processed
            if originPatterns.contains(where: { word.contains($0.pattern) }) {
                continue
            }
            
            // Skip common prepositions
            if ["de", "del", "la", "las", "los", "from", "the", "fotos", "photos"].contains(word) {
                continue
            }
            
            // Check for year patterns (e.g., "2024")
            if let year = Int(word), year >= 1990 && year <= 2100 {
                terms.years.append(year)
                continue
            }
            
            // Check for month patterns
            if let month = parseMonth(word) {
                terms.months.append(month)
                continue
            }
            
            // Add as text term
            terms.textTerms.append(word)
        }
        
        return terms
    }
    
    private struct SearchTerms {
        var textTerms: [String] = []
        var years: [Int] = []
        var months: [Int] = []
        var origins: [PhotoOrigin] = []
    }
    
    private func parseMonth(_ word: String) -> Int? {
        let months: [String: Int] = [
            "enero": 1, "january": 1, "jan": 1,
            "febrero": 2, "february": 2, "feb": 2,
            "marzo": 3, "march": 3, "mar": 3,
            "abril": 4, "april": 4, "apr": 4,
            "mayo": 5, "may": 5,
            "junio": 6, "june": 6, "jun": 6,
            "julio": 7, "july": 7, "jul": 7,
            "agosto": 8, "august": 8, "aug": 8,
            "septiembre": 9, "september": 9, "sep": 9, "sept": 9,
            "octubre": 10, "october": 10, "oct": 10,
            "noviembre": 11, "november": 11, "nov": 11,
            "diciembre": 12, "december": 12, "dec": 12
        ]
        return months[word.lowercased()]
    }
    
    // MARK: - Scoring
    
    private func calculateMatchScore(photo: PersistedPhoto, searchTerms: SearchTerms) -> (Double, [SearchResult.MatchedField]) {
        var totalScore: Double = 0
        var matchedFields: [SearchResult.MatchedField] = []
        
        // Origin matching
        for origin in searchTerms.origins {
            if photo.origin == origin {
                totalScore += 15
                matchedFields.append(.label(origin.rawValue))
            }
        }
        
        // Date matching
        if let date = photo.creationDate {
            let calendar = Calendar.current
            let photoYear = calendar.component(.year, from: date)
            let photoMonth = calendar.component(.month, from: date)
            
            for year in searchTerms.years {
                if photoYear == year {
                    totalScore += 10
                    matchedFields.append(.date)
                }
            }
            
            for month in searchTerms.months {
                if photoMonth == month {
                    totalScore += 5
                    matchedFields.append(.date)
                }
            }
        }
        
        // Text matching
        for term in searchTerms.textTerms {
            // Labels match (including Spanish synonyms)
            if let labels = photo.visionLabels?.lowercased() {
                let labelArray = labels.components(separatedBy: "|")
                for label in labelArray {
                    if SpanishSynonyms.matches(query: term, label: label) || label.contains(term) {
                        totalScore += 8
                        matchedFields.append(.label(label))
                        break
                    }
                }
            }
            
            // OCR text match
            if let ocrText = photo.ocrText?.lowercased(), ocrText.contains(term) {
                totalScore += 6
                matchedFields.append(.ocr(term))
            }
            
            // Place name match
            if let placeName = photo.placeName?.lowercased(), placeName.contains(term) {
                totalScore += 7
                matchedFields.append(.place(placeName))
            }
            
            if let city = photo.placeCity?.lowercased(), city.contains(term) {
                totalScore += 6
                matchedFields.append(.place(city))
            }
            
            if let country = photo.placeCountry?.lowercased(), country.contains(term) {
                totalScore += 4
                matchedFields.append(.place(country))
            }
            
            // Camera model match
            if let camera = photo.cameraModel?.lowercased(), camera.contains(term) {
                totalScore += 5
                matchedFields.append(.label(camera))
            }
        }
        
        return (totalScore, matchedFields)
    }
    
    // MARK: - Filters
    
    private func applyFilters(_ photos: [PersistedPhoto], filters: SearchFilters) -> [PersistedPhoto] {
        var filtered = photos
        
        // Date filter
        if let dateRange = filters.dateRange {
            filtered = filtered.filter { photo in
                guard let date = photo.creationDate else { return false }
                return isDateInRange(date, range: dateRange)
            }
        }
        
        // Place filter
        if !filters.places.isEmpty {
            filtered = filtered.filter { photo in
                let photoPlace = [photo.placeName, photo.placeCity, photo.placeCountry]
                    .compactMap { $0?.lowercased() }
                
                return filters.places.contains { place in
                    photoPlace.contains { $0.contains(place.lowercased()) }
                }
            }
        }
        
        // Type filter
        if !filters.types.isEmpty {
            filtered = filtered.filter { photo in
                for type in filters.types {
                    switch type {
                    case .photo:
                        if photo.mediaTypeRaw == "image" && !photo.mediaSubtypesRaw.contains("screenshot") {
                            return true
                        }
                    case .video:
                        if photo.mediaTypeRaw == "video" {
                            return true
                        }
                    case .screenshot:
                        if photo.mediaSubtypesRaw.contains("screenshot") {
                            return true
                        }
                    case .document:
                        if photo.isDocument == true {
                            return true
                        }
                    case .livePhoto:
                        if photo.mediaSubtypesRaw.contains("livePhoto") {
                            return true
                        }
                    }
                }
                return false
            }
        }
        
        // Origin filter
        if !filters.origins.isEmpty {
            filtered = filtered.filter { photo in
                filters.origins.contains(photo.origin)
            }
        }
        
        return filtered
    }
    
    private func isDateInRange(_ date: Date, range: SearchFilters.DateRange) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        switch range {
        case .today:
            return calendar.isDateInToday(date)
        case .thisWeek:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .thisYear:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .year(let year):
            return calendar.component(.year, from: date) == year
        case .custom(let start, let end):
            return date >= start && date <= end
        }
    }
    
    // MARK: - Recent Searches
    
    private let recentSearchesKey = "recentSearches"
    private let maxRecentSearches = 10
    
    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }
    
    private func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        // Remove if already exists
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }
        
        // Add at the beginning
        recentSearches.insert(trimmed, at: 0)
        
        // Keep only last N
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }
    
    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }
}

// MARK: - Search Protocol for Future Embeddings

protocol EmbeddingSearchProvider {
    func generateQueryEmbedding(for text: String) async -> [Float]?
    func searchByEmbedding(_ embedding: [Float], limit: Int) async -> [String]
}
