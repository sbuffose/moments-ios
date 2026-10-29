// PeopleView.swift
// Vista de personas

import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = PeopleViewModel()
    
    @State private var searchText = ""
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.people.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .searchable(text: $searchText, prompt: "people_search_prompt")
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("people_loading")
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("people.loading")
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("people_empty_title", systemImage: "person.2")
        } description: {
            Text("people_empty_description")
        }
        .accessibilityIdentifier("people.empty")
    }
    
    private var filteredPeople: [PeopleViewModel.PersonItem] {
        if searchText.isEmpty {
            return viewModel.people
        }
        return viewModel.people.filter { person in
            person.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Upcoming Birthdays
                if !viewModel.upcomingBirthdays.isEmpty {
                    birthdaysSection
                }
                
                // People Grid
                peopleSection
            }
            .padding()
        }
    }
    
    // MARK: - Birthdays Section
    
    private var birthdaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundStyle(.pink)
                Text("people_upcoming_birthdays")
                    .font(.headline)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.upcomingBirthdays) { birthday in
                        BirthdayCard(birthday: birthday)
                    }
                }
            }
        }
    }
    
    // MARK: - People Section
    
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.blue)
                Text("people_all")
                    .font(.headline)
                
                Spacer()
                
                Text(MomentsPluralization.people(filteredPeople.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            let columns = [
                GridItem(.adaptive(minimum: 100), spacing: 16)
            ]
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredPeople) { person in
                    NavigationLink {
                        PersonDetailView(person: person, viewModel: viewModel)
                    } label: {
                        PersonCell(person: person)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Birthday Card

struct BirthdayCard: View {
    let birthday: PeopleViewModel.BirthdayItem
    
    var body: some View {
        VStack(spacing: 8) {
            if let photoId = birthday.person.representativePhotoId {
                AsyncPhotoThumbnail(localIdentifier: photoId)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }
            
            Text(birthday.person.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Text(birthday.displayText)
                .font(.caption2)
                .foregroundStyle(birthday.daysUntil == 0 ? .pink : .secondary)
        }
        .frame(width: 80)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Person Cell

struct PersonCell: View {
    let person: PeopleViewModel.PersonItem
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if let photoId = person.representativePhotoId {
                    AsyncPhotoThumbnail(localIdentifier: photoId)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                }
                
                if person.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            
            Text(person.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            Text(MomentsPluralization.photos(person.photoCount))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Person Detail View

struct PersonDetailView: View {
    let person: PeopleViewModel.PersonItem
    @ObservedObject var viewModel: PeopleViewModel
    
    @Environment(\.modelContext) private var modelContext
    @State private var photos: [PersistedPhoto] = []
    @State private var showNameEditor = false
    @State private var showBirthdayPicker = false
    @State private var editedName = ""
    @State private var selectedMonth = 1
    @State private var selectedDay = 1
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Actions
                actionsSection
                
                // Photos
                photosSection
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.toggleFavorite(person)
                    }
                } label: {
                    Image(systemName: person.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(person.isFavorite ? .red : .primary)
                }
            }
        }
        .task {
            await loadPhotos()
        }
        .sheet(isPresented: $showNameEditor) {
            nameEditorSheet
        }
        .sheet(isPresented: $showBirthdayPicker) {
            birthdayPickerSheet
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            if let photoId = person.representativePhotoId {
                AsyncPhotoThumbnail(localIdentifier: photoId, targetSize: CGSize(width: 200, height: 200))
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(spacing: 4) {
                Text(person.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let birthday = person.birthdayString {
                    HStack {
                        Image(systemName: "gift")
                        Text(birthday)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 24) {
                VStack {
                    Text("\(person.photoCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Fotos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack {
                    Text("\(person.faceCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Apariciones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private var actionsSection: some View {
        HStack(spacing: 16) {
            Button {
                editedName = person.name ?? ""
                showNameEditor = true
            } label: {
                Label("Editar nombre", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            
            Button {
                selectedMonth = person.birthdayMonth ?? 1
                selectedDay = person.birthdayDay ?? 1
                showBirthdayPicker = true
            } label: {
                Label("Cumpleaños", systemImage: "gift")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Photos
    
    private var photosSection: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(photos, id: \.id) { photo in
                PhotoGridItem(photo: photo)
            }
        }
    }
    
    // MARK: - Sheets
    
    private var nameEditorSheet: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $editedName)
            }
            .navigationTitle("Editar nombre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        showNameEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            await viewModel.updatePersonName(person, name: editedName)
                            showNameEditor = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var birthdayPickerSheet: some View {
        NavigationStack {
            Form {
                Picker("Mes", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(monthName(month)).tag(month)
                    }
                }
                
                Picker("Día", selection: $selectedDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
            }
            .navigationTitle("Cumpleaños")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        showBirthdayPicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            await viewModel.updatePersonBirthday(person, month: selectedMonth, day: selectedDay)
                            showBirthdayPicker = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Helpers
    
    private func loadPhotos() async {
        let ids = person.photoIds
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        
        do {
            var fetchedPhotos = try modelContext.fetch(descriptor)
            fetchedPhotos.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            photos = fetchedPhotos
        } catch {
            print("Error loading person photos: \(error)")
        }
    }
    
    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        return formatter.monthSymbols[month - 1].capitalized
    }
}

#Preview {
    PeopleView()
        .modelContainer(for: PersistedPerson.self)
}
