// ContactsService.swift
// Servicio para integración opcional con Contactos (CNContactStore)

import Foundation
import Contacts
import SwiftData

@MainActor
class ContactsService: ObservableObject {
    static let shared = ContactsService()
    
    private var modelContext: ModelContext?
    private let contactStore = CNContactStore()
    
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var importedBirthdays: [ContactBirthday] = []
    
    struct ContactBirthday: Identifiable {
        let id: String
        let contactIdentifier: String
        let name: String
        let birthdayMonth: Int
        let birthdayDay: Int
        let birthdayYear: Int?
        let matchedPersonId: String?
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await contactStore.requestAccess(for: .contacts)
            authorizationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            authorizationStatus = .denied
            return false
        }
    }
    
    // MARK: - Import Birthdays
    
    func importBirthdaysFromContacts() async {
        guard authorizationStatus == .authorized else { return }
        guard let context = modelContext else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        
        var birthdays: [ContactBirthday] = []
        
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                guard let birthday = contact.birthday,
                      let month = birthday.month,
                      let day = birthday.day else { return }
                
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                
                guard !name.isEmpty else { return }
                
                let matchedPersonId = self.findMatchingPerson(name: name, context: context)
                
                let contactBirthday = ContactBirthday(
                    id: contact.identifier,
                    contactIdentifier: contact.identifier,
                    name: name,
                    birthdayMonth: month,
                    birthdayDay: day,
                    birthdayYear: birthday.year,
                    matchedPersonId: matchedPersonId
                )
                
                birthdays.append(contactBirthday)
            }
        } catch {
            // Handle error silently
        }
        
        importedBirthdays = birthdays
        
        await createOrUpdateImportantDates(from: birthdays)
    }
    
    // MARK: - Match with Persons
    
    private func findMatchingPerson(name: String, context: ModelContext) -> String? {
        let descriptor = FetchDescriptor<PersistedPerson>()
        guard let persons = try? context.fetch(descriptor) else { return nil }
        
        let normalizedSearchName = name.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        
        for person in persons {
            guard let personName = person.name else { continue }
            let normalizedPersonName = personName.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            
            if normalizedSearchName == normalizedPersonName {
                return person.id
            }
            
            let searchParts = normalizedSearchName.split(separator: " ").map(String.init)
            let personParts = normalizedPersonName.split(separator: " ").map(String.init)
            
            let commonParts = Set(searchParts).intersection(Set(personParts))
            if commonParts.count >= 1 && searchParts.count <= 3 {
                return person.id
            }
        }
        
        return nil
    }
    
    // MARK: - Create Important Dates
    
    private func createOrUpdateImportantDates(from birthdays: [ContactBirthday]) async {
        guard let context = modelContext else { return }
        
        for birthday in birthdays {
            let existingDescriptor = FetchDescriptor<PersistedImportantDate>(
                predicate: #Predicate<PersistedImportantDate> {
                    $0.sourceRaw == "contacts" &&
                    $0.personName == birthday.name
                }
            )
            
            let existing = try? context.fetch(existingDescriptor).first
            
            if let existing = existing {
                if existing.month != birthday.birthdayMonth || existing.day != birthday.birthdayDay {
                    existing.month = birthday.birthdayMonth
                    existing.day = birthday.birthdayDay
                    existing.year = birthday.birthdayYear
                    existing.lastUpdatedAt = Date()
                }
                
                if birthday.matchedPersonId != nil && existing.personId != birthday.matchedPersonId {
                    existing.personId = birthday.matchedPersonId
                    existing.confidence = 0.9
                }
            } else {
                let importantDate = PersistedImportantDate(
                    dateType: .birthday,
                    source: .contacts,
                    month: birthday.birthdayMonth,
                    day: birthday.birthdayDay,
                    year: birthday.birthdayYear,
                    personId: birthday.matchedPersonId,
                    personName: birthday.name,
                    confidence: birthday.matchedPersonId != nil ? 0.9 : 0.7,
                    yearsDetected: 0
                )
                
                context.insert(importantDate)
            }
        }
        
        try? context.save()
    }
    
    // MARK: - Link Person to Contact
    
    func linkPersonToContact(personId: String, contactIdentifier: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate<PersistedPerson> { $0.id == personId }
        )
        
        if let person = try? context.fetch(descriptor).first {
            person.contactIdentifier = contactIdentifier
            try? context.save()
        }
        
        let contactDescriptor = FetchDescriptor<PersistedImportantDate>(
            predicate: #Predicate<PersistedImportantDate> {
                $0.sourceRaw == "contacts"
            }
        )
        
        if let dates = try? context.fetch(contactDescriptor) {
            for date in dates {
                let keysToFetch: [CNKeyDescriptor] = [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor
                ]
                
                if let contact = try? contactStore.unifiedContact(withIdentifier: contactIdentifier, keysToFetch: keysToFetch) {
                    let contactName = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    
                    if date.personName == contactName {
                        date.personId = personId
                        date.confidence = 1.0
                        date.isUserConfirmed = true
                        date.lastUpdatedAt = Date()
                    }
                }
            }
            
            try? context.save()
        }
    }
    
    // MARK: - Suggest Matches
    
    func getSuggestedMatches() async -> [(contactBirthday: ContactBirthday, suggestedPerson: PersistedPerson)] {
        guard let context = modelContext else { return [] }
        
        var suggestions: [(ContactBirthday, PersistedPerson)] = []
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.name != nil && $0.contactIdentifier == nil }
        )
        
        let unmatchedPersons = (try? context.fetch(descriptor)) ?? []
        
        for birthday in importedBirthdays where birthday.matchedPersonId == nil {
            let normalizedBirthdayName = birthday.name.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            
            for person in unmatchedPersons {
                guard let personName = person.name else { continue }
                let normalizedPersonName = personName.lowercased().folding(options: .diacriticInsensitive, locale: .current)
                
                let birthdayParts = Set(normalizedBirthdayName.split(separator: " ").map(String.init))
                let personParts = Set(normalizedPersonName.split(separator: " ").map(String.init))
                
                let intersection = birthdayParts.intersection(personParts)
                
                if !intersection.isEmpty {
                    suggestions.append((birthday, person))
                    break
                }
            }
        }
        
        return suggestions
    }
}
