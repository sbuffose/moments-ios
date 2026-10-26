// CleanupAnalyzer.swift
// Analizador de fotos para sugerencias de limpieza

import Foundation

/// Analizador principal para detectar fotos que pueden ser eliminadas
public struct CleanupAnalyzer {
    
    // MARK: - Configuración
    
    public struct Configuration {
        /// Threshold for blur detection - photos with sharpness below this are considered blurry
        /// Lowered from 0.3 to 0.15 to reduce false positives (sharp photos flagged as blurry)
        public var sharpnessThreshold: Double = 0.15
        public var overexposureThreshold: Double = 0.85
        public var underexposureThreshold: Double = 0.15
        public var duplicateSimilarityThreshold: Double = 0.95
        public var nearDuplicateSimilarityThreshold: Double = 0.80
        public var largeVideoSizeThreshold: Int64 = 100_000_000 // 100 MB
        public var accidentalShotDarkThreshold: Double = 0.05
        public var accidentalShotAspectRatioMin: Double = 0.3
        public var accidentalShotAspectRatioMax: Double = 3.0
        
        public init() {}
    }
    
    public var configuration: Configuration
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }
    
    // MARK: - Análisis Principal
    
    /// Analiza todas las fotos y genera sugerencias de limpieza
    public func analyze(photos: [PhotoMetadata]) -> CleanupSuggestions {
        var suggestions = CleanupSuggestions()
        
        // Screenshots y screen recordings
        suggestions.screenshots = detectScreenshots(in: photos)
        suggestions.screenRecordings = detectScreenRecordings(in: photos)
        
        // Calidad de imagen
        suggestions.blurryPhotos = detectBlurryPhotos(in: photos)
        suggestions.overexposedPhotos = detectOverexposedPhotos(in: photos)
        suggestions.underexposedPhotos = detectUnderexposedPhotos(in: photos)
        
        // Duplicados
        suggestions.duplicateGroups = detectDuplicates(in: photos, near: false)
        suggestions.nearDuplicateGroups = detectDuplicates(in: photos, near: true)
        
        // Bursts
        suggestions.burstGroups = detectBursts(in: photos)
        
        // Tomas accidentales
        suggestions.accidentalShots = detectAccidentalShots(in: photos)
        
        // Documentos
        suggestions.documents = detectDocuments(in: photos)
        
        // Videos grandes
        suggestions.largeVideos = detectLargeVideos(in: photos)
        
        return suggestions
    }
    
    // MARK: - Detección de Screenshots
    
    public func detectScreenshots(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            photo.mediaType == .image && photo.mediaSubtypes.contains(.screenshot)
        }.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }
    
    public func detectScreenRecordings(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            photo.mediaType == .video && photo.mediaSubtypes.contains(.screenRecording)
        }.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }
    
    // MARK: - Detección de Calidad
    
    public func detectBlurryPhotos(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            guard photo.mediaType == .image else { return false }
            guard let sharpness = photo.sharpnessScore else { return false }
            return sharpness < configuration.sharpnessThreshold
        }.sorted { ($0.sharpnessScore ?? 0) < ($1.sharpnessScore ?? 0) }
    }
    
    public func detectOverexposedPhotos(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            guard photo.mediaType == .image else { return false }
            guard let exposure = photo.exposureScore else { return false }
            return exposure > configuration.overexposureThreshold
        }.sorted { ($0.exposureScore ?? 0) > ($1.exposureScore ?? 0) }
    }
    
    public func detectUnderexposedPhotos(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            guard photo.mediaType == .image else { return false }
            guard let exposure = photo.exposureScore else { return false }
            return exposure < configuration.underexposureThreshold
        }.sorted { ($0.exposureScore ?? 1) < ($1.exposureScore ?? 1) }
    }
    
    // MARK: - Detección de Duplicados
    
    public func detectDuplicates(in photos: [PhotoMetadata], near: Bool) -> [DuplicateGroup] {
        let threshold = near ? configuration.nearDuplicateSimilarityThreshold : configuration.duplicateSimilarityThreshold
        
        let imagesWithPrints = photos.filter { 
            $0.mediaType == .image && $0.imageFeaturePrint != nil 
        }
        
        var processed = Set<String>()
        var groups: [DuplicateGroup] = []
        
        for photo in imagesWithPrints {
            guard !processed.contains(photo.id) else { continue }
            guard let print1 = photo.imageFeaturePrint else { continue }
            
            var duplicates: [PhotoMetadata] = []
            
            for other in imagesWithPrints {
                guard other.id != photo.id else { continue }
                guard !processed.contains(other.id) else { continue }
                guard let print2 = other.imageFeaturePrint else { continue }
                
                let similarity = cosineSimilarity(print1, print2)
                
                if near {
                    if similarity >= configuration.nearDuplicateSimilarityThreshold && 
                       similarity < configuration.duplicateSimilarityThreshold {
                        duplicates.append(other)
                        processed.insert(other.id)
                    }
                } else {
                    if similarity >= configuration.duplicateSimilarityThreshold {
                        duplicates.append(other)
                        processed.insert(other.id)
                    }
                }
            }
            
            if !duplicates.isEmpty {
                processed.insert(photo.id)
                let allPhotos = [photo] + duplicates
                let best = selectBestPhoto(from: allPhotos)
                let others = allPhotos.filter { $0.id != best.id }
                
                groups.append(DuplicateGroup(
                    best: best,
                    duplicates: others,
                    similarity: threshold
                ))
            }
        }
        
        return groups.sorted { $0.duplicates.count > $1.duplicates.count }
    }
    
    // MARK: - Detección de Bursts
    
    public func detectBursts(in photos: [PhotoMetadata]) -> [BurstGroup] {
        let burstPhotos = photos.filter { $0.burstIdentifier != nil }
        
        let grouped = Dictionary(grouping: burstPhotos) { $0.burstIdentifier! }
        
        return grouped.compactMap { (burstId, photos) -> BurstGroup? in
            guard photos.count > 1 else { return nil }
            
            let best = selectBestPhoto(from: photos)
            let others = photos.filter { $0.id != best.id }
            
            return BurstGroup(
                burstIdentifier: burstId,
                best: best,
                others: others
            )
        }.sorted { $0.others.count > $1.others.count }
    }
    
    // MARK: - Detección de Tomas Accidentales
    
    public func detectAccidentalShots(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            guard photo.mediaType == .image else { return false }
            
            // Muy oscura (dedo sobre lente, bolsillo)
            if let exposure = photo.exposureScore, exposure < configuration.accidentalShotDarkThreshold {
                return true
            }
            
            // Aspecto ratio muy extremo
            let aspect = photo.aspectRatio
            if aspect < configuration.accidentalShotAspectRatioMin || 
               aspect > configuration.accidentalShotAspectRatioMax {
                return true
            }
            
            // Muy borrosa Y sin rostros (posible toma accidental)
            if let sharpness = photo.sharpnessScore,
               sharpness < 0.1,
               let faces = photo.facesDetected,
               faces == 0 {
                return true
            }
            
            // Colores dominantes muy uniformes (piso, techo, bolsillo)
            if let colors = photo.dominantColors,
               colors.count == 1,
               let sharpness = photo.sharpnessScore,
               sharpness < 0.2 {
                return true
            }
            
            return false
        }
    }
    
    // MARK: - Detección de Documentos
    
    public func detectDocuments(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            guard photo.mediaType == .image else { return false }
            return photo.isDocument == true || photo.hasText == true
        }
    }
    
    // MARK: - Detección de Videos Grandes
    
    public func detectLargeVideos(in photos: [PhotoMetadata]) -> [PhotoMetadata] {
        photos.filter { photo in
            guard photo.mediaType == .video else { return false }
            guard let size = photo.estimatedFileSize else { return false }
            return size >= configuration.largeVideoSizeThreshold
        }.sorted { ($0.estimatedFileSize ?? 0) > ($1.estimatedFileSize ?? 0) }
    }
    
    // MARK: - Helpers
    
    /// Selecciona la mejor foto de un grupo basándose en calidad
    public func selectBestPhoto(from photos: [PhotoMetadata]) -> PhotoMetadata {
        guard !photos.isEmpty else { fatalError("Cannot select from empty array") }
        
        return photos.max { a, b in
            let scoreA = qualityScore(for: a)
            let scoreB = qualityScore(for: b)
            return scoreA < scoreB
        } ?? photos[0]
    }
    
    /// Calcula un score de calidad para una foto
    public func qualityScore(for photo: PhotoMetadata) -> Double {
        var score = 0.0
        
        // Nitidez (0-40 puntos)
        if let sharpness = photo.sharpnessScore {
            score += sharpness * 40
        }
        
        // Exposición (0-30 puntos, penaliza extremos)
        if let exposure = photo.exposureScore {
            let exposureScore = 1.0 - abs(exposure - 0.5) * 2
            score += exposureScore * 30
        }
        
        // Resolución (0-20 puntos)
        let megapixelScore = min(photo.megapixels / 12.0, 1.0)
        score += megapixelScore * 20
        
        // Favorita (+10 puntos)
        if photo.isFavorite {
            score += 10
        }
        
        // Representa burst (+5 puntos)
        if photo.representsBurst {
            score += 5
        }
        
        return score
    }
    
    /// Calcula similitud coseno entre dos vectores
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
}
