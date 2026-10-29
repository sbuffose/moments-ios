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
    
    /// Cover for a moment: stored id, then any photo in the moment, then any photo from that day.
    static func coverLocalIdentifier(
        storedCover: String?,
        photoIds: [String],
        startDate: Date,
        endDate: Date,
        photos: [PersistedPhoto]
    ) -> String? {
        let idToLocal = idToLocalMap(from: photos)
        let knownLocals = Set(photos.map(\.localIdentifier).filter { !$0.isEmpty })
        
        if let resolved = photoKitIdentifier(for: storedCover, idToLocal: idToLocal),
           knownLocals.contains(resolved) {
            return resolved
        }
        for photoId in photoIds {
            if let local = idToLocal[photoId], knownLocals.contains(local) {
                return local
            }
        }
        return fallbackCoverForDay(startDate: startDate, endDate: endDate, photos: photos)
    }
    
    static func fallbackCoverForDay(startDate: Date, endDate: Date, photos: [PersistedPhoto]) -> String? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: startDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        let inRange = photos.filter { photo in
            guard let date = photo.creationDate, !photo.localIdentifier.isEmpty else { return false }
            return date >= dayStart && date < dayEnd
        }
        return inRange.first?.localIdentifier ?? photos.first(where: { !$0.localIdentifier.isEmpty })?.localIdentifier
    }
}
