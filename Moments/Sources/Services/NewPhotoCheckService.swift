// NewPhotoCheckService.swift
// Revisa fotos nuevas ~5 minutos después de capturarlas.

import Foundation
import Photos
import SwiftData
import UserNotifications
import UIKit

struct NewPhotoCandidate: Identifiable, Equatable {
    let id: String
    let localIdentifier: String
    let reason: String
    let size: Int64
}

@MainActor
final class NewPhotoCheckService: ObservableObject {
    static let shared = NewPhotoCheckService()
    static let enabledKey = "com.moments.newPhotoCheck.enabled"
    static let countKey = "com.moments.newPhotoCheck.count"
    static let dayKey = "com.moments.newPhotoCheck.day"
    static let maxPerDay = 3
    static let delay: TimeInterval = 5 * 60
    static let simulateArgument = "-simulateNewPhotoCheck"
    
    @Published var pending: NewPhotoCandidate?
    
    private var modelContext: ModelContext?
    private var observer: PhotoLibraryChangeObserver?
    private var pendingAssetIds: [String: Date] = [:]
    private var pollTask: Task<Void, Never>?
    
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    
    static var isSimulated: Bool {
        ProcessInfo.processInfo.arguments.contains(simulateArgument)
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        if Self.isSimulated {
            pending = NewPhotoCandidate(
                id: "fixture-sim-new-photo",
                localIdentifier: "fixture-blurry-1",
                reason: "Está borrosa",
                size: 1_200_000
            )
            return
        }
        startObserving()
        startPolling()
    }
    
    func startObserving() {
        guard observer == nil else { return }
        let created = PhotoLibraryChangeObserver { [weak self] _ in
            Task { @MainActor in
                self?.noteLibraryChange()
            }
        }
        PHPhotoLibrary.shared().register(created)
        observer = created
        noteLibraryChange()
    }
    
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await MainActor.run {
                    self?.checkDuePhotos(isForeground: true)
                }
            }
        }
    }
    
    func noteLibraryChange() {
        guard Self.isEnabled else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 8
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        assets.enumerateObjects { asset, _, _ in
            guard let created = asset.creationDate else { return }
            let age = Date().timeIntervalSince(created)
            if age >= 0, age < 20 * 60 {
                self.pendingAssetIds[asset.localIdentifier] = created.addingTimeInterval(Self.delay)
            }
        }
    }
    
    func checkDuePhotos(isForeground: Bool) {
        guard Self.isEnabled else { return }
        let now = Date()
        let due = pendingAssetIds.filter { now >= $0.value }.map(\.key)
        guard let first = due.first else { return }
        pendingAssetIds.removeValue(forKey: first)
        
        guard remainingToday() > 0 else { return }
        if let photo = persistedPhoto(for: first), photo.isKeptByUser { return }
        
        let candidate = evaluate(localIdentifier: first)
        guard let candidate else { return }
        incrementToday()
        
        if isForeground {
            pending = candidate
        } else {
            notify(candidate)
        }
    }
    
    func remainingToday() -> Int {
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if UserDefaults.standard.double(forKey: Self.dayKey) != day {
            UserDefaults.standard.set(day, forKey: Self.dayKey)
            UserDefaults.standard.set(0, forKey: Self.countKey)
        }
        return max(0, Self.maxPerDay - UserDefaults.standard.integer(forKey: Self.countKey))
    }
    
    private func incrementToday() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.countKey) + 1, forKey: Self.countKey)
    }
    
    private func persistedPhoto(for localIdentifier: String) -> PersistedPhoto? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.localIdentifier == localIdentifier }
        )
        return try? context.fetch(descriptor).first
    }
    
    private func evaluate(localIdentifier: String) -> NewPhotoCandidate? {
        if let photo = persistedPhoto(for: localIdentifier) {
            if photo.cleanupCategory == .blurry || photo.cleanupCategory == .accidental || photo.cleanupCategory == .underexposed {
                return NewPhotoCandidate(
                    id: photo.id,
                    localIdentifier: localIdentifier,
                    reason: photo.cleanupCategory == .blurry ? "Está borrosa" : "Parece un disparo accidental",
                    size: photo.estimatedFileSize ?? 0
                )
            }
            return nil
        }
        return NewPhotoCandidate(
            id: localIdentifier,
            localIdentifier: localIdentifier,
            reason: "Revisá esta foto nueva",
            size: 0
        )
    }
    
    private func notify(_ candidate: NewPhotoCandidate) {
        let content = UNMutableNotificationContent()
        content.title = "Foto nueva"
        content.body = candidate.size > 0
            ? "\(candidate.reason) · \(SpaceFormatting.string(from: candidate.size))"
            : candidate.reason
        content.categoryIdentifier = "NEW_PHOTO_CHECK"
        content.userInfo = [
            "type": "newPhotoCheck",
            "id": candidate.id,
            "localIdentifier": candidate.localIdentifier,
            "reason": candidate.reason,
            "size": candidate.size
        ]
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "new-photo-\(candidate.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    func present(fromNotification userInfo: [AnyHashable: Any]) {
        let localId = userInfo["localIdentifier"] as? String ?? ""
        guard !localId.isEmpty else {
            checkDuePhotos(isForeground: true)
            return
        }
        pending = NewPhotoCandidate(
            id: userInfo["id"] as? String ?? localId,
            localIdentifier: localId,
            reason: userInfo["reason"] as? String ?? "Revisá esta foto nueva",
            size: userInfo["size"] as? Int64 ?? 0
        )
    }
    
    nonisolated static func isObviouslyBad(category: CleanupCategoryType, keepDecision: String?) -> Bool {
        guard keepDecision == nil || keepDecision == "none" else { return false }
        return category == .blurry || category == .accidental || category == .underexposed
    }
}
