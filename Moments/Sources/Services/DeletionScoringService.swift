// DeletionScoringService.swift
// Calculates deletion likelihood scores for photos

import Foundation
import SwiftData

@MainActor
final class DeletionScoringService {
    static let shared = DeletionScoringService()
    
    private var modelContext: ModelContext?
    private var namedPersonIds: Set<String> = []
    
    private init() {}
    
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadNamedPeople()
    }
    
    private func loadNamedPeople() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate { $0.name != nil }
        )
        
        if let people = try? context.fetch(descriptor) {
            namedPersonIds = Set(people.map { $0.id })
        }
    }
    
    // MARK: - Score Calculation
    
    /// Calculates the deletion likelihood score for a photo (0-1, higher = more likely to delete)
    func calculateScore(for photo: PersistedPhoto) -> Double {
        var score: Double = 0.0
        
        // === STRONG SIGNALS (increase score - more likely to delete) ===
        
        // 1. Exact duplicates (non-best in group)
        if photo.duplicateGroupId != nil && photo.isBestInGroup != true {
            score += 0.30
        }
        
        // 2. Near-duplicate burst losers
        if photo.burstIdentifier != nil && !photo.representsBurst {
            score += 0.25
        }
        
        // 3. Blurry photos - very strict threshold
        if let sharpness = photo.sharpnessScore, photo.mediaTypeRaw == "image" {
            if sharpness < 0.08 {
                score += 0.30 // Very blurry
            } else if sharpness < 0.15 {
                score += 0.20 // Somewhat blurry
            }
        }
        
        // 4. Very dark / accidental photos
        if let exposure = photo.exposureScore, photo.mediaTypeRaw == "image" {
            if exposure < 0.05 {
                score += 0.30 // Near-black pocket shot
            } else if exposure < 0.15 {
                score += 0.15 // Very underexposed
            }
        }
        
        // 5. Old screenshots (>30 days)
        if photo.mediaSubtypesRaw.contains("screenshot") {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let isOld = (photo.creationDate ?? Date()) < thirtyDaysAgo
            
            if isOld {
                score += 0.20
                
                // Extra boost for receipts/codes (OCR text patterns)
                if let ocrText = photo.ocrText?.lowercased() {
                    let receiptPatterns = ["total", "subtotal", "factura", "recibo", "iva", "$", "pago"]
                    let codePatterns = ["código", "code", "pin", "otp", "verificación"]
                    
                    let hasReceipt = receiptPatterns.contains { ocrText.contains($0) }
                    let hasCode = codePatterns.contains { ocrText.contains($0) }
                    
                    if hasReceipt || hasCode {
                        score += 0.15
                    }
                }
            } else {
                score += 0.10 // Recent screenshots still somewhat deletable
            }
        }
        
        // 6. Already-shared messaging app media
        if photo.origin.isMessagingApp {
            score += 0.15
            
            // Extra boost for forwarded/downloaded content
            if photo.cleanupCategory == .forwardedImage || photo.cleanupCategory == .downloadedMeme {
                score += 0.15
            }
        }
        
        // 7. App downloads/memes
        if photo.origin == .download || photo.origin == .savedFromWeb {
            score += 0.20
            
            // Small images without faces are likely memes
            let maxDim = max(photo.pixelWidth, photo.pixelHeight)
            if maxDim < 1000 && (photo.facesDetected ?? 0) == 0 {
                score += 0.10
            }
        }
        
        // 8. QR codes and barcodes
        if photo.hasBarcode == true || photo.cleanupCategory == .qrCode {
            score += 0.25
        }
        
        // 9. Very short or tiny videos
        if photo.mediaTypeRaw == "video" {
            if photo.duration < 3.0 && photo.duration > 0 {
                score += 0.20 // Very short video (likely accidental)
            }
            if let size = photo.estimatedFileSize, size < 1_000_000 && size > 0 {
                score += 0.15 // Tiny video (likely a clip/gif)
            }
        }
        
        // 10. Documents (usually can be deleted after processing)
        if photo.isDocument == true || photo.cleanupCategory == .document {
            score += 0.10
        }
        
        // 11. Screen recordings
        if photo.cleanupCategory == .screenRecording {
            score += 0.15
        }
        
        // === LOWERING SIGNALS (decrease score - less likely to delete) ===
        
        // 1. Favorites - strong protection
        if photo.isFavorite {
            score -= 0.40
        }
        
        // 2. Edited photos - user invested effort
        if photo.isEdited {
            score -= 0.25
        }
        
        // 3. Faces/people detected
        if let faces = photo.facesDetected, faces > 0 {
            let faceReduction = min(Double(faces) * 0.10, 0.30)
            score -= faceReduction
            
            // Check for named/frequent people
            if let faceDetections = photo.faceDetections {
                let hasNamedPerson = faceDetections.contains { detection in
                    if let clusterId = detection.clusterId {
                        return namedPersonIds.contains(clusterId)
                    }
                    return false
                }
                if hasNamedPerson {
                    score -= 0.15
                }
            }
        }
        
        // 4. Trip/place photos
        if photo.placeClusterId != nil || photo.placeName != nil {
            score -= 0.10
        }
        
        // 5. High aesthetics score
        if let sharpness = photo.sharpnessScore, sharpness > 0.7 {
            score -= 0.10
        }
        if let exposure = photo.exposureScore, exposure > 0.35 && exposure < 0.65 {
            score -= 0.05 // Well-exposed
        }
        
        // 6. Live Photos - NOT a deletion signal (suggest conversion instead)
        // Don't add to score for being a Live Photo
        
        // 7. Shared or received with people
        if photo.isSharedOrReceived && (photo.facesDetected ?? 0) > 0 {
            score -= 0.10
        }
        
        // 8. Protected photos should never be suggested
        if photo.isProtected {
            score -= 0.50
        }
        
        // Clamp to 0-1 range
        return max(0.0, min(1.0, score))
    }
    
    // MARK: - Batch Updates
    
    func updateScoresForAllPhotos() async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted }
        )
        
        do {
            let photos = try context.fetch(descriptor)
            
            for photo in photos {
                photo.deletionLikelihoodScore = calculateScore(for: photo)
            }
            
            try context.save()
        } catch {
            print("[DeletionScoringService] Error updating scores: \(error)")
        }
    }
    
    func updateScore(for photo: PersistedPhoto) {
        photo.deletionLikelihoodScore = calculateScore(for: photo)
    }
}

// MARK: - Scoring Fixtures for Testing

enum DeletionScoreFixture {
    case exactDuplicate
    case burstLoser
    case veryBlurry
    case pocketShot
    case oldScreenshotWithReceipt
    case recentScreenshot
    case whatsappMeme
    case downloadedImage
    case qrCode
    case shortVideo
    case favoritePhoto
    case editedPhoto
    case photoWithFaces
    case tripPhoto
    case highQualityPhoto
    case livePhoto
    case protectedPhoto
    
    var expectedScoreRange: ClosedRange<Double> {
        switch self {
        case .exactDuplicate: return 0.25...0.35
        case .burstLoser: return 0.20...0.30
        case .veryBlurry: return 0.25...0.35
        case .pocketShot: return 0.25...0.35
        case .oldScreenshotWithReceipt: return 0.30...0.45
        case .recentScreenshot: return 0.05...0.15
        case .whatsappMeme: return 0.35...0.50
        case .downloadedImage: return 0.15...0.30
        case .qrCode: return 0.20...0.30
        case .shortVideo: return 0.15...0.25
        case .favoritePhoto: return 0.0...0.10
        case .editedPhoto: return 0.0...0.15
        case .photoWithFaces: return 0.0...0.20
        case .tripPhoto: return 0.0...0.20
        case .highQualityPhoto: return 0.0...0.15
        case .livePhoto: return 0.0...0.10
        case .protectedPhoto: return 0.0...0.05
        }
    }
}
