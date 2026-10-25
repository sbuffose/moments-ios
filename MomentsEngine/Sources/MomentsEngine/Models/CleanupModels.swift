// CleanupModels.swift
// Modelos para sugerencias de limpieza

import Foundation

/// Categorías de limpieza
public enum CleanupCategory: String, Codable, CaseIterable, Sendable {
    case screenshots = "screenshots"
    case screenRecordings = "screen_recordings"
    case blurry = "blurry"
    case overexposed = "overexposed"
    case underexposed = "underexposed"
    case duplicates = "duplicates"
    case nearDuplicates = "near_duplicates"
    case bursts = "bursts"
    case accidentalShots = "accidental_shots"
    case documents = "documents"
    case largeVideos = "large_videos"
    
    public var localizedKey: String {
        switch self {
        case .screenshots: return "cleanup_category_screenshots"
        case .screenRecordings: return "cleanup_category_screen_recordings"
        case .blurry: return "cleanup_category_blurry"
        case .overexposed: return "cleanup_category_overexposed"
        case .underexposed: return "cleanup_category_underexposed"
        case .duplicates: return "cleanup_category_duplicates"
        case .nearDuplicates: return "cleanup_category_near_duplicates"
        case .bursts: return "cleanup_category_bursts"
        case .accidentalShots: return "cleanup_category_accidental"
        case .documents: return "cleanup_category_documents"
        case .largeVideos: return "cleanup_category_large_videos"
        }
    }
    
    public var iconName: String {
        switch self {
        case .screenshots: return "rectangle.on.rectangle"
        case .screenRecordings: return "record.circle"
        case .blurry: return "camera.metering.unknown"
        case .overexposed: return "sun.max.fill"
        case .underexposed: return "moon.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .nearDuplicates: return "square.on.square"
        case .bursts: return "square.stack.3d.up.fill"
        case .accidentalShots: return "hand.raised.slash"
        case .documents: return "doc.text"
        case .largeVideos: return "film"
        }
    }
}

/// Resultado completo de análisis de limpieza
public struct CleanupSuggestions: Codable, Sendable {
    public var screenshots: [PhotoMetadata]
    public var screenRecordings: [PhotoMetadata]
    public var blurryPhotos: [PhotoMetadata]
    public var overexposedPhotos: [PhotoMetadata]
    public var underexposedPhotos: [PhotoMetadata]
    public var duplicateGroups: [DuplicateGroup]
    public var nearDuplicateGroups: [DuplicateGroup]
    public var burstGroups: [BurstGroup]
    public var accidentalShots: [PhotoMetadata]
    public var documents: [PhotoMetadata]
    public var largeVideos: [PhotoMetadata]
    
    public init(
        screenshots: [PhotoMetadata] = [],
        screenRecordings: [PhotoMetadata] = [],
        blurryPhotos: [PhotoMetadata] = [],
        overexposedPhotos: [PhotoMetadata] = [],
        underexposedPhotos: [PhotoMetadata] = [],
        duplicateGroups: [DuplicateGroup] = [],
        nearDuplicateGroups: [DuplicateGroup] = [],
        burstGroups: [BurstGroup] = [],
        accidentalShots: [PhotoMetadata] = [],
        documents: [PhotoMetadata] = [],
        largeVideos: [PhotoMetadata] = []
    ) {
        self.screenshots = screenshots
        self.screenRecordings = screenRecordings
        self.blurryPhotos = blurryPhotos
        self.overexposedPhotos = overexposedPhotos
        self.underexposedPhotos = underexposedPhotos
        self.duplicateGroups = duplicateGroups
        self.nearDuplicateGroups = nearDuplicateGroups
        self.burstGroups = burstGroups
        self.accidentalShots = accidentalShots
        self.documents = documents
        self.largeVideos = largeVideos
    }
    
    /// Total de fotos sugeridas para eliminar
    public var totalSuggestedForDeletion: Int {
        screenshots.count +
        screenRecordings.count +
        blurryPhotos.count +
        overexposedPhotos.count +
        underexposedPhotos.count +
        duplicateGroups.reduce(0) { $0 + $1.duplicates.count } +
        nearDuplicateGroups.reduce(0) { $0 + $1.duplicates.count } +
        burstGroups.reduce(0) { $0 + $1.nonBestPhotos.count } +
        accidentalShots.count +
        documents.count +
        largeVideos.count
    }
    
    /// Espacio estimado que se liberaría (bytes)
    public var estimatedSpaceFreed: Int64 {
        var total: Int64 = 0
        
        let allSuggested: [PhotoMetadata] = screenshots + screenRecordings + blurryPhotos +
            overexposedPhotos + underexposedPhotos + accidentalShots + documents + largeVideos
        
        for photo in allSuggested {
            total += photo.estimatedFileSize ?? 0
        }
        
        for group in duplicateGroups {
            for photo in group.duplicates {
                total += photo.estimatedFileSize ?? 0
            }
        }
        
        for group in nearDuplicateGroups {
            for photo in group.duplicates {
                total += photo.estimatedFileSize ?? 0
            }
        }
        
        for group in burstGroups {
            for photo in group.nonBestPhotos {
                total += photo.estimatedFileSize ?? 0
            }
        }
        
        return total
    }
    
    /// Obtener items por categoría
    public func items(for category: CleanupCategory) -> [PhotoMetadata] {
        switch category {
        case .screenshots: return screenshots
        case .screenRecordings: return screenRecordings
        case .blurry: return blurryPhotos
        case .overexposed: return overexposedPhotos
        case .underexposed: return underexposedPhotos
        case .duplicates: return duplicateGroups.flatMap { $0.all }
        case .nearDuplicates: return nearDuplicateGroups.flatMap { $0.all }
        case .bursts: return burstGroups.flatMap { $0.all }
        case .accidentalShots: return accidentalShots
        case .documents: return documents
        case .largeVideos: return largeVideos
        }
    }
    
    public func count(for category: CleanupCategory) -> Int {
        items(for: category).count
    }
}

/// Grupo de fotos duplicadas
public struct DuplicateGroup: Codable, Identifiable, Sendable {
    public let id: String
    public let best: PhotoMetadata
    public let duplicates: [PhotoMetadata]
    public let similarity: Double // 0.0 - 1.0
    
    public init(id: String = UUID().uuidString, best: PhotoMetadata, duplicates: [PhotoMetadata], similarity: Double) {
        self.id = id
        self.best = best
        self.duplicates = duplicates
        self.similarity = similarity
    }
    
    public var all: [PhotoMetadata] {
        [best] + duplicates
    }
}

/// Grupo de fotos en ráfaga
public struct BurstGroup: Codable, Identifiable, Sendable {
    public let id: String
    public let burstIdentifier: String
    public let best: PhotoMetadata
    public let others: [PhotoMetadata]
    
    public init(id: String = UUID().uuidString, burstIdentifier: String, best: PhotoMetadata, others: [PhotoMetadata]) {
        self.id = id
        self.burstIdentifier = burstIdentifier
        self.best = best
        self.others = others
    }
    
    public var all: [PhotoMetadata] {
        [best] + others
    }
    
    public var nonBestPhotos: [PhotoMetadata] {
        others
    }
}
