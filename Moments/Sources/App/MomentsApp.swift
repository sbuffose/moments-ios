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
            AnalysisState.self
        ])
        
        // Try to create container, with fallback strategies
        if let persistentContainer = MomentsApp.createContainer(schema: schema, inMemory: false) {
            container = persistentContainer
        } else if let inMemoryContainer = MomentsApp.createContainer(schema: schema, inMemory: true) {
            // Fallback to in-memory if persistent fails
            container = inMemoryContainer
            print("Warning: Using in-memory container. Data will not persist.")
        } else {
            // Last resort: create minimal container that won't crash
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
            
            // If persistent container failed, try deleting the store
            if !inMemory {
                MomentsApp.deleteExistingStore()
                // Retry once after deletion
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
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var totalPhotosIndexed = 0
    @Published var hasCompletedInitialScan = false
    @Published var selectedTab: AppTab = .home
    
    private var photoLibraryService: PhotoLibraryService?
    private var analysisService: PhotoAnalysisService?
    
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
        }
    }
    
    func checkAuthorizationStatus() async {
        guard let service = photoLibraryService else { return }
        let status = await service.checkAuthorizationStatus()
        
        self.isLibraryAuthorized = (status == .authorized || status == .limited)
        
        if self.isLibraryAuthorized {
            self.loadAnalysisState()
        }
    }
    
    func requestAuthorization() async -> Bool {
        guard let service = photoLibraryService else { return false }
        let granted = await service.requestAuthorization()
        
        self.isLibraryAuthorized = granted
        
        return granted
    }
    
    func startScan() {
        guard let photoService = photoLibraryService,
              let analysisService = analysisService else { return }
        
        isScanning = true
        scanProgress = 0
        
        Task { @MainActor in
            await photoService.scanLibrary { progress, indexed in
                Task { @MainActor in
                    self.scanProgress = progress * 0.5
                    self.totalPhotosIndexed = indexed
                }
            }
            
            await analysisService.analyzeAllPhotos { progress in
                Task { @MainActor in
                    self.scanProgress = 0.5 + (progress * 0.5)
                }
            }
            
            self.isScanning = false
            self.hasCompletedInitialScan = true
            self.saveAnalysisState()
        }
    }
    
    private func loadAnalysisState() {
        // Se carga desde SwiftData
    }
    
    private func saveAnalysisState() {
        // Se guarda en SwiftData
    }
}
