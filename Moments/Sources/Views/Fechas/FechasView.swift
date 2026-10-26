// FechasView.swift
// Vista de fechas importantes próximas (cumpleaños, aniversarios, etc.)

import SwiftUI
import SwiftData

struct FechasView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var importantDatesService = ImportantDatesService.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var contactsService = ContactsService.shared
    
    @State private var upcomingDates: [PersistedImportantDate] = []
    @State private var unconfirmedDates: [PersistedImportantDate] = []
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var showContactsImport = false
    @State private var selectedDate: PersistedImportantDate?
    @State private var showMemoryReel = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if upcomingDates.isEmpty && unconfirmedDates.isEmpty {
                    emptyStateView
                } else {
                    datesList
                }
            }
            .navigationTitle(Text("fechas_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("fechas_settings", systemImage: "gear")
                        }
                        
                        Button {
                            showContactsImport = true
                        } label: {
                            Label("fechas_import_contacts", systemImage: "person.crop.circle.badge.plus")
                        }
                        
                        Button {
                            Task {
                                await refreshDates()
                            }
                        } label: {
                            Label("fechas_refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NotificationSettingsView()
            }
            .sheet(isPresented: $showContactsImport) {
                ContactsImportView()
            }
            .sheet(item: $selectedDate) { date in
                MemoryReelView(importantDate: date)
            }
        }
        .onAppear {
            importantDatesService.initialize(modelContext: modelContext)
            notificationService.initialize(modelContext: modelContext)
            contactsService.initialize(modelContext: modelContext)
            Task {
                await refreshDates()
            }
        }
        .accessibilityIdentifier("fechas.root")
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("fechas_loading")
                .foregroundStyle(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("fechas_empty_title", systemImage: "calendar.badge.clock")
        } description: {
            Text("fechas_empty_description")
        } actions: {
            Button {
                Task {
                    await importantDatesService.detectImportantDates()
                    await refreshDates()
                }
            } label: {
                Text("fechas_scan_photos")
            }
            .buttonStyle(.borderedProminent)
            
            Button {
                showContactsImport = true
            } label: {
                Text("fechas_import_contacts")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var datesList: some View {
        List {
            if !upcomingDates.isEmpty {
                Section {
                    ForEach(upcomingDates) { date in
                        UpcomingDateRow(
                            importantDate: date,
                            onTap: {
                                selectedDate = date
                            }
                        )
                    }
                } header: {
                    Text("fechas_upcoming_header")
                } footer: {
                    Text("fechas_upcoming_footer")
                }
            }
            
            if !unconfirmedDates.isEmpty {
                Section {
                    ForEach(unconfirmedDates) { date in
                        UnconfirmedDateRow(
                            importantDate: date,
                            onConfirm: {
                                // Navigate to confirmation
                            },
                            onDismiss: {
                                importantDatesService.dismissDate(date.id)
                                Task { await refreshDates() }
                            }
                        )
                    }
                } header: {
                    Text("fechas_unconfirmed_header")
                } footer: {
                    Text("fechas_unconfirmed_footer")
                }
            }
        }
    }
    
    private func refreshDates() async {
        isLoading = true
        
        upcomingDates = await importantDatesService.getUpcomingDates(withinDays: 30)
        await importantDatesService.loadDetectedDates()
        
        unconfirmedDates = importantDatesService.detectedDates.filter { 
            !$0.isUserConfirmed && !$0.isDismissed && $0.confidence >= 0.3
        }
        
        isLoading = false
    }
}

// MARK: - Upcoming Date Row

struct UpcomingDateRow: View {
    let importantDate: PersistedImportantDate
    let onTap: () -> Void
    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var notificationService = NotificationService.shared
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(colorForDateType.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    VStack(spacing: 0) {
                        Text(monthAbbreviation)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(colorForDateType)
                        
                        Text("\(importantDate.day)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        if let days = importantDate.daysUntilNext {
                            Text(daysUntilText(days))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(daysBackgroundColor(days))
                                .foregroundStyle(daysForegroundColor(days))
                                .cornerRadius(8)
                        }
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Button {
                        Task {
                            _ = await calendarService.addToCalendar(importantDate: importantDate)
                        }
                    } label: {
                        Image(systemName: calendarService.hasCalendarEvent(for: importantDate) ? "calendar.badge.checkmark" : "calendar.badge.plus")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.borderless)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private var colorForDateType: Color {
        switch importantDate.dateType {
        case .birthday, .friendBirthday: return .pink
        case .wedding, .anniversary: return .red
        case .childBirthday: return .orange
        case .other: return .blue
        }
    }
    
    private var monthAbbreviation: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let months = formatter.shortMonthSymbols ?? []
        guard importantDate.month > 0 && importantDate.month <= months.count else { return "" }
        return months[importantDate.month - 1].uppercased()
    }
    
    private var titleText: String {
        let emoji = importantDate.dateType.notificationEmoji
        switch importantDate.dateType {
        case .birthday, .childBirthday, .friendBirthday:
            return "\(emoji) Cumple de \(importantDate.displayName)"
        case .wedding, .anniversary:
            return "\(emoji) Aniversario de \(importantDate.displayName)"
        case .other:
            return importantDate.displayName
        }
    }
    
    private var subtitleText: String {
        switch importantDate.dateType {
        case .birthday, .childBirthday, .friendBirthday:
            if let year = importantDate.year {
                let currentYear = Calendar.current.component(.year, from: Date())
                let age = currentYear - year
                let upcomingAge = importantDate.daysUntilNext == 0 ? age : age + 1
                return "Cumple \(upcomingAge) años"
            }
            return importantDate.displayDate
        case .wedding, .anniversary:
            if let years = importantDate.anniversaryYear {
                return "\(years + 1)º aniversario"
            }
            return importantDate.displayDate
        case .other:
            return importantDate.displayDate
        }
    }
    
    private func daysUntilText(_ days: Int) -> String {
        switch days {
        case 0: return "¡Hoy!"
        case 1: return "Mañana"
        default: return "Faltan \(days) días"
        }
    }
    
    private func daysBackgroundColor(_ days: Int) -> Color {
        switch days {
        case 0: return .green
        case 1...3: return .orange
        default: return Color(.systemGray5)
        }
    }
    
    private func daysForegroundColor(_ days: Int) -> Color {
        switch days {
        case 0, 1...3: return .white
        default: return .secondary
        }
    }
}

// MARK: - Unconfirmed Date Row

struct UnconfirmedDateRow: View {
    let importantDate: PersistedImportantDate
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: importantDate.dateType.iconName)
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(questionText)
                        .font(.subheadline)
                    
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(importantDate.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("fechas_not_this")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button {
                    onConfirm()
                } label: {
                    Text("fechas_confirm")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var questionText: LocalizedStringKey {
        let date = importantDate.displayDate
        let name = importantDate.personName ?? "esta persona"
        
        switch importantDate.dateType {
        case .birthday, .friendBirthday:
            return "¿El \(date) es el cumpleaños de \(name)?"
        case .wedding, .anniversary:
            return "¿El \(date) es el aniversario de \(name)?"
        case .childBirthday:
            return "¿El \(date) es el cumpleaños de \(name)?"
        case .other:
            return "¿Hay un evento importante el \(date)?"
        }
    }
    
    private var detailText: String {
        if importantDate.yearsDetected > 1 {
            return "Detectado en fotos de \(importantDate.yearsDetected) años diferentes"
        }
        return "Detectado en tus fotos"
    }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("fechas_notifications_enabled", isOn: Binding(
                        get: { notificationService.settings.enabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    _ = await notificationService.requestAuthorization()
                                } else {
                                    await notificationService.disableNotifications()
                                }
                            }
                        }
                    ))
                } footer: {
                    Text("fechas_notifications_footer")
                }
                
                if notificationService.settings.enabled {
                    Section {
                        Stepper(
                            "fechas_lead_days \(notificationService.settings.defaultLeadDays)",
                            value: Binding(
                                get: { notificationService.settings.defaultLeadDays },
                                set: { newValue in
                                    Task {
                                        await notificationService.updateLeadDays(newValue)
                                    }
                                }
                            ),
                            in: 0...14
                        )
                        
                        Toggle("fechas_notify_on_day", isOn: Binding(
                            get: { notificationService.settings.notifyOnDay },
                            set: { newValue in
                                notificationService.settings.notifyOnDay = newValue
                                Task { await notificationService.saveSettings() }
                            }
                        ))
                    } header: {
                        Text("fechas_timing_header")
                    }
                    
                    Section {
                        Toggle("fechas_notify_birthdays", isOn: Binding(
                            get: { notificationService.settings.notifyBirthdays },
                            set: { newValue in
                                notificationService.settings.notifyBirthdays = newValue
                                Task { await notificationService.saveSettings() }
                            }
                        ))
                        
                        Toggle("fechas_notify_anniversaries", isOn: Binding(
                            get: { notificationService.settings.notifyAnniversaries },
                            set: { newValue in
                                notificationService.settings.notifyAnniversaries = newValue
                                Task { await notificationService.saveSettings() }
                            }
                        ))
                        
                        Toggle("fechas_notify_child_birthdays", isOn: Binding(
                            get: { notificationService.settings.notifyChildBirthdays },
                            set: { newValue in
                                notificationService.settings.notifyChildBirthdays = newValue
                                Task { await notificationService.saveSettings() }
                            }
                        ))
                    } header: {
                        Text("fechas_event_types_header")
                    }
                }
            }
            .navigationTitle(Text("fechas_settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("fechas_done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Contacts Import View

struct ContactsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var contactsService = ContactsService.shared
    @State private var isImporting = false
    @State private var importComplete = false
    
    var body: some View {
        NavigationStack {
            Group {
                if contactsService.authorizationStatus != .authorized {
                    permissionRequiredView
                } else if isImporting {
                    importingView
                } else if importComplete {
                    importCompleteView
                } else {
                    readyToImportView
                }
            }
            .navigationTitle(Text("fechas_contacts_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("fechas_cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var permissionRequiredView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("fechas_contacts_permission_title")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("fechas_contacts_permission_description")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                Task {
                    _ = await contactsService.requestAuthorization()
                }
            } label: {
                Text("fechas_allow_contacts")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var readyToImportView: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            Text("fechas_import_ready_title")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("fechas_import_ready_description")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                isImporting = true
                Task {
                    await contactsService.importBirthdaysFromContacts()
                    isImporting = false
                    importComplete = true
                }
            } label: {
                Text("fechas_import_now")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var importingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("fechas_importing")
                .font(.headline)
        }
    }
    
    private var importCompleteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("fechas_import_complete_title")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("fechas_import_count \(contactsService.importedBirthdays.count)")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Button {
                dismiss()
            } label: {
                Text("fechas_done")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    FechasView()
        .modelContainer(for: PersistedPhoto.self)
}
