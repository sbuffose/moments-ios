// PhotoSearchService.swift
// Natural language photo search with Vision labels, OCR, feature-print similarity

import Foundation
import SwiftData
import Vision
import NaturalLanguage

@MainActor
class PhotoSearchService: ObservableObject {
    static let shared = PhotoSearchService()
    
    private var modelContext: ModelContext?
    
    @Published var isSearching = false
    @Published var lastQuery: String = ""
    @Published var activeFilters: SearchFilters = SearchFilters()
    
    struct SearchFilters: Equatable {
        var people: [String] = []
        var places: [String] = []
        var dateRange: DateInterval?
        var sceneLabels: [String] = []
        var textInImage: String?
        var mediaType: MediaTypeFilter = .all
        var origin: PhotoOrigin = .all
        
        enum MediaTypeFilter: String, CaseIterable {
            case all = "todos"
            case photos = "fotos"
            case videos = "videos"
            case screenshots = "capturas"
            case livePhotos = "live"
        }
        
        enum PhotoOrigin: String, CaseIterable {
            case all = "todos"
            case camera = "cámara"
            case messaging = "mensajes"
            case downloaded = "descargado"
        }
        
        var isEmpty: Bool {
            people.isEmpty && places.isEmpty && dateRange == nil &&
            sceneLabels.isEmpty && textInImage == nil &&
            mediaType == .all && origin == .all
        }
    }
    
    struct SearchResult {
        let photos: [PersistedPhoto]
        let query: String
        let filters: SearchFilters
        let refinementChips: [RefinementChip]
        
        struct RefinementChip: Identifiable {
            let id = UUID()
            let type: ChipType
            let value: String
            let count: Int
            
            enum ChipType {
                case person
                case place
                case date
                case type
            }
        }
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Main Search
    
    func search(query: String, filters: SearchFilters = SearchFilters()) async -> SearchResult {
        guard let context = modelContext else {
            return SearchResult(photos: [], query: query, filters: filters, refinementChips: [])
        }
        
        isSearching = true
        lastQuery = query
        activeFilters = filters
        defer { isSearching = false }
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted }
        )
        
        guard let allPhotos = try? context.fetch(descriptor) else {
            return SearchResult(photos: [], query: query, filters: filters, refinementChips: [])
        }
        
        var results = allPhotos
        
        // Parse query into terms with Spanish synonyms
        let queryTerms = parseQueryTerms(query)
        
        // Apply filters
        results = applyFilters(results, filters: filters, queryTerms: queryTerms)
        
        // Score and rank results
        results = rankResults(results, query: query, queryTerms: queryTerms)
        
        // Generate refinement chips from results
        let chips = generateRefinementChips(from: results)
        
        return SearchResult(
            photos: results,
            query: query,
            filters: filters,
            refinementChips: chips
        )
    }
    
    // MARK: - Query Parsing with Spanish Synonyms
    
    private func parseQueryTerms(_ query: String) -> [String] {
        let normalized = query.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
        
        var terms = normalized
            .components(separatedBy: CharacterSet.whitespaces.union(.punctuationCharacters))
            .filter { !$0.isEmpty && !spanishStopWords.contains($0) }
        
        // Expand synonyms
        var expandedTerms = Set<String>()
        for term in terms {
            expandedTerms.insert(term)
            if let synonyms = spanishSceneSynonyms[term] {
                expandedTerms.formUnion(synonyms)
            }
        }
        
        return Array(expandedTerms)
    }
    
    private let spanishStopWords: Set<String> = [
        "de", "la", "el", "en", "con", "y", "a", "los", "las", "un", "una",
        "del", "al", "es", "que", "por", "para", "se", "su", "sus", "mi", "mis",
        "fotos", "foto", "imagen", "imagenes", "mostrame", "busca", "encuentra"
    ]
    
    private let spanishSceneSynonyms: [String: Set<String>] = [
        // Beach / Playa
        "playa": ["beach", "mar", "ocean", "costa", "arena", "sand", "shore", "waterfront"],
        "beach": ["playa", "mar", "ocean", "costa", "arena"],
        "mar": ["sea", "ocean", "playa", "beach", "agua", "water"],
        
        // Mountain / Montaña
        "montaña": ["mountain", "cerro", "sierra", "peak", "hill", "cordillera"],
        "mountain": ["montaña", "cerro", "sierra", "peak"],
        "cerro": ["montaña", "mountain", "hill"],
        
        // Food / Comida
        "comida": ["food", "meal", "restaurant", "cena", "almuerzo", "dinner", "lunch"],
        "food": ["comida", "meal", "restaurant", "eating"],
        "cena": ["dinner", "comida", "food", "restaurant", "evening meal"],
        "almuerzo": ["lunch", "comida", "food", "midday meal"],
        "restaurant": ["restaurante", "comida", "food", "dining"],
        
        // Party / Fiesta
        "fiesta": ["party", "celebration", "evento", "cumpleaños", "birthday"],
        "party": ["fiesta", "celebration", "event"],
        "cumple": ["birthday", "cumpleaños", "fiesta", "party", "celebration"],
        "cumpleaños": ["birthday", "cumple", "fiesta", "party", "cake"],
        
        // Family
        "familia": ["family", "familias", "parientes", "relatives"],
        "family": ["familia", "relatives"],
        
        // Travel
        "viaje": ["travel", "trip", "vacation", "vacaciones", "holiday", "journey"],
        "vacaciones": ["vacation", "holiday", "viaje", "travel"],
        "trip": ["viaje", "travel", "vacation"],
        
        // Nature / Naturaleza
        "naturaleza": ["nature", "outdoor", "landscape", "paisaje", "bosque", "forest"],
        "nature": ["naturaleza", "outdoor", "landscape"],
        "bosque": ["forest", "woods", "trees", "naturaleza", "nature"],
        
        // City / Ciudad
        "ciudad": ["city", "urban", "downtown", "centro", "edificio"],
        "city": ["ciudad", "urban", "downtown"],
        
        // Night / Noche
        "noche": ["night", "nighttime", "evening", "nocturno", "dark"],
        "night": ["noche", "nighttime", "evening"],
        
        // Pet / Mascota
        "mascota": ["pet", "animal", "perro", "dog", "gato", "cat"],
        "perro": ["dog", "mascota", "pet", "puppy", "canine"],
        "dog": ["perro", "mascota", "pet", "puppy"],
        "gato": ["cat", "mascota", "pet", "kitten", "feline"],
        "cat": ["gato", "mascota", "pet", "kitten"],
        
        // Document / Documento
        "documento": ["document", "paper", "recibo", "receipt", "factura", "invoice"],
        "recibo": ["receipt", "documento", "document", "bill", "factura"],
        "captura": ["screenshot", "screen capture", "pantalla"],
        "screenshot": ["captura", "screen capture", "pantalla"],
        
        // Sports / Deportes
        "deporte": ["sport", "sports", "atletico", "athletic", "juego", "game"],
        "futbol": ["soccer", "football", "deporte", "sport"],
        "soccer": ["futbol", "football", "sport"],
        
        // Wedding / Boda
        "boda": ["wedding", "casamiento", "matrimonio", "marriage"],
        "wedding": ["boda", "casamiento", "matrimonio"],
        
        // Baby / Bebé
        "bebe": ["baby", "infant", "recien nacido", "newborn"],
        "baby": ["bebe", "infant", "newborn"],
        
        // Sunset / Atardecer
        "atardecer": ["sunset", "dusk", "evening sky", "puesta de sol"],
        "sunset": ["atardecer", "dusk", "puesta de sol"],
        
        // Sunrise / Amanecer
        "amanecer": ["sunrise", "dawn", "morning sky", "salida del sol"],
        "sunrise": ["amanecer", "dawn", "morning"]
    ]
    
    // MARK: - Filtering
    
    private func applyFilters(_ photos: [PersistedPhoto], filters: SearchFilters, queryTerms: [String]) -> [PersistedPhoto] {
        var results = photos
        
        // Filter by people
        if !filters.people.isEmpty {
            results = results.filter { photo in
                guard let faceDetections = photo.faceDetections else { return false }
                return faceDetections.contains { face in
                    filters.people.contains { personName in
                        face.personName?.lowercased().contains(personName.lowercased()) ?? false
                    }
                }
            }
        }
        
        // Filter by places
        if !filters.places.isEmpty {
            results = results.filter { photo in
                for place in filters.places {
                    let placeLower = place.lowercased()
                    if (photo.placeCity?.lowercased().contains(placeLower) ?? false) ||
                       (photo.placeName?.lowercased().contains(placeLower) ?? false) ||
                       (photo.placeCountry?.lowercased().contains(placeLower) ?? false) {
                        return true
                    }
                }
                return false
            }
        }
        
        // Filter by date range
        if let dateRange = filters.dateRange {
            results = results.filter { photo in
                guard let date = photo.creationDate else { return false }
                return dateRange.contains(date)
            }
        }
        
        // Filter by scene labels
        if !filters.sceneLabels.isEmpty {
            results = results.filter { photo in
                let labels = photo.visionLabels ?? []
                return filters.sceneLabels.contains { label in
                    labels.contains { $0.lowercased().contains(label.lowercased()) }
                }
            }
        }
        
        // Filter by text in image (OCR)
        if let textQuery = filters.textInImage, !textQuery.isEmpty {
            results = results.filter { photo in
                photo.ocrText?.lowercased().contains(textQuery.lowercased()) ?? false
            }
        }
        
        // Filter by media type
        switch filters.mediaType {
        case .all:
            break
        case .photos:
            results = results.filter { $0.mediaTypeRaw == "image" && $0.sourceTypeRaw != "screenshot" }
        case .videos:
            results = results.filter { $0.mediaTypeRaw == "video" }
        case .screenshots:
            results = results.filter { $0.sourceTypeRaw == "screenshot" }
        case .livePhotos:
            results = results.filter { $0.mediaTypeRaw == "livePhoto" }
        }
        
        // Filter by origin
        switch filters.origin {
        case .all:
            break
        case .camera:
            results = results.filter { $0.sourceTypeRaw == "camera" }
        case .messaging:
            results = results.filter { $0.sourceTypeRaw == "messaging" }
        case .downloaded:
            results = results.filter { $0.sourceTypeRaw == "downloaded" || $0.sourceTypeRaw == "saved" }
        }
        
        // Search in text fields (labels, OCR, searchable text)
        if !queryTerms.isEmpty {
            results = results.filter { photo in
                let searchable = photo.searchableText.lowercased()
                let labels = (photo.visionLabels ?? []).joined(separator: " ").lowercased()
                let ocr = (photo.ocrText ?? "").lowercased()
                let combined = "\(searchable) \(labels) \(ocr)"
                
                return queryTerms.contains { combined.contains($0) }
            }
        }
        
        return results
    }
    
    // MARK: - Ranking
    
    private func rankResults(_ photos: [PersistedPhoto], query: String, queryTerms: [String]) -> [PersistedPhoto] {
        guard !queryTerms.isEmpty else {
            return photos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
        
        let scored = photos.map { photo -> (PersistedPhoto, Double) in
            var score: Double = 0
            
            let searchable = photo.searchableText.lowercased()
            let labels = (photo.visionLabels ?? []).joined(separator: " ").lowercased()
            let ocr = (photo.ocrText ?? "").lowercased()
            
            for term in queryTerms {
                if searchable.contains(term) { score += 2.0 }
                if labels.contains(term) { score += 3.0 }
                if ocr.contains(term) { score += 1.5 }
                
                if let faceDetections = photo.faceDetections {
                    for face in faceDetections {
                        if face.personName?.lowercased().contains(term) ?? false {
                            score += 5.0
                        }
                    }
                }
                
                let placeName = (photo.placeCity ?? photo.placeName ?? "").lowercased()
                if placeName.contains(term) { score += 4.0 }
            }
            
            if let date = photo.creationDate {
                let daysSincePhoto = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
                score += max(0, 1.0 - Double(daysSincePhoto) / 365.0)
            }
            
            return (photo, score)
        }
        
        return scored
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
    
    // MARK: - Refinement Chips
    
    private func generateRefinementChips(from photos: [PersistedPhoto]) -> [SearchResult.RefinementChip] {
        var chips: [SearchResult.RefinementChip] = []
        
        // People chips
        var peopleCounts: [String: Int] = [:]
        for photo in photos {
            if let faces = photo.faceDetections {
                for face in faces {
                    if let name = face.personName, !name.isEmpty {
                        peopleCounts[name, default: 0] += 1
                    }
                }
            }
        }
        let topPeople = peopleCounts.sorted { $0.value > $1.value }.prefix(3)
        for (name, count) in topPeople {
            chips.append(.init(type: .person, value: name, count: count))
        }
        
        // Place chips
        var placeCounts: [String: Int] = [:]
        for photo in photos {
            if let city = photo.placeCity {
                placeCounts[city, default: 0] += 1
            }
        }
        let topPlaces = placeCounts.sorted { $0.value > $1.value }.prefix(3)
        for (place, count) in topPlaces {
            chips.append(.init(type: .place, value: place, count: count))
        }
        
        // Date chips (group by month/year)
        var dateCounts: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.dateFormat = "MMMM yyyy"
        for photo in photos {
            if let date = photo.creationDate {
                let key = formatter.string(from: date)
                dateCounts[key, default: 0] += 1
            }
        }
        let topDates = dateCounts.sorted { $0.value > $1.value }.prefix(2)
        for (dateStr, count) in topDates {
            chips.append(.init(type: .date, value: dateStr, count: count))
        }
        
        // Type chips
        let videoCount = photos.filter { $0.mediaTypeRaw == "video" }.count
        let screenshotCount = photos.filter { $0.sourceTypeRaw == "screenshot" }.count
        if videoCount > 3 {
            chips.append(.init(type: .type, value: "Videos", count: videoCount))
        }
        if screenshotCount > 3 {
            chips.append(.init(type: .type, value: "Capturas", count: screenshotCount))
        }
        
        return chips
    }
    
    // MARK: - Feature Print Similarity Search
    
    func searchSimilar(to photo: PersistedPhoto, limit: Int = 20) async -> [PersistedPhoto] {
        guard let context = modelContext,
              let referenceData = photo.featurePrintData else {
            return []
        }
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.featurePrintData != nil }
        )
        
        guard let allPhotos = try? context.fetch(descriptor) else {
            return []
        }
        
        let scored = allPhotos.compactMap { candidate -> (PersistedPhoto, Float)? in
            guard candidate.id != photo.id,
                  let candidateData = candidate.featurePrintData,
                  let similarity = computeFeaturePrintSimilarity(referenceData, candidateData) else {
                return nil
            }
            return (candidate, similarity)
        }
        
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
    
    private func computeFeaturePrintSimilarity(_ data1: Data, _ data2: Data) -> Float? {
        guard let print1 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data1),
              let print2 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data2) else {
            return nil
        }
        var distance: Float = 0
        try? print1.computeDistance(&distance, to: print2)
        return max(0, 1 - distance)
    }
}
