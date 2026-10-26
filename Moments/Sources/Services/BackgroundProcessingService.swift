// BackgroundProcessingService.swift
// Servicio para procesamiento en segundo plano con control de batería

import Foundation
import UIKit
import Combine

actor BackgroundProcessingService {
    static let shared = BackgroundProcessingService()
    
    // MARK: - State
    
    private var isProcessing = false
    private var isPaused = false
    private var currentBatchIndex = 0
    private var processedCount = 0
    
    // MARK: - Configuration
    
    let batchSize = 20
    let minBatteryLevel: Float = 0.20
    let pauseBetweenBatches: UInt64 = 500_000_000 // 0.5 seconds
    
    // MARK: - Callbacks
    
    private var progressCallback: ((Double, Int) -> Void)?
    private var completionCallback: (() -> Void)?
    
    private init() {}
    
    // MARK: - Battery State
    
    nonisolated var shouldPauseForBattery: Bool {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        
        // Pause if Low Power Mode is enabled
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return true
        }
        
        // Pause if battery is low and not charging
        let batteryState = device.batteryState
        let batteryLevel = device.batteryLevel
        
        if batteryLevel >= 0 && batteryLevel < minBatteryLevel {
            if batteryState != .charging && batteryState != .full {
                return true
            }
        }
        
        return false
    }
    
    nonisolated var batteryStatus: BatteryStatus {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        
        return BatteryStatus(
            level: device.batteryLevel,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            isCharging: device.batteryState == .charging || device.batteryState == .full
        )
    }
    
    struct BatteryStatus: Sendable {
        let level: Float
        let isLowPowerMode: Bool
        let isCharging: Bool
        
        var canProcess: Bool {
            if isLowPowerMode { return false }
            if level >= 0 && level < 0.20 && !isCharging { return false }
            return true
        }
    }
    
    // MARK: - Processing Control
    
    func startProcessing<T>(
        items: [T],
        processor: @escaping @Sendable (T) async throws -> Void,
        progressHandler: @escaping @Sendable (Double, Int) async -> Void,
        completion: @escaping @Sendable () async -> Void
    ) async where T: Sendable {
        guard !isProcessing else { return }
        
        isProcessing = true
        isPaused = false
        currentBatchIndex = 0
        processedCount = 0
        
        let total = items.count
        guard total > 0 else {
            isProcessing = false
            await completion()
            return
        }
        
        for (index, item) in items.enumerated() {
            // Check if we should pause
            while shouldPauseForBattery && !isPaused {
                isPaused = true
                // Wait and check again
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                
                if Task.isCancelled {
                    isProcessing = false
                    return
                }
            }
            
            if !shouldPauseForBattery {
                isPaused = false
            }
            
            // Process item with low priority
            do {
                try await processor(item)
                processedCount += 1
            } catch {
                // Log error but continue processing
                print("Processing error for item \(index): \(error)")
            }
            
            // Report progress after each batch
            if (index + 1) % batchSize == 0 || index == total - 1 {
                let progress = Double(index + 1) / Double(total)
                await progressHandler(progress, processedCount)
                
                // Yield to other tasks
                try? await Task.sleep(nanoseconds: pauseBetweenBatches)
            }
            
            if Task.isCancelled {
                isProcessing = false
                return
            }
        }
        
        isProcessing = false
        await completion()
    }
    
    func pauseProcessing() {
        isPaused = true
    }
    
    func resumeProcessing() {
        isPaused = false
    }
    
    func cancelProcessing() {
        isProcessing = false
        isPaused = false
    }
    
    var processingState: ProcessingState {
        ProcessingState(
            isProcessing: isProcessing,
            isPaused: isPaused,
            processedCount: processedCount
        )
    }
    
    struct ProcessingState: Sendable {
        let isProcessing: Bool
        let isPaused: Bool
        let processedCount: Int
    }
}

// MARK: - Low Power Mode Observer

@MainActor
class PowerModeObserver: ObservableObject {
    @Published var isLowPowerMode: Bool = false
    @Published var batteryLevel: Float = 1.0
    @Published var isCharging: Bool = false
    
    private var notificationToken: NSObjectProtocol?
    
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateState()
        
        notificationToken = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateState()
        }
    }
    
    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    private func updateState() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        batteryLevel = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }
    
    var canProcess: Bool {
        if isLowPowerMode { return false }
        if batteryLevel >= 0 && batteryLevel < 0.20 && !isCharging { return false }
        return true
    }
}
