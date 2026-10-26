// MomentsApp.swift
// Punto de entrada de la aplicación Moments

import SwiftUI
import SwiftData

@main
struct MomentsApp: App {
    let container: ModelContainer
    
    @StateObject private var appState = AppState()
    
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
            DeletionRecord.self
        ])
        
        if let persistentContainer = MomentsApp.createContainer(schema: schema, inMemory: false) {
            container = persistentContainer
        } else if let inMemoryContainer = MomentsApp.createContainer(schema: schema, inMemory: true) {
            container = inMemoryContainer
            print("Warning: Using in-memory container. Data will not persist.")
        } else {
            container = try! ModelContainer(for: schema)
        }
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
    @Published var hasCompletedInitialIndexing = false
    @Published var hasCompletedOnboarding = false
    @Published var selectedTab: AppTab = .home
    
    private var photoLibraryService: PhotoLibraryService?
    private var analysisService: PhotoAnalysisService?
    private var analysisTask: Task<Void, Never>?
    
    private let onboardingCompletedKey = "com.moments.hasCompletedOnboarding"
    private let indexingCompletedKey = "com.moments.hasCompletedInitialIndexing"
    
    var hasCompletedInitialScan: Bool {
        hasCompletedInitialIndexing
    }
    
    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        self.hasCompletedInitialIndexing = UserDefaults.standard.bool(forKey: indexingCompletedKey)
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        hasCompletedInitialIndexing = false
        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
        UserDefaults.standard.removeObject(forKey: indexingCompletedKey)
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
        photoLibraryService = PhotoLibraryService(modelContext: modelContext)
        analysisService = PhotoAnalysisService(modelContext: modelContext)
        
        Task {
            await checkAuthorizationStatus()
            
            if hasCompletedInitialIndexing && isLibraryAuthorized {
                startBackgroundAnalysis()
            }
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
    
    func startScan() {
        guard let photoService = photoLibraryService else { return }
        
        isIndexing = true
        indexingProgress = 0
        
        Task { @MainActor in
            await photoService.scanLibrary { progress, indexed in
                Task { @MainActor in
                    self.indexingProgress = progress
                    self.totalPhotosIndexed = indexed
                }
            }
            
            self.isIndexing = false
            self.hasCompletedInitialIndexing = true
            UserDefaults.standard.set(true, forKey: self.indexingCompletedKey)
            
            self.startBackgroundAnalysis()
        }
    }
    
    func startBackgroundAnalysis() {
        guard let analysisService = analysisService else { return }
        
        analysisTask?.cancel()
        
        analysisTask = Task { @MainActor in
            self.isAnalyzing = true
            
            await analysisService.analyzePhotosInBackground { analyzed, total, progress in
                Task { @MainActor in
                    self.totalPhotosAnalyzed = analyzed
                    self.totalPhotosToAnalyze = total
                    self.analysisProgress = progress
                }
            }
            
            self.isAnalyzing = false
        }
    }
    
    func pauseAnalysis() {
        analysisTask?.cancel()
        isAnalyzing = false
    }
}
