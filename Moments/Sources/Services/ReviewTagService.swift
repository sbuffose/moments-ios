// ReviewTagService.swift
// In-app tags for review. No PhotoKit albums — people, fixed categories, and
// trips clustered from GPS + dates (far from home), named via reverse geocode.

import Foundation
import SwiftData
import CoreLocation

enum ReviewTagKind: String, Sendable, Equatable {
    case category
    case person
    case trip
}

protocol ReverseGeocoding: Sendable {
    func placeName(latitude: Double, longitude: Double) async -> String?
}

/// Offline-first wrapper around `GeocodingService` (cache, then CLGeocoder).
struct CachedCLGeocoder: ReverseGeocoding {
    func placeName(latitude: Double, longitude: Double) async -> String? {
        if let cached = await GeocodingService.shared.cachedLocationName(
            latitude: latitude,
            longitude: longitude
        ) {
            return cached.city ?? cached.name
        }
        if let live = await GeocodingService.shared.getLocationName(
            latitude: latitude,
            longitude: longitude
        ) {
            return live.city ?? live.name
        }
        return nil
    }
}

/// Deterministic geocoder for tests.
struct StubReverseGeocoder: ReverseGeocoding, Sendable {
    var places: [(latitude: Double, longitude: Double, name: String)]
    var matchKilometers: Double = 40
    
    func placeName(latitude: Double, longitude: Double) async -> String? {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        var best: (name: String, meters: Double)?
        for place in places {
            let meters = here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
            if best == nil || meters < best!.meters {
                best = (place.name, meters)
            }
        }
        guard let best, best.meters <= matchKilometers * 1000 else { return nil }
        return best.name
    }
}

struct TripPhotoFix: Sendable, Equatable {
    var id: String
    var date: Date
    var latitude: Double
    var longitude: Double
}

struct DetectedTrip: Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    var city: String
    var start: Date
    var end: Date
    var photoIds: [String]
    var latitude: Double
    var longitude: Double
}

struct ReviewTagOption: Identifiable, Hashable, Sendable {
    var id: String
    var kind: ReviewTagKind
    var title: String
    var subtitle: String?
    var personId: String?
    var facePhotoLocalIdentifier: String?
    var isPreselected: Bool
    var searchAliases: [String]
    
    static let familia = ReviewTagOption(
        id: "category.familia",
        kind: .category,
        title: "Familia",
        subtitle: nil,
        personId: nil,
        facePhotoLocalIdentifier: nil,
        isPreselected: false,
        searchAliases: ["familia", "family"]
    )
    static let amigos = ReviewTagOption(
        id: "category.amigos",
        kind: .category,
        title: "Amigos",
        subtitle: nil,
        personId: nil,
        facePhotoLocalIdentifier: nil,
        isPreselected: false,
        searchAliases: ["amigos", "friends"]
    )
    static let viajes = ReviewTagOption(
        id: "category.viajes",
        kind: .category,
        title: "Viajes",
        subtitle: nil,
        personId: nil,
        facePhotoLocalIdentifier: nil,
        isPreselected: false,
        searchAliases: ["viajes", "viaje", "trips", "travel"]
    )
    
    static let fixedCategories: [ReviewTagOption] = [.familia, .amigos, .viajes]
}

struct ReviewTagSheetData: Equatable {
    var people: [ReviewTagOption]
    var categories: [ReviewTagOption]
    var trips: [ReviewTagOption]
    
    var allOptions: [ReviewTagOption] { people + categories + trips }
    
    var titles: [String] { allOptions.map(\.title) }
    
    var hasDuplicateIds: Bool {
        Set(allOptions.map(\.id)).count != allOptions.count
    }
    
    var hasDuplicateTitles: Bool {
        Set(titles.map { $0.lowercased() }).count != titles.count
    }
    
    /// Raw PhotoKit album names that must never appear in this sheet.
    static let forbiddenAlbumTitles: Set<String> = [
        "whatsapp", "instagram", "dji album", "dji", "hola", "moments",
        "recientes", "recents", "camera roll", "recently deleted"
    ]
    
    var containsPhotoKitAlbum: Bool {
        titles.contains { title in
            Self.forbiddenAlbumTitles.contains(title.trimmingCharacters(in: .whitespaces).lowercased())
        }
    }
}

enum TripClustering {
    static let homeRadiusMeters: Double = 8_000
    static let frequentMinPhotos = 4
    static let tripDistanceMeters: Double = 50_000
    static let clusterRadiusMeters: Double = 40_000
    static let tripGapDays = 14
    
    static func detectTrips(
        photos: [TripPhotoFix],
        homeLocations: [CLLocation] = [],
        geocoder: ReverseGeocoding
    ) async -> [DetectedTrip] {
        let homes = homeLocations.isEmpty ? inferredHomes(from: photos) : homeLocations
        let away = photos.filter { photo in
            let loc = CLLocation(latitude: photo.latitude, longitude: photo.longitude)
            return homes.allSatisfy { loc.distance(from: $0) >= tripDistanceMeters }
        }
        let clusters = cluster(away)
        var trips: [DetectedTrip] = []
        for cluster in clusters {
            guard let first = cluster.first else { continue }
            let centroid = centroidLocation(cluster)
            let city = await geocoder.placeName(
                latitude: centroid.coordinate.latitude,
                longitude: centroid.coordinate.longitude
            ) ?? "destino"
            let start = cluster.map(\.date).min() ?? first.date
            let end = cluster.map(\.date).max() ?? first.date
            let title = tripTitle(city: city, date: start)
            trips.append(DetectedTrip(
                id: tripId(city: city, date: start),
                title: title,
                city: city,
                start: start,
                end: end,
                photoIds: cluster.map(\.id),
                latitude: centroid.coordinate.latitude,
                longitude: centroid.coordinate.longitude
            ))
        }
        return trips.sorted { $0.start < $1.start }
    }
    
    static func tripTitle(city: String, date: Date) -> String {
        let month = spanishMonthAbbrev(date)
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return "Viaje a \(city) · \(month) \(year)"
    }
    
    static func tripId(city: String, date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let slug = city
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "trip.\(slug)-\(year)-\(String(format: "%02d", month))"
    }
    
    static func spanishMonthAbbrev(_ date: Date) -> String {
        let month = Calendar(identifier: .gregorian).component(.month, from: date)
        return ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"][month - 1]
    }
    
    static func cityAliases(for city: String) -> [String] {
        let key = city.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR")).lowercased()
        var aliases = [city.lowercased(), key]
        switch key {
        case "mar del plata":
            aliases += ["mdq", "mardel", "mardelplata"]
        case "cordoba":
            aliases += ["cba", "cordoba"]
        case "buenos aires":
            aliases += ["baires", "bsas", "caba"]
        default:
            break
        }
        return Array(Set(aliases))
    }
    
    private static func inferredHomes(from photos: [TripPhotoFix]) -> [CLLocation] {
        var used = Set<String>()
        var homes: [CLLocation] = []
        for photo in photos {
            guard !used.contains(photo.id) else { continue }
            let center = CLLocation(latitude: photo.latitude, longitude: photo.longitude)
            let nearby = photos.filter {
                center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= homeRadiusMeters
            }
            nearby.forEach { used.insert($0.id) }
            if nearby.count >= frequentMinPhotos {
                homes.append(center)
            }
        }
        return homes
    }
    
    private static func cluster(_ photos: [TripPhotoFix]) -> [[TripPhotoFix]] {
        let sorted = photos.sorted { $0.date < $1.date }
        var groups: [[TripPhotoFix]] = []
        var current: [TripPhotoFix] = []
        for photo in sorted {
            if current.isEmpty {
                current = [photo]
                continue
            }
            let last = current[current.count - 1]
            let samePlace = CLLocation(latitude: photo.latitude, longitude: photo.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) <= clusterRadiusMeters
            let days = abs(photo.date.timeIntervalSince(last.date)) / 86_400
            if samePlace && days <= Double(tripGapDays) {
                current.append(photo)
            } else {
                groups.append(current)
                current = [photo]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
    
    private static func centroidLocation(_ photos: [TripPhotoFix]) -> CLLocation {
        let lat = photos.map(\.latitude).reduce(0, +) / Double(photos.count)
        let lon = photos.map(\.longitude).reduce(0, +) / Double(photos.count)
        return CLLocation(latitude: lat, longitude: lon)
    }
}

enum ReviewTagService {
    static let forbiddenAlbumTitles = ReviewTagSheetData.forbiddenAlbumTitles
    
    static func defaultGeocoder() -> ReverseGeocoding {
        let testing = ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-seedFixturePhotos")
        if testing {
            return StubReverseGeocoder(places: [
                (-38.0055, -57.5426, "Mar del Plata"),
                (-31.4201, -64.1888, "Córdoba"),
                (-34.6037, -58.3816, "Buenos Aires")
            ])
        }
        return CachedCLGeocoder()
    }
    
    @MainActor
    static func sheetData(
        photos: [PersistedPhoto],
        context: ModelContext,
        geocoder: ReverseGeocoding = ReviewTagService.defaultGeocoder()
    ) async -> ReviewTagSheetData {
        let people = namedPeople(in: context)
        let trips = await suggestedTrips(photos: photos, context: context, geocoder: geocoder)
        var data = ReviewTagSheetData(
            people: people,
            categories: ReviewTagOption.fixedCategories,
            trips: trips
        )
        data = deduplicated(data)
        return data
    }
    
    @MainActor
    static func namedPeople(in context: ModelContext) -> [ReviewTagOption] {
        let all = (try? context.fetch(FetchDescriptor<PersistedPerson>())) ?? []
        var seen = Set<String>()
        var options: [ReviewTagOption] = []
        for person in all where person.isNamed {
            let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let id = "person.\(person.id)"
            guard seen.insert(id).inserted else { continue }
            let faceId = person.representativeFacePhotoId.flatMap { stored in
                let photos = (try? context.fetch(FetchDescriptor<PersistedPhoto>())) ?? []
                return photos.first { $0.id == stored || $0.localIdentifier == stored }?.localIdentifier
            }
            options.append(ReviewTagOption(
                id: id,
                kind: .person,
                title: name,
                subtitle: nil,
                personId: person.id,
                facePhotoLocalIdentifier: faceId,
                isPreselected: false,
                searchAliases: [name.lowercased()]
            ))
        }
        return options.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    
    @MainActor
    static func suggestedTrips(
        photos: [PersistedPhoto],
        context: ModelContext,
        geocoder: ReverseGeocoding
    ) async -> [ReviewTagOption] {
        let library = (try? context.fetch(FetchDescriptor<PersistedPhoto>())) ?? []
        let withGPS: [TripPhotoFix] = library.compactMap { photo in
            guard let lat = photo.latitude, let lon = photo.longitude, let date = photo.creationDate else {
                return nil
            }
            return TripPhotoFix(id: photo.id, date: date, latitude: lat, longitude: lon)
        }
        let homes = homeLocations(from: context, photos: withGPS)
        let detected = await TripClustering.detectTrips(
            photos: withGPS,
            homeLocations: homes,
            geocoder: geocoder
        )
        let currentIds = Set(photos.map(\.id))
        return detected.map { trip in
            ReviewTagOption(
                id: trip.id,
                kind: .trip,
                title: trip.title,
                subtitle: trip.city,
                personId: nil,
                facePhotoLocalIdentifier: nil,
                isPreselected: trip.photoIds.contains(where: currentIds.contains),
                searchAliases: TripClustering.cityAliases(for: trip.city) + ["viaje", trip.title.lowercased()]
            )
        }
    }
    
    @MainActor
    static func apply(
        options: [ReviewTagOption],
        to photos: [PersistedPhoto],
        context: ModelContext
    ) {
        let unique = deduplicated(options)
        for option in unique {
            let tag = existingTag(id: option.id, context: context) ?? {
                let created = PhotoTag(id: option.id, name: option.title, photoIds: [])
                created.isSystemTag = option.kind == .category
                context.insert(created)
                return created
            }()
            tag.name = option.title
            if option.kind == .category { tag.isSystemTag = true }
            for photo in photos {
                tag.addPhoto(photo.id)
                photo.keepDecision = .forever
                photo.keepUntil = nil
                photo.keepDecisionDate = Date()
            }
        }
        try? context.save()
    }
    
    @MainActor
    static func tags(containing photoId: String, context: ModelContext) -> [PhotoTag] {
        let all = (try? context.fetch(FetchDescriptor<PhotoTag>())) ?? []
        return all.filter { $0.photoIdArray.contains(photoId) }
    }
    
    @MainActor
    static func searchTokens(for tag: PhotoTag) -> [String] {
        var tokens = [tag.name.lowercased()]
        if tag.id.hasPrefix("trip.") {
            tokens += tag.name.lowercased().split(separator: " ").map(String.init)
            if let city = tag.name.components(separatedBy: " · ").first?
                .replacingOccurrences(of: "Viaje a ", with: "") {
                tokens += TripClustering.cityAliases(for: city)
            }
        }
        if tag.id == ReviewTagOption.familia.id { tokens += ReviewTagOption.familia.searchAliases }
        if tag.id == ReviewTagOption.amigos.id { tokens += ReviewTagOption.amigos.searchAliases }
        if tag.id == ReviewTagOption.viajes.id { tokens += ReviewTagOption.viajes.searchAliases }
        return Array(Set(tokens))
    }
    
    @MainActor
    static func photoMatches(_ photo: PersistedPhoto, query: String, context: ModelContext) -> Bool {
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !["info", "de", "del", "la", "las", "los", "fotos", "foto", "a"].contains($0) }
        guard !terms.isEmpty else { return false }
        let tags = tags(containing: photo.id, context: context)
        let haystack = tags.flatMap { searchTokens(for: $0) }.joined(separator: " ")
        return terms.contains { term in haystack.contains(term) }
    }
    
    @MainActor
    static func persistedTripItems(from context: ModelContext) -> [TimelineViewModel.TripItem] {
        let tags = (try? context.fetch(FetchDescriptor<PhotoTag>())) ?? []
        return tags.filter { $0.id.hasPrefix("trip.") }.map { tag in
            TimelineViewModel.TripItem(
                id: tag.id,
                destination: tag.name,
                startDate: tag.createdAt,
                endDate: tag.createdAt,
                photoCount: tag.photoIdArray.count,
                coverPhotoId: nil,
                distanceFromHome: 0
            )
        }
    }
    
    @MainActor
    static func persistedCategoryTags(from context: ModelContext) -> [PhotoTag] {
        let tags = (try? context.fetch(FetchDescriptor<PhotoTag>())) ?? []
        return tags.filter { $0.id.hasPrefix("category.") || $0.id.hasPrefix("trip.") || $0.id.hasPrefix("person.") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private static func existingTag(id: String, context: ModelContext) -> PhotoTag? {
        let all = (try? context.fetch(FetchDescriptor<PhotoTag>())) ?? []
        return all.first { $0.id == id }
    }
    
    private static func deduplicated(_ options: [ReviewTagOption]) -> [ReviewTagOption] {
        var seen = Set<String>()
        var result: [ReviewTagOption] = []
        for option in options {
            let titleKey = option.title.lowercased()
            if ReviewTagSheetData.forbiddenAlbumTitles.contains(titleKey) { continue }
            if seen.contains(option.id) || seen.contains(titleKey) { continue }
            seen.insert(option.id)
            seen.insert(titleKey)
            result.append(option)
        }
        return result
    }
    
    private static func deduplicated(_ data: ReviewTagSheetData) -> ReviewTagSheetData {
        var seen = Set<String>()
        func take(_ items: [ReviewTagOption]) -> [ReviewTagOption] {
            items.filter { option in
                let titleKey = option.title.lowercased()
                if ReviewTagSheetData.forbiddenAlbumTitles.contains(titleKey) { return false }
                if seen.contains(option.id) || seen.contains(titleKey) { return false }
                seen.insert(option.id)
                seen.insert(titleKey)
                return true
            }
        }
        return ReviewTagSheetData(
            people: take(data.people),
            categories: take(data.categories),
            trips: take(data.trips)
        )
    }
    
    @MainActor
    private static func homeLocations(from context: ModelContext, photos: [TripPhotoFix]) -> [CLLocation] {
        let clusters = (try? context.fetch(FetchDescriptor<PersistedPlaceCluster>())) ?? []
        let labeled = clusters.compactMap { cluster -> CLLocation? in
            if cluster.placeType == .home || cluster.placeType == .familyHome || cluster.isUserLabeled {
                return CLLocation(latitude: cluster.latitude, longitude: cluster.longitude)
            }
            return nil
        }
        if !labeled.isEmpty { return labeled }
        return inferredHomesSync(photos)
    }
    
    private static func inferredHomesSync(_ photos: [TripPhotoFix]) -> [CLLocation] {
        var used = Set<String>()
        var homes: [CLLocation] = []
        for photo in photos {
            guard !used.contains(photo.id) else { continue }
            let center = CLLocation(latitude: photo.latitude, longitude: photo.longitude)
            let nearby = photos.filter {
                center.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                    <= TripClustering.homeRadiusMeters
            }
            nearby.forEach { used.insert($0.id) }
            if nearby.count >= TripClustering.frequentMinPhotos {
                homes.append(center)
            }
        }
        return homes
    }
}
