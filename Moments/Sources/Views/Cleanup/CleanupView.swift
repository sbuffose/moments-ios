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
            .animation(MomentsAnimation.spring, value: showConfetti)
            .momentsEntrance()
            
            // Space freed
            VStack(spacing: 8) {
                Text("celebration_title")
                    .font(.title)
                    .fontWeight(.bold)
                
                RecentlyDeletedHintView(bytes: spaceSaved)
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

// MARK: - Cleanup Review View (All categories combined - Now with Groups)

struct CleanupReviewView: View {
    @ObservedObject var viewModel: CleanupViewModel
    @StateObject private var shareService = ShareLoadingService()
    @State private var showFinishSheet = false
    @State private var shareItem: ShareItem?
    @State private var showPostShareDeletePrompt = false
    @State private var sharedPhotoId: String?
    @State private var showShareError = false
    @State private var showKeepDurationChip = false
    @State private var lastKeptPhotoId: String?
    @Environment(\.dismiss) private var dismiss
    
    private var allPhotos: [PersistedPhoto] {
        viewModel.categories.flatMap { $0.photos }
    }
    
    private var unreviewedItems: [ReviewItem] {
        viewModel.unreviewedItems()
    }
    
    private var photosToDelete: [PersistedPhoto] {
        viewModel.photosMarkedForDeletion(from: allPhotos)
    }
    
    private var deletionSize: Int64 {
        viewModel.deletionSizeForReview(from: allPhotos)
    }
    
    private var totalItems: Int {
        min(DailyReviewBatch.size, viewModel.reviewQueue.count)
    }
    
    private var currentProgress: Double {
        guard totalItems > 0 else { return 0 }
        return Double(viewModel.reviewedItemCount()) / Double(totalItems)
    }
    
    private var currentPosition: Int {
        min(viewModel.reviewedItemCount() + 1, max(totalItems, 1))
    }
    
    private var currentItem: ReviewItem? {
        unreviewedItems.first
    }
    
    private var currentCategory: CleanupCategoryType? {
        guard let item = currentItem else { return nil }
        switch item {
        case .single(let photo):
            return photo.cleanupCategory != .none ? photo.cleanupCategory : nil
        case .exactDuplicateGroup(_, _):
            return CleanupCategoryType.duplicate
        case .similarGroup(_, _):
            return CleanupCategoryType.nearDuplicate
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let currentItem {
                ProgressView(value: currentProgress)
                    .padding(.horizontal)
                    .padding(.top)
                    .animation(.easeInOut(duration: 0.3), value: currentProgress)
                
                Text(DailyReviewBatch.progressLabel(reviewed: viewModel.reviewedItemCount(), batchCount: totalItems))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: currentPosition)
                    .accessibilityIdentifier("review.progress")
                
                if deletionSize > 0 {
                    Text(SpaceFormatting.pendingLiberationLabel(bytes: deletionSize))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35), value: deletionSize)
                        .accessibilityIdentifier("review.pendingSpace")
                }
                
                // Category label for current photo
                if let category = currentCategory {
                    Label(LocalizedStringKey(category.localizedKey), systemImage: category.iconName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(MomentsColors.pastelChip(for: category), in: Capsule())
                        .padding(.top, 2)
                        .id(category)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: category)
                }
                
                Spacer()
                
                // Show appropriate card based on item type
                switch currentItem {
                case .single(let photo):
                    singlePhotoCard(photo: photo)
                    
                case .exactDuplicateGroup(let group, let photos):
                    ExactDuplicateGroupCard(
                        group: group,
                        photos: photos,
                        viewModel: viewModel,
                        onComplete: {
                            // Queue shrinks automatically - don't advance index
                        }
                    )
                    
                case .similarGroup(let group, let photos):
                    SimilarGroupCard(
                        group: group,
                        photos: photos,
                        viewModel: viewModel,
                        onComplete: {
                            // Queue shrinks automatically - don't advance index
                        }
                    )
                }
                
            } else {
                // Review complete (all items reviewed)
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
                    viewModel.markAsReviewed(photoId, delete: true)
                    // Queue shrinks automatically - don't advance index
                }
                sharedPhotoId = nil
            }
            Button("Conservar", role: .cancel) {
                if let photoId = sharedPhotoId {
                    viewModel.markAsReviewed(photoId, delete: false)
                    // Queue shrinks automatically - don't advance index
                }
                sharedPhotoId = nil
            }
        } message: {
            Text("Ya compartiste esta foto. ¿Querés eliminarla de tu biblioteca?")
        }
    }
    
    // MARK: - Single Photo Card (existing behavior)
    
    private func showChipRowAfterKeep(photoId: String) {
        lastKeptPhotoId = photoId
        showKeepDurationChip = true
    }
    
    @ViewBuilder
    private func singlePhotoCard(photo: PersistedPhoto) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Photo card with consistent sizing
            GeometryReader { geometry in
                let cardWidth = geometry.size.width - 32
                let cardHeight = min(geometry.size.height, cardWidth * 1.3)
                
                SwipeablePhotoCard(
                    photo: photo,
                    onKeep: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.markAsReviewed(photo.id, delete: false)
                            showChipRowAfterKeep(photoId: photo.id)
                            // Queue shrinks automatically - don't advance index
                        }
                    },
                    onDelete: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.markAsReviewed(photo.id, delete: true)
                            // Queue shrinks automatically - don't advance index
                        }
                    }
                )
                .frame(width: cardWidth, height: cardHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if let size = photo.estimatedFileSize, size > 0 {
                        Text(SpaceFormatting.string(from: size))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                            .accessibilityIdentifier("review.itemSize")
                    }
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
            
            // Inline duration chip row - shows for 2.5s after keep
            if showKeepDurationChip, let keptId = lastKeptPhotoId {
                KeepDurationChipRow(
                    onSelect: { duration in
                        viewModel.keepPhoto(keptId, duration: duration)
                        withAnimation {
                            showKeepDurationChip = false
                        }
                    },
                    onDismiss: {
                        withAnimation {
                            showKeepDurationChip = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            
            // Action buttons - fixed width, equal spacing, centered labels
            HStack(spacing: 0) {
                // Keep button with menu for options (long-press discoverable)
                Menu {
                    Button {
                        viewModel.keepPhoto(photo.id, duration: .forever)
                        // Queue shrinks automatically
                    } label: {
                        Label("Conservar siempre", systemImage: "checkmark.circle.fill")
                    }
                    
                    Button {
                        viewModel.keepPhoto(photo.id, duration: .oneWeek)
                        // Queue shrinks automatically
                    } label: {
                        Label("Preguntar en 1 semana", systemImage: "clock")
                    }
                    
                    Button {
                        viewModel.keepPhoto(photo.id, duration: .oneMonth)
                        // Queue shrinks automatically
                    } label: {
                        Label("Preguntar en 1 mes", systemImage: "calendar")
                    }
                    
                    Button {
                        viewModel.keepPhoto(photo.id, duration: .threeMonths)
                        // Queue shrinks automatically
                    } label: {
                        Label("Preguntar en 3 meses", systemImage: "calendar.badge.clock")
                    }
                } label: {
                    ReviewActionButton(
                        iconName: "checkmark.circle.fill",
                        label: "Conservar",
                        color: .green,
                        isLoading: false
                    )
                } primaryAction: {
                    viewModel.keepPhoto(photo.id, duration: .forever)
                    showChipRowAfterKeep(photoId: photo.id)
                    // Queue shrinks automatically
                }
                .disabled(shareService.isLoading)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("review.keepButton")
                
                // Share button
                Button {
                    Task {
                        sharedPhotoId = photo.id
                        if let item = await shareService.loadShareItem(for: photo) {
                            shareItem = item
                        } else {
                            showShareError = true
                        }
                    }
                } label: {
                    ReviewActionButton(
                        iconName: "square.and.arrow.up.circle.fill",
                        label: "Compartir",
                        color: .blue,
                        isLoading: shareService.isLoading && shareService.loadingPhotoId == photo.id
                    )
                }
                .disabled(shareService.isLoading)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("review.shareButton")
                
                // Delete button
                Button {
                    viewModel.markAsReviewed(photo.id, delete: true)
                    // Queue shrinks automatically
                } label: {
                    ReviewActionButton(
                        iconName: "trash.circle.fill",
                        label: "Eliminar",
                        color: .red,
                        isLoading: false
                    )
                }
                .disabled(shareService.isLoading)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("review.deleteButton")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
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
                RecentlyDeletedHintView(bytes: deletionSize)
                    .multilineTextAlignment(.center)
                
                if photosToDelete.isEmpty {
                    Text("No marcaste nada para borrar en este lote")
                        .foregroundStyle(.secondary)
                } else {
                    Text("En este lote de \(totalItems)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("review.sessionSummary")
            
            Spacer()
            
            if viewModel.remainingAfterBatch > 0 {
                Button {
                    viewModel.startNextDailyBatch()
                } label: {
                    Text("Otras 20")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(MomentsColors.accent)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                .accessibilityIdentifier("review.moreBatch")
            }
            
            Button {
                if photosToDelete.isEmpty {
                    viewModel.clearPersistedProgress()
                    dismiss()
                } else {
                    showFinishSheet = true
                }
            } label: {
                Text("Listo por hoy")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
            .accessibilityIdentifier("review.doneForToday")
        }
        .momentsEntrance()
    }
}

// MARK: - Exact Duplicate Group Card

struct ExactDuplicateGroupCard: View {
    let group: SimilarGroup
    let photos: [PersistedPhoto]
    @ObservedObject var viewModel: CleanupViewModel
    let onComplete: () -> Void
    
    private var bestPhoto: PersistedPhoto? {
        photos.first { $0.id == group.bestPhotoId } ?? photos.first
    }
    
    private var duplicateCount: Int {
        photos.count - 1
    }
    
    private var deletionSize: Int64 {
        photos.filter { $0.id != bestPhoto?.id }.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Label("Fotos idénticas", systemImage: "doc.on.doc.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            
            Spacer()
            
            // Main preview of best photo
            if let best = bestPhoto {
                AsyncPhotoThumbnail(localIdentifier: best.localIdentifier, targetSize: CGSize(width: 400, height: 400))
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(radius: 8)
                    .padding(.horizontal)
                    .overlay(alignment: .topLeading) {
                        Label("Mejor copia", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .cornerRadius(8)
                            .padding(24)
                    }
            }
            
            // Duplicate thumbnails strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos, id: \.id) { photo in
                        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                if photo.id == bestPhoto?.id {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                        .padding(4)
                                }
                            }
                            .overlay {
                                if photo.id != bestPhoto?.id {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.red.opacity(0.3))
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
            
            // Info text
            VStack(spacing: 4) {
                Text("\(MomentsPluralization.photos(photos.count)) idénticas")
                    .font(.headline)
                
                Text("Conservar la mejor y eliminar \(MomentsPluralization.deleteOthers(duplicateCount))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(formattedSize(deletionSize))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                // Primary action: Keep best, delete others
                Button {
                    // Keep the best photo forever, mark others for deletion
                    if let bestId = bestPhoto?.id {
                        viewModel.keepPhotos([bestId], duration: .forever, groupId: group.id)
                    }
                    let deleteIds = photos.filter { $0.id != bestPhoto?.id }.map { $0.id }
                    for photoId in deleteIds {
                        viewModel.markAsReviewed(photoId, delete: true)
                    }
                    onComplete()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Conservar una copia")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(14)
                }
                .accessibilityIdentifier("group.keepBest")
                
                // Secondary action: Keep all (with menu for duration)
                Menu {
                    Button {
                        viewModel.keepPhotos(photos.map { $0.id }, duration: .forever, groupId: group.id)
                        onComplete()
                    } label: {
                        Label("Conservar todas siempre", systemImage: "checkmark.circle.fill")
                    }
                    
                    Button {
                        viewModel.keepPhotos(photos.map { $0.id }, duration: .oneWeek, groupId: group.id)
                        onComplete()
                    } label: {
                        Label("Conservar, preguntar en 1 semana", systemImage: "clock")
                    }
                    
                    Button {
                        viewModel.keepPhotos(photos.map { $0.id }, duration: .oneMonth, groupId: group.id)
                        onComplete()
                    } label: {
                        Label("Conservar, preguntar en 1 mes", systemImage: "calendar")
                    }
                } label: {
                    Text("Conservar todas")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                } primaryAction: {
                    viewModel.keepPhotos(photos.map { $0.id }, duration: .forever, groupId: group.id)
                    onComplete()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .accessibilityIdentifier("review.exactDuplicateGroup")
    }
    
    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Similar Group Card (for near-duplicates, bursts)

struct SimilarGroupCard: View {
    let group: SimilarGroup
    let photos: [PersistedPhoto]
    @ObservedObject var viewModel: CleanupViewModel
    let onComplete: () -> Void
    
    @State private var selectedToKeep: Set<String> = []
    @State private var previewPhoto: PersistedPhoto?
    
    private var bestPhoto: PersistedPhoto? {
        photos.first { $0.id == group.bestPhotoId } ?? photos.first
    }
    
    private var photosToDelete: [PersistedPhoto] {
        photos.filter { !selectedToKeep.contains($0.id) }
    }
    
    private var deletionSize: Int64 {
        photosToDelete.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Label("Fotos similares", systemImage: "square.on.square")
                .font(.caption)
                .foregroundStyle(MomentsColors.accent)
            
            Spacer()
            
            // Preview of selected/hovered photo or best
            let displayPhoto = previewPhoto ?? photos.first { selectedToKeep.contains($0.id) } ?? bestPhoto
            if let photo = displayPhoto {
                AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier, targetSize: CGSize(width: 400, height: 400))
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(radius: 8)
                    .padding(.horizontal)
                    .overlay(alignment: .topLeading) {
                        if photo.id == bestPhoto?.id {
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
                        if selectedToKeep.contains(photo.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.green)
                                .padding(24)
                        }
                    }
            }
            
            // Selectable thumbnails strip
            Text("Seleccioná las que querés conservar")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos, id: \.id) { photo in
                        Button {
                            if selectedToKeep.contains(photo.id) {
                                selectedToKeep.remove(photo.id)
                            } else {
                                selectedToKeep.insert(photo.id)
                            }
                            previewPhoto = photo
                        } label: {
                            AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                                .frame(width: 70, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: selectedToKeep.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(selectedToKeep.contains(photo.id) ? .green : .white.opacity(0.8))
                                        .shadow(radius: 2)
                                        .padding(4)
                                }
                                .overlay(alignment: .topLeading) {
                                    if photo.id == bestPhoto?.id {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.yellow)
                                            .shadow(radius: 2)
                                            .padding(4)
                                    }
                                }
                                .overlay {
                                    if selectedToKeep.contains(photo.id) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.green, lineWidth: 3)
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Info text
            VStack(spacing: 4) {
                Text("\(MomentsPluralization.photos(photos.count)) similares")
                    .font(.headline)
                
                if photosToDelete.count > 0 {
                    Text("Eliminar \(MomentsPluralization.deleteOthers(photosToDelete.count)) (\(formattedSize(deletionSize)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Seleccioná al menos una para conservar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                // Primary action: Keep selected, delete unselected
                Button {
                    // Keep selected photos forever
                    viewModel.keepPhotos(Array(selectedToKeep), duration: .forever, groupId: group.id)
                    // Mark unselected for deletion
                    let deleteIds = photos.filter { !selectedToKeep.contains($0.id) }.map { $0.id }
                    for photoId in deleteIds {
                        viewModel.markAsReviewed(photoId, delete: true)
                    }
                    onComplete()
                } label: {
                    HStack {
                        if photosToDelete.count > 0 {
                            Image(systemName: "trash")
                            Text(MomentsPluralization.deleteOthers(photosToDelete.count))
                        } else {
                            Image(systemName: "checkmark")
                            Text("Conservar todas")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(photosToDelete.count > 0 ? Color.red : Color.green)
                    .cornerRadius(14)
                }
                .disabled(selectedToKeep.isEmpty)
                .accessibilityIdentifier("group.confirmSelection")
                
                // Secondary action: Keep all (with menu for duration)
                if photosToDelete.count > 0 {
                    Menu {
                        Button {
                            viewModel.keepPhotos(photos.map { $0.id }, duration: .forever, groupId: group.id)
                            onComplete()
                        } label: {
                            Label("Conservar todas siempre", systemImage: "checkmark.circle.fill")
                        }
                        
                        Button {
                            viewModel.keepPhotos(photos.map { $0.id }, duration: .oneWeek, groupId: group.id)
                            onComplete()
                        } label: {
                            Label("Conservar, preguntar en 1 semana", systemImage: "clock")
                        }
                        
                        Button {
                            viewModel.keepPhotos(photos.map { $0.id }, duration: .oneMonth, groupId: group.id)
                            onComplete()
                        } label: {
                            Label("Conservar, preguntar en 1 mes", systemImage: "calendar")
                        }
                    } label: {
                        Text("Conservar todas")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    } primaryAction: {
                        viewModel.keepPhotos(photos.map { $0.id }, duration: .forever, groupId: group.id)
                        onComplete()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .accessibilityIdentifier("review.similarGroup")
        .onAppear {
            // Pre-select best photo
            if let best = bestPhoto {
                selectedToKeep.insert(best.id)
            }
        }
    }
    
    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
                        
                        RecentlyDeletedHintView(bytes: deletionSize)
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
    
    @State private var showKeepDurationChip = false
    @State private var lastKeptPhotoId: String?
    
    private var swipeReviewView: some View {
        VStack {
            if currentIndex < category.photos.count {
                let photo = category.photos[currentIndex]
                
                SwipeablePhotoCard(
                    photo: photo,
                    onKeep: {
                        withAnimation {
                            viewModel.keepPhoto(photo.id, duration: .forever)
                            lastKeptPhotoId = photo.id
                            showKeepDurationChip = true
                            // Queue shrinks automatically - don't advance index
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation {
                                    showKeepDurationChip = false
                                }
                            }
                        }
                    },
                    onDelete: {
                        withAnimation {
                            viewModel.markAsReviewed(photo.id, delete: true)
                            // Queue shrinks automatically
                        }
                    }
                )
                .padding()
                
                // Inline duration chip row - shows for 2.5s after keep
                if showKeepDurationChip, let keptId = lastKeptPhotoId {
                    KeepDurationChipRow(
                        onSelect: { duration in
                            viewModel.keepPhoto(keptId, duration: duration)
                            withAnimation {
                                showKeepDurationChip = false
                            }
                        },
                        onDismiss: {
                            withAnimation {
                                showKeepDurationChip = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal)
                }
                
                HStack(spacing: 40) {
                    // Keep button with long-press menu
                    Menu {
                        Button {
                            viewModel.keepPhoto(photo.id, duration: .forever)
                        } label: {
                            Label("Conservar siempre", systemImage: "checkmark.circle.fill")
                        }
                        
                        Button {
                            viewModel.keepPhoto(photo.id, duration: .oneWeek)
                        } label: {
                            Label("Preguntar en 1 semana", systemImage: "clock")
                        }
                        
                        Button {
                            viewModel.keepPhoto(photo.id, duration: .oneMonth)
                        } label: {
                            Label("Preguntar en 1 mes", systemImage: "calendar")
                        }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                    } primaryAction: {
                        viewModel.keepPhoto(photo.id, duration: .forever)
                        lastKeptPhotoId = photo.id
                        showKeepDurationChip = true
                        // Queue shrinks automatically
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation {
                                showKeepDurationChip = false
                            }
                        }
                    }
                    
                    Button {
                        viewModel.markAsReviewed(photo.id, delete: true)
                        // Queue shrinks automatically
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 40)
                
                // Show position in queue based on reviewed count
                Text("swipe_progress \(viewModel.reviewedItemCount() + 1) \(category.photos.count)")
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

// MARK: - Keep Duration Chip Row

struct KeepDurationChipRow: View {
    let onSelect: (CleanupViewModel.KeepDuration) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Conservar:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button {
                    MomentsHaptics.selection()
                    onSelect(.forever)
                } label: {
                    Text("Siempre")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .cornerRadius(12)
                }
                
                Button {
                    MomentsHaptics.selection()
                    onSelect(.oneWeek)
                } label: {
                    Text("1 semana")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
                
                Button {
                    MomentsHaptics.selection()
                    onSelect(.oneMonth)
                } label: {
                    Text("1 mes")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
                
                Button {
                    MomentsHaptics.selection()
                    onSelect(.threeMonths)
                } label: {
                    Text("3 meses")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .accessibilityIdentifier("review.keepChips")
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
        GeometryReader { geometry in
            let cardSize = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                
                AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier, targetSize: CGSize(width: 600, height: 600))
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
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
        .accessibilityIdentifier("review.photoCard")
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

// MARK: - Review Action Button

struct ReviewActionButton: View {
    let iconName: String
    let label: String
    let color: Color
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .frame(width: 56, height: 56)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 56))
                    .foregroundStyle(color)
            }
            
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 96)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityIdentifier("review.actionButton.\(label)")
    }
}

#Preview {
    CleanupView()
        .modelContainer(for: PersistedPhoto.self)
}
