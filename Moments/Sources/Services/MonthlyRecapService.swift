// MonthlyRecapService.swift
// Service for generating "Tu mes en fotos" monthly recaps

import Foundation
import SwiftData
import CoreLocation
import UserNotifications

@MainActor
class MonthlyRecapService: ObservableObject {
    static let shared = MonthlyRecapService()
    
    private var modelContext: ModelContext?
    
    static let recapNotificationIdentifier = "monthly-recap"
    static let notificationHour = 10
    
    @Published var currentRecap: MonthlyRecapData?
    @Published var isGenerating = false
    
    private init() {}
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Recap Generation
    
    func generateRecap(for month: Int, year: Int) async -> MonthlyRecapData? {
        guard let context = modelContext else { return nil }
        
        isGenerating = true
        defer { isGenerating = false }
        
        let calendar = Calendar.current
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1
        
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else {
            return nil
        }
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { photo in
                photo.creationDate != nil &&
                photo.creationDate! >= startDate &&
                photo.creationDate! < endDate
            }
        )
        
        guard let photos = try? context.fetch(descriptor), !photos.isEmpty else {
            return nil
        }
        
        let totalPhotos = photos.count
        let topPlaces = await getTopPlaces(photos: photos, context: context)
        let mostSeenPeople = await getMostSeenPeople(photos: photos, context: context)
        let highlights = await getHighlights(photos: photos)
        let trips = await getTrips(for: month, year: year, context: context)
        let firsts = await getFirsts(photos: photos, context: context)
        let busiestDay = getBusiestDay(photos: photos)
        let spaceFreed = await getSpaceFreed(for: month, year: year, context: context)
        
        let monthName = getSpanishMonthName(month)
        
        let recap = MonthlyRecapData(
            month: month,
            year: year,
            monthName: monthName,
            totalPhotos: totalPhotos,
            topPlaces: topPlaces,
            mostSeenPeople: mostSeenPeople,
            highlights: highlights,
            trips: trips,
            firsts: firsts,
            busiestDay: busiestDay,
            spaceFreedBytes: spaceFreed,
            generatedAt: Date()
        )
        
        let narrative = await generateNarrative(for: recap)
        var finalRecap = recap
        finalRecap.narrative = narrative
        
        currentRecap = finalRecap
        return finalRecap
    }
    
    func generateCurrentMonthRecap() async -> MonthlyRecapData? {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        return await generateRecap(for: month, year: year)
    }
    
    func generatePreviousMonthRecap() async -> MonthlyRecapData? {
        let calendar = Calendar.current
        let now = Date()
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
            return nil
        }
        let month = calendar.component(.month, from: previousMonth)
        let year = calendar.component(.year, from: previousMonth)
        return await generateRecap(for: month, year: year)
    }
    
    // MARK: - Top Places
    
    private func getTopPlaces(photos: [PersistedPhoto], context: ModelContext) async -> [MonthlyRecapPlace] {
        var placeGroups: [String: (photos: [PersistedPhoto], lat: Double, lon: Double)] = [:]
        
        for photo in photos {
            guard let lat = photo.latitude, let lon = photo.longitude else { continue }
            
            if let clusterId = photo.placeClusterId {
                if placeGroups[clusterId] == nil {
                    placeGroups[clusterId] = ([], lat, lon)
                }
                placeGroups[clusterId]?.photos.append(photo)
            } else if let city = photo.placeCity {
                let key = "city_\(city)"
                if placeGroups[key] == nil {
                    placeGroups[key] = ([], lat, lon)
                }
                placeGroups[key]?.photos.append(photo)
            }
        }
        
        let clusterDescriptor = FetchDescriptor<PersistedPlaceCluster>()
        let clusters = (try? context.fetch(clusterDescriptor)) ?? []
        let clusterMap = Dictionary(uniqueKeysWithValues: clusters.map { ($0.id, $0) })
        
        var places: [MonthlyRecapPlace] = []
        for (key, group) in placeGroups {
            let name: String
            if key.hasPrefix("city_") {
                name = String(key.dropFirst(5))
            } else if let cluster = clusterMap[key] {
                name = cluster.displayName
            } else {
                continue
            }
            
            places.append(MonthlyRecapPlace(
                name: name,
                photoCount: group.photos.count,
                latitude: group.lat,
                longitude: group.lon,
                representativePhotoId: group.photos.first?.id
            ))
        }
        
        return places.sorted { $0.photoCount > $1.photoCount }.prefix(5).map { $0 }
    }
    
    // MARK: - Most Seen People
    
    private func getMostSeenPeople(photos: [PersistedPhoto], context: ModelContext) async -> [MonthlyRecapPerson] {
        let photoIds = Set(photos.map { $0.id })
        
        let personDescriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.name != nil }
        )
        let people = (try? context.fetch(personDescriptor)) ?? []
        
        var personCounts: [(person: PersistedPerson, count: Int)] = []
        
        for person in people {
            let personPhotoIds = Set(person.photoIdArray)
            let matchCount = photoIds.intersection(personPhotoIds).count
            if matchCount > 0 {
                personCounts.append((person, matchCount))
            }
        }
        
        return personCounts
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { MonthlyRecapPerson(
                name: $0.person.name ?? "",
                photoCount: $0.count,
                personId: $0.person.id,
                representativePhotoId: $0.person.representativeFacePhotoId
            )}
    }
    
    // MARK: - Highlights (Best Aesthetics)
    
    private func getHighlights(photos: [PersistedPhoto]) async -> [MonthlyRecapHighlight] {
        let calendar = Calendar.current
        
        var dayGroups: [Date: [PersistedPhoto]] = [:]
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            let dayStart = calendar.startOfDay(for: date)
            if dayGroups[dayStart] == nil {
                dayGroups[dayStart] = []
            }
            dayGroups[dayStart]?.append(photo)
        }
        
        var highlights: [MonthlyRecapHighlight] = []
        var usedDHashes: Set<Int64> = []
        
        for (day, dayPhotos) in dayGroups {
            let best = dayPhotos
                .filter { photo in
                    if let dhash = photo.imageDHash, usedDHashes.contains(dhash) {
                        return false
                    }
                    return true
                }
                .max { ($0.visionAestheticsScore ?? 0) < ($1.visionAestheticsScore ?? 0) }
            
            if let bestPhoto = best {
                if let dhash = bestPhoto.imageDHash {
                    usedDHashes.insert(dhash)
                }
                
                highlights.append(MonthlyRecapHighlight(
                    photoId: bestPhoto.id,
                    localIdentifier: bestPhoto.localIdentifier,
                    date: day,
                    aestheticsScore: bestPhoto.visionAestheticsScore ?? 0,
                    placeName: bestPhoto.placeName ?? bestPhoto.placeCity
                ))
            }
        }
        
        return highlights
            .sorted { $0.aestheticsScore > $1.aestheticsScore }
            .prefix(10)
            .map { $0 }
    }
    
    // MARK: - Trips
    
    private func getTrips(for month: Int, year: Int, context: ModelContext) async -> [MonthlyRecapTrip] {
        let calendar = Calendar.current
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1
        
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else {
            return []
        }
        
        let tripDescriptor = FetchDescriptor<PersistedMoment>(
            predicate: #Predicate { moment in
                moment.isTrip &&
                moment.startDate >= startDate &&
                moment.startDate < endDate
            }
        )
        
        let moments = (try? context.fetch(tripDescriptor)) ?? []
        
        return moments.map { moment in
            let days = calendar.dateComponents([.day], from: moment.startDate, to: moment.endDate).day ?? 1
            return MonthlyRecapTrip(
                destination: moment.tripDestination ?? moment.locationName ?? "Viaje",
                startDate: moment.startDate,
                endDate: moment.endDate,
                durationDays: max(1, days),
                photoCount: moment.photoIdArray.count,
                coverPhotoId: moment.coverPhotoId
            )
        }
    }
    
    // MARK: - Firsts
    
    private func getFirsts(photos: [PersistedPhoto], context: ModelContext) async -> [MonthlyRecapFirst] {
        var firsts: [MonthlyRecapFirst] = []
        
        let clusterDescriptor = FetchDescriptor<PersistedPlaceCluster>()
        let clusters = (try? context.fetch(clusterDescriptor)) ?? []
        
        for photo in photos {
            guard let clusterId = photo.placeClusterId,
                  let cluster = clusters.first(where: { $0.id == clusterId }),
                  let firstVisit = cluster.firstVisit,
                  let photoDate = photo.creationDate else { continue }
            
            let calendar = Calendar.current
            if calendar.isDate(firstVisit, equalTo: photoDate, toGranularity: .day) {
                firsts.append(MonthlyRecapFirst(
                    type: .place,
                    description: cluster.displayName,
                    date: photoDate,
                    photoId: photo.id
                ))
            }
        }
        
        return Array(firsts.prefix(5))
    }
    
    // MARK: - Busiest Day
    
    private func getBusiestDay(photos: [PersistedPhoto]) -> MonthlyRecapBusiestDay? {
        let calendar = Calendar.current
        var dayGroups: [Date: Int] = [:]
        
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            let dayStart = calendar.startOfDay(for: date)
            dayGroups[dayStart, default: 0] += 1
        }
        
        guard let (date, count) = dayGroups.max(by: { $0.value < $1.value }) else {
            return nil
        }
        
        return MonthlyRecapBusiestDay(date: date, photoCount: count)
    }
    
    // MARK: - Space Freed
    
    private func getSpaceFreed(for month: Int, year: Int, context: ModelContext) async -> Int64 {
        let calendar = Calendar.current
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1
        
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else {
            return 0
        }
        
        let recordDescriptor = FetchDescriptor<DeletionRecord>(
            predicate: #Predicate { record in
                record.requestedAt >= startDate &&
                record.requestedAt < endDate &&
                record.wasSuccessful == true
            }
        )
        
        let records = (try? context.fetch(recordDescriptor)) ?? []
        return records.reduce(0) { $0 + $1.fileSize }
    }
    
    // MARK: - Narrative Generation
    
    private func generateNarrative(for recap: MonthlyRecapData) async -> String {
        let facts = buildStructuredFacts(for: recap)
        
        if #available(iOS 26.0, *) {
            if let aiNarrative = await generateWithFoundationModels(facts: facts, recap: recap) {
                return aiNarrative
            }
        }
        
        return generateTemplateNarrative(for: recap)
    }
    
    private func buildStructuredFacts(for recap: MonthlyRecapData) -> [String: Any] {
        var facts: [String: Any] = [
            "monthName": recap.monthName,
            "totalPhotos": recap.totalPhotos
        ]
        
        if !recap.topPlaces.isEmpty {
            facts["topPlace"] = recap.topPlaces[0].name
            facts["topPlaceCount"] = recap.topPlaces[0].photoCount
        }
        
        if !recap.mostSeenPeople.isEmpty {
            facts["topPeople"] = recap.mostSeenPeople.prefix(3).map { $0.name }
        }
        
        if !recap.trips.isEmpty {
            facts["trips"] = recap.trips.map { [
                "destination": $0.destination,
                "days": $0.durationDays
            ]}
        }
        
        if let busiest = recap.busiestDay {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es-AR")
            formatter.dateFormat = "d 'de' MMMM"
            facts["busiestDay"] = formatter.string(from: busiest.date)
            facts["busiestDayCount"] = busiest.photoCount
        }
        
        if recap.spaceFreedBytes > 0 {
            facts["spaceFreedMB"] = recap.spaceFreedBytes / 1_000_000
        }
        
        return facts
    }
    
    @available(iOS 26.0, *)
    private func generateWithFoundationModels(facts: [String: Any], recap: MonthlyRecapData) async -> String? {
        return nil
    }
    
    private func generateTemplateNarrative(for recap: MonthlyRecapData) -> String {
        var parts: [String] = []
        
        parts.append("\(recap.monthName) fue")
        
        if !recap.trips.isEmpty {
            let tripNames = recap.trips.map { $0.destination }
            if tripNames.count == 1 {
                parts.append("viaje a \(tripNames[0])")
            } else {
                parts.append("viajes a \(tripNames.joined(separator: " y "))")
            }
        } else if !recap.topPlaces.isEmpty {
            parts.append(recap.topPlaces[0].name.lowercased())
        }
        
        if !recap.mostSeenPeople.isEmpty {
            let names = recap.mostSeenPeople.prefix(2).map { $0.name }
            parts.append("con \(names.joined(separator: " y "))")
        }
        
        var narrative = parts.joined(separator: " ")
        
        if !recap.trips.isEmpty, let trip = recap.trips.first {
            narrative += ": \(trip.durationDays) días en \(trip.destination)"
            if !recap.mostSeenPeople.isEmpty {
                let names = recap.mostSeenPeople.prefix(2).map { $0.name }
                narrative += " con \(names.joined(separator: " y "))"
            }
        }
        
        narrative += "."
        
        if let busiest = recap.busiestDay {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es-AR")
            formatter.dateFormat = "d 'de' MMMM"
            narrative += " El \(formatter.string(from: busiest.date)) sacaste \(busiest.photoCount) fotos."
        }
        
        if recap.spaceFreedBytes > 1_000_000 {
            let mb = recap.spaceFreedBytes / 1_000_000
            narrative += " Liberaste \(mb) MB con Moments."
        }
        
        return narrative
    }
    
    // MARK: - Spanish Month Names
    
    private func getSpanishMonthName(_ month: Int) -> String {
        let months = [
            "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
            "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
        ]
        return months[max(0, min(month - 1, 11))]
    }
    
    // MARK: - Notifications
    
    func scheduleMonthlyRecapNotification() async {
        let center = UNUserNotificationCenter.current()
        
        center.removePendingNotificationRequests(withIdentifiers: [Self.recapNotificationIdentifier])
        
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        
        let content = UNMutableNotificationContent()
        
        let calendar = Calendar.current
        let now = Date()
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return }
        let monthName = getSpanishMonthName(calendar.component(.month, from: previousMonth))
        
        content.title = "Tu \(monthName.lowercased()) en fotos está listo"
        content.body = "Mirá cómo fue tu mes 📷"
        content.sound = .default
        content.categoryIdentifier = "MONTHLY_RECAP"
        content.userInfo = ["type": "monthlyRecap"]
        
        var dateComponents = DateComponents()
        dateComponents.day = 1
        dateComponents.hour = Self.notificationHour
        dateComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: Self.recapNotificationIdentifier,
            content: content,
            trigger: trigger
        )
        
        try? await center.add(request)
    }
    
    func cancelMonthlyRecapNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.recapNotificationIdentifier]
        )
    }
    
    // MARK: - Query Parsing (for Assistant)
    
    func parseMonthQuery(_ query: String) -> (month: Int, year: Int)? {
        let lowercased = query.lowercased()
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        
        let monthMappings: [String: Int] = [
            "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
            "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
            "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12
        ]
        
        for (name, month) in monthMappings {
            if lowercased.contains(name) {
                let year = month > currentMonth ? currentYear - 1 : currentYear
                return (month, year)
            }
        }
        
        if lowercased.contains("este mes") || lowercased.contains("mes actual") {
            return (currentMonth, currentYear)
        }
        
        if lowercased.contains("mes pasado") || lowercased.contains("último mes") {
            if let previousMonth = calendar.date(byAdding: .month, value: -1, to: now) {
                return (calendar.component(.month, from: previousMonth),
                        calendar.component(.year, from: previousMonth))
            }
        }
        
        return nil
    }
}

// MARK: - Data Models

struct MonthlyRecapData: Identifiable {
    let id = UUID()
    let month: Int
    let year: Int
    let monthName: String
    let totalPhotos: Int
    let topPlaces: [MonthlyRecapPlace]
    let mostSeenPeople: [MonthlyRecapPerson]
    let highlights: [MonthlyRecapHighlight]
    let trips: [MonthlyRecapTrip]
    let firsts: [MonthlyRecapFirst]
    let busiestDay: MonthlyRecapBusiestDay?
    let spaceFreedBytes: Int64
    let generatedAt: Date
    var narrative: String = ""
    
    var formattedSpaceFreed: String {
        ByteCountFormatter.string(fromByteCount: spaceFreedBytes, countStyle: .file)
    }
}

struct MonthlyRecapPlace: Identifiable {
    let id = UUID()
    let name: String
    let photoCount: Int
    let latitude: Double
    let longitude: Double
    let representativePhotoId: String?
}

struct MonthlyRecapPerson: Identifiable {
    let id = UUID()
    let name: String
    let photoCount: Int
    let personId: String
    let representativePhotoId: String?
}

struct MonthlyRecapHighlight: Identifiable {
    let id = UUID()
    let photoId: String
    let localIdentifier: String
    let date: Date
    let aestheticsScore: Double
    let placeName: String?
}

struct MonthlyRecapTrip: Identifiable {
    let id = UUID()
    let destination: String
    let startDate: Date
    let endDate: Date
    let durationDays: Int
    let photoCount: Int
    let coverPhotoId: String?
}

struct MonthlyRecapFirst: Identifiable {
    let id = UUID()
    let type: FirstType
    let description: String
    let date: Date
    let photoId: String?
    
    enum FirstType {
        case place
        case person
        case event
    }
}

struct MonthlyRecapBusiestDay {
    let date: Date
    let photoCount: Int
}
