// CatalogingService.swift
// Servicio para detectar unknowns y generar tarjetas de catalogación interactivas

import Foundation
import SwiftData

@MainActor
class CatalogingService: ObservableObject {
    static let shared = CatalogingService()
    private var modelContext: ModelContext?
    
    @Published var pendingCards: [CatalogingCard] = []
    
    // MARK: - Card Model (UI representation)
    
    struct CatalogingCard: Identifiable {
        let id: String
        let type: CatalogingCardType
        let title: String
        let subtitle: String
        let photoCount: Int
        let impactScore: Int
        let targetId: String?
        let previewPhotoIds: [String]
        
        var localizedTitle: String {
            switch type {
            case .unknownPerson:
                return String(localized: "cataloging_unknown_person_title")
            case .unknownPlace:
                return String(localized: "cataloging_unknown_place_title")
            case .messagingAppPhotos:
                return String(localized: "cataloging_messaging_photos_title")
            case .recurringDate:
                return String(localized: "cataloging_recurring_date_title")
            case .downloadedContent:
                return String(localized: "cataloging_downloaded_title")
            case .confirmBirthday:
                return String(localized: "cataloging_confirm_birthday")
            case .confirmWedding:
                return String(localized: "cataloging_confirm_wedding")
            case .confirmChildRelation:
                return String(localized: "cataloging_confirm_child")
            case .confirmAnniversary:
                return String(localized: "cataloging_confirm_anniversary")
            }
        }
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Generate Cards
    
    func generateCatalogingCards() async {
        guard let context = modelContext else { return }
        
        var cards: [CatalogingCard] = []
        
        // 1. Unknown persons (unnamed face clusters with many photos)
        let personCards = await generateUnknownPersonCards()
        cards.append(contentsOf: personCards)
        
        // 2. Unknown places (unlabeled place clusters)
        let placeCards = await generateUnknownPlaceCards()
        cards.append(contentsOf: placeCards)
        
        // 3. Messaging app photos to review
        let messagingCards = await generateMessagingAppCards()
        cards.append(contentsOf: messagingCards)
        
        // 4. Recurring date patterns
        let dateCards = await generateRecurringDateCards()
        cards.append(contentsOf: dateCards)
        
        // 5. Downloaded content without EXIF
        let downloadCards = await generateDownloadedContentCards()
        cards.append(contentsOf: downloadCards)
        
        // Sort by impact (photo count)
        cards.sort { $0.impactScore > $1.impactScore }
        
        pendingCards = cards
        
        // Persist cards for tracking
        await persistCards(cards)
    }
    
    // MARK: - Person Cards
    
    private func generateUnknownPersonCards() async -> [CatalogingCard] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.name == nil },
            sortBy: [SortDescriptor(\.faceCount, order: .reverse)]
        )
        
        let persons = (try? context.fetch(descriptor)) ?? []
        
        return persons.prefix(5).compactMap { person in
            guard person.faceCount >= 10 else { return nil }
            
            let photoIds = person.photoIdArray.prefix(4).map { $0 }
            
            return CatalogingCard(
                id: "person_\(person.id)",
                type: .unknownPerson,
                title: String(localized: "cataloging_person_appears \(person.faceCount)"),
                subtitle: String(localized: "cataloging_who_is_this"),
                photoCount: person.faceCount,
                impactScore: person.faceCount,
                targetId: person.id,
                previewPhotoIds: photoIds
            )
        }
    }
    
    // MARK: - Place Cards
    
    private func generateUnknownPlaceCards() async -> [CatalogingCard] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<PersistedPlaceCluster>(
            predicate: #Predicate { $0.placeTypeRaw == "unknown" && !$0.isUserLabeled },
            sortBy: [SortDescriptor(\.photoCount, order: .reverse)]
        )
        
        let clusters = (try? context.fetch(descriptor)) ?? []
        
        return clusters.prefix(5).compactMap { cluster in
            guard cluster.photoCount >= 10 else { return nil }
            
            let subtitle = cluster.city ?? cluster.address ?? String(localized: "cataloging_unknown_location")
            
            return CatalogingCard(
                id: "place_\(cluster.id)",
                type: .unknownPlace,
                title: String(localized: "cataloging_place_photos \(cluster.photoCount)"),
                subtitle: subtitle,
                photoCount: cluster.photoCount,
                impactScore: cluster.photoCount,
                targetId: cluster.id,
                previewPhotoIds: []
            )
        }
    }
    
    // MARK: - Messaging App Cards
    
    private func generateMessagingAppCards() async -> [CatalogingCard] {
        guard let context = modelContext else { return [] }
        
        // Group by origin
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted }
        )
        
        let photos = (try? context.fetch(descriptor)) ?? []
        
        // Group by messaging app origin
        var originGroups: [PhotoOrigin: [PersistedPhoto]] = [:]
        
        for photo in photos {
            if photo.origin.isMessagingApp {
                originGroups[photo.origin, default: []].append(photo)
            }
        }
        
        return originGroups.compactMap { origin, groupPhotos in
            guard groupPhotos.count >= 50 else { return nil }
            
            let previewIds = groupPhotos.prefix(4).map { $0.id }
            
            return CatalogingCard(
                id: "messaging_\(origin.rawValue)",
                type: .messagingAppPhotos,
                title: String(localized: "cataloging_from_app \(origin.rawValue) \(groupPhotos.count)"),
                subtitle: String(localized: "cataloging_review_these"),
                photoCount: groupPhotos.count,
                impactScore: groupPhotos.count,
                targetId: origin.rawValue,
                previewPhotoIds: previewIds
            )
        }
    }
    
    // MARK: - Recurring Date Cards
    
    private func generateRecurringDateCards() async -> [CatalogingCard] {
        guard let context = modelContext else { return [] }
        
        var cards: [CatalogingCard] = []
        
        let importantDateDescriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate { !$0.isUserConfirmed && !$0.isDismissed }
        )
        
        let unconfirmedDates = (try? context.fetch(importantDateDescriptor)) ?? []
        
        for date in unconfirmedDates.prefix(5) {
            let cardType: CatalogingCardType
            let title: String
            let subtitle: String
            
            switch date.dateType {
            case .birthday, .friendBirthday:
                cardType = .confirmBirthday
                let name = date.personName ?? String(localized: "cataloging_unknown_person")
                title = String(localized: "cataloging_birthday_question \(date.displayDate) \(name)")
                subtitle = String(localized: "cataloging_detected_years \(date.yearsDetected)")
                
            case .wedding, .anniversary:
                cardType = .confirmWedding
                let names = date.displayName
                let displayYear = date.year ?? 0
                title = String(localized: "cataloging_wedding_question \(names) \(date.displayDate)/\(displayYear)")
                subtitle = String(localized: "cataloging_detected_photos \(date.photoIdArray.count)")
                
            case .childBirthday:
                cardType = .confirmChildRelation
                let name = date.personName ?? String(localized: "cataloging_this_child")
                title = String(localized: "cataloging_child_question \(name)")
                subtitle = String(localized: "cataloging_growing_over_years")
                
            case .other:
                cardType = .recurringDate
                title = String(localized: "cataloging_event_question \(date.displayDate)")
                subtitle = String(localized: "cataloging_detected_years \(date.yearsDetected)")
            }
            
            cards.append(CatalogingCard(
                id: "important_date_\(date.id)",
                type: cardType,
                title: title,
                subtitle: subtitle,
                photoCount: date.photoIdArray.count,
                impactScore: Int(date.confidence * 100) + date.yearsDetected * 10,
                targetId: date.id,
                previewPhotoIds: Array(date.photoIdArray.prefix(4))
            ))
        }
        
        let photoDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.creationDate != nil }
        )
        
        let photos = (try? context.fetch(photoDescriptor)) ?? []
        
        var dayOfYearGroups: [Int: [(photo: PersistedPhoto, year: Int)]] = [:]
        let calendar = Calendar.current
        
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
            let year = calendar.component(.year, from: date)
            dayOfYearGroups[dayOfYear, default: []].append((photo, year))
        }
        
        var recurringDates: [(day: Int, month: Int, yearsCount: Int, photoCount: Int, personId: String?)] = []
        
        for (_, entries) in dayOfYearGroups {
            let uniqueYears = Set(entries.map { $0.year })
            
            if uniqueYears.count >= 3 {
                let totalPhotos = entries.count
                var personId: String?
                
                if let firstDate = entries.first?.photo.creationDate {
                    let month = calendar.component(.month, from: firstDate)
                    let day = calendar.component(.day, from: firstDate)
                    
                    let existingCard = cards.first { card in
                        if card.type == .confirmBirthday || card.type == .confirmWedding {
                            return card.targetId != nil
                        }
                        return false
                    }
                    
                    if existingCard == nil {
                        recurringDates.append((day: day, month: month, yearsCount: uniqueYears.count, 
                                              photoCount: totalPhotos, personId: personId))
                    }
                }
            }
        }
        
        recurringDates.sort { $0.yearsCount > $1.yearsCount }
        
        for recurring in recurringDates.prefix(3) where cards.count < 8 {
            let dateString = String(format: "%02d/%02d", recurring.day, recurring.month)
            
            cards.append(CatalogingCard(
                id: "date_\(recurring.month)_\(recurring.day)",
                type: .recurringDate,
                title: String(localized: "cataloging_every_date \(dateString) \(recurring.yearsCount)"),
                subtitle: String(localized: "cataloging_is_birthday"),
                photoCount: recurring.photoCount,
                impactScore: recurring.yearsCount * 10 + recurring.photoCount,
                targetId: "\(recurring.month)_\(recurring.day)",
                previewPhotoIds: []
            ))
        }
        
        return cards
    }
    
    // MARK: - Downloaded Content Cards
    
    private func generateDownloadedContentCards() async -> [CatalogingCard] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { 
                $0.analysisCompleted && $0.hasExifData == false
            }
        )
        
        let photos = (try? context.fetch(descriptor)) ?? []
        
        // Filter to likely memes/forwards
        let downloadedContent = photos.filter { $0.isDownloadedWithoutExif }
        
        guard downloadedContent.count >= 20 else { return [] }
        
        let previewIds = downloadedContent.prefix(4).map { $0.id }
        
        return [CatalogingCard(
            id: "downloaded_content",
            type: .downloadedContent,
            title: String(localized: "cataloging_downloaded_count \(downloadedContent.count)"),
            subtitle: String(localized: "cataloging_review_cleanup"),
            photoCount: downloadedContent.count,
            impactScore: downloadedContent.count,
            targetId: nil,
            previewPhotoIds: previewIds
        )]
    }
    
    // MARK: - Persist Cards
    
    private func persistCards(_ cards: [CatalogingCard]) async {
        guard let context = modelContext else { return }
        
        // Clear old cards
        let oldDescriptor = FetchDescriptor<PersistedCatalogingCard>()
        let oldCards = (try? context.fetch(oldDescriptor)) ?? []
        for card in oldCards {
            context.delete(card)
        }
        
        // Insert new cards
        for card in cards {
            let persisted = PersistedCatalogingCard(
                cardType: card.type,
                targetId: card.targetId,
                photoCount: card.photoCount,
                priority: card.impactScore
            )
            context.insert(persisted)
        }
        
        try? context.save()
    }
    
    // MARK: - Card Actions
    
    func dismissCard(_ cardId: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedCatalogingCard>(
            predicate: #Predicate { $0.id == cardId }
        )
        
        if let card = try? context.fetch(descriptor).first {
            card.isDismissed = true
            try? context.save()
        }
        
        pendingCards.removeAll { $0.id == cardId }
    }
    
    func completeCard(_ cardId: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedCatalogingCard>(
            predicate: #Predicate { $0.id == cardId }
        )
        
        if let card = try? context.fetch(descriptor).first {
            card.isCompleted = true
            try? context.save()
        }
        
        pendingCards.removeAll { $0.id == cardId }
    }
    
    // MARK: - Apply Labels
    
    func labelPerson(_ personId: String, name: String, birthdayMonth: Int? = nil, birthdayDay: Int? = nil) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.id == personId }
        )
        
        guard let person = try? context.fetch(descriptor).first else { return }
        
        person.name = name
        person.birthdayMonth = birthdayMonth
        person.birthdayDay = birthdayDay
        
        try? context.save()
    }
    
    func applyAnswer(_ optionId: String) {
        let parts = optionId.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return }
        let kind = parts[0]
        let targetId = parts[1]
        let value = parts.dropFirst(2).joined(separator: ":")
        if kind == "person" {
            labelPerson(targetId, name: value)
        } else if kind == "place" {
            labelPlace(targetId, name: value)
        }
    }
    
    func labelPlace(_ placeId: String, name: String) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<PersistedPlace>(
            predicate: #Predicate { $0.id == placeId }
        )
        guard let place = try? context.fetch(descriptor).first else { return }
        place.name = name
        try? context.save()
    }
    
    func frequentUnnamedPrompts() -> [AssistantMessage] {
        guard let context = modelContext else { return [] }
        var cards: [AssistantMessage] = []
        
        let people = (try? context.fetch(FetchDescriptor<PersistedPerson>())) ?? []
        if let person = people.filter({ !$0.isNamed }).sorted(by: { $0.faceCount > $1.faceCount }).first, person.faceCount >= 3 {
            cards.append(AssistantMessage(
                text: "Esta persona aparece mucho. ¿Cómo se llama?",
                isUser: false,
                card: .catalogQuestion(
                    question: "¿Quién es?",
                    subtitle: MomentsPluralization.photos(person.faceCount),
                    photos: [],
                    options: [
                        .init(id: "person:\(person.id):Mamá", title: "Mamá"),
                        .init(id: "person:\(person.id):Papá", title: "Papá"),
                        .init(id: "person:\(person.id):Sofía", title: "Sofía")
                    ]
                )
            ))
        }
        
        let places = (try? context.fetch(FetchDescriptor<PersistedPlace>())) ?? []
        if let place = places.filter({ $0.name.trimmingCharacters(in: .whitespaces).isEmpty }).sorted(by: { $0.visitCount > $1.visitCount }).first, place.visitCount >= 3 {
            cards.append(AssistantMessage(
                text: "Este lugar aparece seguido. ¿Cómo lo llamamos?",
                isUser: false,
                card: .catalogQuestion(
                    question: "¿Qué lugar es?",
                    subtitle: "\(place.visitCount) visitas",
                    photos: [],
                    options: [
                        .init(id: "place:\(place.id):Casa", title: "Casa"),
                        .init(id: "place:\(place.id):Trabajo", title: "Trabajo")
                    ]
                )
            ))
        }
        return cards
    }
    
    func confirmRecurringDate(month: Int, day: Int, eventType: String, personId: String? = nil) {
        guard let context = modelContext else { return }
        
        let dayOfYear = month * 31 + day // Simplified
        
        let event = PersistedRecurringEvent(
            typeRaw: eventType,
            personId: personId,
            dayOfYear: dayOfYear,
            month: month,
            day: day,
            confidence: 1.0
        )
        event.isUserConfirmed = true
        
        context.insert(event)
        try? context.save()
    }
}
