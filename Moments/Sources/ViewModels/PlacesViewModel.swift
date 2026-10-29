// PlacesViewModel.swift
// ViewModel para la vista de lugares

import Foundation
import SwiftData
import MapKit
import MomentsEngine

@MainActor
class PlacesViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isLoading = true
    @Published var places: [PlaceItem] = []
    @Published var clusters: [PlaceClusterItem] = []
    @Published var selectedPlace: PlaceItem?
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -34.6037, longitude: -58.3816), // Buenos Aires default
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    @Published var displayMode: DisplayMode = .map
    @Published var errorMessage: String?
    
    enum DisplayMode {
        case map
        case list
    }
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private let placeAnalyzer = PlaceAnalyzer()
    
    // MARK: - Models
    
    struct PlaceItem: Identifiable, Equatable {
        let id: String
        let name: String
        let address: String?
        let city: String?
        let country: String?
        let coordinate: CLLocationCoordinate2D
        let photoIds: [String]
        let firstVisit: Date?
        let lastVisit: Date?
        let visitCount: Int
        
        var photoCount: Int { photoIds.count }
        
        var displayName: String {
            if !name.isEmpty {
                return name
            } else if let city = city {
                return city
            } else if let country = country {
                return country
            }
            return "Ubicación"
        }
        
        static func == (lhs: PlaceItem, rhs: PlaceItem) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    struct PlaceClusterItem: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let places: [PlaceItem]
        
        var photoCount: Int {
            places.reduce(0) { $0 + $1.photoCount }
        }
    }
    
    // MARK: - Initialization
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await loadPlaces()
        }
    }
    
    // MARK: - Loading
    
    func loadPlaces() async {
        guard let context = modelContext else {
            isLoading = false
            return
        }
        
        do {
            let descriptor = FetchDescriptor<PersistedPlace>(
                sortBy: [SortDescriptor(\.visitCount, order: .reverse)]
            )
            
            let persistedPlaces = try context.fetch(descriptor)
            
            if !persistedPlaces.isEmpty {
                places = persistedPlaces.map { place in
                    PlaceItem(
                        id: place.id,
                        name: place.name,
                        address: place.address,
                        city: place.city,
                        country: place.country,
                        coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                        photoIds: place.photoIdArray,
                        firstVisit: place.firstVisit,
                        lastVisit: place.lastVisit,
                        visitCount: place.visitCount
                    )
                }
                
                updateClusters()
                fitMapToPlaces()
                isLoading = false
                return
            }
            
            isLoading = false
            await generatePlaces()
            
        } catch {
            errorMessage = "Error al cargar lugares: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func generatePlaces() async {
        guard let context = modelContext else { return }
        
        do {
            let photoDescriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.latitude != nil && $0.longitude != nil }
            )
            
            let photos = try context.fetch(photoDescriptor)
            
            let photoMetadata = photos.compactMap { photo -> PhotoMetadata? in
                guard let lat = photo.latitude, let lon = photo.longitude else { return nil }
                
                return PhotoMetadata(
                    id: photo.id,
                    creationDate: photo.creationDate,
                    modificationDate: photo.modificationDate,
                    mediaType: photo.mediaTypeRaw == "video" ? .video : .image,
                    mediaSubtypes: [],
                    pixelWidth: photo.pixelWidth,
                    pixelHeight: photo.pixelHeight,
                    location: Coordinate(latitude: lat, longitude: lon)
                )
            }
            
            let generatedPlaces = placeAnalyzer.clusterPlaces(from: photoMetadata)
            
            for place in generatedPlaces {
                // Reverse geocoding para obtener el nombre
                let locationName = await GeocodingService.shared.getLocationName(
                    latitude: place.coordinate.latitude,
                    longitude: place.coordinate.longitude
                )
                
                let persisted = PersistedPlace(
                    id: place.id,
                    name: locationName?.name ?? "",
                    city: locationName?.city,
                    country: locationName?.country,
                    latitude: place.coordinate.latitude,
                    longitude: place.coordinate.longitude,
                    radius: place.radius,
                    photoIds: place.photoIds,
                    firstVisit: place.firstVisit,
                    lastVisit: place.lastVisit,
                    visitCount: place.visitCount
                )
                
                context.insert(persisted)
            }
            
            try context.save()
            await loadPlaces()
            
        } catch {
            errorMessage = "Error generando lugares: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Clustering
    
    func updateClusters() {
        let zoomLevel = calculateZoomLevel(from: mapRegion.span)
        
        if zoomLevel > 14 {
            clusters = places.map { place in
                PlaceClusterItem(
                    id: place.id,
                    coordinate: place.coordinate,
                    places: [place]
                )
            }
        } else {
            clusters = clusterPlaces(places, radius: clusterRadius(for: zoomLevel))
        }
    }
    
    private func calculateZoomLevel(from span: MKCoordinateSpan) -> Double {
        let maxSpan = max(span.latitudeDelta, span.longitudeDelta)
        return max(0, min(20, log2(360 / maxSpan)))
    }
    
    private func clusterRadius(for zoomLevel: Double) -> Double {
        100_000 / pow(2, zoomLevel)
    }
    
    private func clusterPlaces(_ places: [PlaceItem], radius: Double) -> [PlaceClusterItem] {
        var clusters: [PlaceClusterItem] = []
        var processed = Set<String>()
        
        for place in places {
            guard !processed.contains(place.id) else { continue }
            
            var clusterPlaces: [PlaceItem] = [place]
            processed.insert(place.id)
            
            let placeLoc = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            
            for other in places {
                guard !processed.contains(other.id) else { continue }
                
                let otherLoc = CLLocation(latitude: other.coordinate.latitude, longitude: other.coordinate.longitude)
                let distance = placeLoc.distance(from: otherLoc)
                
                if distance <= radius {
                    clusterPlaces.append(other)
                    processed.insert(other.id)
                }
            }
            
            let centerLat = clusterPlaces.reduce(0) { $0 + $1.coordinate.latitude } / Double(clusterPlaces.count)
            let centerLon = clusterPlaces.reduce(0) { $0 + $1.coordinate.longitude } / Double(clusterPlaces.count)
            
            clusters.append(PlaceClusterItem(
                id: UUID().uuidString,
                coordinate: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                places: clusterPlaces
            ))
        }
        
        return clusters
    }
    
    // MARK: - Map Fitting
    
    func fitMapToPlaces() {
        guard !places.isEmpty else { return }
        
        let lats = places.map { $0.coordinate.latitude }
        let lons = places.map { $0.coordinate.longitude }
        
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.2),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.2)
        )
        
        mapRegion = MKCoordinateRegion(center: center, span: span)
    }
    
    func selectPlace(_ place: PlaceItem) {
        selectedPlace = place
        
        mapRegion = MKCoordinateRegion(
            center: place.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }
}
