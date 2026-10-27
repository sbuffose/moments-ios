// CleanupView.swift
// Vista principal - Home con Limpieza + Momentos

import SwiftUI
import SwiftData
import Photos
import AVFoundation

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
            ZStack {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("cleanup.root")
                
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
                        subtitle: LocalizedStringKey(trip.tripDestination ?? trip.locationName ?? String(localized: "home_trip_photos") + " \(trip.photoIdArray.count)"),
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
        case .birthday, .childBirthday, .friendBirthday:
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
    @StateObject private var shareService = ShareLoadingService()
    @State private var currentIndex = 0
    @State private var showFinishSheet = false
    @State private var shareItem: ShareItem?
    @State private var showPostShareDeletePrompt = false
    @State private var sharedPhotoId: String?
    @State private var showShareError = false
    @Environment(\.dismiss) private var dismiss
    
    private var allPhotos: [PersistedPhoto] {
        viewModel.categories.flatMap { $0.photos }
    }
    
    private var unreviewedPhotos: [PersistedPhoto] {
        viewModel.unreviewedPhotos(from: allPhotos)
    }
    
    private var photosToDelete: [PersistedPhoto] {
        viewModel.photosMarkedForDeletion(from: allPhotos)
    }
    
    private var deletionSize: Int64 {
        viewModel.deletionSizeForReview(from: allPhotos)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if currentIndex < unreviewedPhotos.count {
                let currentPhoto = unreviewedPhotos[currentIndex]
                let totalReviewed = viewModel.reviewedCount(from: allPhotos)
                let totalPhotos = allPhotos.count
                
                // Progress indicator
                ProgressView(value: Double(totalReviewed + currentIndex), total: Double(totalPhotos))
                    .padding(.horizontal)
                    .padding(.top)
                
                Text("\(totalReviewed + currentIndex + 1) de \(totalPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                // Current photo category
                if let category = categoryFor(photo: currentPhoto) {
                    Label(LocalizedStringKey(category.localizedKey), systemImage: category.iconName)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                // Swipeable card
                SwipeablePhotoCard(
                    photo: currentPhoto,
                    onKeep: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.markAsReviewed(currentPhoto.id, delete: false)
                            currentIndex += 1
                        }
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.markAsReviewed(currentPhoto.id, delete: true)
                            currentIndex += 1
                        }
                    }
                )
                .padding()
                
                // Action buttons
                HStack(spacing: 40) {
                    // Keep button
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.markAsReviewed(currentPhoto.id, delete: false)
                            currentIndex += 1
                        }
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.green)
                            Text("Conservar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(shareService.isLoading)
                    
                    // Share button
                    Button {
                        Task {
                            sharedPhotoId = currentPhoto.id
                            if let item = await shareService.loadShareItem(for: currentPhoto) {
                                shareItem = item
                            } else {
                                showShareError = true
                            }
                        }
                    } label: {
                        VStack {
                            if shareService.isLoading && shareService.loadingPhotoId == currentPhoto.id {
                                ProgressView()
                                    .frame(width: 56, height: 56)
                            } else {
                                Image(systemName: "square.and.arrow.up.circle.fill")
                                    .font(.system(size: 56))
                                    .foregroundStyle(.blue)
                            }
                            Text("Compartir")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(shareService.isLoading)
                    .accessibilityIdentifier("review.shareButton")
                    
                    // Delete button
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.markAsReviewed(currentPhoto.id, delete: true)
                            currentIndex += 1
                        }
                    } label: {
                        VStack {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red)
                            Text("Eliminar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(shareService.isLoading)
                }
                .padding(.bottom, 40)
                
            } else {
                // Review complete (all photos reviewed)
                reviewCompleteView
            }
        }
        .navigationTitle(Text("Revisar fotos"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(photosToDelete.count > 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.root")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if photosToDelete.count > 0 {
                    Button {
                        showFinishSheet = true
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button("Terminar") {
                    showFinishSheet = true
                }
                .fontWeight(.medium)
            }
        }
        .interactiveDismissDisabled(photosToDelete.count > 0)
        .sheet(isPresented: $showFinishSheet) {
            ReviewSummarySheet(
                photosToDelete: photosToDelete,
                deletionSize: deletionSize,
                viewModel: viewModel,
                onConfirmDelete: {
                    Task {
                        await viewModel.deleteSelectedPhotos()
                        viewModel.clearPersistedProgress()
                        dismiss()
                    }
                },
                onKeepAll: {
                    viewModel.clearPersistedProgress()
                    dismiss()
                },
                onContinue: {
                    showFinishSheet = false
                }
            )
        }
        .sheet(item: $shareItem) { item in
            ShareActivityController(shareItem: item) { didShare in
                shareItem = nil
                if didShare {
                    showPostShareDeletePrompt = true
                }
            }
            .presentationDetents([.medium, .large])
            .accessibilityIdentifier("share.activitySheet")
        }
        .alert("Error al compartir", isPresented: $showShareError) {
            Button("OK") {
                showShareError = false
            }
        } message: {
            Text(shareService.errorMessage ?? "No se pudo preparar la foto para compartir")
        }
        .alert("¿Eliminar después de compartir?", isPresented: $showPostShareDeletePrompt) {
            Button("Eliminar", role: .destructive) {
                if let photoId = sharedPhotoId {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.markAsReviewed(photoId, delete: true)
                        currentIndex += 1
                    }
                }
                sharedPhotoId = nil
            }
            Button("Conservar", role: .cancel) {
                if let photoId = sharedPhotoId {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.markAsReviewed(photoId, delete: false)
                        currentIndex += 1
                    }
                }
                sharedPhotoId = nil
            }
        } message: {
            Text("Ya compartiste esta foto. ¿Querés eliminarla de tu biblioteca?")
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
                Text("¡Revisión completada!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if photosToDelete.count > 0 {
                    Text("Seleccionaste \(MomentsPluralization.photos(photosToDelete.count)) para eliminar")
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.formattedSize(deletionSize))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.tint)
                } else {
                    Text("No seleccionaste fotos para eliminar")
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if photosToDelete.count > 0 {
                Button(role: .destructive) {
                    showFinishSheet = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(MomentsPluralization.deletePhotos(photosToDelete.count))
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
                viewModel.clearPersistedProgress()
                dismiss()
            } label: {
                Text("Listo")
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

// MARK: - Review Summary Sheet

struct ReviewSummarySheet: View {
    let photosToDelete: [PersistedPhoto]
    let deletionSize: Int64
    let viewModel: CleanupViewModel
    let onConfirmDelete: () -> Void
    let onKeepAll: () -> Void
    let onContinue: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                if photosToDelete.isEmpty {
                    // No photos marked for deletion
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                    }
                    
                    Text("No hay fotos para eliminar")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Conservaste todas las fotos revisadas")
                        .foregroundStyle(.secondary)
                } else {
                    // Photos marked for deletion
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                    }
                    
                    VStack(spacing: 8) {
                        Text(MomentsPluralization.deletePhotos(photosToDelete.count))
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(formattedSize(deletionSize))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                        
                        Text("Se moverán a Eliminados Recientemente")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Preview of photos to delete
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(photosToDelete.prefix(10), id: \.id) { photo in
                                AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            if photosToDelete.count > 10 {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray4))
                                        .frame(width: 60, height: 60)
                                    
                                    Text("+\(photosToDelete.count - 10)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    if !photosToDelete.isEmpty {
                        Button(role: .destructive) {
                            onConfirmDelete()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text(MomentsPluralization.deletePhotos(photosToDelete.count))
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(14)
                        }
                    }
                    
                    Button {
                        onKeepAll()
                    } label: {
                        Text(photosToDelete.isEmpty ? "Salir" : "Conservar todas y salir")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(14)
                    }
                    
                    Button {
                        onContinue()
                    } label: {
                        Text("Seguir revisando")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Resumen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Share Item (Identifiable for .sheet(item:))

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let photoId: String
}

// MARK: - Share Activity Controller (UIKit wrapper - presented directly)

struct ShareActivityController: UIViewControllerRepresentable {
    let shareItem: ShareItem
    let onComplete: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [shareItem.url],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Share Loading Service

@MainActor
class ShareLoadingService: ObservableObject {
    @Published var isLoading = false
    @Published var loadingPhotoId: String?
    @Published var errorMessage: String?
    
    func loadShareItem(for photo: PersistedPhoto) async -> ShareItem? {
        isLoading = true
        loadingPhotoId = photo.id
        errorMessage = nil
        
        defer {
            isLoading = false
            loadingPhotoId = nil
        }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            errorMessage = "No se pudo encontrar la foto"
            return nil
        }
        
        do {
            let tempURL = try await exportAssetToTempFile(asset: asset)
            return ShareItem(url: tempURL, photoId: photo.id)
        } catch {
            errorMessage = "Error al preparar: \(error.localizedDescription)"
            return nil
        }
    }
    
    private func exportAssetToTempFile(asset: PHAsset) async throws -> URL {
        if asset.mediaType == .video {
            return try await exportVideo(asset: asset)
        } else if asset.mediaSubtypes.contains(.photoLive) {
            return try await exportLivePhoto(asset: asset)
        } else {
            return try await exportImage(asset: asset)
        }
    }
    
    private func exportImage(asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.version = .current
            
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, uti, _, info in
                guard let imageData = data else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: error ?? NSError(domain: "ShareError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar la imagen"]))
                    return
                }
                
                let fileExtension: String
                if let uniformType = uti {
                    switch uniformType {
                    case "public.jpeg", "public.jpg": fileExtension = "jpg"
                    case "public.png": fileExtension = "png"
                    case "public.heic", "public.heif": fileExtension = "heic"
                    case "com.compuserve.gif": fileExtension = "gif"
                    default: fileExtension = "jpg"
                    }
                } else {
                    fileExtension = "jpg"
                }
                
                let resources = PHAssetResource.assetResources(for: asset)
                let originalFilename = resources.first?.originalFilename ?? "photo"
                let baseName = (originalFilename as NSString).deletingPathExtension
                
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "\(baseName)_\(UUID().uuidString.prefix(8)).\(fileExtension)"
                let tempURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try imageData.write(to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func exportVideo(asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: error ?? NSError(domain: "ShareError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar el video"]))
                    return
                }
                
                let resources = PHAssetResource.assetResources(for: asset)
                let originalFilename = resources.first?.originalFilename ?? "video.mov"
                let baseName = (originalFilename as NSString).deletingPathExtension
                let ext = (originalFilename as NSString).pathExtension.isEmpty ? "mov" : (originalFilename as NSString).pathExtension
                
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "\(baseName)_\(UUID().uuidString.prefix(8)).\(ext)"
                let tempURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: urlAsset.url, to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func exportLivePhoto(asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, uti, _, info in
                guard let imageData = data else {
                    let error = info?[PHImageErrorKey] as? Error
                    continuation.resume(throwing: error ?? NSError(domain: "ShareError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo cargar Live Photo"]))
                    return
                }
                
                let resources = PHAssetResource.assetResources(for: asset)
                let originalFilename = resources.first?.originalFilename ?? "livephoto"
                let baseName = (originalFilename as NSString).deletingPathExtension
                
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "\(baseName)_\(UUID().uuidString.prefix(8)).heic"
                let tempURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try imageData.write(to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
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

// MARK: - Similar Photos Group View

struct SimilarPhotosGroupView: View {
    let groupId: String
    let photos: [PersistedPhoto]
    @ObservedObject var viewModel: CleanupViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedToKeep: Set<String> = []
    @State private var selectedPreviewPhoto: PersistedPhoto?
    @State private var showDeleteConfirmation = false
    
    private var bestPhoto: PersistedPhoto? {
        photos.first { $0.isBestInGroup == true } ?? photos.first
    }
    
    private var photosToDelete: [PersistedPhoto] {
        photos.filter { !selectedToKeep.contains($0.id) }
    }
    
    private var deletionSize: Int64 {
        photosToDelete.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Large preview of selected photo
            if let previewPhoto = selectedPreviewPhoto ?? bestPhoto {
                AsyncPhotoThumbnail(localIdentifier: previewPhoto.localIdentifier, targetSize: CGSize(width: 600, height: 600))
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .cornerRadius(12)
                    .padding()
                    .overlay(alignment: .topLeading) {
                        if previewPhoto.isBestInGroup == true {
                            Label("Mejor foto", systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .cornerRadius(8)
                                .padding(24)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if selectedToKeep.contains(previewPhoto.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.green)
                                .padding(24)
                        }
                    }
            }
            
            Text("\(MomentsPluralization.photos(photos.count)) similares")
                .font(.headline)
                .padding(.bottom, 8)
            
            Text("Seleccioná las que querés conservar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Horizontal grid of all photos in group
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos, id: \.id) { photo in
                        SimilarPhotoCell(
                            photo: photo,
                            isSelected: selectedToKeep.contains(photo.id),
                            isBest: photo.isBestInGroup == true,
                            isPreview: selectedPreviewPhoto?.id == photo.id || (selectedPreviewPhoto == nil && photo.id == bestPhoto?.id)
                        ) {
                            // Toggle selection
                            if selectedToKeep.contains(photo.id) {
                                selectedToKeep.remove(photo.id)
                            } else {
                                selectedToKeep.insert(photo.id)
                            }
                        } onLongPress: {
                            selectedPreviewPhoto = photo
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            
            Spacer()
            
            // Delete button
            VStack(spacing: 12) {
                if photosToDelete.count > 0 {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("\(MomentsPluralization.deleteOthers(photosToDelete.count)) (\(formattedSize(deletionSize)))")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                    }
                } else {
                    Text("Seleccioná al menos una para conservar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("Cancelar")
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
            }
            .padding()
            .padding(.bottom, 16)
        }
        .navigationTitle("Fotos similares")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Pre-select best photo
            if let best = bestPhoto {
                selectedToKeep.insert(best.id)
            }
        }
        .confirmationDialog(
            MomentsPluralization.deletePhotos(photosToDelete.count),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(MomentsPluralization.deletePhotos(photosToDelete.count), role: .destructive) {
                Task {
                    // Mark photos for deletion
                    for photo in photosToDelete {
                        viewModel.selectedPhotos.insert(photo.id)
                    }
                    await viewModel.deleteSelectedPhotos()
                    dismiss()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se liberarán \(formattedSize(deletionSize)). Las fotos se moverán a Eliminados Recientemente.")
        }
    }
    
    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SimilarPhotoCell: View {
    let photo: PersistedPhoto
    let isSelected: Bool
    let isBest: Bool
    let isPreview: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .green : .white.opacity(0.8))
                    .shadow(radius: 2)
                    .padding(4)
            }
            .overlay(alignment: .topLeading) {
                if isBest {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green, lineWidth: 3)
                }
                if isPreview {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture {
                onLongPress()
            }
    }
}

#Preview {
    CleanupView()
        .modelContainer(for: PersistedPhoto.self)
}
