// ProtectionService.swift
// Determines which photos are protected from cleanup suggestions

import Foundation
import SwiftData
import Photos

@MainActor
class ProtectionService: ObservableObject {
    private var modelContext: ModelContext?
    
    @Published var protectedCount: Int = 0
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Analyze Protection Status
    
    func analyzeProtectionStatus(for photos: [PersistedPhoto]) async {
        guard let context = modelContext else { return }
        
        // Get all photo IDs in user albums
        let albumPhotoIds = await getPhotoIdsInUserAlbums()
        
        // Get photos with named people
        let namedPersonPhotoIds = await getPhotoIdsWithNamedPeople()
        
        // Get "only photo of day" status
        let onlyPhotosOfDay = await calculateOnlyPhotosOfDay(photos: photos)
        
        // Get photos associated with important dates
        let importantDatePhotoIds = await getPhotoIdsWithImportantDates()
        
        for photo in photos {
            var reasons: [ProtectionReason] = []
            
            // Check favorite
            if photo.isFavorite {
                reasons.append(.favorite)
            }
            
            // Check edited
            if photo.isEdited {
                reasons.append(.edited)
            }
            
            // Check hidden
            if photo.isHidden {
                reasons.append(.hidden)
            }
            
            // Check in album
            if albumPhotoIds.contains(photo.localIdentifier) {
                photo.isInUserAlbum = true
                reasons.append(.inAlbum)
            }
            
            // Check shared/received
            if photo.isSharedOrReceived {
                reasons.append(.sharedOrReceived)
            }
            
            // Check only photo of day
            if onlyPhotosOfDay.contains(photo.id) {
                photo.isOnlyPhotoOfDay = true
                reasons.append(.onlyPhotoOfDay)
            }
            
            // Check named person
            if namedPersonPhotoIds.contains(photo.id) {
                reasons.append(.hasNamedPerson)
            }
            
            // Check important date
            if importantDatePhotoIds.contains(photo.id) {
                reasons.append(.importantDate)
            }
            
            // Update protection status
            photo.isProtected = !reasons.isEmpty
            photo.protectionReasons = reasons.map { $0.rawValue }
            photo.protectionReasonRaw = reasons.first?.rawValue ?? ProtectionReason.none.rawValue
        }
        
        try? context.save()
        
        protectedCount = photos.filter { $0.isProtected }.count
    }
    
    // MARK: - Check Edited Status from Photos Library
    
    func checkEditedStatus(for photo: PersistedPhoto) async -> Bool {
        let fetchOptions = PHFetchOptions()
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: fetchOptions)
        
        guard let asset = assets.firstObject else { return false }
        
        // Check if asset has adjustments (edited)
        let resources = PHAssetResource.assetResources(for: asset)
        let hasAdjustments = resources.contains { 
            $0.type == .adjustmentData || $0.type == .fullSizePhoto
        }
        
        return hasAdjustments
    }
    
    // MARK: - Get Photos in User Albums
    
    private func getPhotoIdsInUserAlbums() async -> Set<String> {
        var photoIds = Set<String>()
        
        // Fetch user-created albums (not smart albums)
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        
        userAlbums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                photoIds.insert(asset.localIdentifier)
            }
        }
        
        return photoIds
    }
    
    // MARK: - Get Photos with Named People
    
    private func getPhotoIdsWithNamedPeople() async -> Set<String> {
        guard let context = modelContext else { return [] }
        
        var photoIds = Set<String>()
        
        // Fetch persons with names
        let personDescriptor = FetchDescriptor<PersistedPerson>(
            predicate: #Predicate<PersistedPerson> { person in
                person.name != nil
            }
        )
        
        let namedPersons = (try? context.fetch(personDescriptor)) ?? []
        
        for person in namedPersons {
            for photoId in person.photoIdArray {
                photoIds.insert(photoId)
            }
        }
        
        return photoIds
    }
    
    // MARK: - Calculate Only Photos of Day
    
    private func calculateOnlyPhotosOfDay(photos: [PersistedPhoto]) async -> Set<String> {
        var onlyPhotos = Set<String>()
        
        // Group photos by day
        let calendar = Calendar.current
        var photosByDay: [String: [PersistedPhoto]] = [:]
        
        for photo in photos {
            guard let date = photo.creationDate else { continue }
            let dayKey = calendar.startOfDay(for: date).timeIntervalSince1970.description
            photosByDay[dayKey, default: []].append(photo)
        }
        
        // Find days with only one photo
        for (_, dayPhotos) in photosByDay where dayPhotos.count == 1 {
            if let photo = dayPhotos.first {
                onlyPhotos.insert(photo.id)
            }
        }
        
        return onlyPhotos
    }
    
    // MARK: - Get Photos with Important Dates
    
    private func getPhotoIdsWithImportantDates() async -> Set<String> {
        guard let context = modelContext else { return [] }
        
        var photoIds = Set<String>()
        
        let dateDescriptor = FetchDescriptor<PersistedImportantDate>()
        let dates = (try? context.fetch(dateDescriptor)) ?? []
        
        for date in dates {
            for photoId in date.photoIdArray {
                photoIds.insert(photoId)
            }
        }
        
        return photoIds
    }
    
    // MARK: - Check Shared/Received Status
    
    func checkSharedStatus(asset: PHAsset) -> Bool {
        // Check if the asset was received via iCloud sharing or AirDrop
        let resources = PHAssetResource.assetResources(for: asset)
        
        for resource in resources {
            // Check for shared asset indicators
            if resource.type == .photo || resource.type == .video {
                // Check original filename patterns that indicate received content
                let filename = resource.originalFilename.lowercased()
                if filename.contains("shared") || filename.contains("received") {
                    return true
                }
            }
        }
        
        // Check sourceType for received photos
        if asset.sourceType.contains(.typeCloudShared) || 
           asset.sourceType.contains(.typeiTunesSynced) {
            return true
        }
        
        return false
    }
    
    // MARK: - Get Protection Summary
    
    func getProtectionSummary(for photo: PersistedPhoto) -> String {
        guard photo.isProtected else { return "" }
        
        let reasons = photo.protectionReasons?.compactMap { ProtectionReason(rawValue: $0) } ?? []
        
        if reasons.isEmpty {
            return photo.protectionReason.localizedDescription
        }
        
        return reasons.map { $0.localizedDescription }.joined(separator: ", ")
    }
}
