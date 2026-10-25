// PeopleAnalyzer.swift
// Analizador de personas y clustering de rostros

import Foundation

/// Analizador para clustering de rostros y detección de personas
public struct PeopleAnalyzer {
    
    // MARK: - Configuración
    
    public struct Configuration {
        /// Umbral de similitud para considerar el mismo rostro
        public var faceSimilarityThreshold: Double = 0.6
        
        /// Mínimo de rostros para crear una persona
        public var minimumFacesPerPerson: Int = 3
        
        /// Días de tolerancia para detectar cumpleaños (mismo día ± tolerancia)
        public var birthdayDateTolerance: Int = 2
        
        /// Años mínimos de ocurrencias para detectar evento recurrente
        public var minimumYearsForRecurringEvent: Int = 2
        
        public init() {}
    }
    
    public var configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    // MARK: - Clustering de Rostros
    
    /// Agrupa detecciones de rostros en clusters (personas)
    public func clusterFaces(detections: [FaceDetection]) -> [FaceCluster] {
        guard !detections.isEmpty else { return [] }
        
        var clusters: [FaceCluster] = []
        var processed = Set<String>()
        
        for detection in detections {
            guard !processed.contains(detection.id) else { continue }
            
            var clusterFaces: [FaceDetection] = [detection]
            processed.insert(detection.id)
            
            for other in detections {
                guard !processed.contains(other.id) else { continue }
                
                let similarity = cosineSimilarity(detection.featurePrint, other.featurePrint)
                if similarity >= configuration.faceSimilarityThreshold {
                    clusterFaces.append(other)
                    processed.insert(other.id)
                }
            }
            
            if clusterFaces.count >= configuration.minimumFacesPerPerson {
                let centroid = calculateCentroid(from: clusterFaces.map { $0.featurePrint })
                
                clusters.append(FaceCluster(
                    centroidFeaturePrint: centroid,
                    faceIds: clusterFaces.map { $0.id },
                    photoIds: Array(Set(clusterFaces.map { $0.photoId }))
                ))
            }
        }
        
        return clusters.sorted { $0.faceIds.count > $1.faceIds.count }
    }
    
    /// Crea personas a partir de clusters de rostros
    public func createPeople(from clusters: [FaceCluster]) -> [Person] {
        clusters.enumerated().map { index, cluster in
            // Seleccionar foto representativa (la de mayor calidad)
            let representativeId = cluster.photoIds.first
            
            return Person(
                name: nil, // El usuario lo nombra
                faceClusterId: cluster.id,
                representativeFacePhotoId: representativeId,
                photoIds: cluster.photoIds,
                faceCount: cluster.faceIds.count
            )
        }
    }
    
    /// Asigna una nueva detección de rostro a un cluster existente
    public func assignToCluster(
        detection: FaceDetection,
        clusters: [FaceCluster]
    ) -> String? {
        var bestMatch: (clusterId: String, similarity: Double)?
        
        for cluster in clusters {
            let similarity = cosineSimilarity(detection.featurePrint, cluster.centroidFeaturePrint)
            
            if similarity >= configuration.faceSimilarityThreshold {
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (cluster.id, similarity)
                }
            }
        }
        
        return bestMatch?.clusterId
    }
    
    // MARK: - Detección de Eventos Recurrentes
    
    /// Detecta cumpleaños y otros eventos recurrentes
    public func detectRecurringEvents(
        person: Person,
        photos: [PhotoMetadata]
    ) -> [RecurringEvent] {
        let personPhotos = photos.filter { person.photoIds.contains($0.id) }
        return detectRecurringDates(in: personPhotos, personId: person.id, personName: person.name)
    }
    
    /// Detecta eventos recurrentes generales (no específicos de una persona)
    public func detectGlobalRecurringEvents(in photos: [PhotoMetadata]) -> [RecurringEvent] {
        return detectRecurringDates(in: photos, personId: nil, personName: nil)
    }
    
    private func detectRecurringDates(
        in photos: [PhotoMetadata],
        personId: String?,
        personName: String?
    ) -> [RecurringEvent] {
        let calendar = Calendar.current
        
        // Agrupar fotos por día del año
        let byDayOfYear = Dictionary(grouping: photos) { photo -> Int? in
            guard let date = photo.creationDate else { return nil }
            return calendar.ordinality(of: .day, in: .year, for: date)
        }
        
        var events: [RecurringEvent] = []
        
        for (dayOfYear, dayPhotos) in byDayOfYear {
            guard let day = dayOfYear else { continue }
            
            // Agrupar por año
            let byYear = Dictionary(grouping: dayPhotos) { photo -> Int? in
                guard let date = photo.creationDate else { return nil }
                return calendar.component(.year, from: date)
            }
            
            // ¿Hay fotos en múltiples años para este día?
            let yearsWithPhotos = byYear.keys.compactMap { $0 }
            
            if yearsWithPhotos.count >= configuration.minimumYearsForRecurringEvent {
                // Tenemos un posible evento recurrente
                let sampleDate = dayPhotos.first?.creationDate ?? Date()
                let components = calendar.dateComponents([.month, .day], from: sampleDate)
                
                let occurrences = yearsWithPhotos.sorted().compactMap { year -> RecurringEventOccurrence? in
                    guard let yearPhotos = byYear[year] else { return nil }
                    
                    // Detectar indicadores de fiesta (heurística simple)
                    let hasPartyIndicators = detectPartyIndicators(in: yearPhotos)
                    
                    var dateComponents = DateComponents()
                    dateComponents.year = year
                    dateComponents.month = components.month
                    dateComponents.day = components.day
                    
                    guard let date = calendar.date(from: dateComponents) else { return nil }
                    
                    return RecurringEventOccurrence(
                        year: year,
                        date: date,
                        photoIds: yearPhotos.map { $0.id },
                        hasPartyIndicators: hasPartyIndicators
                    )
                }
                
                // Determinar tipo de evento
                let type = classifyRecurringEvent(occurrences: occurrences, personId: personId)
                
                // Calcular confianza basada en consistencia
                let confidence = Double(yearsWithPhotos.count) / Double(max(yearsWithPhotos.max()! - yearsWithPhotos.min()! + 1, 1))
                
                events.append(RecurringEvent(
                    type: type,
                    personId: personId,
                    personName: personName,
                    dayOfYear: day,
                    month: components.month ?? 1,
                    day: components.day ?? 1,
                    occurrences: occurrences,
                    confidence: min(confidence, 1.0)
                ))
            }
        }
        
        return events.sorted { $0.confidence > $1.confidence }
    }
    
    private func classifyRecurringEvent(
        occurrences: [RecurringEventOccurrence],
        personId: String?
    ) -> RecurringEventType {
        // Si está asociado a una persona y hay indicadores de fiesta, probablemente cumpleaños
        if personId != nil {
            let hasPartyIndicatorsCount = occurrences.filter { $0.hasPartyIndicators }.count
            if hasPartyIndicatorsCount >= occurrences.count / 2 {
                return .birthday
            }
        }
        
        // Verificar si coincide con fechas conocidas
        guard let firstOccurrence = occurrences.first else { return .unknown }
        let month = Calendar.current.component(.month, from: firstOccurrence.date)
        let day = Calendar.current.component(.day, from: firstOccurrence.date)
        
        // Fechas festivas comunes (Argentina)
        let holidays: [(month: Int, day: Int, type: RecurringEventType)] = [
            (1, 1, .holiday),   // Año Nuevo
            (12, 25, .holiday), // Navidad
            (5, 25, .holiday),  // Revolución de Mayo
            (7, 9, .holiday),   // Independencia
        ]
        
        for holiday in holidays {
            if month == holiday.month && day == holiday.day {
                return holiday.type
            }
        }
        
        return .annualEvent
    }
    
    private func detectPartyIndicators(in photos: [PhotoMetadata]) -> Bool {
        // Heurísticas simples para detectar fiestas
        // En una implementación real, usaríamos clasificación de imágenes
        
        // Muchas fotos en poco tiempo (evento)
        if photos.count >= 5 {
            let dates = photos.compactMap { $0.creationDate }.sorted()
            if let first = dates.first, let last = dates.last {
                let hours = last.timeIntervalSince(first) / 3600
                if hours < 6 && photos.count >= 10 {
                    return true
                }
            }
        }
        
        // Muchos rostros detectados
        let totalFaces = photos.compactMap { $0.facesDetected }.reduce(0, +)
        if totalFaces >= 10 {
            return true
        }
        
        return false
    }
    
    // MARK: - Memorias "En Este Día"
    
    /// Genera memorias de "En este día" para una fecha
    public func generateOnThisDayMemories(
        for date: Date,
        photos: [PhotoMetadata],
        moments: [Moment],
        people: [Person]
    ) -> [OnThisDayMemory] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        var memories: [OnThisDayMemory] = []
        
        // Agrupar fotos por año para este día
        let photosOnThisDay = photos.filter { photo in
            guard let photoDate = photo.creationDate else { return false }
            let photoMonth = calendar.component(.month, from: photoDate)
            let photoDay = calendar.component(.day, from: photoDate)
            return photoMonth == month && photoDay == day
        }
        
        let byYear = Dictionary(grouping: photosOnThisDay) { photo -> Int in
            guard let date = photo.creationDate else { return 0 }
            return calendar.component(.year, from: date)
        }
        
        for (year, yearPhotos) in byYear {
            guard year < currentYear else { continue }
            
            let yearsAgo = currentYear - year
            
            // Encontrar momento relacionado
            let relatedMoment = moments.first { moment in
                guard let startDate = yearPhotos.first?.creationDate else { return false }
                return moment.photos.contains { $0.creationDate == startDate }
            }
            
            // Encontrar personas relacionadas
            let photoIds = Set(yearPhotos.map { $0.id })
            let relatedPeople = people.filter { person in
                !Set(person.photoIds).isDisjoint(with: photoIds)
            }
            
            memories.append(OnThisDayMemory(
                date: date,
                yearsAgo: yearsAgo,
                photos: yearPhotos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) },
                moment: relatedMoment,
                relatedPeople: relatedPeople
            ))
        }
        
        return memories.sorted { $0.yearsAgo < $1.yearsAgo }
    }
    
    /// Genera recordatorios de cumpleaños próximos
    public func upcomingBirthdays(
        events: [RecurringEvent],
        withinDays: Int = 30
    ) -> [(event: RecurringEvent, daysUntil: Int)] {
        let now = Date()
        
        return events
            .filter { $0.type == .birthday }
            .compactMap { event -> (RecurringEvent, Int)? in
                guard let days = event.daysUntilNext(from: now) else { return nil }
                guard days <= withinDays else { return nil }
                return (event, days)
            }
            .sorted { $0.1 < $1.1 }
    }
    
    // MARK: - Helpers
    
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        
        return dotProduct / denominator
    }
    
    private func calculateCentroid(from vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty, let first = vectors.first else { return [] }
        
        var centroid = [Double](repeating: 0, count: first.count)
        
        for vector in vectors {
            for i in 0..<min(vector.count, centroid.count) {
                centroid[i] += vector[i]
            }
        }
        
        let count = Double(vectors.count)
        return centroid.map { $0 / count }
    }
}
