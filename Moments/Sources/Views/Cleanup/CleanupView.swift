// CleanupView.swift
// Vista principal - Home con Limpieza + Momentos

import SwiftUI
import SwiftData

struct CleanupView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CleanupViewModel()
    @StateObject private var importantDatesService = ImportantDatesService.shared
    
    @State private var totalSpaceSaved: Int64 = 0
    @State private var onThisDayPhotos: [PersistedPhoto] = []
    @State private var upcomingDates: [PersistedImportantDate] = []
    @State private var latestTrip: PersistedMoment?
    @State private var showCelebration = false
    @State private var lastCleanupSize: Int64 = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Space Card (Hero)
                    spaceCard
                    
                    // Moments Card
                    momentsCard
                    
                    // Cleanup categories (collapsed by default)
                    if viewModel.totalCleanupItems > 0 {
                        categoriesSection
                    }
                }
                .padding()
            }
            .navigationTitle(Text("home_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
            importantDatesService.initialize(modelContext: modelContext)
            loadSpaceSaved()
            Task {
                await loadMoments()
            }
        }
        .sheet(isPresented: $showCelebration) {
            CleanupCelebrationView(
                spaceSaved: lastCleanupSize,
                onThisDayPhotos: onThisDayPhotos,
                onDismiss: {
                    showCelebration = false
                }
            )
        }
        .onChange(of: viewModel.lastDeletedSize) { _, newSize in
            if newSize > 0 {
                lastCleanupSize = newSize
                totalSpaceSaved += newSize
                saveSpaceSaved()
                showCelebration = true
            }
        }
        .alert("cleanup_error_title", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Space Card
    
    private var spaceCard: some View {
        VStack(spacing: 20) {
            // Header with running total
            if totalSpaceSaved > 0 {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("home_space_saved_total \(viewModel.formattedSize(totalSpaceSaved))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(20)
            }
            
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else if viewModel.totalCleanupItems > 0 {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "externaldrive.badge.minus")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                }
                
                // Space to free
                VStack(spacing: 4) {
                    Text(viewModel.formattedSize(viewModel.estimatedSpaceFreed))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    
                    Text("home_space_can_free")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text("home_space_items_count \(viewModel.totalCleanupItems)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // CTA
                NavigationLink {
                    CleanupReviewView(viewModel: viewModel)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("home_free_space_cta")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(14)
                }
            } else {
                // All clean state
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                }
                
                Text("home_all_clean_title")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("home_all_clean_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Moments Card
    
    private var momentsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.pink)
                Text("home_moments_title")
                    .font(.headline)
            }
            
            // On This Day
            if !onThisDayPhotos.isEmpty {
                NavigationLink {
                    OnThisDayView(photos: onThisDayPhotos)
                } label: {
                    MomentRowView(
                        icon: "clock.arrow.circlepath",
                        iconColor: .orange,
                        title: "home_on_this_day",
                        subtitle: "home_on_this_day_count \(onThisDayPhotos.count)",
                        previewPhotos: Array(onThisDayPhotos.prefix(3))
                    )
                }
            }
            
            // Upcoming dates
            if !upcomingDates.isEmpty {
                NavigationLink {
                    FechasView()
                } label: {
                    if let nextDate = upcomingDates.first {
                        MomentRowView(
                            icon: "gift.fill",
                            iconColor: .pink,
                            title: upcomingDateTitle(nextDate),
                            subtitle: upcomingDateSubtitle(nextDate),
                            previewPhotos: []
                        )
                    }
                }
            }
            
            // Latest trip
            if let trip = latestTrip {
                NavigationLink {
                    TimelineView()
                } label: {
                    MomentRowView(
                        icon: "airplane",
                        iconColor: .blue,
                        title: "home_latest_trip",
                        subtitle: trip.tripDestination ?? trip.locationName ?? "home_trip_photos \(trip.photoIdArray.count)",
                        previewPhotos: []
                    )
                }
            }
            
            // Empty state if no moments
            if onThisDayPhotos.isEmpty && upcomingDates.isEmpty && latestTrip == nil {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("home_moments_empty")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Categories Section (collapsible)
    
    @State private var showCategories = false
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    showCategories.toggle()
                }
            } label: {
                HStack {
                    Text("cleanup_categories_header")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showCategories ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            
            if showCategories {
                ForEach(viewModel.categories) { category in
                    NavigationLink {
                        CleanupCategoryDetailView(
                            category: category,
                            viewModel: viewModel
                        )
                    } label: {
                        CleanupCategoryRow(category: category, viewModel: viewModel)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Helpers
    
    private func loadSpaceSaved() {
        totalSpaceSaved = Int64(UserDefaults.standard.integer(forKey: "totalSpaceSaved"))
    }
    
    private func saveSpaceSaved() {
        UserDefaults.standard.set(Int(totalSpaceSaved), forKey: "totalSpaceSaved")
    }
    
    private func loadMoments() async {
        // Load on this day photos
        let calendar = Calendar.current
        let today = Date()
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.creationDate != nil }
        )
        
        if let photos = try? modelContext.fetch(descriptor) {
            onThisDayPhotos = photos.filter { photo in
                guard let date = photo.creationDate else { return false }
                let photoMonth = calendar.component(.month, from: date)
                let photoDay = calendar.component(.day, from: date)
                let photoYear = calendar.component(.year, from: date)
                let currentYear = calendar.component(.year, from: today)
                
                return photoMonth == month && photoDay == day && photoYear < currentYear
            }
        }
        
        // Load upcoming dates
        upcomingDates = await importantDatesService.getUpcomingDates(withinDays: 14)
        
        // Load latest trip
        let tripDescriptor = FetchDescriptor<PersistedMoment>(
            predicate: #Predicate { $0.isTrip },
            sortBy: [SortDescriptor(\.endDate, order: .reverse)]
        )
        latestTrip = try? modelContext.fetch(tripDescriptor).first
    }
    
    private func upcomingDateTitle(_ date: PersistedImportantDate) -> LocalizedStringKey {
        guard let days = date.daysUntilNext else { return "home_upcoming_date" }
        
        if days == 0 {
            return "home_date_today \(date.displayName)"
        } else if days == 1 {
            return "home_date_tomorrow \(date.displayName)"
        } else {
            return "home_date_in_days \(days) \(date.displayName)"
        }
    }
    
    private func upcomingDateSubtitle(_ date: PersistedImportantDate) -> LocalizedStringKey {
        switch date.dateType {
        case .birthday, .childBirthday:
            if let year = date.year {
                let age = Calendar.current.component(.year, from: Date()) - year
                let nextAge = (date.daysUntilNext ?? 0) == 0 ? age : age + 1
                return "home_turns_years \(nextAge)"
            }
            return "home_birthday"
        case .wedding, .anniversary:
            if let years = date.anniversaryYear {
                return "home_anniversary_years \(years + 1)"
            }
            return "home_anniversary"
        case .other:
            return "home_special_date"
        }
    }
}

// MARK: - Moment Row View

struct MomentRowView: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let previewPhotos: [PersistedPhoto]
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !previewPhotos.isEmpty {
                HStack(spacing: -8) {
                    ForEach(previewPhotos.prefix(3), id: \.id) { photo in
                        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Cleanup Celebration View

struct CleanupCelebrationView: View {
    let spaceSaved: Int64
    let onThisDayPhotos: [PersistedPhoto]
    let onDismiss: () -> Void
    
    @State private var showConfetti = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Celebration icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
            }
            .scaleEffect(showConfetti ? 1.0 : 0.5)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showConfetti)
            
            // Space freed
            VStack(spacing: 8) {
                Text("celebration_title")
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 4) {
                    Text("celebration_freed")
                        .foregroundStyle(.secondary)
                    Text(formattedSize(spaceSaved))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Suggested memory
            if !onThisDayPhotos.isEmpty {
                VStack(spacing: 12) {
                    Text("celebration_memory_suggestion")
                        .font(.headline)
                    
                    Text("celebration_on_this_day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // Preview photos
                    HStack(spacing: 8) {
                        ForEach(onThisDayPhotos.prefix(4), id: \.id) { photo in
                            AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    NavigationLink {
                        OnThisDayView(photos: onThisDayPhotos)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("celebration_view_memories")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Text("celebration_done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                showConfetti = true
            }
        }
    }
    
    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - On This Day View

struct OnThisDayView: View {
    let photos: [PersistedPhoto]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
                ForEach(photos, id: \.id) { photo in
                    AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
        }
        .navigationTitle(Text("on_this_day_title"))
    }
}

// MARK: - Cleanup Review View (All categories combined)

struct CleanupReviewView: View {
    @ObservedObject var viewModel: CleanupViewModel
    @State private var currentIndex = 0
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    private var allPhotos: [PersistedPhoto] {
        viewModel.categories.flatMap { $0.photos }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if currentIndex < allPhotos.count {
                // Progress indicator
                ProgressView(value: Double(currentIndex), total: Double(allPhotos.count))
                    .padding(.horizontal)
                    .padding(.top)
                
                Text("cleanup_review_progress \(currentIndex + 1) \(allPhotos.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                // Current photo category
                if let category = categoryFor(photo: allPhotos[currentIndex]) {
                    Label(LocalizedStringKey(category.localizedKey), systemImage: category.iconName)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                // Swipeable card
                SwipeablePhotoCard(
                    photo: allPhotos[currentIndex],
                    onKeep: {
                        withAnimation {
                            viewModel.selectedPhotos.remove(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    },
                    onDelete: {
                        withAnimation {
                            viewModel.selectedPhotos.insert(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    }
                )
                .padding()
                
                // Action buttons
                HStack(spacing: 60) {
                    // Keep button
                    Button {
                        withAnimation {
                            viewModel.selectedPhotos.remove(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.green)
                            Text("cleanup_keep")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Delete button
                    Button {
                        withAnimation {
                            viewModel.selectedPhotos.insert(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    } label: {
                        VStack {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red)
                            Text("cleanup_delete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 40)
                
            } else {
                // Review complete
                reviewCompleteView
            }
        }
        .navigationTitle(Text("cleanup_review_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.selectedCount > 0 {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("cleanup_delete_selected \(viewModel.selectedCount)")
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "cleanup_delete_confirmation_title",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("cleanup_delete_confirm \(viewModel.selectedCount)", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedPhotos()
                    dismiss()
                }
            }
            Button("cleanup_cancel", role: .cancel) {}
        } message: {
            Text("cleanup_delete_confirmation_message \(viewModel.formattedSize(viewModel.selectedSize))")
        }
    }
    
    private func categoryFor(photo: PersistedPhoto) -> CleanupCategoryType? {
        return photo.cleanupCategory != .none ? photo.cleanupCategory : nil
    }
    
    private var reviewCompleteView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 8) {
                Text("cleanup_review_complete_title")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if viewModel.selectedCount > 0 {
                    Text("cleanup_review_complete_selected \(viewModel.selectedCount)")
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.formattedSize(viewModel.selectedSize))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.tint)
                } else {
                    Text("cleanup_review_complete_none")
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if viewModel.selectedCount > 0 {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("cleanup_delete_selected \(viewModel.selectedCount)")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
            }
            
            Button {
                dismiss()
            } label: {
                Text("cleanup_done")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Category Row

struct CleanupCategoryRow: View {
    let category: CleanupViewModel.CleanupCategoryItem
    @ObservedObject var viewModel: CleanupViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(category.localizedKey))
                    .font(.body)
                    .foregroundStyle(.primary)
                
                Text("cleanup_category_count \(category.count) \(viewModel.formattedSize(category.estimatedSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Category Detail View

struct CleanupCategoryDetailView: View {
    let category: CleanupViewModel.CleanupCategoryItem
    @ObservedObject var viewModel: CleanupViewModel
    
    @State private var displayMode: DisplayMode = .grid
    @State private var showDeleteConfirmation = false
    
    enum DisplayMode {
        case grid
        case swipe
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Mode selector
            Picker("Modo", selection: $displayMode) {
                Label("Cuadrícula", systemImage: "square.grid.2x2").tag(DisplayMode.grid)
                Label("Deslizar", systemImage: "hand.draw").tag(DisplayMode.swipe)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if displayMode == .grid {
                gridView
            } else {
                swipeReviewView
            }
        }
        .navigationTitle(Text(LocalizedStringKey(category.localizedKey)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    viewModel.selectAll(in: category)
                } label: {
                    Text("cleanup_select_all")
                }
                
                Spacer()
                
                if viewModel.selectedCount > 0 {
                    Text("cleanup_selected \(viewModel.selectedCount)")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("cleanup_delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedCount == 0)
            }
        }
        .confirmationDialog(
            "cleanup_delete_confirmation_title",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("cleanup_delete_confirm \(viewModel.selectedCount)", role: .destructive) {
                Task {
                    await viewModel.deleteSelectedPhotos()
                }
            }
            Button("cleanup_cancel", role: .cancel) {}
        } message: {
            Text("cleanup_delete_confirmation_message \(viewModel.formattedSize(viewModel.selectedSize))")
        }
        .onAppear {
            viewModel.selectedCategory = category
        }
    }
    
    // MARK: - Grid View
    
    private var gridView: some View {
        let columns = [
            GridItem(.adaptive(minimum: 100), spacing: 2)
        ]
        
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(category.photos, id: \.id) { photo in
                    CleanupPhotoCell(
                        photo: photo,
                        isSelected: viewModel.isSelected(photo),
                        isBest: photo.isBestInGroup == true,
                        onTap: {
                            viewModel.toggleSelection(for: photo)
                        }
                    )
                }
            }
            .padding(2)
        }
    }
    
    // MARK: - Swipe Review View
    
    @State private var currentIndex = 0
    
    private var swipeReviewView: some View {
        VStack {
            if currentIndex < category.photos.count {
                let photo = category.photos[currentIndex]
                
                SwipeablePhotoCard(
                    photo: photo,
                    onKeep: {
                        withAnimation {
                            viewModel.selectedPhotos.remove(photo.id)
                            currentIndex += 1
                        }
                    },
                    onDelete: {
                        withAnimation {
                            viewModel.selectedPhotos.insert(photo.id)
                            currentIndex += 1
                        }
                    }
                )
                .padding()
                
                HStack(spacing: 40) {
                    Button {
                        viewModel.selectedPhotos.remove(photo.id)
                        currentIndex += 1
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                    }
                    
                    Button {
                        viewModel.selectedPhotos.insert(photo.id)
                        currentIndex += 1
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 40)
                
                Text("swipe_progress \(currentIndex + 1) \(category.photos.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
            } else {
                ContentUnavailableView {
                    Label("swipe_complete_title", systemImage: "checkmark.circle")
                } description: {
                    Text("swipe_complete_description \(viewModel.selectedCount)")
                }
            }
        }
    }
}

// MARK: - Photo Cell

struct CleanupPhotoCell: View {
    let photo: PersistedPhoto
    let isSelected: Bool
    var isBest: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .shadow(radius: 2)
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if isBest {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay {
                if isSelected {
                    Color.blue.opacity(0.3)
                }
            }
            .onTapGesture {
                onTap()
            }
    }
}

// MARK: - Swipeable Photo Card

struct SwipeablePhotoCard: View {
    let photo: PersistedPhoto
    let onKeep: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0
    
    var body: some View {
        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier, targetSize: CGSize(width: 500, height: 500))
            .aspectRatio(contentMode: .fit)
            .cornerRadius(16)
            .shadow(radius: 8)
            .offset(offset)
            .rotationEffect(.degrees(rotation))
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        offset = gesture.translation
                        rotation = Double(gesture.translation.width / 20)
                    }
                    .onEnded { gesture in
                        if gesture.translation.width > 100 {
                            withAnimation(.spring()) {
                                offset = CGSize(width: 500, height: 0)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onKeep()
                                offset = .zero
                                rotation = 0
                            }
                        } else if gesture.translation.width < -100 {
                            withAnimation(.spring()) {
                                offset = CGSize(width: -500, height: 0)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDelete()
                                offset = .zero
                                rotation = 0
                            }
                        } else {
                            withAnimation(.spring()) {
                                offset = .zero
                                rotation = 0
                            }
                        }
                    }
            )
            .overlay(alignment: .top) {
                HStack {
                    if offset.width > 50 {
                        Label("Conservar", systemImage: "checkmark")
                            .font(.headline)
                            .foregroundStyle(.green)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Spacer()
                    
                    if offset.width < -50 {
                        Label("Eliminar", systemImage: "trash")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
    }
}

#Preview {
    CleanupView()
        .modelContainer(for: PersistedPhoto.self)
}
