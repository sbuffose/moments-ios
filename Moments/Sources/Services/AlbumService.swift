// AlbumService.swift
// Guardar en álbum de PhotoKit y marcar como keep.

import Foundation
import Photos
import SwiftUI

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

struct SaveToAlbumSheet: View {
    let item: ReviewItem?
    var onSaved: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var albums: [String] = []
    @State private var errorMessage: String?
    
    private var identifiers: [String] {
        switch item {
        case .single(let photo):
            return [photo.localIdentifier]
        case .exactDuplicateGroup(_, let photos), .similarGroup(_, let photos):
            return photos.map(\.localIdentifier)
        case .none:
            return []
        }
    }
    
    private var suggested: String {
        let labels: String?
        switch item {
        case .single(let photo): labels = photo.visionLabels
        default: labels = nil
        }
        return AlbumService.suggestedAlbumTitle(
            labels: labels,
            lastChoice: UserDefaults.standard.string(forKey: AlbumService.lastAlbumKey)
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Sugerido") {
                    Button(suggested) { save(named: suggested) }
                        .accessibilityIdentifier("review.albumSuggested")
                }
                Section("Álbumes") {
                    ForEach(albums, id: \.self) { title in
                        Button(title) { save(named: title) }
                    }
                }
                Section("Nuevo álbum…") {
                    TextField("Cooking4U", text: $newName)
                        .accessibilityIdentifier("review.albumNewName")
                    Button("Crear y guardar") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        save(named: name)
                    }
                    .accessibilityIdentifier("review.albumCreate")
                }
            }
            .navigationTitle("Guardar en álbum")
            .onAppear {
                albums = AlbumService.userAlbumTitles()
                if newName.isEmpty { newName = suggested }
            }
            .alert("No se pudo guardar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .accessibilityIdentifier("review.albumSheet")
    }
    
    private func save(named title: String) {
        let ids = identifiers
        Task {
            do {
                try await AlbumService.addAssets(ids, toAlbumNamed: title)
                await MainActor.run {
                    onSaved(item?.photoIds ?? [])
                    dismiss()
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
