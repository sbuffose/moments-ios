// MomentsApp.swift
// Punto de entrada de la aplicación Moments

import SwiftUI
import SwiftData

@main
struct MomentsApp: App {
    let container: ModelContainer
    
    @StateObject private var appState = AppState()
    
    init() {
        do {
            let schema = Schema([
                PersistedPhoto.self,
                PersistedMoment.self,
                PersistedPlace.self,
                PersistedPerson.self,
                PersistedFaceDetection.self,
                PersistedRecurringEvent.self,
                AnalysisState.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("No se pudo inicializar el ModelContainer: \(error)")
        }
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
    @Published var selectedTab: AppTab = .timeline
    
    private var photoLibraryService: PhotoLibraryService?
    private var analysisService: PhotoAnalysisService?
    
    enum AppTab: String, CaseIterable, Sendable {
        case timeline = "timeline"
        case cleanup = "cleanup"
        case places = "places"
        case people = "people"
        case settings = "settings"
        
        var icon: String {
            switch self {
            case .timeline: return "calendar"
            case .cleanup: return "sparkles"
            case .places: return "map"
            case .people: return "person.2"
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
        
        Task {
            await photoService.scanLibrary { [weak self] progress, indexed in
                await MainActor.run {
                    self?.scanProgress = progress * 0.5
                    self?.totalPhotosIndexed = indexed
                }
            }
            
            await analysisService.analyzeAllPhotos { [weak self] progress in
                await MainActor.run {
                    self?.scanProgress = 0.5 + (progress * 0.5)
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
