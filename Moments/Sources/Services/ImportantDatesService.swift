// ImportantDatesService.swift
// Servicio para detectar y gestionar fechas importantes de amigos/familia

import Foundation
import SwiftData
import Vision
import Photos

@MainActor
class ImportantDatesService: ObservableObject {
    static let shared = ImportantDatesService()
    
    private var modelContext: ModelContext?
    
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var detectedDates: [PersistedImportantDate] = []
    
    private let birthdayLabels = Set([
        "cake", "birthday cake", "candle", "balloon", "party",
        "celebration", "decorations", "confetti", "gift", "present",
        "pastel", "vela", "globo", "fiesta", "regalo"
    ])
    
    private let weddingLabels = Set([
        "wedding", "bride", "groom", "wedding dress", "suit", "tuxedo",
        "church", "ceremony", "flowers", "bouquet", "ring", "altar",
        "decorated hall", "reception", "veil", "bridesmaids",
        "boda", "novia", "novio", "iglesia", "ceremonia", "flores",
        "ramo", "anillo", "vestido de novia"
    ])
    
    private let birthdayOcrPatterns = [
        "feliz cumple", "happy birthday", "cumpleaños",
        "felicidades", "años cumple", "years old"
    ]
    
    private let weddingOcrPatterns = [
        "nos casamos", "we're getting married", "casamiento", "boda",
        "wedding", "married", "matrimonio", "te invitamos"
    ]
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Detect Important Dates
    
    func detectImportantDates() async {
        guard let context = modelContext else { return }
        
        isAnalyzing = true
        analysisProgress = 0
        
        defer {
            isAnalyzing = false
        }
        
        let photoDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.creationDate != nil }
        )
        
        guard let photos = try? context.fetch(photoDescriptor) else { return }
        
        let personDescriptor = FetchDescriptor<PersistedPerson>()
        let persons = (try? context.fetch(personDescriptor)) ?? []
        let personMap = Dictionary(uniqueKeysWithValues: persons.map { ($0.id, $0) })
        
        var candidateDates: [CandidateDate] = []
        
        // Phase 1: Group photos by (person, month-day) across years
        let personDateGroups = groupPhotosByPersonAndDate(photos: photos, personMap: personMap)
        analysisProgress = 0.25
        
        // Phase 2: Find recurring patterns (same person, same day, multiple years)
        let recurringPatterns = findRecurringPatterns(groups: personDateGroups)
        analysisProgress = 0.5
        
        // Phase 3: Analyze visual cues for each candidate
        for (index, pattern) in recurringPatterns.enumerated() {
            let analyzed = await analyzePatternVisualCues(pattern: pattern, photos: photos)
            candidateDates.append(analyzed)
            analysisProgress = 0.5 + (0.3 * Double(index + 1) / Double(recurringPatterns.count))
        }
        
        // Phase 4: Detect child-growing patterns
        let childPatterns = await detectChildGrowingPatterns(photos: photos, personMap: personMap)
        candidateDates.append(contentsOf: childPatterns)
        analysisProgress = 0.9
        
        // Phase 5: Persist candidates as ImportantDates
        await persistCandidates(candidateDates)
        analysisProgress = 1.0
        
        await loadDetectedDates()
    }
    
    // MARK: - Group Photos by Person and Date
    
    private struct PersonDateKey: Hashable {
        let personId: String
        let month: Int
        let day: Int
    }
    
    private struct PhotoInGroup {
        let photo: PersistedPhoto
        let year: Int
        let personId: String
    }
    
    private func groupPhotosByPersonAndDate(
        photos: [PersistedPhoto],
        personMap: [String: PersistedPerson]
    ) -> [PersonDateKey: [PhotoInGroup]] {
        var groups: [PersonDateKey: [PhotoInGroup]] = [:]
        let calendar = Calendar.current
        
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            let year = calendar.component(.year, from: date)
            
            let faceDetections = photo.faceDetections ?? []
            for face in faceDetections {
                guard let clusterId = face.clusterId else { continue }
                
                if let person = personMap.values.first(where: { $0.faceClusterId == clusterId }) {
                    let key = PersonDateKey(personId: person.id, month: month, day: day)
                    let item = PhotoInGroup(photo: photo, year: year, personId: person.id)
                    groups[key, default: []].append(item)
                }
            }
        }
        
        return groups
    }
    
    // MARK: - Find Recurring Patterns
    
    private struct RecurringPattern {
        let personId: String
        let month: Int
        let day: Int
        let years: Set<Int>
        let photos: [PersistedPhoto]
    }
    
    private func findRecurringPatterns(groups: [PersonDateKey: [PhotoInGroup]]) -> [RecurringPattern] {
        var patterns: [RecurringPattern] = []
        
        for (key, items) in groups {
            let uniqueYears = Set(items.map { $0.year })
            
            if uniqueYears.count >= 2 {
                let pattern = RecurringPattern(
                    personId: key.personId,
                    month: key.month,
                    day: key.day,
                    years: uniqueYears,
                    photos: items.map { $0.photo }
                )
                patterns.append(pattern)
            }
        }
        
        return patterns.sorted { $0.years.count > $1.years.count }
    }
    
    // MARK: - Analyze Visual Cues
    
    struct CandidateDate {
        let personId: String
        let secondPersonId: String?
        let childOfPersonId: String?
        let month: Int
        let day: Int
        let year: Int?
        let dateType: ImportantDateType
        let confidence: Double
        let yearsDetected: Int
        let photoIds: [String]
        let detectedLabels: [String]
        let detectedOcrText: String?
    }
    
    private func analyzePatternVisualCues(
        pattern: RecurringPattern,
        photos: [PersistedPhoto]
    ) async -> CandidateDate {
        var birthdayScore = 0.0
        var weddingScore = 0.0
        var allLabels: [String] = []
        var allOcrText: [String] = []
        
        for photo in pattern.photos {
            let labels = photo.labelsArray.map { $0.lowercased() }
            allLabels.append(contentsOf: labels)
            
            let matchedBirthday = labels.filter { birthdayLabels.contains($0) }
            let matchedWedding = labels.filter { weddingLabels.contains($0) }
            
            birthdayScore += Double(matchedBirthday.count) * 0.2
            weddingScore += Double(matchedWedding.count) * 0.2
            
            if let ocr = photo.ocrText?.lowercased() {
                allOcrText.append(ocr)
                
                for birthdayPattern in birthdayOcrPatterns {
                    if ocr.contains(birthdayPattern) {
                        birthdayScore += 0.5
                    }
                }
                
                for weddingPattern in weddingOcrPatterns {
                    if ocr.contains(weddingPattern) {
                        weddingScore += 0.5
                    }
                }
            }
        }
        
        let yearsCount = pattern.years.count
        let baseConfidence = min(0.3 * Double(yearsCount), 0.9)
        
        let dateType: ImportantDateType
        var finalConfidence: Double
        
        if weddingScore > birthdayScore && weddingScore > 0.3 {
            dateType = .wedding
            finalConfidence = baseConfidence + min(weddingScore, 0.5)
        } else if birthdayScore > 0.2 {
            dateType = .birthday
            finalConfidence = baseConfidence + min(birthdayScore, 0.5)
        } else {
            dateType = .birthday
            finalConfidence = baseConfidence
        }
        
        finalConfidence = min(finalConfidence, 1.0)
        
        let firstYear = pattern.years.min()
        
        return CandidateDate(
            personId: pattern.personId,
            secondPersonId: nil,
            childOfPersonId: nil,
            month: pattern.month,
            day: pattern.day,
            year: dateType == .wedding ? firstYear : nil,
            dateType: dateType,
            confidence: finalConfidence,
            yearsDetected: yearsCount,
            photoIds: pattern.photos.map { $0.id },
            detectedLabels: Array(Set(allLabels)),
            detectedOcrText: allOcrText.joined(separator: " ").isEmpty ? nil : allOcrText.joined(separator: " ")
        )
    }
    
    // MARK: - Detect Child Growing Patterns
    
    private func detectChildGrowingPatterns(
        photos: [PersistedPhoto],
        personMap: [String: PersistedPerson]
    ) async -> [CandidateDate] {
        var candidates: [CandidateDate] = []
        let calendar = Calendar.current
        
        var personYearAppearances: [String: [(year: Int, photos: [PersistedPhoto])]] = [:]
        
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            let year = calendar.component(.year, from: date)
            
            let faceDetections = photo.faceDetections ?? []
            for face in faceDetections {
                guard let clusterId = face.clusterId else { continue }
                if let person = personMap.values.first(where: { $0.faceClusterId == clusterId }) {
                    if personYearAppearances[person.id] == nil {
                        personYearAppearances[person.id] = []
                    }
                    if let idx = personYearAppearances[person.id]?.firstIndex(where: { $0.year == year }) {
                        personYearAppearances[person.id]?[idx].photos.append(photo)
                    } else {
                        personYearAppearances[person.id]?.append((year: year, photos: [photo]))
                    }
                }
            }
        }
        
        for (personId, yearData) in personYearAppearances {
            guard yearData.count >= 3 else { continue }
            
            let sortedYears = yearData.sorted { $0.year < $1.year }
            let firstYear = sortedYears.first?.year ?? 0
            let lastYear = sortedYears.last?.year ?? 0
            
            if lastYear - firstYear >= 3 {
                let allPhotos = yearData.flatMap { $0.photos }
                
                let coAppearingAdults = findCoAppearingPersons(photos: allPhotos, targetPersonId: personId, personMap: personMap)
                
                if !coAppearingAdults.isEmpty {
                    for adultId in coAppearingAdults {
                        let firstDayPhotos = sortedYears.first?.photos ?? []
                        let firstPhoto = firstDayPhotos.first
                        let month = firstPhoto.flatMap { $0.creationDate.map { calendar.component(.month, from: $0) } } ?? 1
                        let day = firstPhoto.flatMap { $0.creationDate.map { calendar.component(.day, from: $0) } } ?? 1
                        
                        candidates.append(CandidateDate(
                            personId: personId,
                            secondPersonId: nil,
                            childOfPersonId: adultId,
                            month: month,
                            day: day,
                            year: firstYear,
                            dateType: .childBirthday,
                            confidence: 0.4 + (0.1 * Double(yearData.count)),
                            yearsDetected: yearData.count,
                            photoIds: allPhotos.map { $0.id },
                            detectedLabels: [],
                            detectedOcrText: nil
                        ))
                        break
                    }
                }
            }
        }
        
        return candidates
    }
    
    private func findCoAppearingPersons(
        photos: [PersistedPhoto],
        targetPersonId: String,
        personMap: [String: PersistedPerson]
    ) -> [String] {
        var coAppearanceCounts: [String: Int] = [:]
        
        for photo in photos {
            let faceDetections = photo.faceDetections ?? []
            let clusterIds = faceDetections.compactMap { $0.clusterId }
            
            let personIds = clusterIds.compactMap { clusterId in
                personMap.values.first(where: { $0.faceClusterId == clusterId })?.id
            }
            
            if personIds.contains(targetPersonId) {
                for otherId in personIds where otherId != targetPersonId {
                    coAppearanceCounts[otherId, default: 0] += 1
                }
            }
        }
        
        return coAppearanceCounts
            .filter { $0.value >= 3 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
    
    // MARK: - Persist Candidates
    
    private func persistCandidates(_ candidates: [CandidateDate]) async {
        guard let context = modelContext else { return }
        
        let personDescriptor = FetchDescriptor<PersistedPerson>()
        let persons = (try? context.fetch(personDescriptor)) ?? []
        let personMap = Dictionary(uniqueKeysWithValues: persons.map { ($0.id, $0) })
        
        for candidate in candidates {
            let candidatePersonId: String? = candidate.personId
            let candidateMonth = candidate.month
            let candidateDay = candidate.day
            let existing = try? context.fetch(
                FetchDescriptor<PersistedImportantDate>(
                    predicate: #Predicate<PersistedImportantDate> {
                        $0.personId == candidatePersonId &&
                        $0.month == candidateMonth &&
                        $0.day == candidateDay
                    }
                )
            ).first
            
            if existing == nil {
                let personName = personMap[candidate.personId]?.name
                let secondPersonName = candidate.secondPersonId.flatMap { personMap[$0]?.name }
                
                let importantDate = PersistedImportantDate(
                    dateType: candidate.dateType,
                    source: .photos,
                    month: candidate.month,
                    day: candidate.day,
                    year: candidate.year,
                    personId: candidate.personId,
                    secondPersonId: candidate.secondPersonId,
                    personName: personName,
                    secondPersonName: secondPersonName,
                    childOfPersonId: candidate.childOfPersonId,
                    confidence: candidate.confidence,
                    yearsDetected: candidate.yearsDetected,
                    photoIds: candidate.photoIds
                )
                importantDate.detectedLabels = candidate.detectedLabels.joined(separator: "|")
                importantDate.detectedOcrText = candidate.detectedOcrText
                
                context.insert(importantDate)
            }
        }
        
        try? context.save()
    }
    
    // MARK: - Load Detected Dates
    
    func loadDetectedDates() async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate { !$0.isDismissed },
            sortBy: [SortDescriptor(\.confidence, order: .reverse)]
        )
        
        detectedDates = (try? context.fetch(descriptor)) ?? []
    }
    
    // MARK: - Upcoming Dates
    
    func getUpcomingDates(withinDays: Int = 30) async -> [PersistedImportantDate] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate { $0.isUserConfirmed && !$0.isDismissed }
        )
        
        let allConfirmed = (try? context.fetch(descriptor)) ?? []
        
        let now = Date()
        let calendar = Calendar.current
        
        return allConfirmed
            .filter { date in
                guard let daysUntil = date.daysUntilNext else { return false }
                return daysUntil >= 0 && daysUntil <= withinDays
            }
            .sorted { ($0.daysUntilNext ?? Int.max) < ($1.daysUntilNext ?? Int.max) }
    }
    
    // MARK: - Get Photos From Previous Years
    
    func getPhotosFromPreviousYears(for importantDate: PersistedImportantDate) async -> [Int: [PersistedPhoto]] {
        guard let context = modelContext else { return [:] }
        
        let month = importantDate.month
        let day = importantDate.day
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.creationDate != nil }
        )
        
        guard let photos = try? context.fetch(descriptor) else { return [:] }
        
        var result: [Int: [PersistedPhoto]] = [:]
        let calendar = Calendar.current
        
        let windowDays = 3
        
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            
            let photoMonth = calendar.component(.month, from: date)
            let photoDay = calendar.component(.day, from: date)
            let photoYear = calendar.component(.year, from: date)
            
            let daysDiff = abs((month * 31 + day) - (photoMonth * 31 + photoDay))
            
            if daysDiff <= windowDays {
                if let personId = importantDate.personId {
                    let faceDetections = photo.faceDetections ?? []
                    let hasTargetPerson = faceDetections.contains { face in
                        guard let clusterId = face.clusterId else { return false }
                        let personDescriptor = FetchDescriptor<PersistedPerson>(
                            predicate: #Predicate<PersistedPerson> { $0.faceClusterId == clusterId && $0.id == personId }
                        )
                        return (try? context.fetch(personDescriptor).first) != nil
                    }
                    
                    if hasTargetPerson {
                        result[photoYear, default: []].append(photo)
                    }
                } else {
                    result[photoYear, default: []].append(photo)
                }
            }
        }
        
        return result
    }
    
    // MARK: - User Actions
    
    func confirmDate(_ dateId: String, asType: ImportantDateType, personName: String?, secondPersonName: String?, year: Int?) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate<PersistedImportantDate> { $0.id == dateId }
        )
        
        guard let date = try? context.fetch(descriptor).first else { return }
        
        date.isUserConfirmed = true
        date.dateType = asType
        date.confidence = 1.0
        date.lastUpdatedAt = Date()
        
        if let name = personName {
            date.personName = name
            if let personId = date.personId {
                updatePersonName(personId: personId, name: name)
            }
        }
        
        if let secondName = secondPersonName {
            date.secondPersonName = secondName
            if let personId = date.secondPersonId {
                updatePersonName(personId: personId, name: secondName)
            }
        }
        
        if let y = year {
            date.year = y
        }
        
        try? context.save()
    }
    
    private func updatePersonName(personId: String, name: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate<PersistedPerson> { $0.id == personId }
        )
        
        if let person = try? context.fetch(descriptor).first {
            person.name = name
            try? context.save()
        }
    }
    
    func dismissDate(_ dateId: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate<PersistedImportantDate> { $0.id == dateId }
        )
        
        if let date = try? context.fetch(descriptor).first {
            date.isDismissed = true
            date.lastUpdatedAt = Date()
            try? context.save()
        }
    }
    
    func setRelationship(parentId: String, childId: String) {
        guard let context = modelContext else { return }
        
        let parentDescriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate<PersistedPerson> { $0.id == parentId }
        )
        let childDescriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate<PersistedPerson> { $0.id == childId }
        )
        
        guard let parent = try? context.fetch(parentDescriptor).first,
              let child = try? context.fetch(childDescriptor).first else { return }
        
        var childIds = parent.childIdArray
        if !childIds.contains(childId) {
            childIds.append(childId)
            parent.setChildIds(childIds)
        }
        
        var parentIds = child.parentIdArray
        if !parentIds.contains(parentId) {
            parentIds.append(parentId)
            child.setParentIds(parentIds)
        }
        
        try? context.save()
    }
    
    func setPartnership(person1Id: String, person2Id: String) {
        guard let context = modelContext else { return }
        
        let descriptor1 = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate<PersistedPerson> { $0.id == person1Id }
        )
        let descriptor2 = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate<PersistedPerson> { $0.id == person2Id }
        )
        
        guard let person1 = try? context.fetch(descriptor1).first,
              let person2 = try? context.fetch(descriptor2).first else { return }
        
        person1.partnerId = person2Id
        person2.partnerId = person1Id
        
        try? context.save()
    }
}
