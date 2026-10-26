// DailyReviewSettingsView.swift
// Configuración del repaso diario

import SwiftUI
import SwiftData

struct DailyReviewSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    
    @State private var settings: DailyReviewSettings?
    @State private var isEnabled = false
    @State private var reviewHour = 21
    @State private var reviewMinute = 0
    @State private var includeScreenshots = true
    @State private var includeBlurry = true
    @State private var includeDuplicates = true
    @State private var includeReceipts = true
    @State private var includeMemes = true
    
    var body: some View {
        List {
            Section {
                Toggle("Activar repaso del día", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        updateSettings()
                        if newValue {
                            appState.scheduleDailyReviewNotification(hour: reviewHour, minute: reviewMinute)
                        } else {
                            appState.cancelDailyReviewNotification()
                        }
                    }
                
                if isEnabled {
                    DatePicker(
                        "Hora del repaso",
                        selection: Binding(
                            get: {
                                var components = DateComponents()
                                components.hour = reviewHour
                                components.minute = reviewMinute
                                return Calendar.current.date(from: components) ?? Date()
                            },
                            set: { date in
                                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                                reviewHour = components.hour ?? 21
                                reviewMinute = components.minute ?? 0
                                updateSettings()
                                appState.scheduleDailyReviewNotification(hour: reviewHour, minute: reviewMinute)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Text("Repaso del día")
            } footer: {
                Text("Cada día a esta hora te vamos a mostrar las fotos de bajo valor que podés eliminar.")
            }
            
            if isEnabled {
                Section {
                    Toggle("Capturas de pantalla", isOn: $includeScreenshots)
                    Toggle("Fotos borrosas", isOn: $includeBlurry)
                    Toggle("Duplicados", isOn: $includeDuplicates)
                    Toggle("Recibos y documentos", isOn: $includeReceipts)
                    Toggle("Memes descargados", isOn: $includeMemes)
                } header: {
                    Text("Incluir en el repaso")
                }
                .onChange(of: includeScreenshots) { _, _ in updateSettings() }
                .onChange(of: includeBlurry) { _, _ in updateSettings() }
                .onChange(of: includeDuplicates) { _, _ in updateSettings() }
                .onChange(of: includeReceipts) { _, _ in updateSettings() }
                .onChange(of: includeMemes) { _, _ in updateSettings() }
            }
            
            if !appState.notificationsAuthorized {
                Section {
                    Button {
                        Task {
                            _ = await appState.requestNotificationPermission()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(.orange)
                            Text("Permitir notificaciones")
                        }
                    }
                } footer: {
                    Text("Necesitás permitir notificaciones para recibir el repaso diario.")
                }
            }
        }
        .navigationTitle("Repaso del día")
        .onAppear { loadSettings() }
    }
    
    private func loadSettings() {
        let descriptor = FetchDescriptor<DailyReviewSettings>(
            predicate: #Predicate { $0.id == "main" }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            settings = existing
            isEnabled = existing.isEnabled
            reviewHour = existing.reviewHour
            reviewMinute = existing.reviewMinute
            includeScreenshots = existing.includeScreenshots
            includeBlurry = existing.includeBlurry
            includeDuplicates = existing.includeDuplicates
            includeReceipts = existing.includeReceipts
            includeMemes = existing.includeMemes
        } else {
            let newSettings = DailyReviewSettings()
            modelContext.insert(newSettings)
            settings = newSettings
        }
    }
    
    private func updateSettings() {
        guard let settings = settings else { return }
        settings.isEnabled = isEnabled
        settings.reviewHour = reviewHour
        settings.reviewMinute = reviewMinute
        settings.includeScreenshots = includeScreenshots
        settings.includeBlurry = includeBlurry
        settings.includeDuplicates = includeDuplicates
        settings.includeReceipts = includeReceipts
        settings.includeMemes = includeMemes
        try? modelContext.save()
    }
}

struct GeneralNotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState
    
    @State private var settings: PersistedNotificationSettings?
    @State private var notificationsEnabled = false
    @State private var defaultLeadDays = 3
    @State private var notifyOnDay = true
    @State private var notifyBirthdays = true
    @State private var notifyAnniversaries = true
    
    var body: some View {
        List {
            Section {
                if appState.notificationsAuthorized {
                    Toggle("Notificaciones activadas", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, _ in updateSettings() }
                } else {
                    Button {
                        Task {
                            let granted = await appState.requestNotificationPermission()
                            if granted {
                                notificationsEnabled = true
                                updateSettings()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(.orange)
                            Text("Permitir notificaciones")
                        }
                    }
                }
            } header: {
                Text("Permisos")
            }
            
            if appState.notificationsAuthorized && notificationsEnabled {
                Section {
                    Stepper("Avisar \(defaultLeadDays) días antes", value: $defaultLeadDays, in: 1...14)
                        .onChange(of: defaultLeadDays) { _, _ in updateSettings() }
                    
                    Toggle("Avisar el mismo día", isOn: $notifyOnDay)
                        .onChange(of: notifyOnDay) { _, _ in updateSettings() }
                } header: {
                    Text("Fechas importantes")
                }
                
                Section {
                    Toggle("Cumpleaños", isOn: $notifyBirthdays)
                    Toggle("Aniversarios", isOn: $notifyAnniversaries)
                } header: {
                    Text("Tipos de recordatorios")
                }
                .onChange(of: notifyBirthdays) { _, _ in updateSettings() }
                .onChange(of: notifyAnniversaries) { _, _ in updateSettings() }
            }
        }
        .navigationTitle("Notificaciones")
        .onAppear { loadSettings() }
    }
    
    private func loadSettings() {
        let descriptor = FetchDescriptor<PersistedNotificationSettings>(
            predicate: #Predicate { $0.id == "main" }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            settings = existing
            notificationsEnabled = existing.notificationsEnabled
            defaultLeadDays = existing.defaultLeadDays
            notifyOnDay = existing.notifyOnDay
            notifyBirthdays = existing.notifyBirthdays
            notifyAnniversaries = existing.notifyAnniversaries
        } else {
            let newSettings = PersistedNotificationSettings()
            modelContext.insert(newSettings)
            settings = newSettings
        }
    }
    
    private func updateSettings() {
        guard let settings = settings else { return }
        settings.notificationsEnabled = notificationsEnabled
        settings.defaultLeadDays = defaultLeadDays
        settings.notifyOnDay = notifyOnDay
        settings.notifyBirthdays = notifyBirthdays
        settings.notifyAnniversaries = notifyAnniversaries
        try? modelContext.save()
    }
}

struct TagsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PhotoTag.usageCount, order: .reverse) private var tags: [PhotoTag]
    
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
                ForEach(tags) { tag in
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
    }
    
    private func createTag() {
        guard !newTagName.isEmpty else { return }
        let tag = PhotoTag(name: newTagName)
        modelContext.insert(tag)
        try? modelContext.save()
        newTagName = ""
    }
    
    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(tags[index])
        }
        try? modelContext.save()
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
    NavigationStack {
        DailyReviewSettingsView()
    }
    .preferredColorScheme(.dark)
}
