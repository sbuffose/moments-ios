// SettingsView.swift
// Vista de configuraciones

import SwiftUI
import Photos
import SwiftData

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
                    
                    NavigationLink {
                        LearningSettingsView()
                    } label: {
                        Label("Aprendizaje", systemImage: "brain")
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.libraryStatus")
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
                    Text(MomentsPluralization.photosConserved(keptPhotos.count))
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
            predicate: #Predicate<PersistedPhoto> { photo in
                photo.keepDecisionRaw != nil && photo.keepDecisionRaw != "none"
            },
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

// MARK: - Learning Settings View

struct LearningSettingsView: View {
    @StateObject private var learningService = PreferenceLearningService.shared
    @State private var preferences: LearnedPreferences?
    @State private var learningSummary: [String] = []
    @State private var showResetConfirmation = false
    @State private var suppressedCategories: [CleanupCategoryType] = []
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            // Learning Summary
            Section {
                if learningSummary.isEmpty {
                    Text("Moments todavía está aprendiendo tus preferencias. Seguí revisando fotos para que aprenda qué te gusta conservar.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(learningSummary, id: \.self) { summary in
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                            Text(summary)
                        }
                    }
                }
            } header: {
                Text("Lo que aprendí")
            } footer: {
                if let prefs = preferences {
                    Text("Basado en \(prefs.totalDecisions) decisiones")
                }
            }
            
            // Confidence indicator
            if let prefs = preferences, prefs.totalDecisions > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Confianza del modelo")
                            Spacer()
                            Text("\(Int(prefs.confidenceWeight * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        
                        ProgressView(value: prefs.confidenceWeight)
                            .tint(.blue)
                    }
                } footer: {
                    Text("Las predicciones son más precisas después de ~50 decisiones")
                }
            }
            
            // Suppressed categories
            if !suppressedCategories.isEmpty {
                Section {
                    ForEach(suppressedCategories, id: \.rawValue) { category in
                        HStack {
                            Image(systemName: category.iconName)
                                .foregroundStyle(.secondary)
                            Text(LocalizedStringKey(category.localizedKey))
                            Spacer()
                            Button("Activar") {
                                Task {
                                    await learningService.unsuppressCategory(category)
                                    await loadData()
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.blue)
                        }
                    }
                } header: {
                    Text("Categorías desactivadas")
                } footer: {
                    Text("Estas categorías no se te sugerirán para eliminar")
                }
            }
            
            // Category keep rates
            if let prefs = preferences, prefs.totalDecisions >= 5 {
                Section {
                    CategoryKeepRateRow(category: .screenshot, rate: prefs.screenshotKeepRate, count: prefs.screenshotDecisions)
                    CategoryKeepRateRow(category: .blurry, rate: prefs.blurryKeepRate, count: prefs.blurryDecisions)
                    CategoryKeepRateRow(category: .duplicate, rate: prefs.duplicateKeepRate, count: prefs.duplicateDecisions)
                    CategoryKeepRateRow(category: .downloadedMeme, rate: prefs.downloadKeepRate, count: prefs.downloadDecisions)
                    CategoryKeepRateRow(category: .receipt, rate: prefs.receiptKeepRate, count: prefs.receiptDecisions)
                } header: {
                    Text("Tasas de conservación por categoría")
                }
            }
            
            // Reset
            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Resetear aprendizaje", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("Esto borrará todas las preferencias aprendidas y empezará de nuevo")
            }
        }
        .navigationTitle("Aprendizaje")
        .onAppear {
            learningService.initialize(modelContext: modelContext)
            Task {
                await loadData()
            }
        }
        .confirmationDialog(
            "¿Resetear aprendizaje?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Resetear", role: .destructive) {
                Task {
                    await learningService.resetLearning()
                    await loadData()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrarán todas las preferencias aprendidas")
        }
    }
    
    private func loadData() async {
        preferences = await learningService.getPreferences()
        learningSummary = await learningService.getLearningSummary()
        suppressedCategories = preferences?.suppressedCategories ?? []
    }
}

struct CategoryKeepRateRow: View {
    let category: CleanupCategoryType
    let rate: Double
    let count: Int
    
    var body: some View {
        HStack {
            Image(systemName: category.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(LocalizedStringKey(category.localizedKey))
            
            Spacer()
            
            if count > 0 {
                Text("\(Int(rate * 100))%")
                    .foregroundStyle(rate > 0.7 ? .green : rate < 0.3 ? .red : .secondary)
                    .font(.subheadline)
            } else {
                Text("-")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Daily Review Settings View

struct DailyReviewSettingsView: View {
    @StateObject private var reviewService = DailyReviewService.shared
    @State private var isEnabled = true
    @State private var selectedHour = 21
    @State private var selectedMinute = 0
    @State private var showPermissionAlert = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            // Enable/Disable
            Section {
                Toggle(isOn: $isEnabled) {
                    Label("Activar repaso diario", systemImage: "moon.stars")
                }
                .onChange(of: isEnabled) { _, newValue in
                    Task {
                        if newValue && !reviewService.isNotificationPermissionGranted {
                            let granted = await reviewService.requestNotificationPermission()
                            if !granted {
                                showPermissionAlert = true
                                isEnabled = false
                                return
                            }
                        }
                        await reviewService.updateSettings(isEnabled: newValue)
                    }
                }
            } footer: {
                Text("Recibí un resumen de las fotos del día para revisar")
            }
            
            // Time picker
            if isEnabled {
                Section {
                    HStack {
                        Text("Hora del recordatorio")
                        Spacer()
                        Picker("Hora", selection: $selectedHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d", hour)).tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Text(":")
                        
                        Picker("Minuto", selection: $selectedMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .onChange(of: selectedHour) { _, newHour in
                        Task {
                            await reviewService.updateSettings(hour: newHour)
                        }
                    }
                    .onChange(of: selectedMinute) { _, newMinute in
                        Task {
                            await reviewService.updateSettings(minute: newMinute)
                        }
                    }
                }
                
                // Today's preview
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fotos de hoy para revisar")
                                .font(.subheadline)
                            
                            if reviewService.todayCandidateCount > 0 {
                                Text("\(MomentsPluralization.photosToReview(reviewService.todayCandidateCount)) (\(ByteCountFormatter.string(fromByteCount: reviewService.todayCandidateSize, countStyle: .file)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No hay fotos para revisar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if reviewService.todayCandidateCount > 0 {
                            NavigationLink {
                                TodayReviewView()
                            } label: {
                                Text("Revisar")
                            }
                        }
                    }
                }
            }
            
            // Notification preview
            if isEnabled && reviewService.todayCandidateCount > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vista previa de la notificación:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Image(systemName: "app.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Repaso del día")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Text("Hoy sacaste \(MomentsPluralization.photosToReview(reviewService.todayCandidateCount)), te recomiendo revisar \(Int(Double(reviewService.todayCandidateCount) * 0.3)) (\(ByteCountFormatter.string(fromByteCount: Int64(Double(reviewService.todayCandidateSize) * 0.3), countStyle: .file)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .navigationTitle("Repaso del día")
        .onAppear {
            reviewService.initialize(modelContext: modelContext)
            Task {
                let settings = await reviewService.getSettings()
                isEnabled = settings.isEnabled
                selectedHour = settings.reviewHour
                selectedMinute = settings.reviewMinute
                await reviewService.updateTodayCandidates()
            }
        }
        .alert("Permisos de notificación", isPresented: $showPermissionAlert) {
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Para recibir el repaso diario, necesitás activar las notificaciones en Ajustes")
        }
    }
}

// MARK: - Today Review View

struct TodayReviewView: View {
    @StateObject private var reviewService = DailyReviewService.shared
    @StateObject private var cleanupViewModel = CleanupViewModel()
    @State private var candidates: [PersistedPhoto] = []
    @State private var currentIndex = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    private var batch: [PersistedPhoto] {
        Array(candidates.prefix(DailyReviewBatch.size))
    }
    
    var body: some View {
        VStack {
            if batch.isEmpty {
                ContentUnavailableView {
                    Label("No hay fotos para revisar", systemImage: "checkmark.circle")
                } description: {
                    Text("No hay fotos de hoy que necesiten revisión")
                }
            } else if currentIndex < batch.count {
                ProgressView(value: Double(currentIndex), total: Double(batch.count))
                    .padding(.horizontal)
                
                Text("\(currentIndex + 1) de \(batch.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("dailyReview.progress")
                
                Spacer()
                
                let photo = batch[currentIndex]
                AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier, targetSize: CGSize(width: 400, height: 400))
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .padding()
                
                let category = photo.cleanupCategory
                if category != .none {
                    Label(LocalizedStringKey(category.localizedKey), systemImage: category.iconName)
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                
                Spacer()
                
                HStack(spacing: 40) {
                    Button {
                        cleanupViewModel.keepPhoto(photo.id, duration: .forever)
                        currentIndex += 1
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.green)
                            Text("Conservar")
                                .font(.caption)
                        }
                    }
                    .accessibilityIdentifier("dailyReview.keep")
                    
                    Button {
                        cleanupViewModel.markAsReviewed(photo.id, delete: true)
                        currentIndex += 1
                    } label: {
                        VStack {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red)
                            Text("Eliminar")
                                .font(.caption)
                        }
                    }
                    .accessibilityIdentifier("dailyReview.delete")
                }
                .padding(.bottom, 40)
            } else {
                // Complete
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    
                    Text("¡Listo!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Revisaste todas las fotos de hoy")
                        .foregroundStyle(.secondary)
                    
                    Button("Cerrar") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Fotos de hoy")
        .onAppear {
            reviewService.initialize(modelContext: modelContext)
            cleanupViewModel.initialize(modelContext: modelContext)
            Task {
                let all = await reviewService.getTodayCandidates()
                candidates = Array(all.prefix(DailyReviewBatch.size))
            }
        }
    }
}

// MARK: - General Notification Settings View

struct GeneralNotificationSettingsView: View {
    var body: some View {
        List {
            Section {
                Text("Configuración de notificaciones general")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notificaciones")
    }
}

// MARK: - Tags List View

struct TagsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var tags: [PhotoTag] = []
    @State private var showAddTag = false
    @State private var newTagName = ""
    
    var body: some View {
        List {
            if tags.isEmpty {
                ContentUnavailableView(
                    "Sin etiquetas",
                    systemImage: "tag",
                    description: Text("Las etiquetas que crees aparecerán acá")
                )
            } else {
                ForEach(tags, id: \.id) { tag in
                    HStack {
                        Circle()
                            .fill(Color(hex: tag.colorHex) ?? MomentsColors.accent)
                            .frame(width: 12, height: 12)
                        
                        Text(tag.name)
                        
                        Spacer()
                        
                        Text("\(tag.usageCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteTags)
            }
        }
        .navigationTitle("Etiquetas")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTag = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Nueva etiqueta", isPresented: $showAddTag) {
            TextField("Nombre", text: $newTagName)
            Button("Crear") { createTag() }
            Button("Cancelar", role: .cancel) { newTagName = "" }
        }
        .onAppear { loadTags() }
    }
    
    private func loadTags() {
        let descriptor = FetchDescriptor<PhotoTag>(
            sortBy: [SortDescriptor(\.usageCount, order: .reverse)]
        )
        tags = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func createTag() {
        guard !newTagName.isEmpty else { return }
        let tag = PhotoTag(name: newTagName)
        modelContext.insert(tag)
        try? modelContext.save()
        newTagName = ""
        loadTags()
    }
    
    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tags[index])
        }
        try? modelContext.save()
        loadTags()
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
