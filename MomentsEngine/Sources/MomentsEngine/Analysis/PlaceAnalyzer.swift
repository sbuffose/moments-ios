// PlaceAnalyzer.swift
// Analizador de lugares y clustering geográfico

import Foundation

/// Analizador para agrupar fotos por ubicación
public struct PlaceAnalyzer {
    
    // MARK: - Configuración
    
    public struct Configuration {
        /// Radio en metros para agrupar fotos en el mismo lugar
        public var placeClusterRadius: Double = 200
        
        /// Mínimo de fotos para considerar un lugar
        public var minimumPhotosPerPlace: Int = 2
        
        /// Radio para detectar ubicación del hogar
        public var homeDetectionRadius: Double = 500
        
        /// Porcentaje mínimo de fotos en una ubicación para considerarla hogar
        public var homeDetectionThreshold: Double = 0.2
        
        public init() {}
    }
    
    public var configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    // MARK: - Clustering de Lugares
    
    /// Agrupa fotos en lugares usando clustering por densidad
    public func clusterPlaces(from photos: [PhotoMetadata]) -> [Place] {
        let locatedPhotos = photos.filter { $0.location != nil }
        guard !locatedPhotos.isEmpty else { return [] }
        
        var places: [Place] = []
        var processed = Set<String>()
        
        for photo in locatedPhotos {
            guard !processed.contains(photo.id) else { continue }
            guard let location = photo.location else { continue }
            
            // Encontrar todas las fotos cercanas
            var cluster: [PhotoMetadata] = [photo]
            processed.insert(photo.id)
            
            for other in locatedPhotos {
                guard !processed.contains(other.id) else { continue }
                guard let otherLocation = other.location else { continue }
                
                let distance = location.distance(to: otherLocation)
                if distance <= configuration.placeClusterRadius {
                    cluster.append(other)
                    processed.insert(other.id)
                }
            }
            
            if cluster.count >= configuration.minimumPhotosPerPlace {
                let place = createPlace(from: cluster)
                places.append(place)
            }
        }
        
        return places.sorted { $0.photoCount > $1.photoCount }
    }
    
    /// Crea un lugar a partir de un cluster de fotos
    private func createPlace(from photos: [PhotoMetadata]) -> Place {
        let coordinates = photos.compactMap { $0.location }
        let centerLat = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let centerLon = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
        let center = Coordinate(latitude: centerLat, longitude: centerLon)
        
        // Calcular radio del cluster
        let maxDistance = coordinates.map { center.distance(to: $0) }.max() ?? configuration.placeClusterRadius
        
        let dates = photos.compactMap { $0.creationDate }.sorted()
        
        // Contar visitas únicas (días diferentes)
        let visitDays = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        
        return Place(
            name: "", // Se llena con reverse geocoding
            coordinate: center,
            radius: maxDistance,
            photoIds: photos.map { $0.id },
            firstVisit: dates.first,
            lastVisit: dates.last,
            visitCount: visitDays.count
        )
    }
    
    // MARK: - Detección del Hogar
    
    /// Detecta la ubicación del hogar basándose en frecuencia de fotos
    public func detectHomeLocation(from photos: [PhotoMetadata]) -> HomeLocation? {
        let locatedPhotos = photos.filter { $0.location != nil }
        guard locatedPhotos.count >= 10 else { return nil } // Necesitamos suficientes fotos
        
        // Usar clustering más amplio para encontrar áreas frecuentes
        var locationCounts: [(Coordinate, Int)] = []
        var processed = Set<String>()
        
        for photo in locatedPhotos {
            guard !processed.contains(photo.id) else { continue }
            guard let location = photo.location else { continue }
            
            var count = 1
            processed.insert(photo.id)
            
            for other in locatedPhotos {
                guard !processed.contains(other.id) else { continue }
                guard let otherLocation = other.location else { continue }
                
                let distance = location.distance(to: otherLocation)
                if distance <= configuration.homeDetectionRadius {
                    count += 1
                    processed.insert(other.id)
                }
            }
            
            locationCounts.append((location, count))
        }
        
        // Ordenar por cantidad de fotos
        let sorted = locationCounts.sorted { $0.1 > $1.1 }
        
        guard let top = sorted.first else { return nil }
        
        let totalPhotos = locatedPhotos.count
        let percentage = Double(top.1) / Double(totalPhotos)
        
        // Verificar que es significativo
        guard percentage >= configuration.homeDetectionThreshold else { return nil }
        
        return HomeLocation(
            coordinate: top.0,
            confidence: min(percentage * 2, 1.0), // Escalar confianza
            photoCount: top.1
        )
    }
    
    // MARK: - Clustering para Mapa
    
    /// Agrupa lugares cercanos para mostrar en el mapa según nivel de zoom
    public func clusterForMap(
        places: [Place],
        zoomLevel: Double,
        mapBounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)?
    ) -> [PlaceCluster] {
        // Ajustar radio de clustering según zoom
        let clusterRadius = calculateClusterRadius(for: zoomLevel)
        
        // Filtrar por bounds si se proporcionan
        var visiblePlaces = places
        if let bounds = mapBounds {
            visiblePlaces = places.filter { place in
                place.coordinate.latitude >= bounds.minLat &&
                place.coordinate.latitude <= bounds.maxLat &&
                place.coordinate.longitude >= bounds.minLon &&
                place.coordinate.longitude <= bounds.maxLon
            }
        }
        
        // Si zoom alto, no agrupar
        if zoomLevel > 14 {
            return visiblePlaces.map { place in
                PlaceCluster(coordinate: place.coordinate, places: [place])
            }
        }
        
        // Clustering
        var clusters: [PlaceCluster] = []
        var processed = Set<String>()
        
        for place in visiblePlaces {
            guard !processed.contains(place.id) else { continue }
            
            var clusterPlaces: [Place] = [place]
            processed.insert(place.id)
            
            for other in visiblePlaces {
                guard !processed.contains(other.id) else { continue }
                
                let distance = place.coordinate.distance(to: other.coordinate)
                if distance <= clusterRadius {
                    clusterPlaces.append(other)
                    processed.insert(other.id)
                }
            }
            
            // Calcular centro del cluster
            let centerLat = clusterPlaces.reduce(0) { $0 + $1.coordinate.latitude } / Double(clusterPlaces.count)
            let centerLon = clusterPlaces.reduce(0) { $0 + $1.coordinate.longitude } / Double(clusterPlaces.count)
            
            clusters.append(PlaceCluster(
                coordinate: Coordinate(latitude: centerLat, longitude: centerLon),
                places: clusterPlaces
            ))
        }
        
        return clusters
    }
    
    private func calculateClusterRadius(for zoomLevel: Double) -> Double {
        // Aproximación: a menor zoom, mayor radio de clustering
        let baseRadius = 100_000.0 // 100 km a zoom 0
        return baseRadius / pow(2, zoomLevel)
    }
    
    // MARK: - Análisis de Visitas
    
    /// Analiza patrones de visitas a un lugar
    public func analyzeVisitPattern(for place: Place, photos: [PhotoMetadata]) -> VisitPattern {
        let placePhotos = photos.filter { place.photoIds.contains($0.id) }
        let dates = placePhotos.compactMap { $0.creationDate }.sorted()
        
        guard !dates.isEmpty else {
            return VisitPattern(place: place, visits: [], frequency: .rare)
        }
        
        // Agrupar por visitas (días diferentes)
        var visits: [Visit] = []
        var currentVisitPhotos: [Date] = []
        var lastDate: Date?
        
        for date in dates {
            if let last = lastDate {
                let daysDiff = Calendar.current.dateComponents([.day], from: last, to: date).day ?? 0
                if daysDiff > 1 {
                    // Nueva visita
                    if !currentVisitPhotos.isEmpty {
                        visits.append(Visit(
                            startDate: currentVisitPhotos.first!,
                            endDate: currentVisitPhotos.last!,
                            photoCount: currentVisitPhotos.count
                        ))
                    }
                    currentVisitPhotos = [date]
                } else {
                    currentVisitPhotos.append(date)
                }
            } else {
                currentVisitPhotos.append(date)
            }
            lastDate = date
        }
        
        // Última visita
        if !currentVisitPhotos.isEmpty {
            visits.append(Visit(
                startDate: currentVisitPhotos.first!,
                endDate: currentVisitPhotos.last!,
                photoCount: currentVisitPhotos.count
            ))
        }
        
        // Determinar frecuencia
        let frequency = determineVisitFrequency(visits: visits)
        
        return VisitPattern(place: place, visits: visits, frequency: frequency)
    }
    
    private func determineVisitFrequency(visits: [Visit]) -> VisitFrequency {
        guard visits.count >= 2 else { return .rare }
        
        let intervals = zip(visits, visits.dropFirst()).map { (v1, v2) in
            Calendar.current.dateComponents([.day], from: v1.endDate, to: v2.startDate).day ?? 0
        }
        
        let averageInterval = Double(intervals.reduce(0, +)) / Double(intervals.count)
        
        if averageInterval <= 7 {
            return .weekly
        } else if averageInterval <= 30 {
            return .monthly
        } else if averageInterval <= 90 {
            return .quarterly
        } else if averageInterval <= 365 {
            return .yearly
        } else {
            return .rare
        }
    }
}

// MARK: - Modelos Auxiliares

public struct Visit: Codable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let photoCount: Int
    
    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}

public struct VisitPattern: Sendable {
    public let place: Place
    public let visits: [Visit]
    public let frequency: VisitFrequency
}

public enum VisitFrequency: String, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly
    case rare
    
    public var localizedKey: String {
        "visit_frequency_\(rawValue)"
    }
}
