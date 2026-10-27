// SettingsView.swift
// Vista de configuraciones

import SwiftUI
import Photos

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("showHiddenPhotos") private var showHiddenPhotos = false
    @AppStorage("analysisQuality") private var analysisQuality = "balanced"
    
    @State private var showRescanConfirmation = false
    @State private var showClearCacheConfirmation = false
    @State private var cacheSize: String = "Calculando..."
    
    var body: some View {
        NavigationStack {
            List {
                // Library Section
                Section {
                    libraryStatusRow
                    
                    Toggle(isOn: $showHiddenPhotos) {
                        Label("settings_show_hidden", systemImage: "eye.slash")
                    }
                    
                    Button {
                        showRescanConfirmation = true
                    } label: {
                        Label("settings_rescan_library", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("settings_library_section")
                }
                
                // Analysis Section
                Section {
                    Picker(selection: $analysisQuality) {
                        Text("settings_quality_fast").tag("fast")
                        Text("settings_quality_balanced").tag("balanced")
                        Text("settings_quality_detailed").tag("detailed")
                    } label: {
                        Label("settings_analysis_quality", systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text("settings_analysis_section")
                } footer: {
                    Text("settings_analysis_footer")
                }
                
                // Data Section
                Section {
                    NavigationLink {
                        RememberListView()
                    } label: {
                        Label("Recordá esto", systemImage: "brain.head.profile")
                    }
                    
                    NavigationLink {
                        PendingTrashView()
                    } label: {
                        Label("Papelera pendiente", systemImage: "trash")
                    }
                    
                    NavigationLink {
                        TagsListView()
                    } label: {
                        Label("Etiquetas", systemImage: "tag")
                    }
                    
                    NavigationLink {
                        KeptPhotosListView()
                    } label: {
                        Label("Fotos conservadas", systemImage: "checkmark.circle")
                    }
                } header: {
                    Text("Tus datos")
                } footer: {
                    Text("Los datos que Moments aprende de vos se guardan localmente y podés editarlos.")
                }
                
                // Notifications Section
                Section {
                    NavigationLink {
                        DailyReviewSettingsView()
                    } label: {
                        Label("Repaso del día", systemImage: "moon.stars")
                    }
                    
                    NavigationLink {
                        GeneralNotificationSettingsView()
                    } label: {
                        Label("Notificaciones", systemImage: "bell")
                    }
                } header: {
                    Text("Recordatorios")
                }
                
                // Storage Section
                Section {
                    HStack {
                        Label("settings_cache_size", systemImage: "internaldrive")
                        Spacer()
                        Text(cacheSize)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showClearCacheConfirmation = true
                    } label: {
                        Label("settings_clear_cache", systemImage: "trash")
                    }
                } header: {
                    Text("settings_storage_section")
                }
                
                // About Section
                Section {
                    HStack {
                        Label("settings_version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("settings_privacy_policy", systemImage: "hand.raised")
                    }
                    
                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Label("settings_terms", systemImage: "doc.text")
                    }
                } header: {
                    Text("settings_about_section")
                }
                
                // Developer Section
                #if DEBUG
                Section {
                    Button {
                        resetApp()
                    } label: {
                        Label("Resetear datos (Debug)", systemImage: "trash.circle")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Desarrollo")
                }
                #endif
            }
            .navigationTitle(Text("settings_title"))
        }
        .onAppear {
            calculateCacheSize()
        }
        .confirmationDialog(
            "settings_rescan_confirmation_title",
            isPresented: $showRescanConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings_rescan_confirm", role: .destructive) {
                appState.startScan()
            }
            Button("settings_cancel", role: .cancel) {}
        } message: {
            Text("settings_rescan_confirmation_message")
        }
        .confirmationDialog(
            "settings_clear_cache_title",
            isPresented: $showClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings_clear_confirm", role: .destructive) {
                Task {
                    await clearCache()
                }
            }
            Button("settings_cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Library Status Row
    
    private var libraryStatusRow: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text("settings_library_status")
                    Text(libraryStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: libraryStatusIcon)
                    .foregroundStyle(libraryStatusColor)
            }
            
            Spacer()
            
            if appState.isIndexing || appState.isAnalyzing {
                ProgressView()
            }
        }
    }
    
    private var libraryStatusText: String {
        if appState.isIndexing {
            return "Indexando... \(Int(appState.indexingProgress * 100))%"
        } else if appState.isAnalyzing {
            return "Analizando \(appState.totalPhotosAnalyzed) / \(appState.totalPhotosToAnalyze)"
        } else if appState.hasCompletedInitialScan {
            return "\(appState.totalPhotosIndexed) elementos indexados"
        } else {
            return "No escaneado"
        }
    }
    
    private var libraryStatusIcon: String {
        if appState.isIndexing || appState.isAnalyzing {
            return "arrow.triangle.2.circlepath"
        } else if appState.hasCompletedInitialScan {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.circle"
        }
    }
    
    private var libraryStatusColor: Color {
        if appState.isIndexing || appState.isAnalyzing {
            return .orange
        } else if appState.hasCompletedInitialScan {
            return .green
        } else {
            return .red
        }
    }
    
    // MARK: - Actions
    
    private func calculateCacheSize() {
        Task {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            var totalSize: Int64 = 0
            
            if let enumerator = FileManager.default.enumerator(at: documentsPath, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            
            await MainActor.run {
                cacheSize = formatter.string(fromByteCount: totalSize)
            }
        }
    }
    
    private func clearCache() async {
        await GeocodingService.shared.clearCache()
        calculateCacheSize()
    }
    
    private func resetApp() {
        UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        // En una implementación real, también limpiaríamos SwiftData
    }
}

// MARK: - Kept Photos List View

struct KeptPhotosListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var keptPhotos: [PersistedPhoto] = []
    @State private var showUndoConfirmation = false
    @State private var photoToUndo: PersistedPhoto?
    
    var body: some View {
        List {
            if keptPhotos.isEmpty {
                ContentUnavailableView {
                    Label("No hay fotos conservadas", systemImage: "checkmark.circle")
                } description: {
                    Text("Las fotos que elijas conservar aparecerán aquí")
                }
            } else {
                Section {
                    ForEach(keptPhotos, id: \.id) { photo in
                        KeptPhotoRow(photo: photo) {
                            photoToUndo = photo
                            showUndoConfirmation = true
                        }
                    }
                } header: {
                    Text("\(keptPhotos.count) fotos conservadas")
                } footer: {
                    Text("Estas fotos no aparecerán en las sugerencias de limpieza")
                }
            }
        }
        .navigationTitle("Fotos conservadas")
        .onAppear {
            loadKeptPhotos()
        }
        .refreshable {
            loadKeptPhotos()
        }
        .confirmationDialog(
            "¿Volver a preguntar?",
            isPresented: $showUndoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Deshacer decisión", role: .destructive) {
                if let photo = photoToUndo {
                    undoKeepDecision(photo)
                }
            }
            Button("Cancelar", role: .cancel) {
                photoToUndo = nil
            }
        } message: {
            Text("La foto volverá a aparecer en las sugerencias de limpieza")
        }
    }
    
    private func loadKeptPhotos() {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.keepDecisionRaw != nil && $0.keepDecisionRaw != "none" },
            sortBy: [SortDescriptor(\.keepDecisionDate, order: .reverse)]
        )
        
        do {
            keptPhotos = try modelContext.fetch(descriptor)
        } catch {
            print("Error loading kept photos: \(error)")
        }
    }
    
    private func undoKeepDecision(_ photo: PersistedPhoto) {
        photo.keepDecision = .none
        photo.keepUntil = nil
        photo.keepDecisionDate = nil
        photo.keepDecisionGroupId = nil
        
        try? modelContext.save()
        loadKeptPhotos()
        photoToUndo = nil
    }
}

struct KeptPhotoRow: View {
    let photo: PersistedPhoto
    let onUndo: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(keepDecisionText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let date = photo.keepDecisionDate {
                    Text("Conservada \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if photo.keepDecision == .snoozed, let until = photo.keepUntil {
                    Text("Vuelve a aparecer \(until.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            Button {
                onUndo()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private var keepDecisionText: String {
        switch photo.keepDecision {
        case .forever:
            return "Conservar siempre"
        case .snoozed:
            return "Conservar temporalmente"
        case .none:
            return "Sin decisión"
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
