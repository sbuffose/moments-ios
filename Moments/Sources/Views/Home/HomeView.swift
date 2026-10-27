// HomeView.swift
// Home feed with proactive cards - space savings, moments, cataloging
// Shows metadata-based categories immediately, updates live during analysis

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    
    @StateObject private var viewModel = HomeViewModel()
    @AppStorage("hasSeenScanNotice") private var hasSeenScanNotice = false
    @State private var showScanNotice = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("home.root")
                
                ScrollView {
                    VStack(spacing: MomentsSpacing.lg) {
                        headerSection
                        
                        // One-time scan notice (replaces persistent pill)
                        if showScanNotice {
                            scanNoticeCard
                        }
                        
                        if viewModel.canFreeSpace > 0 || !viewModel.metadataCategories.isEmpty {
                            spaceCard
                        }
                        
                        ForEach(viewModel.feedCards) { card in
                            FeedCardView(card: card, viewModel: viewModel)
                        }
                        
                        if viewModel.canFreeSpace == 0 && viewModel.feedCards.isEmpty && viewModel.metadataCategories.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    .padding(.vertical, MomentsSpacing.md)
                }
                .accessibilityIdentifier("home.scrollView")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: MomentsSpacing.xs) {
                        Text("Moments")
                            .font(MomentsTypography.headlineLarge)
                            .foregroundStyle(MomentsColors.textPrimary)
                        
                        // Clock icon when analyzing (replaces persistent pill)
                        if appState.isAnalyzing || appState.isIndexing {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14))
                                .foregroundStyle(MomentsColors.accent)
                                .symbolEffect(.pulse.byLayer, options: .repeating)
                                .accessibilityLabel("Análisis en progreso")
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
            // Show one-time scan notice if analyzing and user hasn't seen it
            if (appState.isAnalyzing || appState.isIndexing) && !hasSeenScanNotice {
                showScanNotice = true
            }
        }
        .onChange(of: appState.isAnalyzing) { _, isAnalyzing in
            // Hide notice when analysis completes
            if !isAnalyzing && !appState.isIndexing {
                withAnimation {
                    showScanNotice = false
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if appState.isAnalyzing {
                viewModel.refreshCategories()
            }
        }
    }
    
    // MARK: - One-time Scan Notice Card
    
    private var scanNoticeCard: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.sm) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(MomentsColors.accent)
                
                Text("Analizando tu biblioteca")
                    .font(MomentsTypography.headlineSmall)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                Spacer()
                
                Button {
                    withAnimation {
                        showScanNotice = false
                        hasSeenScanNotice = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MomentsColors.textTertiary)
                }
            }
            
            Text("El análisis continúa en segundo plano. Podés seguir usando la app normalmente.")
                .font(MomentsTypography.bodySmall)
                .foregroundStyle(MomentsColors.textSecondary)
            
            // Progress info
            HStack(spacing: MomentsSpacing.md) {
                if appState.isIndexing {
                    Text("\(MomentsPluralization.photos(appState.totalPhotosIndexed)) encontradas")
                        .font(MomentsTypography.labelSmall)
                        .foregroundStyle(MomentsColors.textTertiary)
                } else {
                    Text("\(appState.totalPhotosAnalyzed) / \(appState.totalPhotosToAnalyze)")
                        .font(MomentsTypography.labelSmall)
                        .foregroundStyle(MomentsColors.textTertiary)
                    
                    // Estimated time remaining
                    if let eta = appState.estimatedTimeRemaining {
                        Text("~\(eta) restante")
                            .font(MomentsTypography.labelSmall)
                            .foregroundStyle(MomentsColors.accent)
                    }
                }
            }
            
            ProgressView(value: appState.isIndexing ? appState.indexingProgress : appState.analysisProgress)
                .progressViewStyle(.linear)
                .tint(MomentsColors.accent)
        }
        .padding(MomentsSpacing.md)
        .background(MomentsColors.bgSecondary)
        .cornerRadius(MomentsCorners.large)
        .accessibilityIdentifier("home.scanNotice")
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.xs) {
            Text(greeting)
                .font(MomentsTypography.displaySmall)
                .foregroundStyle(MomentsColors.textPrimary)
            
            if viewModel.totalSpaceSaved > 0 {
                HStack(spacing: MomentsSpacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Ya liberaste \(viewModel.formattedSpaceSaved)")
                        .font(MomentsTypography.bodyMedium)
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Buenos días"
        case 12..<18: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }
    
    // Note: analysisProgressPill replaced by scanNoticeCard + toolbar clock icon
    
    // MARK: - Space Card
    
    private var spaceCard: some View {
        VStack(spacing: MomentsSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MomentsSpacing.xs) {
                    if viewModel.canFreeSpace > 0 {
                        Text("Podés liberar")
                            .font(MomentsTypography.headlineMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                        
                        Text("\(viewModel.cleanupItemCount) elementos para revisar")
                            .font(MomentsTypography.bodySmall)
                            .foregroundStyle(MomentsColors.textSecondary)
                    } else {
                        Text("Liberá espacio")
                            .font(MomentsTypography.headlineMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                        
                        Text("\(viewModel.totalMetadataItems) elementos detectados")
                            .font(MomentsTypography.bodySmall)
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.canFreeSpace > 0 ? viewModel.formattedCanFree : viewModel.formattedMetadataSize)
                        .font(MomentsTypography.numberMedium)
                        .foregroundStyle(MomentsColors.accent)
                    
                    Text("disponibles")
                        .font(MomentsTypography.labelSmall)
                        .foregroundStyle(MomentsColors.textTertiary)
                }
            }
            
            if !viewModel.metadataCategories.isEmpty {
                VStack(alignment: .leading, spacing: MomentsSpacing.sm) {
                    ForEach(viewModel.metadataCategories.prefix(4)) { category in
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundStyle(MomentsColors.accent)
                                .frame(width: 24)
                            
                            Text(category.title)
                                .font(MomentsTypography.bodyMedium)
                                .foregroundStyle(MomentsColors.textPrimary)
                            
                            Spacer()
                            
                            Text("\(category.count)")
                                .font(MomentsTypography.labelMedium)
                                .foregroundStyle(MomentsColors.textSecondary)
                        }
                    }
                }
                .padding(.top, MomentsSpacing.xs)
            }
            
            if !viewModel.topScoredPreviewPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.topScoredPreviewPhotos, id: \.id) { photo in
                            AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            
            NavigationLink {
                CleanupReviewView(viewModel: viewModel.cleanupViewModel)
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Revisar \(viewModel.cleanupItemCount > 0 ? MomentsPluralization.photos(viewModel.cleanupItemCount) : "ahora")")
                }
            }
            .momentsAccentButton()
            .accessibilityIdentifier("home.reviewButton")
        }
        .accessibilityIdentifier("home.spaceCard")
        .momentsCard()
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: MomentsSpacing.lg) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(MomentsColors.textTertiary)
            
            VStack(spacing: MomentsSpacing.xs) {
                Text("Tu biblioteca está impecable")
                    .font(MomentsTypography.headlineMedium)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                Text("No encontramos fotos para limpiar. ¡Bien hecho!")
                    .font(MomentsTypography.bodyMedium)
                    .foregroundStyle(MomentsColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MomentsSpacing.xl)
        .accessibilityIdentifier("home.emptyState")
    }
}

// MARK: - Feed Card View

struct FeedCardView: View {
    let card: HomeFeedCard
    @ObservedObject var viewModel: HomeViewModel
    
    var body: some View {
        switch card.type {
        case .onThisDay(let photos):
            PhotoGridCard(
                title: "Hace un año hoy...",
                subtitle: "\(MomentsPluralization.photos(photos.count)) de esta fecha",
                photos: photos,
                action: { viewModel.showOnThisDay() }
            )
            
        case .upcomingDate(let date, let photos):
            DateReminderCard(
                importantDate: date,
                previewPhotos: photos,
                onTap: { viewModel.showDateMemories(date) },
                onAddCalendar: { viewModel.addToCalendar(date) }
            )
            
        case .catalogQuestion(let question, let subtitle, let photos, let options):
            CatalogingQuestionCard(
                question: question,
                subtitle: subtitle,
                photos: photos,
                options: options.map { opt in
                    CatalogingQuestionCard.CatalogOption(
                        title: opt.title,
                        action: { viewModel.answerQuestion(opt) }
                    )
                },
                onDismiss: { viewModel.dismissCard(card) }
            )
            
        case .latestTrip(let title, let location, let photos):
            PhotoGridCard(
                title: "Tu último viaje",
                subtitle: location,
                photos: photos,
                action: { viewModel.showTrip() }
            )
            
        case .cleanup(let title, let count, let size, let photos, let category):
            CleanupBatchCard(
                title: title,
                itemCount: count,
                estimatedSize: size,
                photos: photos,
                onReview: { viewModel.reviewCleanup(category: category) },
                onQuickDelete: { viewModel.quickDelete(photos: photos) }
            )
        }
    }
}

// MARK: - Metadata Category

struct MetadataCategory: Identifiable {
    let id: String
    let title: String
    let icon: String
    let count: Int
    let estimatedSize: Int64
    let averageScore: Double
    let photos: [PersistedPhoto]
    
    /// Combined score for sorting: prioritizes high deletion scores and large space savings
    var sortScore: Double {
        let scoreWeight = averageScore * 0.6
        let sizeWeight = min(Double(estimatedSize) / 1_000_000_000.0, 1.0) * 0.4
        return scoreWeight + sizeWeight
    }
}

// MARK: - Home View Model

@MainActor
class HomeViewModel: ObservableObject {
    @Published var feedCards: [HomeFeedCard] = []
    @Published var canFreeSpace: Int64 = 0
    @Published var totalSpaceSaved: Int64 = 0
    @Published var cleanupItemCount: Int = 0
    @Published var cleanupPreviewPhotos: [PersistedPhoto] = []
    @Published var topScoredPreviewPhotos: [PersistedPhoto] = []
    @Published var metadataCategories: [MetadataCategory] = []
    @Published var totalMetadataItems: Int = 0
    @Published var metadataSize: Int64 = 0
    
    var cleanupViewModel = CleanupViewModel()
    
    private var modelContext: ModelContext?
    private let importantDatesService = ImportantDatesService.shared
    
    var formattedCanFree: String {
        ByteCountFormatter.string(fromByteCount: canFreeSpace, countStyle: .file)
    }
    
    var formattedSpaceSaved: String {
        ByteCountFormatter.string(fromByteCount: totalSpaceSaved, countStyle: .file)
    }
    
    var formattedMetadataSize: String {
        ByteCountFormatter.string(fromByteCount: metadataSize, countStyle: .file)
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        cleanupViewModel.initialize(modelContext: modelContext)
        importantDatesService.initialize(modelContext: modelContext)
        
        loadSpaceSaved()
        loadMetadataCategories()
        
        Task {
            await loadFeedCards()
        }
    }
    
    func refreshCategories() {
        loadMetadataCategories()
        
        canFreeSpace = cleanupViewModel.estimatedSpaceFreed
        cleanupItemCount = cleanupViewModel.totalCleanupItems
        cleanupPreviewPhotos = Array(cleanupViewModel.categories.flatMap { $0.photos }.prefix(10))
        
        // Top-scored photos: sorted by deletion likelihood (highest first), excluding Live Photos at top
        let allCleanupPhotos = cleanupViewModel.categories.flatMap { $0.photos }
        topScoredPreviewPhotos = Array(
            allCleanupPhotos
                .sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
                .prefix(10)
        )
    }
    
    private func loadSpaceSaved() {
        totalSpaceSaved = Int64(UserDefaults.standard.integer(forKey: "totalSpaceSaved"))
    }
    
    private func loadMetadataCategories() {
        guard let context = modelContext else { return }
        
        var categories: [MetadataCategory] = []
        
        // Helper to calculate average deletion score
        func avgScore(_ photos: [PersistedPhoto]) -> Double {
            guard !photos.isEmpty else { return 0 }
            return photos.reduce(0) { $0 + $1.deletionLikelihoodScore } / Double(photos.count)
        }
        
        let screenshotDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.mediaSubtypesRaw.contains("screenshot") }
        )
        if let screenshots = try? context.fetch(screenshotDescriptor), !screenshots.isEmpty {
            let size = screenshots.reduce(0) { $0 + ($1.estimatedFileSize ?? 50_000) }
            categories.append(MetadataCategory(
                id: "screenshots",
                title: "Capturas de pantalla",
                icon: "rectangle.on.rectangle",
                count: screenshots.count,
                estimatedSize: size,
                averageScore: avgScore(screenshots),
                photos: screenshots
            ))
        }
        
        let burstDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.burstIdentifier != nil && !$0.representsBurst }
        )
        if let bursts = try? context.fetch(burstDescriptor), !bursts.isEmpty {
            let size = bursts.reduce(0) { $0 + ($1.estimatedFileSize ?? 2_000_000) }
            categories.append(MetadataCategory(
                id: "bursts",
                title: "Ráfagas duplicadas",
                icon: "square.stack.3d.up",
                count: bursts.count,
                estimatedSize: size,
                averageScore: avgScore(bursts),
                photos: bursts
            ))
        }
        
        // Live Photos - show as low-priority conversion suggestion, not deletion
        let livePhotoDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.isLivePhoto }
        )
        if let livePhotos = try? context.fetch(livePhotoDescriptor), !livePhotos.isEmpty {
            let size = livePhotos.reduce(0) { $0 + ($1.estimatedFileSize ?? 3_000_000) }
            // Live Photos have low deletion score - suggest conversion instead
            categories.append(MetadataCategory(
                id: "livePhotos",
                title: "Live Photos",
                icon: "livephoto",
                count: livePhotos.count,
                estimatedSize: size,
                averageScore: 0.05, // Very low score - not deletion candidates
                photos: livePhotos
            ))
        }
        
        // Use stored property originRaw, not computed property origin
        let whatsapp = "whatsapp"
        let telegram = "telegram"
        let instagram = "instagram"
        let downloadedDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.originRaw == whatsapp || $0.originRaw == telegram || $0.originRaw == instagram }
        )
        if let downloaded = try? context.fetch(downloadedDescriptor), !downloaded.isEmpty {
            let size = downloaded.reduce(0) { $0 + ($1.estimatedFileSize ?? 500_000) }
            categories.append(MetadataCategory(
                id: "downloaded",
                title: "Descargas de apps",
                icon: "arrow.down.circle",
                count: downloaded.count,
                estimatedSize: size,
                averageScore: avgScore(downloaded),
                photos: downloaded
            ))
        }
        
        let videoDescriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.mediaTypeRaw == "video" && ($0.estimatedFileSize ?? 0) > 100_000_000 }
        )
        if let largeVideos = try? context.fetch(videoDescriptor), !largeVideos.isEmpty {
            let size = largeVideos.reduce(0) { $0 + ($1.estimatedFileSize ?? 100_000_000) }
            categories.append(MetadataCategory(
                id: "largeVideos",
                title: "Videos grandes (+100 MB)",
                icon: "film",
                count: largeVideos.count,
                estimatedSize: size,
                averageScore: avgScore(largeVideos),
                photos: largeVideos
            ))
        }
        
        // Sort by combined score (deletion likelihood + space savings)
        metadataCategories = categories.sorted { $0.sortScore > $1.sortScore }
        totalMetadataItems = categories.reduce(0) { $0 + $1.count }
        metadataSize = categories.reduce(0) { $0 + $1.estimatedSize }
        
        canFreeSpace = cleanupViewModel.estimatedSpaceFreed
        cleanupItemCount = cleanupViewModel.totalCleanupItems
        cleanupPreviewPhotos = Array(cleanupViewModel.categories.flatMap { $0.photos }.prefix(10))
        
        // Top-scored photos for preview strip (sorted by deletion likelihood, highest first)
        let allPhotosFromCategories = categories.flatMap { $0.photos }
        topScoredPreviewPhotos = Array(
            allPhotosFromCategories
                .sorted { $0.deletionLikelihoodScore > $1.deletionLikelihoodScore }
                .prefix(10)
        )
    }
    
    private func loadFeedCards() async {
        guard let context = modelContext else { return }
        
        var cards: [HomeFeedCard] = []
        
        canFreeSpace = cleanupViewModel.estimatedSpaceFreed
        cleanupItemCount = cleanupViewModel.totalCleanupItems
        cleanupPreviewPhotos = Array(cleanupViewModel.categories.flatMap { $0.photos }.prefix(10))
        
        let calendar = Calendar.current
        let today = Date()
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted && $0.creationDate != nil }
        )
        
        if let photos = try? context.fetch(descriptor) {
            let onThisDayPhotos = photos.filter { photo in
                guard let date = photo.creationDate else { return false }
                let photoMonth = calendar.component(.month, from: date)
                let photoDay = calendar.component(.day, from: date)
                let photoYear = calendar.component(.year, from: date)
                let currentYear = calendar.component(.year, from: today)
                
                return photoMonth == month && photoDay == day && photoYear < currentYear
            }
            
            if !onThisDayPhotos.isEmpty {
                cards.append(HomeFeedCard(
                    type: .onThisDay(photos: Array(onThisDayPhotos.prefix(9)))
                ))
            }
        }
        
        let upcoming = await importantDatesService.getUpcomingDates(withinDays: 14)
        for date in upcoming.prefix(2) {
            let photoIds = date.photoIdArray
            let photoDescriptor = FetchDescriptor<PersistedPhoto>()
            let allPhotos = (try? context.fetch(photoDescriptor)) ?? []
            let datePhotos = allPhotos.filter { photoIds.contains($0.id) }
            
            cards.append(HomeFeedCard(
                type: .upcomingDate(date: date, photos: Array(datePhotos.prefix(4)))
            ))
        }
        
        let tripDescriptor = FetchDescriptor<PersistedMoment>(
            predicate: #Predicate { $0.isTrip },
            sortBy: [SortDescriptor(\.endDate, order: .reverse)]
        )
        
        if let trip = try? context.fetch(tripDescriptor).first {
            let photoIds = trip.photoIdArray
            let photoDescriptor = FetchDescriptor<PersistedPhoto>()
            let allPhotos = (try? context.fetch(photoDescriptor)) ?? []
            let tripPhotos = allPhotos.filter { photoIds.contains($0.id) }
            
            cards.append(HomeFeedCard(
                type: .latestTrip(
                    title: trip.title ?? "Viaje",
                    location: trip.tripDestination ?? trip.locationName,
                    photos: Array(tripPhotos.prefix(6))
                )
            ))
        }
        
        let catalogingService = CatalogingService()
        catalogingService.initialize(modelContext: context)
        await catalogingService.generateCatalogingCards()
        
        for catalogCard in catalogingService.pendingCards.prefix(2) {
            let photoDescriptor = FetchDescriptor<PersistedPhoto>()
            let allPhotos = (try? context.fetch(photoDescriptor)) ?? []
            let cardPhotos = allPhotos.filter { catalogCard.previewPhotoIds.contains($0.id) }
            
            let question: String
            switch catalogCard.type {
            case .unknownPerson:
                question = "¿Quién es esta persona?"
            case .unknownPlace:
                question = "¿Qué lugar es este?"
            case .recurringDate, .confirmBirthday:
                question = "¿Es una fecha especial?"
            default:
                continue
            }
            
            cards.append(HomeFeedCard(
                type: .catalogQuestion(
                    question: question,
                    subtitle: catalogCard.subtitle,
                    photos: cardPhotos,
                    options: [
                        HomeFeedCard.CatalogOption(id: "label", title: "Sí, agregar nombre"),
                        HomeFeedCard.CatalogOption(id: "skip", title: "Ahora no")
                    ]
                )
            ))
        }
        
        feedCards = cards
    }
    
    // MARK: - Actions
    
    func showOnThisDay() {
        MomentsHaptics.light()
    }
    
    func showDateMemories(_ date: PersistedImportantDate) {
        MomentsHaptics.light()
    }
    
    func addToCalendar(_ date: PersistedImportantDate) {
        MomentsHaptics.success()
        Task {
            guard let context = modelContext else { return }
            let calendarService = CalendarService.shared
            calendarService.initialize(modelContext: context)
            _ = await calendarService.addToCalendar(importantDate: date)
        }
    }
    
    func showTrip() {
        MomentsHaptics.light()
    }
    
    func reviewCleanup(category: CleanupCategoryType?) {
        MomentsHaptics.light()
    }
    
    func quickDelete(photos: [PersistedPhoto]) {
        MomentsHaptics.success()
        Task {
            for photo in photos {
                cleanupViewModel.selectedPhotos.insert(photo.id)
            }
            await cleanupViewModel.deleteSelectedPhotos()
            await loadFeedCards()
        }
    }
    
    func answerQuestion(_ option: HomeFeedCard.CatalogOption) {
        MomentsHaptics.selection()
    }
    
    func dismissCard(_ card: HomeFeedCard) {
        MomentsHaptics.light()
        feedCards.removeAll { $0.id == card.id }
    }
}

// MARK: - Feed Card Model

struct HomeFeedCard: Identifiable {
    let id = UUID()
    let type: CardType
    
    enum CardType {
        case onThisDay(photos: [PersistedPhoto])
        case upcomingDate(date: PersistedImportantDate, photos: [PersistedPhoto])
        case catalogQuestion(question: String, subtitle: String, photos: [PersistedPhoto], options: [CatalogOption])
        case latestTrip(title: String, location: String?, photos: [PersistedPhoto])
        case cleanup(title: String, count: Int, size: String, photos: [PersistedPhoto], category: CleanupCategoryType?)
    }
    
    struct CatalogOption {
        let id: String
        let title: String
    }
}

#Preview {
    HomeView()
        // Follow system light/dark mode
        .modelContainer(for: PersistedPhoto.self)
        .environmentObject(AppState())
}
