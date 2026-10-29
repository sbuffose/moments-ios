// AlbumService.swift
// Guardar en álbum de PhotoKit y marcar como keep.

import Foundation
import Photos

enum AlbumService {
    static let lastAlbumKey = "com.moments.lastAlbumTitle"
    
    static func suggestedAlbumTitle(labels: String?, lastChoice: String?) -> String {
        if let lastChoice, !lastChoice.isEmpty { return lastChoice }
        let raw = labels?.lowercased() ?? ""
        if raw.contains("food") || raw.contains("comida") || raw.contains("cocin") { return "Cooking4U" }
        if raw.contains("travel") || raw.contains("viaje") { return "Viajes" }
        return "Moments"
    }
    
    static func userAlbumTitles() -> [String] {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var titles: [String] = []
        result.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle, !title.isEmpty {
                titles.append(title)
            }
        }
        return titles
    }
    
    static func addAssets(_ identifiers: [String], toAlbumNamed title: String) async throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }
        
        try await PHPhotoLibrary.shared().performChanges {
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            var target: PHAssetCollection?
            collections.enumerateObjects { collection, _, stop in
                if collection.localizedTitle == title {
                    target = collection
                    stop.pointee = true
                }
            }
            if let target, let change = PHAssetCollectionChangeRequest(for: target) {
                change.addAssets(assets as NSFastEnumeration)
            } else {
                let create = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                create.addAssets(assets as NSFastEnumeration)
            }
        }
        UserDefaults.standard.set(title, forKey: lastAlbumKey)
    }
}

