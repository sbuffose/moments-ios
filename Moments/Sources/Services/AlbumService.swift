// AlbumService.swift
// Service to manage user photo albums

import Foundation
import Photos

@MainActor
class AlbumService: ObservableObject {
    static let shared = AlbumService()
    
    @Published var userAlbums: [PHAssetCollection] = []
    @Published var momentsAlbum: PHAssetCollection?
    
    private let momentsAlbumName = "Momentos Guardados"
    
    private init() {
        loadUserAlbums()
        ensureMomentsAlbumExists()
    }
    
    // MARK: - Load Albums
    
    func loadUserAlbums() {
        var albums: [PHAssetCollection] = []
        
        let userAlbumsResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        
        userAlbumsResult.enumerateObjects { collection, _, _ in
            albums.append(collection)
        }
        
        // Sort alphabetically
        userAlbums = albums.sorted { ($0.localizedTitle ?? "") < ($1.localizedTitle ?? "") }
    }
    
    // MARK: - Moments Album
    
    private func ensureMomentsAlbumExists() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", momentsAlbumName)
        
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: fetchOptions
        )
        
        if let existingAlbum = collections.firstObject {
            momentsAlbum = existingAlbum
        } else {
            Task {
                await createMomentsAlbum()
            }
        }
    }
    
    private func createMomentsAlbum() async {
        do {
            var placeholder: PHObjectPlaceholder?
            
            try await PHPhotoLibrary.shared().performChanges {
                let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.momentsAlbumName)
                placeholder = createRequest.placeholderForCreatedAssetCollection
            }
            
            if let placeholder = placeholder {
                let fetchResult = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [placeholder.localIdentifier],
                    options: nil
                )
                momentsAlbum = fetchResult.firstObject
            }
        } catch {
            print("[AlbumService] Failed to create Moments album: \(error)")
        }
    }
    
    // MARK: - Create Album
    
    func createAlbum(named name: String) async -> PHAssetCollection? {
        do {
            var placeholder: PHObjectPlaceholder?
            
            try await PHPhotoLibrary.shared().performChanges {
                let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                placeholder = createRequest.placeholderForCreatedAssetCollection
            }
            
            if let placeholder = placeholder {
                let fetchResult = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [placeholder.localIdentifier],
                    options: nil
                )
                
                if let newAlbum = fetchResult.firstObject {
                    loadUserAlbums()
                    return newAlbum
                }
            }
        } catch {
            print("[AlbumService] Failed to create album: \(error)")
        }
        return nil
    }
    
    // MARK: - Add to Album
    
    func addToAlbum(_ localIdentifiers: [String], album: PHAssetCollection) async -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else { return false }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                albumChangeRequest.addAssets(assets)
            }
            return true
        } catch {
            print("[AlbumService] Failed to add to album: \(error)")
            return false
        }
    }
    
    func addToMomentsAlbum(_ localIdentifiers: [String]) async -> Bool {
        guard let album = momentsAlbum else {
            await createMomentsAlbum()
            guard let album = momentsAlbum else { return false }
            return await addToAlbum(localIdentifiers, album: album)
        }
        return await addToAlbum(localIdentifiers, album: album)
    }
    
    // MARK: - Remove from Album
    
    func removeFromAlbum(_ localIdentifiers: [String], album: PHAssetCollection) async -> Bool {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else { return false }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
                albumChangeRequest.removeAssets(assets)
            }
            return true
        } catch {
            print("[AlbumService] Failed to remove from album: \(error)")
            return false
        }
    }
}
