// LibraryInventoryService.swift
// One source of truth for indexed / reclaimable / today's-batch counts.
// Home, Asistente and Settings must all read this snapshot.

import Foundation
import SwiftData

struct LibraryInventory: Equatable, Sendable {
    var indexedCount: Int
    var analyzedCount: Int
    var totalReclaimableItems: Int
    var totalReclaimableBytes: Int64
    var todayBatchItems: Int
    var todayBatchBytes: Int64
    
    static let empty = LibraryInventory(
        indexedCount: 0,
        analyzedCount: 0,
        totalReclaimableItems: 0,
        totalReclaimableBytes: 0,
        todayBatchItems: 0,
        todayBatchBytes: 0
    )
}

enum LibraryInventoryService {
    /// Shared store query used by Home, Asistente and Settings.
    @MainActor
    static func snapshot(from context: ModelContext) -> LibraryInventory {
        let photos = (try? context.fetch(FetchDescriptor<PersistedPhoto>())) ?? []
        let analyzed = photos.filter(\.analysisCompleted)
        let groups = (try? context.fetch(
            FetchDescriptor<SimilarGroup>(predicate: #Predicate { $0.feedbackRaw != "notSimilar" })
        )) ?? []
        let preferences = try? context.fetch(FetchDescriptor<LearnedPreferences>()).first
        
        let queue = CleanupViewModel.makeQueue(
            photos: analyzed,
            groups: groups,
            preferences: preferences
        )
        let capped = DailyReviewBatch.cap(queue, preferences: preferences)
        
        return LibraryInventory(
            indexedCount: photos.count,
            analyzedCount: analyzed.count,
            totalReclaimableItems: queue.count,
            totalReclaimableBytes: queue.reduce(0) { $0 + $1.totalSize },
            todayBatchItems: capped.batch.count,
            todayBatchBytes: capped.batch.reduce(0) { $0 + $1.totalSize }
        )
    }
}

enum HomeLibraryCopy {
    static func heroHeadline(from inventory: LibraryInventory) -> String {
        HomeView.heroHeadline(
            todayBytes: inventory.todayBatchBytes,
            totalBytes: inventory.totalReclaimableBytes
        )
    }
    
    static func indexedCount(from inventory: LibraryInventory) -> Int {
        inventory.indexedCount
    }
}

enum AssistantLibraryCopy {
    static func todayBatchItems(from inventory: LibraryInventory) -> Int {
        min(inventory.todayBatchItems, DailyReviewBatch.size)
    }
    
    static func totalReclaimableItems(from inventory: LibraryInventory) -> Int {
        inventory.totalReclaimableItems
    }
    
    static func quickDeleteLimit(from inventory: LibraryInventory) -> Int {
        min(inventory.todayBatchItems, DailyReviewBatch.size)
    }
    
    static func offersDeleteAll(from inventory: LibraryInventory) -> Bool {
        false
    }
    
    static func infoLine(from inventory: LibraryInventory, batchSize: String, totalSize: String) -> String {
        let today = todayBatchItems(from: inventory)
        return "\(today) en el lote de hoy · \(inventory.totalReclaimableItems) en total · \(totalSize)"
    }
}

enum SettingsLibraryCopy {
    static func indexedCount(from inventory: LibraryInventory) -> Int {
        inventory.indexedCount
    }
    
    static func statusText(from inventory: LibraryInventory, isIndexing: Bool, isAnalyzing: Bool, analyzed: Int, toAnalyze: Int, progress: Double) -> String {
        if isIndexing {
            return "Indexando... \(Int(progress * 100))%"
        }
        if isAnalyzing {
            return "Analizando \(analyzed) / \(toAnalyze)"
        }
        return "\(inventory.indexedCount) elementos indexados"
    }
}
