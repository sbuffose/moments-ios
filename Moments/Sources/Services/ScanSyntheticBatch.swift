// ScanSyntheticBatch.swift
// Foundation-only synthetic scan work. Unit tests call this directly so the
// host never hops to ScanPipeline (Photos/Vision/SwiftData) or MainActor.

import Foundation
import os

private let syntheticScanLog = Logger(subsystem: "com.sbuffose.moments", category: "ScanPipeline")

enum ScanSyntheticBatch {
    /// One item of CPU work + checkpoint write. Safe on any thread.
    @discardableResult
    static func processNext(item: ScanWorkItem, store: ScanCheckpointStore) -> Bool {
        syntheticScanLog.info("processNext id=\(item.id, privacy: .public) main=\(Thread.isMainThread, privacy: .public)")
        if store.isProcessed(item.id) { return false }
        var hash: UInt64 = 14695981039346656037
        for byte in item.id.utf8 {
            hash = hash &* 1099511628211 ^ UInt64(byte)
        }
        for i in 0..<64 {
            hash ^= hash << 13
            hash ^= hash >> 7
            hash &+= UInt64(i)
        }
        _ = hash
        store.markProcessed(item.id)
        return true
    }
    
    static func processBatch(
        _ items: [ScanWorkItem],
        store: ScanCheckpointStore,
        onItem: (String) -> Void
    ) {
        syntheticScanLog.info("processBatch start count=\(items.count, privacy: .public) main=\(Thread.isMainThread, privacy: .public)")
        for item in items {
            if store.isProcessed(item.id) { continue }
            _ = processNext(item: item, store: store)
            onItem(item.id)
        }
        store.persist()
        syntheticScanLog.info("processBatch done processed=\(store.processedCount, privacy: .public)")
    }
}
