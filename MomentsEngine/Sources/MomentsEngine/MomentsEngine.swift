// MomentsEngine
// Motor de análisis de fotos para la app Moments
// Pure Swift - sin dependencias de iOS para testing

import Foundation

/// Punto de entrada principal del motor de análisis
public struct MomentsEngine {
    public static let version = "1.0.0"
    
    public init() {}
    
    /// Analiza un conjunto de metadatos de fotos y genera resultados
    public func analyze(photos: [PhotoMetadata]) -> AnalysisResult {
        let cleanupAnalyzer = CleanupAnalyzer()
        let timelineAnalyzer = TimelineAnalyzer()
        let placeAnalyzer = PlaceAnalyzer()
        
        return AnalysisResult(
            cleanupSuggestions: cleanupAnalyzer.analyze(photos: photos),
            moments: timelineAnalyzer.generateMoments(from: photos),
            places: placeAnalyzer.clusterPlaces(from: photos)
        )
    }
}

/// Resultado del análisis completo
public struct AnalysisResult {
    public let cleanupSuggestions: CleanupSuggestions
    public let moments: [Moment]
    public let places: [Place]
    
    public init(cleanupSuggestions: CleanupSuggestions, moments: [Moment], places: [Place]) {
        self.cleanupSuggestions = cleanupSuggestions
        self.moments = moments
        self.places = places
    }
}
