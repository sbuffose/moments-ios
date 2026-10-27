// CatalogingCardsView.swift
// Vista interactiva para catalogar unknowns (personas, lugares, fechas)

import SwiftUI
import SwiftData

struct CatalogingCardsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var catalogingService = CatalogingService()
    @StateObject private var placeClusteringService = PlaceClusteringService()
    
    @State private var isLoading = true
    @State private var currentCardIndex = 0
    @State private var showLabelSheet = false
    @State private var selectedCard: CatalogingService.CatalogingCard?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if catalogingService.pendingCards.isEmpty {
                    emptyStateView
                } else {
                    cardsView
                }
            }
            .navigationTitle(Text("cataloging_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await refreshCards()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            catalogingService.initialize(modelContext: modelContext)
            placeClusteringService.initialize(modelContext: modelContext)
            Task {
                await refreshCards()
            }
        }
        .sheet(isPresented: $showLabelSheet) {
            if let card = selectedCard {
                LabelingSheetView(card: card, catalogingService: catalogingService, placeClusteringService: placeClusteringService)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("cataloging_analyzing")
                .foregroundStyle(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("cataloging_all_done_title", systemImage: "checkmark.circle")
        } description: {
            Text("cataloging_all_done_description")
        }
    }
    
    private var cardsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with progress
                VStack(alignment: .leading, spacing: 8) {
                    Text("cataloging_header_title")
                        .font(.headline)
                    
                    Text("cataloging_header_subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // Progress indicators
                    if !catalogingService.progress.peopleProgressText.isEmpty {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.purple)
                            Text(catalogingService.progress.peopleProgressText)
                                .font(.caption)
                                .foregroundStyle(MomentsColors.textSecondary)
                        }
                    }
                    
                    if !catalogingService.progress.placesProgressText.isEmpty {
                        HStack {
                            Image(systemName: "mappin")
                                .foregroundStyle(.orange)
                            Text(catalogingService.progress.placesProgressText)
                                .font(.caption)
                                .foregroundStyle(MomentsColors.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                // Cards
                ForEach(catalogingService.pendingCards) { card in
                    CatalogingCardView(
                        card: card,
                        onLabel: {
                            selectedCard = card
                            showLabelSheet = true
                        },
                        onDismiss: {
                            withAnimation {
                                catalogingService.dismissCard(card.id)
                            }
                        }
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
    
    private func refreshCards() async {
        isLoading = true
        await catalogingService.generateCatalogingCards()
        isLoading = false
    }
}

// MARK: - Cataloging Card View

struct CatalogingCardView: View {
    let card: CatalogingService.CatalogingCard
    let onLabel: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: iconForCardType(card.type))
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.headline)
                    
                    Text(card.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(card.photoCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.tint)
            }
            
            // Preview photos (if available)
            if !card.previewPhotoIds.isEmpty {
                HStack(spacing: 4) {
                    ForEach(card.previewPhotoIds.prefix(4), id: \.self) { photoId in
                        AsyncPhotoThumbnailById(photoId: photoId)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                }
            }
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("cataloging_skip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                
                Button {
                    onLabel()
                } label: {
                    Text(actionTextForCardType(card.type))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(MomentsColors.bgCard)
        .cornerRadius(16)
        .shadow(color: MomentsColors.cardShadow, radius: 16, x: 0, y: 6)
    }
    
    private func iconForCardType(_ type: CatalogingCardType) -> String {
        switch type {
        case .unknownPerson: return "person.crop.circle.badge.questionmark"
        case .unknownPlace: return "mappin.circle"
        case .messagingAppPhotos: return "message.circle"
        case .recurringDate: return "calendar.badge.clock"
        case .downloadedContent: return "arrow.down.circle"
        case .confirmBirthday: return "gift"
        case .confirmWedding: return "heart.circle"
        case .confirmChildRelation: return "figure.and.child.holdinghands"
        case .confirmAnniversary: return "heart.circle.fill"
        }
    }
    
    private func actionTextForCardType(_ type: CatalogingCardType) -> LocalizedStringKey {
        switch type {
        case .unknownPerson: return "cataloging_name_person"
        case .unknownPlace: return "cataloging_label_place"
        case .messagingAppPhotos: return "cataloging_review"
        case .recurringDate: return "cataloging_confirm_date"
        case .downloadedContent: return "cataloging_review"
        case .confirmBirthday: return "cataloging_confirm_birthday"
        case .confirmWedding: return "cataloging_confirm_wedding"
        case .confirmChildRelation: return "cataloging_confirm_child"
        case .confirmAnniversary: return "cataloging_confirm_anniversary"
        }
    }
}

// MARK: - Async Photo Thumbnail by ID

struct AsyncPhotoThumbnailById: View {
    let photoId: String
    @Environment(\.modelContext) private var modelContext
    @State private var localIdentifier: String?
    
    var body: some View {
        Group {
            if let identifier = localIdentifier {
                AsyncPhotoThumbnail(localIdentifier: identifier)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .onAppear {
            loadPhoto()
        }
    }
    
    private func loadPhoto() {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.id == photoId }
        )
        
        if let photo = try? modelContext.fetch(descriptor).first {
            localIdentifier = photo.localIdentifier
        }
    }
}

// MARK: - Labeling Sheet View

struct LabelingSheetView: View {
    let card: CatalogingService.CatalogingCard
    @ObservedObject var catalogingService: CatalogingService
    @ObservedObject var placeClusteringService: PlaceClusteringService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var personName = ""
    @State private var secondPersonName = ""
    @State private var birthdayMonth: Int?
    @State private var birthdayDay: Int?
    @State private var eventYear: Int?
    @State private var selectedPlaceType: PlaceClusterType = .unknown
    @State private var customPlaceName = ""
    @State private var selectedEventType = "birthday"
    @State private var childName = ""
    @State private var parentName = ""
    
    @StateObject private var importantDatesService = ImportantDatesService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                switch card.type {
                case .unknownPerson:
                    personLabelingSection
                    
                case .unknownPlace:
                    placeLabelingSection
                    
                case .messagingAppPhotos, .downloadedContent:
                    reviewSection
                    
                case .recurringDate:
                    dateLabelingSection
                    
                case .confirmBirthday:
                    birthdayConfirmationSection
                    
                case .confirmWedding, .confirmAnniversary:
                    weddingConfirmationSection
                    
                case .confirmChildRelation:
                    childConfirmationSection
                }
            }
            .navigationTitle(card.localizedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cataloging_cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("cataloging_save") {
                        saveLabel()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            importantDatesService.initialize(modelContext: modelContext)
        }
    }
    
    // MARK: - Person Labeling
    
    private var personLabelingSection: some View {
        Group {
            Section {
                TextField("cataloging_person_name_placeholder", text: $personName)
                    .textInputAutocapitalization(.words)
                
                ContactPickerButton { selectedName in
                    personName = selectedName
                }
            } header: {
                Text("cataloging_person_name_header")
            } footer: {
                Text("cataloging_contacts_hint")
            }
            
            Section {
                Toggle("cataloging_has_birthday", isOn: Binding(
                    get: { birthdayMonth != nil },
                    set: { if $0 { birthdayMonth = 1; birthdayDay = 1 } else { birthdayMonth = nil; birthdayDay = nil } }
                ))
                
                if birthdayMonth != nil {
                    Picker("cataloging_month", selection: Binding(
                        get: { birthdayMonth ?? 1 },
                        set: { birthdayMonth = $0 }
                    )) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(month)).tag(month)
                        }
                    }
                    
                    Picker("cataloging_day", selection: Binding(
                        get: { birthdayDay ?? 1 },
                        set: { birthdayDay = $0 }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)").tag(day)
                        }
                    }
                }
            } header: {
                Text("cataloging_birthday_header")
            }
        }
    }
    
    // MARK: - Place Labeling
    
    private var placeLabelingSection: some View {
        Group {
            Section {
                Picker("cataloging_place_type", selection: $selectedPlaceType) {
                    Text("place_type_home").tag(PlaceClusterType.home)
                    Text("place_type_work").tag(PlaceClusterType.work)
                    Text("place_type_familyHome").tag(PlaceClusterType.familyHome)
                    Text("place_type_gym").tag(PlaceClusterType.gym)
                    Text("place_type_school").tag(PlaceClusterType.school)
                    Text("place_type_custom").tag(PlaceClusterType.custom)
                }
                .pickerStyle(.inline)
            } header: {
                Text("cataloging_what_place")
            }
            
            if selectedPlaceType == .custom {
                Section {
                    TextField("cataloging_custom_name", text: $customPlaceName)
                } header: {
                    Text("cataloging_custom_name_header")
                }
            }
        }
    }
    
    // MARK: - Review Section
    
    private var reviewSection: some View {
        Section {
            Text("cataloging_review_explanation")
                .font(.body)
                .foregroundStyle(.secondary)
            
            NavigationLink {
                // Navigate to cleanup view filtered by this origin
                Text("Review photos")
            } label: {
                Label("cataloging_go_to_review", systemImage: "arrow.right.circle")
            }
        }
    }
    
    // MARK: - Date Labeling
    
    private var dateLabelingSection: some View {
        Group {
            Section {
                Picker("cataloging_event_type", selection: $selectedEventType) {
                    Text("cataloging_event_birthday").tag("birthday")
                    Text("cataloging_event_anniversary").tag("anniversary")
                    Text("cataloging_event_holiday").tag("holiday")
                    Text("cataloging_event_other").tag("other")
                }
                .pickerStyle(.inline)
            } header: {
                Text("cataloging_what_event")
            }
        }
    }
    
    // MARK: - Birthday Confirmation
    
    private var birthdayConfirmationSection: some View {
        Group {
            Section {
                Text(card.title)
                    .font(.headline)
            }
            
            Section {
                TextField("cataloging_person_name_placeholder", text: $personName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("cataloging_whose_birthday")
            }
            
            Section {
                Picker("cataloging_birth_year", selection: Binding(
                    get: { eventYear ?? Calendar.current.component(.year, from: Date()) - 30 },
                    set: { eventYear = $0 }
                )) {
                    ForEach((1920...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                        Text("\(year)").tag(year)
                    }
                }
            } header: {
                Text("cataloging_optional_birth_year")
            }
        }
    }
    
    // MARK: - Wedding Confirmation
    
    private var weddingConfirmationSection: some View {
        Group {
            Section {
                Text(card.title)
                    .font(.headline)
            }
            
            Section {
                TextField("cataloging_person1_name", text: $personName)
                    .textInputAutocapitalization(.words)
                
                TextField("cataloging_person2_name", text: $secondPersonName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("cataloging_couple_names")
            }
            
            Section {
                Picker("cataloging_wedding_year", selection: Binding(
                    get: { eventYear ?? Calendar.current.component(.year, from: Date()) },
                    set: { eventYear = $0 }
                )) {
                    ForEach((1950...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                        Text("\(year)").tag(year)
                    }
                }
            } header: {
                Text("cataloging_wedding_year_header")
            }
        }
    }
    
    // MARK: - Child Confirmation
    
    private var childConfirmationSection: some View {
        Group {
            Section {
                Text(card.title)
                    .font(.headline)
                
                Text("cataloging_child_explanation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                TextField("cataloging_child_name_placeholder", text: $childName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("cataloging_child_name")
            }
            
            Section {
                TextField("cataloging_parent_name_placeholder", text: $parentName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("cataloging_whose_child")
            }
            
            Section {
                Picker("cataloging_birth_year", selection: Binding(
                    get: { eventYear ?? Calendar.current.component(.year, from: Date()) - 5 },
                    set: { eventYear = $0 }
                )) {
                    ForEach((2000...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                        Text("\(year)").tag(year)
                    }
                }
            } header: {
                Text("cataloging_child_birth_year")
            }
        }
    }
    
    // MARK: - Save
    
    private func saveLabel() {
        switch card.type {
        case .unknownPerson:
            if let targetId = card.targetId, !personName.isEmpty {
                catalogingService.labelPerson(targetId, name: personName, 
                                             birthdayMonth: birthdayMonth, 
                                             birthdayDay: birthdayDay)
            }
            
        case .unknownPlace:
            if let targetId = card.targetId {
                let name = selectedPlaceType == .custom ? customPlaceName : nil
                placeClusteringService.labelCluster(targetId, as: selectedPlaceType, customName: name)
            }
            
        case .recurringDate:
            if let targetId = card.targetId {
                let parts = targetId.split(separator: "_")
                if parts.count == 2,
                   let month = Int(parts[0]),
                   let day = Int(parts[1]) {
                    catalogingService.confirmRecurringDate(month: month, day: day, eventType: selectedEventType)
                }
            }
            
        case .confirmBirthday:
            if let targetId = card.targetId {
                importantDatesService.confirmDate(
                    targetId,
                    asType: .birthday,
                    personName: personName.isEmpty ? nil : personName,
                    secondPersonName: nil,
                    year: eventYear
                )
            }
            
        case .confirmWedding, .confirmAnniversary:
            if let targetId = card.targetId {
                importantDatesService.confirmDate(
                    targetId,
                    asType: card.type == .confirmWedding ? .wedding : .anniversary,
                    personName: personName.isEmpty ? nil : personName,
                    secondPersonName: secondPersonName.isEmpty ? nil : secondPersonName,
                    year: eventYear
                )
                
                if !personName.isEmpty && !secondPersonName.isEmpty {
                    // Could set partnership relationship here if we had person IDs
                }
            }
            
        case .confirmChildRelation:
            if let targetId = card.targetId {
                importantDatesService.confirmDate(
                    targetId,
                    asType: .childBirthday,
                    personName: childName.isEmpty ? nil : childName,
                    secondPersonName: nil,
                    year: eventYear
                )
            }
            
        case .messagingAppPhotos, .downloadedContent:
            break
        }
        
        catalogingService.completeCard(card.id)
    }
    
    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.monthSymbols[month - 1]
    }
}

#Preview {
    CatalogingCardsView()
        .modelContainer(for: PersistedPhoto.self)
}
