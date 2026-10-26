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
                } header: {
                    Text("Tus datos")
                } footer: {
                    Text("Los datos que Moments aprende de vos se guardan localmente y podés editarlos.")
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
