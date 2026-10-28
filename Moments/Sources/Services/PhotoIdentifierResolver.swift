// PhotoIdentifierResolver.swift
// PersistedMoment.coverPhotoId historically stored PersistedPhoto.id (UUID),
// but AsyncPhotoThumbnail fetches PHAsset by localIdentifier.

import Foundation

enum PhotoIdentifierResolver {
    /// Map a stored cover id (photo.id or localIdentifier) to a PhotoKit localIdentifier.
    static func photoKitIdentifier(for storedId: String?, idToLocal: [String: String]) -> String? {
        guard let storedId, !storedId.isEmpty else { return nil }
        if let local = idToLocal[storedId], !local.isEmpty {
            return local
        }
        return storedId
    }
    
    static func idToLocalMap(from photos: [PersistedPhoto]) -> [String: String] {
        var map: [String: String] = [:]
        map.reserveCapacity(photos.count * 2)
        for photo in photos {
            map[photo.id] = photo.localIdentifier
            map[photo.localIdentifier] = photo.localIdentifier
        }
        return map
    }
}
