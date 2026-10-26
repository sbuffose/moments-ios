// RememberListService.swift
// Local editable "Recordá esto" list of facts learned from cataloging and chat

import Foundation
import SwiftData

@MainActor
class RememberListService: ObservableObject {
    private var modelContext: ModelContext?
    
    @Published var facts: [RememberListItem] = []
    @Published var factCount: Int = 0
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadFacts()
    }
    
    // MARK: - Load Facts
    
    func loadFacts() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<RememberListItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .descending)]
        )
        
        facts = (try? context.fetch(descriptor)) ?? []
        factCount = facts.count
    }
    
    // MARK: - Add Fact
    
    func addFact(
        _ fact: String,
        category: String = "general",
        personId: String? = nil,
        personName: String? = nil,
        source: String = "user"
    ) async {
        guard let context = modelContext else { return }
        
        // Check if similar fact exists
        let normalizedFact = fact.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for existingFact in facts {
            if existingFact.fact.lowercased() == normalizedFact {
                return
            }
        }
        
        let item = RememberListItem(
            fact: fact,
            category: category,
            personId: personId,
            personName: personName,
            source: source
        )
        
        context.insert(item)
        try? context.save()
        loadFacts()
    }
    
    // MARK: - Add Relationship Fact
    
    func addRelationshipFact(
        person1Name: String,
        relationship: RelationshipType,
        person2Name: String,
        person1Id: String? = nil,
        person2Id: String? = nil
    ) async {
        let fact: String
        switch relationship {
        case .partner, .spouse:
            fact = "\(person1Name) y \(person2Name) son pareja"
        case .child:
            fact = "\(person1Name) es hijo/a de \(person2Name)"
        case .parent:
            fact = "\(person1Name) es padre/madre de \(person2Name)"
        case .sibling:
            fact = "\(person1Name) y \(person2Name) son hermanos"
        case .friend:
            fact = "\(person1Name) y \(person2Name) son amigos"
        case .colleague:
            fact = "\(person1Name) y \(person2Name) son colegas"
        case .other:
            fact = "\(person1Name) conoce a \(person2Name)"
        }
        
        guard let context = modelContext else { return }
        
        let item = RememberListItem(
            fact: fact,
            category: "relationship",
            personId: person1Id,
            personName: person1Name,
            source: "cataloging"
        )
        item.secondPersonId = person2Id
        item.secondPersonName = person2Name
        
        context.insert(item)
        try? context.save()
        loadFacts()
    }
    
    // MARK: - Add Birthday Fact
    
    func addBirthdayFact(
        personName: String,
        month: Int,
        day: Int,
        year: Int? = nil,
        personId: String? = nil
    ) async {
        let monthNames = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                         "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
        
        let monthName = month > 0 && month <= 12 ? monthNames[month - 1] : "\(month)"
        
        var fact = "El cumpleaños de \(personName) es el \(day) de \(monthName)"
        if let year = year {
            fact += " (nació en \(year))"
        }
        
        await addFact(fact, category: "birthday", personId: personId, personName: personName, source: "cataloging")
    }
    
    // MARK: - Add Place Fact
    
    func addPlaceFact(
        placeName: String,
        placeType: PlaceClusterType,
        personName: String? = nil
    ) async {
        var fact: String
        
        switch placeType {
        case .home:
            if let person = personName {
                fact = "\(placeName) es la casa de \(person)"
            } else {
                fact = "\(placeName) es tu casa"
            }
        case .work:
            fact = "\(placeName) es tu trabajo"
        case .familyHome:
            if let person = personName {
                fact = "\(placeName) es la casa de \(person)"
            } else {
                fact = "\(placeName) es la casa de la familia"
            }
        case .gym:
            fact = "\(placeName) es tu gimnasio"
        case .school:
            fact = "\(placeName) es tu escuela/universidad"
        default:
            fact = "Visitás frecuentemente \(placeName)"
        }
        
        await addFact(fact, category: "place", source: "cataloging")
    }
    
    // MARK: - Update Fact
    
    func updateFact(id: String, newFact: String) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<RememberListItem>(
            predicate: #Predicate<RememberListItem> { $0.id == id }
        )
        
        guard let item = try? context.fetch(descriptor).first else { return }
        
        item.fact = newFact
        item.isUserEdited = true
        
        try? context.save()
        loadFacts()
    }
    
    // MARK: - Delete Fact
    
    func deleteFact(id: String) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<RememberListItem>(
            predicate: #Predicate<RememberListItem> { $0.id == id }
        )
        
        guard let item = try? context.fetch(descriptor).first else { return }
        
        context.delete(item)
        try? context.save()
        loadFacts()
    }
    
    // MARK: - Search Facts
    
    func searchFacts(query: String) -> [RememberListItem] {
        let normalizedQuery = query.lowercased()
        
        return facts.filter { fact in
            fact.fact.lowercased().contains(normalizedQuery) ||
            fact.personName?.lowercased().contains(normalizedQuery) == true ||
            fact.secondPersonName?.lowercased().contains(normalizedQuery) == true
        }
    }
    
    // MARK: - Get Facts for Person
    
    func getFacts(forPersonId personId: String) -> [RememberListItem] {
        facts.filter { $0.personId == personId || $0.secondPersonId == personId }
    }
    
    // MARK: - Get Facts by Category
    
    func getFacts(category: String) -> [RememberListItem] {
        facts.filter { $0.category == category }
    }
    
    // MARK: - Record Usage
    
    func recordUsage(factId: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<RememberListItem>(
            predicate: #Predicate<RememberListItem> { $0.id == factId }
        )
        
        guard let item = try? context.fetch(descriptor).first else { return }
        
        item.lastUsedAt = Date()
        item.usageCount += 1
        
        try? context.save()
    }
}
