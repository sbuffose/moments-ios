// CleanupViewModel.swift
// ViewModel para la funcionalidad de limpieza

import Foundation
import SwiftData
import Photos
import Combine

@MainActor
class CleanupViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isLoading = true
    @Published var selectedCategory: CleanupCategoryItem?
    @Published var selectedPhotos: Set<String> = []
    @Published var isDeleting = false
    @Published var showDeleteConfirmation = false
    @Published var errorMessage: String?
    
    @Published var categories: [CleanupCategoryItem] = []
    @Published var estimatedSpaceFreed: Int64 = 0
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private var allPhotos: [PersistedPhoto] = []
    
    // MARK: - Category Item
    
    struct CleanupCategoryItem: Identifiable {
        let id: String
        let category: CleanupCategory
        let count: Int
        let photos: [PersistedPhoto]
        let estimatedSize: Int64
        
        var icon: String { category.iconName }
        var localizedKey: String { category.localizedKey }
    }
    
    enum CleanupCategory: String, CaseIterable {
        case screenshots
        case screenRecordings
        case blurry
        case overexposed
        case underexposed
        case duplicates
        case bursts
        case accidentalShots
        case documents
        case largeVideos
        
        var iconName: String {
            switch self {
            case .screenshots: return "rectangle.on.rectangle"
            case .screenRecordings: return "record.circle"
            case .blurry: return "camera.metering.unknown"
            case .overexposed: return "sun.max.fill"
            case .underexposed: return "moon.fill"
            case .duplicates: return "doc.on.doc.fill"
            case .bursts: return "square.stack.3d.up.fill"
            case .accidentalShots: return "hand.raised.slash"
            case .documents: return "doc.text"
            case .largeVideos: return "film"
            }
        }
        
        var localizedKey: String {
            "cleanup_category_\(rawValue)"
        }
    }
    
    // MARK: - Initialization
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            await loadCleanupSuggestions()
        }
    }
    
    // MARK: - Loading
    
    func loadCleanupSuggestions() async {
        guard let context = modelContext else { return }
        
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.analysisCompleted }
            )
            
            var fetchedPhotos = try context.fetch(descriptor)
            fetchedPhotos.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            allPhotos = fetchedPhotos
            
            await MainActor.run {
                self.buildCategories()
                self.calculateEstimatedSpace()
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Error al cargar fotos: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func buildCategories() {
        var items: [CleanupCategoryItem] = []
        
        // Screenshots
        let screenshots = allPhotos.filter { $0.mediaSubtypesRaw.contains("screenshot") }
        if !screenshots.isEmpty {
            items.append(CleanupCategoryItem(
                id: "screenshots",
                category: .screenshots,
                count: screenshots.count,
                photos: screenshots,
                estimatedSize: screenshots.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Screen Recordings
        let recordings = allPhotos.filter { 
            $0.mediaTypeRaw == "video" && $0.mediaSubtypesRaw.contains("screenRecording") 
        }
        if !recordings.isEmpty {
            items.append(CleanupCategoryItem(
                id: "screenRecordings",
                category: .screenRecordings,
                count: recordings.count,
                photos: recordings,
                estimatedSize: recordings.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Blurry
        let blurry = allPhotos.filter { 
            $0.mediaTypeRaw == "image" && ($0.sharpnessScore ?? 1.0) < 0.3 
        }
        if !blurry.isEmpty {
            items.append(CleanupCategoryItem(
                id: "blurry",
                category: .blurry,
                count: blurry.count,
                photos: blurry,
                estimatedSize: blurry.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Overexposed
        let overexposed = allPhotos.filter { 
            $0.mediaTypeRaw == "image" && ($0.exposureScore ?? 0.5) > 0.85 
        }
        if !overexposed.isEmpty {
            items.append(CleanupCategoryItem(
                id: "overexposed",
                category: .overexposed,
                count: overexposed.count,
                photos: overexposed,
                estimatedSize: overexposed.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Underexposed
        let underexposed = allPhotos.filter { 
            $0.mediaTypeRaw == "image" && ($0.exposureScore ?? 0.5) < 0.15 
        }
        if !underexposed.isEmpty {
            items.append(CleanupCategoryItem(
                id: "underexposed",
                category: .underexposed,
                count: underexposed.count,
                photos: underexposed,
                estimatedSize: underexposed.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Bursts (no-representative)
        let burstPhotos = allPhotos.filter { 
            $0.burstIdentifier != nil && !$0.representsBurst 
        }
        if !burstPhotos.isEmpty {
            items.append(CleanupCategoryItem(
                id: "bursts",
                category: .bursts,
                count: burstPhotos.count,
                photos: burstPhotos,
                estimatedSize: burstPhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Accidental Shots (very dark + no faces)
        let accidental = allPhotos.filter { photo in
            guard photo.mediaTypeRaw == "image" else { return false }
            
            // Muy oscura
            if let exposure = photo.exposureScore, exposure < 0.05 {
                return true
            }
            
            // Muy borrosa sin rostros
            if let sharpness = photo.sharpnessScore, sharpness < 0.1,
               let faces = photo.facesDetected, faces == 0 {
                return true
            }
            
            return false
        }
        if !accidental.isEmpty {
            items.append(CleanupCategoryItem(
                id: "accidentalShots",
                category: .accidentalShots,
                count: accidental.count,
                photos: accidental,
                estimatedSize: accidental.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Documents
        let documents = allPhotos.filter { $0.isDocument == true }
        if !documents.isEmpty {
            items.append(CleanupCategoryItem(
                id: "documents",
                category: .documents,
                count: documents.count,
                photos: documents,
                estimatedSize: documents.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Large Videos (> 100 MB)
        let largeVideos = allPhotos.filter { 
            $0.mediaTypeRaw == "video" && ($0.estimatedFileSize ?? 0) > 100_000_000 
        }.sorted { ($0.estimatedFileSize ?? 0) > ($1.estimatedFileSize ?? 0) }
        
        if !largeVideos.isEmpty {
            items.append(CleanupCategoryItem(
                id: "largeVideos",
                category: .largeVideos,
                count: largeVideos.count,
                photos: largeVideos,
                estimatedSize: largeVideos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
            ))
        }
        
        // Ordenar por cantidad
        categories = items.sorted { $0.count > $1.count }
    }
    
    private func calculateEstimatedSpace() {
        estimatedSpaceFreed = categories.reduce(0) { $0 + $1.estimatedSize }
    }
    
    // MARK: - Selection
    
    func selectAll(in category: CleanupCategoryItem) {
        for photo in category.photos {
            selectedPhotos.insert(photo.id)
        }
    }
    
    func deselectAll(in category: CleanupCategoryItem) {
        for photo in category.photos {
            selectedPhotos.remove(photo.id)
        }
    }
    
    func toggleSelection(for photo: PersistedPhoto) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }
    
    func isSelected(_ photo: PersistedPhoto) -> Bool {
        selectedPhotos.contains(photo.id)
    }
    
    var selectedCount: Int {
        selectedPhotos.count
    }
    
    var selectedSize: Int64 {
        guard let category = selectedCategory else { return 0 }
        return category.photos
            .filter { selectedPhotos.contains($0.id) }
            .reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    // MARK: - Deletion
    
    func deleteSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        guard let context = modelContext else { return }
        
        isDeleting = true
        
        let photosToDelete = allPhotos.filter { selectedPhotos.contains($0.id) }
        let identifiers = photosToDelete.map { $0.localIdentifier }
        
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            
            // Eliminar de SwiftData
            for photo in photosToDelete {
                context.delete(photo)
            }
            try context.save()
            
            // Actualizar UI
            selectedPhotos.removeAll()
            await loadCleanupSuggestions()
            
        } catch {
            errorMessage = "Error al eliminar: \(error.localizedDescription)"
        }
        
        isDeleting = false
    }
}

// MARK: - Formatted Size

extension CleanupViewModel {
    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
