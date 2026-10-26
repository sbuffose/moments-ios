// TimelineViewModel.swift
// ViewModel para la línea de tiempo

import Foundation
import SwiftData
import MomentsEngine

@MainActor
class TimelineViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isLoading = true
    @Published var sections: [TimelineSectionItem] = []
    @Published var onThisDayMemories: [OnThisDayMemoryItem] = []
    @Published var trips: [TripItem] = []
    @Published var selectedMoment: MomentItem?
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private let timelineAnalyzer = TimelineAnalyzer()
    
    // MARK: - Models
    
    struct TimelineSectionItem: Identifiable {
        let id: String
        let year: Int
        let month: Int?
        let monthName: String?
        let moments: [MomentItem]
        let totalPhotos: Int
    }
    
    struct MomentItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let startDate: Date
        let endDate: Date
        let photoIds: [String]
        let coverPhotoId: String?
        let locationName: String?
        let isTrip: Bool
        
        var photoCount: Int { photoIds.count }
        
        var durationDays: Int {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: startDate, to: endDate)
            return max(1, (components.day ?? 0) + 1)
        }
    }
    
    struct TripItem: Identifiable {
        let id: String
        let destination: String
        let startDate: Date
        let endDate: Date
        let photoCount: Int
        let coverPhotoId: String?
        let distanceFromHome: Double
    }
    
    struct OnThisDayMemoryItem: Identifiable {
        let id: String
        let yearsAgo: Int
        let photos: [PersistedPhoto]
        let momentTitle: String?
    }
    
    // MARK: - Initialization
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await loadTimeline()
            await loadOnThisDayMemories()
        }
    }
    
    // MARK: - Loading
    
    func loadTimeline() async {
        guard let context = modelContext else { return }
        
        isLoading = true
        
        do {
            let momentDescriptor = FetchDescriptor<PersistedMoment>()
            
            var persistedMoments = try context.fetch(momentDescriptor)
            persistedMoments.sort { $0.startDate > $1.startDate }
            
            if persistedMoments.isEmpty {
                await generateMoments()
            } else {
                await loadFromPersistedMoments(persistedMoments)
            }
            
            isLoading = false
            
        } catch {
            errorMessage = "Error al cargar línea de tiempo: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func loadFromPersistedMoments(_ persistedMoments: [PersistedMoment]) async {
        let calendar = Calendar(identifier: .gregorian)
        
        let grouped = Dictionary(grouping: persistedMoments) { moment -> String in
            let year = calendar.component(.year, from: moment.startDate)
            let month = calendar.component(.month, from: moment.startDate)
            return "\(year)-\(month)"
        }
        
        var sectionItems: [TimelineSectionItem] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        
        for (key, moments) in grouped {
            let parts = key.split(separator: "-")
            let year = Int(parts[0]) ?? 0
            let month = Int(parts[1]) ?? 0
            
            let momentItems = moments.map { moment -> MomentItem in
                MomentItem(
                    id: moment.id,
                    title: moment.title ?? generateMomentTitle(for: moment),
                    subtitle: moment.subtitle,
                    startDate: moment.startDate,
                    endDate: moment.endDate,
                    photoIds: moment.photoIdArray,
                    coverPhotoId: moment.coverPhotoId,
                    locationName: moment.locationName,
                    isTrip: moment.isTrip
                )
            }.sorted { $0.startDate > $1.startDate }
            
            let totalPhotos = momentItems.reduce(0) { $0 + $1.photoCount }
            
            sectionItems.append(TimelineSectionItem(
                id: key,
                year: year,
                month: month,
                monthName: formatter.monthSymbols[month - 1].capitalized,
                moments: momentItems,
                totalPhotos: totalPhotos
            ))
        }
        
        sections = sectionItems.sorted { section1, section2 in
            if section1.year != section2.year {
                return section1.year > section2.year
            }
            return (section1.month ?? 0) > (section2.month ?? 0)
        }
        
        // Cargar viajes
        trips = persistedMoments
            .filter { $0.isTrip }
            .map { moment in
                TripItem(
                    id: moment.id,
                    destination: moment.tripDestination ?? moment.locationName ?? "Viaje",
                    startDate: moment.startDate,
                    endDate: moment.endDate,
                    photoCount: moment.photoIdArray.count,
                    coverPhotoId: moment.coverPhotoId,
                    distanceFromHome: 0
                )
            }
            .sorted { $0.startDate > $1.startDate }
    }
    
    private func generateMoments() async {
        guard let context = modelContext else { return }
        
        do {
            let photoDescriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.creationDate != nil }
            )
            
            var photos = try context.fetch(photoDescriptor)
            photos.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            
            // Convertir a PhotoMetadata para el análisis
            let photoMetadata = photos.map { photo -> PhotoMetadata in
                var coordinate: Coordinate?
                if let lat = photo.latitude, let lon = photo.longitude {
                    coordinate = Coordinate(latitude: lat, longitude: lon)
                }
                
                return PhotoMetadata(
                    id: photo.id,
                    creationDate: photo.creationDate,
                    modificationDate: photo.modificationDate,
                    mediaType: photo.mediaTypeRaw == "video" ? .video : .image,
                    mediaSubtypes: [],
                    pixelWidth: photo.pixelWidth,
                    pixelHeight: photo.pixelHeight,
                    location: coordinate,
                    isFavorite: photo.isFavorite,
                    sharpnessScore: photo.sharpnessScore,
                    facesDetected: photo.facesDetected
                )
            }
            
            // Generar momentos
            let moments = timelineAnalyzer.generateMoments(from: photoMetadata)
            
            // Persistir momentos
            for moment in moments {
                let persisted = PersistedMoment(
                    id: moment.id,
                    title: moment.title,
                    startDate: moment.startDate,
                    endDate: moment.endDate,
                    photoIds: moment.photos.map { $0.id },
                    coverPhotoId: moment.coverPhotoId,
                    latitude: moment.location?.latitude,
                    longitude: moment.location?.longitude,
                    isTrip: moment.isTrip
                )
                context.insert(persisted)
            }
            
            try context.save()
            
            // Recargar
            await loadTimeline()
            
        } catch {
            errorMessage = "Error generando momentos: \(error.localizedDescription)"
        }
    }
    
    private func generateMomentTitle(for moment: PersistedMoment) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        
        if let locationName = moment.locationName, !locationName.isEmpty {
            return locationName
        }
        
        if moment.isTrip, let destination = moment.tripDestination {
            return "Viaje a \(destination)"
        }
        
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: moment.startDate, to: moment.endDate).day ?? 0
        
        if days == 0 {
            formatter.dateFormat = "EEEE d 'de' MMMM"
            return formatter.string(from: moment.startDate)
        } else {
            formatter.dateFormat = "d 'de' MMMM"
            return formatter.string(from: moment.startDate)
        }
    }
    
    // MARK: - On This Day
    
    func loadOnThisDayMemories() async {
        guard let context = modelContext else { return }
        
        let calendar = Calendar.current
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentDay = calendar.component(.day, from: today)
        let currentYear = calendar.component(.year, from: today)
        
        do {
            let descriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.creationDate != nil }
            )
            
            let allPhotos = try context.fetch(descriptor)
            
            // Filtrar fotos del mismo día en años anteriores
            let onThisDayPhotos = allPhotos.filter { photo in
                guard let date = photo.creationDate else { return false }
                let month = calendar.component(.month, from: date)
                let day = calendar.component(.day, from: date)
                let year = calendar.component(.year, from: date)
                return month == currentMonth && day == currentDay && year < currentYear
            }
            
            // Agrupar por año
            let byYear = Dictionary(grouping: onThisDayPhotos) { photo -> Int in
                guard let date = photo.creationDate else { return 0 }
                return calendar.component(.year, from: date)
            }
            
            onThisDayMemories = byYear.map { (year, photos) in
                OnThisDayMemoryItem(
                    id: "\(year)",
                    yearsAgo: currentYear - year,
                    photos: photos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) },
                    momentTitle: nil
                )
            }.sorted { $0.yearsAgo < $1.yearsAgo }
            
        } catch {
            print("Error loading on this day: \(error)")
        }
    }
}
