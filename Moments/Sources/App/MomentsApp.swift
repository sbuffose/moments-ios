// MomentsApp.swift
// Punto de entrada de la aplicación Moments

import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import Photos

@main
struct MomentsApp: App {
    let container: ModelContainer
    
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let schema = Schema([
            PersistedPhoto.self,
            PersistedMoment.self,
            PersistedPlace.self,
            PersistedPlaceCluster.self,
            PersistedPerson.self,
            PersistedFaceDetection.self,
            PersistedRecurringEvent.self,
            PersistedCatalogingCard.self,
            PersistedImportantDate.self,
            PersistedNotificationSettings.self,
            AnalysisState.self,
            RememberListItem.self,
            PendingTrashItem.self,
            SimilarGroup.self,
            DeletionRecord.self,
            PhotoTag.self,
            PhotoReminder.self,
            DailyReviewSettings.self,
            ReviewDecision.self,
            LearnedPreferences.self
        ])
        
        if let persistentContainer = MomentsApp.createContainer(schema: schema, inMemory: false) {
            container = persistentContainer
        } else if let inMemoryContainer = MomentsApp.createContainer(schema: schema, inMemory: true) {
            container = inMemoryContainer
            print("Warning: Using in-memory container. Data will not persist.")
        } else {
            container = try! ModelContainer(for: schema)
        }
        
        // Register all background tasks synchronously during launch
        // This MUST happen before the app finishes launching
        BackgroundTaskManager.shared.registerBackgroundTasks()
        DailyReviewService.shared.registerBackgroundTask()
    }
    
    private static func createContainer(schema: Schema, inMemory: Bool) -> ModelContainer? {
        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                allowsSave: true
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("Failed to create ModelContainer (inMemory: \(inMemory)): \(error)")
            
            if !inMemory {
                MomentsApp.deleteExistingStore()
                do {
                    let config = ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        allowsSave: true
                    )
                    return try ModelContainer(for: schema, configurations: [config])
                } catch {
                    print("Still failed after deleting store: \(error)")
                }
            }
            return nil
        }
    }
    
    private static func deleteExistingStore() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        let storeURL = appSupport.appendingPathComponent("default.store")
        let shmURL = appSupport.appendingPathComponent("default.store-shm")
        let walURL = appSupport.appendingPathComponent("default.store-wal")
        
        for url in [storeURL, shmURL, walURL] {
            try? fileManager.removeItem(at: url)
        }
        print("Deleted existing SwiftData store files")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(container)
                .onAppear {
                    appState.initialize(modelContext: container.mainContext)
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            if appState.isIndexing || appState.isAnalyzing {
                BackgroundTaskManager.shared.beginBackgroundTaskForAppExit()
                
                if #available(iOS 26.0, *) {
                    // Calculate remaining photos based on checkpoint
                    let progress = BackgroundTaskManager.shared.getCheckpointProgress()
                    let remainingPhotos = max(0, progress.total - progress.analyzed)
                    BackgroundTaskManager.shared.submitContinuedProcessingTask(remainingPhotos: remainingPhotos)
                } else {
                    BackgroundTaskManager.shared.scheduleScanTaskIfNeeded()
                    BackgroundTaskManager.shared.scheduleAnalysisTaskIfNeeded()
                }
            }
        case .active:
            BackgroundTaskManager.shared.endBackgroundTask()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Estado Global de la App

@MainActor
class AppState: ObservableObject {
    @Published var isLibraryAuthorized = false
    @Published var isIndexing = false
    @Published var isAnalyzing = false
    @Published var indexingProgress: Double = 0
    @Published var analysisProgress: Double = 0
    @Published var totalPhotosIndexed = 0
    @Published var totalPhotosAnalyzed = 0
    @Published var totalPhotosToAnalyze = 0
    @Published var hasCompletedOnboarding = false
    @Published var selectedTab: AppTab = .home
    @Published var showProcessingSheet = false
    @Published var showFirstRunExplanation = false
    @Published var notificationsAuthorized = false
    @Published var estimatedSpaceSavings: Int64 = 0
    
    private var photoLibraryService: PhotoLibraryService?
    private var analysisService: PhotoAnalysisService?
    private var analysisTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    
    private let onboardingCompletedKey = "com.moments.hasCompletedOnboarding"
    private let notificationPromptShownKey = "com.moments.notificationPromptShown"
    private let analysisCompleteNotificationSentKey = "com.moments.analysisCompleteNotificationSent"
    private let firstRunExplanationShownKey = "com.moments.firstRunExplanationShown"
    
    // Legacy compatibility - always returns true after onboarding
    var hasCompletedInitialIndexing: Bool { hasCompletedOnboarding }
    var hasCompletedInitialScan: Bool { hasCompletedOnboarding }
    
    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
        
        // Show first-run explanation if not shown before
        if !UserDefaults.standard.bool(forKey: firstRunExplanationShownKey) {
            showFirstRunExplanation = true
        } else {
            startBackgroundIndexingAndAnalysis()
        }
    }
    
    func dismissFirstRunExplanation() {
        UserDefaults.standard.set(true, forKey: firstRunExplanationShownKey)
        showFirstRunExplanation = false
        startBackgroundIndexingAndAnalysis()
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
        UserDefaults.standard.removeObject(forKey: notificationPromptShownKey)
        UserDefaults.standard.removeObject(forKey: analysisCompleteNotificationSentKey)
    }
    
    enum AppTab: String, CaseIterable, Sendable {
        case home = "home"
        case assistant = "assistant"
        case moments = "moments"
        case settings = "settings"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .assistant: return "sparkles"
            case .moments: return "photo.on.rectangle.angled"
            case .settings: return "gear"
            }
        }
        
        var localizedKey: String {
            "tab_\(rawValue)"
        }
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        photoLibraryService = PhotoLibraryService(modelContext: modelContext)
        analysisService = PhotoAnalysisService(modelContext: modelContext)
        
        if let photoService = photoLibraryService, let analysisService = analysisService {
            BackgroundTaskManager.shared.configure(
                photoLibraryService: photoService,
                analysisService: analysisService
            )
        }
        
        if FixturePhotoSeeder.isRequested {
            do {
                let summary = try FixturePhotoSeeder.seedIfNeeded(into: modelContext)
                totalPhotosIndexed = summary.photos
                totalPhotosAnalyzed = summary.photos
                totalPhotosToAnalyze = summary.photos
                isLibraryAuthorized = true
                hasCompletedOnboarding = true
                print("[FixturePhotoSeeder] seeded \(summary.photos) photos")
            } catch {
                print("[FixturePhotoSeeder] failed: \(error)")
            }
        }
        
        Task {
            if FixturePhotoSeeder.isRequested {
                await checkNotificationStatus()
                scheduleDailyReviewIfNeeded()
                return
            }
            
            await checkAuthorizationStatus()
            await checkNotificationStatus()
            
            // If already onboarded, start background processing
            if hasCompletedOnboarding && isLibraryAuthorized {
                // Check if there's pending work from a previous interrupted scan
                if BackgroundTaskManager.shared.hasPendingWork {
                    resumeBackgroundProcessing()
                } else {
                    startBackgroundIndexingAndAnalysis()
                }
            }
            
            // Schedule daily review if enabled
            scheduleDailyReviewIfNeeded()
        }
    }
    
    func checkAuthorizationStatus() async {
        guard let service = photoLibraryService else { return }
        let status = await service.checkAuthorizationStatus()
        self.isLibraryAuthorized = (status == .authorized || status == .limited)
    }
    
    func requestAuthorization() async -> Bool {
        guard let service = photoLibraryService else { return false }
        let granted = await service.requestAuthorization()
        self.isLibraryAuthorized = granted
        return granted
    }
    
    // MARK: - Notification Permission
    
    func checkNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        self.notificationsAuthorized = settings.authorizationStatus == .authorized
    }
    
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            self.notificationsAuthorized = granted
            UserDefaults.standard.set(true, forKey: notificationPromptShownKey)
            return granted
        } catch {
            return false
        }
    }
    
    var shouldShowNotificationPrompt: Bool {
        !UserDefaults.standard.bool(forKey: notificationPromptShownKey) &&
        (isIndexing || isAnalyzing) &&
        !notificationsAuthorized
    }
    
    // MARK: - Background Processing (Non-blocking)
    
    func startBackgroundIndexingAndAnalysis() {
        guard let photoService = photoLibraryService else { return }
        
        // Cancel any existing tasks
        indexingTask?.cancel()
        analysisTask?.cancel()
        
        isIndexing = true
        indexingProgress = 0
        
        // Start tracking in BackgroundTaskManager
        let fetchOptions = PHFetchOptions()
        let totalPhotos = PHAsset.fetchAssets(with: fetchOptions).count
        BackgroundTaskManager.shared.startScan(totalPhotos: totalPhotos)
        
        // Start indexing in background with checkpointing
        indexingTask = Task { @MainActor in
            await photoService.scanLibraryWithCheckpointing(
                checkpointHandler: { assetId in
                    BackgroundTaskManager.shared.markIndexed(assetId: assetId)
                },
                isAlreadyIndexed: { assetId in
                    BackgroundTaskManager.shared.isAlreadyIndexed(assetId)
                },
                progressHandler: { progress, indexed in
                    Task { @MainActor in
                        self.indexingProgress = progress
                        self.totalPhotosIndexed = indexed
                    }
                }
            )
            
            self.isIndexing = false
            // Immediately start analysis after indexing
            self.startBackgroundAnalysis()
        }
    }
    
    func resumeBackgroundProcessing() {
        guard let photoService = photoLibraryService else { return }
        
        indexingTask?.cancel()
        analysisTask?.cancel()
        
        let progress = BackgroundTaskManager.shared.getCheckpointProgress()
        
        if progress.indexed < progress.total {
            isIndexing = true
            indexingProgress = Double(progress.indexed) / Double(max(progress.total, 1))
            totalPhotosIndexed = progress.indexed
            
            indexingTask = Task { @MainActor in
                await photoService.scanLibraryWithCheckpointing(
                    checkpointHandler: { assetId in
                        BackgroundTaskManager.shared.markIndexed(assetId: assetId)
                    },
                    isAlreadyIndexed: { assetId in
                        BackgroundTaskManager.shared.isAlreadyIndexed(assetId)
                    },
                    progressHandler: { progress, indexed in
                        Task { @MainActor in
                            self.indexingProgress = progress
                            self.totalPhotosIndexed = indexed
                        }
                    }
                )
                
                self.isIndexing = false
                self.startBackgroundAnalysis()
            }
        } else {
            startBackgroundAnalysis()
        }
    }
    
    // Legacy alias for startScan - now non-blocking
    func startScan() {
        startBackgroundIndexingAndAnalysis()
    }
    
    func startBackgroundAnalysis() {
        guard let analysisService = analysisService else { return }
        
        analysisTask?.cancel()
        
        analysisTask = Task { @MainActor in
            self.isAnalyzing = true
            
            let success = await analysisService.analyzeUnprocessedPhotosInBackground { progress in
                Task { @MainActor in
                    self.analysisProgress = progress
                    // Estimate counts based on progress
                    let checkpointProgress = BackgroundTaskManager.shared.getCheckpointProgress()
                    self.totalPhotosAnalyzed = checkpointProgress.analyzed
                    self.totalPhotosToAnalyze = checkpointProgress.indexed
                }
            }
            
            self.isAnalyzing = false
            
            if success {
                BackgroundTaskManager.shared.completeScan()
            }
            
            // Calculate estimated savings and send notification
            await self.calculateEstimatedSavings()
            await self.sendAnalysisCompleteNotification()
        }
    }
    
    func pauseAnalysis() {
        analysisTask?.cancel()
        indexingTask?.cancel()
        isAnalyzing = false
        isIndexing = false
    }
    
    // MARK: - Notifications
    
    private func calculateEstimatedSavings() async {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { photo in
                photo.cleanupCategoryRaw != "none" && photo.cleanupCategoryRaw != nil
            }
        )
        
        if let photos = try? context.fetch(descriptor) {
            let totalBytes = photos.compactMap { $0.estimatedFileSize }.reduce(0, +)
            self.estimatedSpaceSavings = totalBytes
        }
    }
    
    private func sendAnalysisCompleteNotification() async {
        guard notificationsAuthorized else { return }
        guard !UserDefaults.standard.bool(forKey: analysisCompleteNotificationSentKey) else { return }
        
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        
        let gbSavings = Double(estimatedSpaceSavings) / 1_000_000_000.0
        let formattedSavings: String
        if gbSavings >= 1.0 {
            formattedSavings = String(format: "%.1f GB", gbSavings)
        } else {
            let mbSavings = Double(estimatedSpaceSavings) / 1_000_000.0
            formattedSavings = String(format: "%.0f MB", mbSavings)
        }
        
        content.title = "¡Listo!"
        content.body = "Encontramos \(formattedSavings) para liberar"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "analysis-complete",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        try? await center.add(request)
        UserDefaults.standard.set(true, forKey: analysisCompleteNotificationSentKey)
    }
    
    // MARK: - Daily Review
    
    func scheduleDailyReviewIfNeeded() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<DailyReviewSettings>(
            predicate: #Predicate { $0.id == "main" }
        )
        
        guard let settings = try? context.fetch(descriptor).first,
              settings.isEnabled else { return }
        
        scheduleDailyReviewNotification(hour: settings.reviewHour, minute: settings.reviewMinute)
    }
    
    func scheduleDailyReviewNotification(hour: Int, minute: Int) {
        guard notificationsAuthorized else { return }
        
        let center = UNUserNotificationCenter.current()
        
        // Remove existing daily review notifications
        center.removePendingNotificationRequests(withIdentifiers: ["daily-review"])
        
        let content = UNMutableNotificationContent()
        content.title = "Repaso del día"
        content.body = "Revisá las fotos de hoy y organizá tu biblioteca"
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-review",
            content: content,
            trigger: trigger
        )
        
        Task {
            try? await center.add(request)
        }
    }
    
    func cancelDailyReviewNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-review"])
    }
    
    // MARK: - Photo Reminders
    
    func schedulePhotoReminder(_ reminder: PhotoReminder) async {
        guard notificationsAuthorized else { return }
        
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Recordatorio de foto"
        content.body = reminder.note ?? "Tenés una foto pendiente de revisar"
        content.sound = .default
        content.userInfo = ["photoId": reminder.photoId, "reminderId": reminder.id]
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.reminderDate),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "reminder-\(reminder.id)",
            content: content,
            trigger: trigger
        )
        
        try? await center.add(request)
    }
    
    func cancelPhotoReminder(_ reminder: PhotoReminder) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["reminder-\(reminder.id)"])
    }
}
