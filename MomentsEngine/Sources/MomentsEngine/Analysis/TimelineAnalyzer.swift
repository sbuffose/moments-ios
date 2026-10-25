// TimelineAnalyzer.swift
// Analizador de línea de tiempo y detección de momentos/viajes

import Foundation

/// Analizador para generar momentos y detectar viajes
public struct TimelineAnalyzer {
    
    // MARK: - Configuración
    
    public struct Configuration {
        /// Horas máximas entre fotos para considerarlas del mismo momento
        public var momentTimeGapHours: Double = 4.0
        
        /// Distancia máxima en metros para agrupar fotos en el mismo momento
        public var momentDistanceThreshold: Double = 5000 // 5 km
        
        /// Mínimo de fotos para considerar un momento
        public var minimumPhotosPerMoment: Int = 3
        
        /// Distancia mínima desde casa para considerar un viaje (km)
        public var tripDistanceThreshold: Double = 50.0
        
        /// Días mínimos consecutivos para considerar un viaje
        public var tripMinimumDays: Int = 1
        
        public init() {}
    }
    
    public var configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    // MARK: - Generación de Momentos
    
    /// Genera momentos a partir de fotos agrupando por tiempo y ubicación
    public func generateMoments(from photos: [PhotoMetadata]) -> [Moment] {
        let sortedPhotos = photos
            .filter { $0.creationDate != nil }
            .sorted { $0.creationDate! < $1.creationDate! }
        
        guard !sortedPhotos.isEmpty else { return [] }
        
        var moments: [Moment] = []
        var currentGroup: [PhotoMetadata] = []
        var lastPhoto: PhotoMetadata?
        
        for photo in sortedPhotos {
            if let last = lastPhoto {
                let shouldSplit = shouldSplitMoment(between: last, and: photo)
                
                if shouldSplit {
                    if currentGroup.count >= configuration.minimumPhotosPerMoment {
                        if let moment = createMoment(from: currentGroup) {
                            moments.append(moment)
                        }
                    }
                    currentGroup = [photo]
                } else {
                    currentGroup.append(photo)
                }
            } else {
                currentGroup.append(photo)
            }
            
            lastPhoto = photo
        }
        
        // Último grupo
        if currentGroup.count >= configuration.minimumPhotosPerMoment {
            if let moment = createMoment(from: currentGroup) {
                moments.append(moment)
            }
        }
        
        return moments
    }
    
    /// Determina si debe dividirse un momento entre dos fotos
    public func shouldSplitMoment(between photo1: PhotoMetadata, and photo2: PhotoMetadata) -> Bool {
        guard let date1 = photo1.creationDate, let date2 = photo2.creationDate else {
            return true
        }
        
        // Diferencia de tiempo
        let hoursDiff = date2.timeIntervalSince(date1) / 3600
        if hoursDiff > configuration.momentTimeGapHours {
            return true
        }
        
        // Diferencia de ubicación
        if let loc1 = photo1.location, let loc2 = photo2.location {
            let distance = loc1.distance(to: loc2)
            if distance > configuration.momentDistanceThreshold {
                return true
            }
        }
        
        return false
    }
    
    /// Crea un momento a partir de un grupo de fotos
    private func createMoment(from photos: [PhotoMetadata]) -> Moment? {
        guard !photos.isEmpty else { return nil }
        
        let sortedPhotos = photos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        
        guard let startDate = sortedPhotos.first?.creationDate,
              let endDate = sortedPhotos.last?.creationDate else { return nil }
        
        // Calcular ubicación central
        let location = calculateCentralLocation(from: photos)
        
        // Seleccionar foto de portada (mejor calidad con rostros preferida)
        let coverPhoto = selectCoverPhoto(from: photos)
        
        return Moment(
            startDate: startDate,
            endDate: endDate,
            photos: sortedPhotos,
            coverPhotoId: coverPhoto?.id,
            location: location
        )
    }
    
    // MARK: - Detección de Viajes
    
    /// Detecta viajes basándose en la ubicación del hogar
    public func detectTrips(
        moments: [Moment],
        homeLocation: HomeLocation?
    ) -> [Trip] {
        guard let home = homeLocation else { return [] }
        
        var trips: [Trip] = []
        var currentTripMoments: [Moment] = []
        var currentTripDestination: Coordinate?
        
        for moment in moments.sorted(by: { $0.startDate < $1.startDate }) {
            guard let location = moment.location else { continue }
            
            let distanceFromHome = home.coordinate.distance(to: location) / 1000 // km
            
            if distanceFromHome >= configuration.tripDistanceThreshold {
                // Lejos de casa
                if currentTripMoments.isEmpty {
                    currentTripDestination = location
                }
                currentTripMoments.append(moment)
            } else {
                // De vuelta en casa, cerrar viaje si existe
                if let trip = createTrip(from: currentTripMoments, destination: currentTripDestination, homeLocation: home) {
                    trips.append(trip)
                }
                currentTripMoments = []
                currentTripDestination = nil
            }
        }
        
        // Viaje final
        if let trip = createTrip(from: currentTripMoments, destination: currentTripDestination, homeLocation: home) {
            trips.append(trip)
        }
        
        return trips
    }
    
    private func createTrip(
        from moments: [Moment],
        destination: Coordinate?,
        homeLocation: HomeLocation
    ) -> Trip? {
        guard !moments.isEmpty else { return nil }
        
        let sortedMoments = moments.sorted { $0.startDate < $1.startDate }
        guard let first = sortedMoments.first, let last = sortedMoments.last else { return nil }
        
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: first.startDate, to: last.endDate).day ?? 0
        
        guard days >= configuration.tripMinimumDays else { return nil }
        
        let center = destination ?? calculateCentralLocation(from: moments.flatMap { $0.photos }) ?? homeLocation.coordinate
        let distance = homeLocation.coordinate.distance(to: center) / 1000
        
        return Trip(
            destination: "", // Se llena con reverse geocoding en la app
            startDate: first.startDate,
            endDate: last.endDate,
            centerLocation: center,
            moments: sortedMoments,
            distanceFromHome: distance
        )
    }
    
    // MARK: - Secciones de Línea de Tiempo
    
    /// Agrupa momentos en secciones por año/mes
    public func createTimelineSections(from moments: [Moment]) -> [TimelineSection] {
        let calendar = Calendar.current
        
        let grouped = Dictionary(grouping: moments) { moment -> String in
            let components = calendar.dateComponents([.year, .month], from: moment.startDate)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        }
        
        return grouped.map { (key, moments) -> TimelineSection in
            let parts = key.split(separator: "-")
            let year = Int(parts[0]) ?? 0
            let month = Int(parts[1]) ?? 0
            
            return TimelineSection(
                year: year,
                month: month,
                moments: moments.sorted { $0.startDate > $1.startDate }
            )
        }.sorted { section1, section2 in
            if section1.year != section2.year {
                return section1.year > section2.year
            }
            return (section1.month ?? 0) > (section2.month ?? 0)
        }
    }
    
    // MARK: - Helpers
    
    /// Calcula la ubicación central de un grupo de fotos
    public func calculateCentralLocation(from photos: [PhotoMetadata]) -> Coordinate? {
        let locatedPhotos = photos.compactMap { $0.location }
        guard !locatedPhotos.isEmpty else { return nil }
        
        let totalLat = locatedPhotos.reduce(0) { $0 + $1.latitude }
        let totalLon = locatedPhotos.reduce(0) { $0 + $1.longitude }
        
        return Coordinate(
            latitude: totalLat / Double(locatedPhotos.count),
            longitude: totalLon / Double(locatedPhotos.count)
        )
    }
    
    /// Selecciona la mejor foto para portada
    public func selectCoverPhoto(from photos: [PhotoMetadata]) -> PhotoMetadata? {
        // Preferir fotos con rostros y buena calidad
        let withFaces = photos.filter { ($0.facesDetected ?? 0) > 0 }
        
        let candidates = withFaces.isEmpty ? photos : withFaces
        
        return candidates.max { a, b in
            let scoreA = coverScore(for: a)
            let scoreB = coverScore(for: b)
            return scoreA < scoreB
        }
    }
    
    private func coverScore(for photo: PhotoMetadata) -> Double {
        var score = 0.0
        
        // Nitidez
        score += (photo.sharpnessScore ?? 0.5) * 30
        
        // Exposición balanceada
        if let exposure = photo.exposureScore {
            score += (1.0 - abs(exposure - 0.5) * 2) * 20
        }
        
        // Rostros
        if let faces = photo.facesDetected, faces > 0 {
            score += min(Double(faces) * 10, 30)
        }
        
        // Favorita
        if photo.isFavorite {
            score += 20
        }
        
        // Landscape preferido para portadas
        if photo.isLandscape {
            score += 10
        }
        
        return score
    }
}
