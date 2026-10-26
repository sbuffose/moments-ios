// PeopleViewModel.swift
// ViewModel para la vista de personas

import Foundation
import SwiftData
import MomentsEngine

@MainActor
class PeopleViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isLoading = true
    @Published var people: [PersonItem] = []
    @Published var upcomingBirthdays: [BirthdayItem] = []
    @Published var recurringEvents: [RecurringEventItem] = []
    @Published var selectedPerson: PersonItem?
    @Published var isEditingName = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private let peopleAnalyzer = PeopleAnalyzer()
    
    // MARK: - Models
    
    struct PersonItem: Identifiable, Hashable {
        let id: String
        var name: String?
        let faceClusterId: String
        let representativePhotoId: String?
        let photoIds: [String]
        let faceCount: Int
        var birthdayMonth: Int?
        var birthdayDay: Int?
        var isFavorite: Bool
        
        var isNamed: Bool { name != nil && !name!.isEmpty }
        var photoCount: Int { photoIds.count }
        
        var displayName: String {
            name ?? "Persona sin nombre"
        }
        
        var birthdayString: String? {
            guard let month = birthdayMonth, let day = birthdayDay else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_AR")
            let monthName = formatter.monthSymbols[month - 1]
            return "\(day) de \(monthName)"
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: PersonItem, rhs: PersonItem) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    struct BirthdayItem: Identifiable {
        let id: String
        let person: PersonItem
        let daysUntil: Int
        
        var displayText: String {
            if daysUntil == 0 {
                return "¡Hoy!"
            } else if daysUntil == 1 {
                return "Mañana"
            } else {
                return "En \(daysUntil) días"
            }
        }
    }
    
    struct RecurringEventItem: Identifiable {
        let id: String
        let title: String
        let date: String
        let yearsCount: Int
        let personName: String?
        let nextOccurrenceDays: Int?
    }
    
    // MARK: - Initialization
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await loadPeople()
            await loadUpcomingBirthdays()
            await loadRecurringEvents()
        }
    }
    
    // MARK: - Loading
    
    func loadPeople() async {
        guard let context = modelContext else { return }
        
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<PersistedPerson>()
            
            var persistedPeople = try context.fetch(descriptor)
            
            // Sort: favorites first, then by face count descending
            persistedPeople.sort { p1, p2 in
                if p1.isFavorite != p2.isFavorite {
                    return p1.isFavorite && !p2.isFavorite
                }
                return p1.faceCount > p2.faceCount
            }
            
            if persistedPeople.isEmpty {
                await generatePeople()
            } else {
                people = persistedPeople.map { person in
                    PersonItem(
                        id: person.id,
                        name: person.name,
                        faceClusterId: person.faceClusterId,
                        representativePhotoId: person.representativeFacePhotoId,
                        photoIds: person.photoIdArray,
                        faceCount: person.faceCount,
                        birthdayMonth: person.birthdayMonth,
                        birthdayDay: person.birthdayDay,
                        isFavorite: person.isFavorite
                    )
                }
            }
            
            isLoading = false
            
        } catch {
            errorMessage = "Error al cargar personas: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func generatePeople() async {
        guard let context = modelContext else { return }
        
        do {
            let faceDescriptor = FetchDescriptor<PersistedFaceDetection>()
            let detections = try context.fetch(faceDescriptor)
            
            guard !detections.isEmpty else {
                isLoading = false
                return
            }
            
            // Convertir a modelo del engine
            let faceDetections = detections.compactMap { detection -> FaceDetection? in
                guard let featureData = detection.featurePrintData else { return nil }
                
                let featurePrint: [Double]
                do {
                    featurePrint = try JSONDecoder().decode([Double].self, from: featureData)
                } catch {
                    return nil
                }
                
                return FaceDetection(
                    id: detection.id,
                    photoId: detection.photoId,
                    boundingBox: BoundingBox(
                        x: detection.boundingBoxX,
                        y: detection.boundingBoxY,
                        width: detection.boundingBoxWidth,
                        height: detection.boundingBoxHeight
                    ),
                    featurePrint: featurePrint,
                    quality: detection.quality
                )
            }
            
            // Clusterizar
            let clusters = peopleAnalyzer.clusterFaces(detections: faceDetections)
            let generatedPeople = peopleAnalyzer.createPeople(from: clusters)
            
            // Persistir
            for person in generatedPeople {
                let persisted = PersistedPerson(
                    id: person.id,
                    name: nil,
                    faceClusterId: person.faceClusterId,
                    representativeFacePhotoId: person.representativeFacePhotoId,
                    photoIds: person.photoIds,
                    faceCount: person.faceCount
                )
                context.insert(persisted)
            }
            
            try context.save()
            await loadPeople()
            
        } catch {
            errorMessage = "Error generando personas: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Birthdays
    
    func loadUpcomingBirthdays() async {
        let today = Date()
        let calendar = Calendar.current
        
        upcomingBirthdays = people
            .filter { $0.birthdayMonth != nil && $0.birthdayDay != nil }
            .compactMap { person -> BirthdayItem? in
                guard let month = person.birthdayMonth, let day = person.birthdayDay else { return nil }
                
                var components = DateComponents()
                components.month = month
                components.day = day
                components.year = calendar.component(.year, from: today)
                
                guard var birthdayThisYear = calendar.date(from: components) else { return nil }
                
                if birthdayThisYear < today {
                    components.year = (components.year ?? 0) + 1
                    birthdayThisYear = calendar.date(from: components) ?? birthdayThisYear
                }
                
                let daysUntil = calendar.dateComponents([.day], from: today, to: birthdayThisYear).day ?? 0
                
                guard daysUntil <= 30 else { return nil }
                
                return BirthdayItem(
                    id: person.id,
                    person: person,
                    daysUntil: daysUntil
                )
            }
            .sorted { $0.daysUntil < $1.daysUntil }
    }
    
    // MARK: - Recurring Events
    
    func loadRecurringEvents() async {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<PersistedRecurringEvent>()
            
            var events = try context.fetch(descriptor)
            events.sort { $0.confidence > $1.confidence }
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_AR")
            
            recurringEvents = events.map { event in
                let monthName = formatter.monthSymbols[event.month - 1]
                
                return RecurringEventItem(
                    id: event.id,
                    title: event.personName != nil ? "Cumpleaños de \(event.personName!)" : "Evento recurrente",
                    date: "\(event.day) de \(monthName)",
                    yearsCount: 0,
                    personName: event.personName,
                    nextOccurrenceDays: calculateDaysUntil(month: event.month, day: event.day)
                )
            }
            
        } catch {
            print("Error loading recurring events: \(error)")
        }
    }
    
    private func calculateDaysUntil(month: Int, day: Int) -> Int {
        let calendar = Calendar.current
        let today = Date()
        
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = calendar.component(.year, from: today)
        
        guard var targetDate = calendar.date(from: components) else { return 365 }
        
        if targetDate < today {
            components.year = (components.year ?? 0) + 1
            targetDate = calendar.date(from: components) ?? targetDate
        }
        
        return calendar.dateComponents([.day], from: today, to: targetDate).day ?? 365
    }
    
    // MARK: - Person Management
    
    func updatePersonName(_ person: PersonItem, name: String) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.id == person.id }
        )
        
        do {
            if let persisted = try context.fetch(descriptor).first {
                persisted.name = name.isEmpty ? nil : name
                try context.save()
                await loadPeople()
            }
        } catch {
            errorMessage = "Error al guardar nombre: \(error.localizedDescription)"
        }
    }
    
    func updatePersonBirthday(_ person: PersonItem, month: Int, day: Int) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.id == person.id }
        )
        
        do {
            if let persisted = try context.fetch(descriptor).first {
                persisted.birthdayMonth = month
                persisted.birthdayDay = day
                try context.save()
                await loadPeople()
                await loadUpcomingBirthdays()
            }
        } catch {
            errorMessage = "Error al guardar cumpleaños: \(error.localizedDescription)"
        }
    }
    
    func toggleFavorite(_ person: PersonItem) async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.id == person.id }
        )
        
        do {
            if let persisted = try context.fetch(descriptor).first {
                persisted.isFavorite.toggle()
                try context.save()
                await loadPeople()
            }
        } catch {
            errorMessage = "Error al actualizar favorito: \(error.localizedDescription)"
        }
    }
}
