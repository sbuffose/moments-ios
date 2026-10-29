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
    @State private var showRecentlyDeletedInfo = false
    @State private var heroReady = true
    @Namespace private var homeMotion
    
    /// Prevents the hero from laying out at zero width (one-letter columns).
    static let heroMinWidth: CGFloat = 300
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsAliveBackground()
                
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("home.root")
                    .allowsHitTesting(false)
                
                if appState.shouldShowFirstRunAnalyzing {
                    FirstRunAnalyzingView()
                        .id("home.firstRun")
                } else {
                    readyHomeScroll
                        .id("home.ready.\(appState.homeRevealGeneration)")
                        .opacity(1)
                        .allowsHitTesting(true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Moments")
                        .font(MomentsTypography.headlineLarge)
                        .foregroundStyle(MomentsColors.textPrimary)
                }
                
                if (appState.isAnalyzing || appState.isIndexing) && !appState.shouldShowFirstRunAnalyzing {
                    ToolbarItem(placement: .topBarTrailing) {
                        TimelineViewClock()
                            .accessibilityIdentifier("home.scanClock")
                            .accessibilityLabel("Preparando tu limpieza")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .imageScale(.medium)
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                    .accessibilityIdentifier("home.settingsButton")
                    .accessibilityLabel("Ajustes")
                }
            }
        }
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
        }
        .sheet(isPresented: $showRecentlyDeletedInfo) {
            NavigationStack {
                RecentlyDeletedHintView(bytes: viewModel.totalSpaceSaved)
                    .padding()
                    .navigationTitle("Espacio liberado")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            if appState.isAnalyzing && !appState.shouldShowFirstRunAnalyzing && heroReady {
                viewModel.refreshInventory()
            }
        }
    }
    
    private var readyHomeScroll: some View {
        ScrollView {
            VStack(spacing: MomentsSpacing.lg) {
                searchBar
                
                ZStack {
                    if heroReady {
                        heroCard
                    } else {
                        heroSkeleton
                    }
                }
                
                freedAndStorageCard
                
                memoryHero
                
                if !viewModel.metadataCategories.isEmpty {
                    categoryChips
                    detailLink
                }
                
                ForEach(viewModel.feedCards.filter { !$0.isOnThisDay }) { card in
                    FeedCardView(card: card, viewModel: viewModel)
                }
                
                if viewModel.canFreeSpace == 0 && viewModel.feedCards.isEmpty && viewModel.metadataCategories.isEmpty {
                    emptyStateView
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MomentsSpacing.screenHorizontal)
            .padding(.vertical, MomentsSpacing.md)
        }
        .accessibilityIdentifier("home.scrollView")
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                heroReady = true
            }
        }
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
    
    static func todayReviewSubtitle(itemCount: Int) -> String {
        let today = min(max(itemCount, 0), DailyReviewBatch.size)
        if today == 0 {
            return "Nada para revisar hoy"
        }
        return "\(today) de \(DailyReviewBatch.size) para hoy"
    }
    
    static func heroHeadline(todayBytes: Int64, totalBytes: Int64, itemCount: Int = DailyReviewBatch.size) -> String {
        let today = min(max(itemCount, 0), DailyReviewBatch.size)
        let photos = MomentsPluralization.photos(today)
        let todaySize = SpaceFormatting.string(from: todayBytes)
        if todayBytes == totalBytes {
            return "\(photos) para hoy · \(todaySize)"
        }
        return "\(photos) para hoy · \(todaySize) · en total podés liberar \(SpaceFormatting.string(from: totalBytes))"
    }
    
    static func heroHeadline(bytes: Int64, minutes: Int = 2) -> String {
        heroHeadline(todayBytes: bytes, totalBytes: bytes)
    }
    
    private var searchBar: some View {
        Button {
            appState.selectedTab = .assistant
        } label: {
            HStack(spacing: MomentsSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MomentsColors.textSecondary)
                Text("Buscá en tus fotos")
                    .font(MomentsTypography.bodyMedium)
                    .foregroundStyle(MomentsColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, MomentsSpacing.md)
            .padding(.vertical, MomentsSpacing.sm)
            .background(MomentsColors.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityIdentifier("home.searchBar")
        .accessibilityLabel("Buscá en tus fotos")
    }
    
    private var heroSkeleton: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.md) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(MomentsColors.bgTertiary)
                .frame(height: 32)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MomentsColors.bgTertiary)
                .frame(width: 220, height: 16)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MomentsColors.bgTertiary)
                .frame(width: 180, height: 16)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MomentsColors.bgTertiary)
                .frame(height: 52)
        }
        .frame(minWidth: Self.heroMinWidth, maxWidth: .infinity, alignment: .leading)
        .momentsCard()
        .accessibilityIdentifier("home.heroSkeleton")
        .redacted(reason: .placeholder)
    }
    
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.md) {
            Text(Self.heroHeadline(
                todayBytes: viewModel.inventory.todayBatchBytes,
                totalBytes: viewModel.inventory.totalReclaimableBytes,
                itemCount: viewModel.inventory.todayBatchItems
            ))
                .font(MomentsTypography.displaySmall)
                .foregroundStyle(MomentsColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(MomentsColors.bgCard)
                .accessibilityIdentifier("home.heroHeadline")
            
            ForEach(viewModel.topHumanReasons.prefix(3), id: \.self) { reason in
                HStack(spacing: MomentsSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MomentsColors.accent)
                    Text(reason)
                        .font(MomentsTypography.bodyMedium)
                        .foregroundStyle(MomentsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            NavigationLink {
                CleanupReviewView(viewModel: viewModel.cleanupViewModel)
            } label: {
                MomentsAccentLinkLabel(title: "Empezar")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.reviewButton")
            .accessibilityLabel("Empezar")
            .accessibilityAddTraits(.isButton)
        }
        .frame(minWidth: Self.heroMinWidth, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.spaceCard")
        .momentsCard()
        .homeCardBreathing()
        .matchedGeometryEffect(id: "spaceCounter", in: homeMotion)
    }
    
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MomentsSpacing.sm) {
                ForEach(viewModel.metadataCategories.prefix(6)) { category in
                    NavigationLink {
                        CleanupView()
                    } label: {
                        HStack(spacing: 6) {
                            MomentsCategoryGlyph(systemName: category.icon, color: MomentsColors.chipAccent(for: category.id))
                            Text(category.title)
                                .font(MomentsTypography.labelMedium)
                        }
                        .padding(.horizontal, MomentsSpacing.sm)
                        .padding(.vertical, MomentsSpacing.xs)
                        .background(MomentsColors.chipAccent(for: category.id).opacity(0.14))
                        .clipShape(Capsule())
                        .foregroundStyle(MomentsColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.chip.\(category.id)")
                    .accessibilityLabel(category.title)
                }
            }
            .padding(.trailing, 36)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [MomentsColors.bgPrimary.opacity(0), MomentsColors.bgPrimary],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home.categoryChips")
    }
    
    private var freedAndStorageCard: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.sm) {
            HStack(alignment: .top) {
                Text(SpaceFormatting.homeCumulativeSpaceHeadline(bytes: viewModel.totalSpaceSaved))
                    .font(MomentsTypography.headlineMedium)
                    .foregroundStyle(MomentsColors.textPrimary)
                    .accessibilityIdentifier("home.freedTotal")
                Spacer()
                Button {
                    showRecentlyDeletedInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityIdentifier("home.recentlyDeletedInfo")
                .accessibilityLabel("Cómo se recupera el espacio")
            }
            
            Text(SpaceFormatting.recentlyDeletedRecovery)
                .font(MomentsTypography.bodySmall)
                .foregroundStyle(MomentsColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("home.recentlyDeletedCopy")
            
            let storage = DeviceStorage.current()
            VStack(alignment: .leading, spacing: MomentsSpacing.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MomentsColors.bgTertiary)
                        Capsule()
                            .fill(MomentsColors.accentGradient)
                            .frame(width: max(0, geo.size.width * storage.usedRatio))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 10)
                
                Text("Espacio del teléfono: \(SpaceFormatting.string(from: storage.available)) libres de \(SpaceFormatting.string(from: storage.total))")
                    .font(MomentsTypography.labelSmall)
                    .foregroundStyle(MomentsColors.textSecondary)
                    .accessibilityIdentifier("home.storageBar")
            }
        }
        .momentsCard()
    }
    
    private var memoryHero: some View {
        Group {
            if let photos = viewModel.onThisDayPhotos, !photos.isEmpty {
                ParallaxMemoryHero(photos: photos, title: "Hace un año hoy")
                    .accessibilityIdentifier("home.memoryHero")
            }
        }
    }
    
    private var detailLink: some View {
        NavigationLink {
            CleanupView()
        } label: {
            Text("Ver detalle")
                .font(MomentsTypography.labelMedium)
                .foregroundStyle(MomentsColors.accent)
        }
        .accessibilityIdentifier("home.verDetalle")
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    // MARK: - Space Card
    
    private var spaceCard: some View {
        VStack(spacing: MomentsSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MomentsSpacing.xs) {
                    if viewModel.canFreeSpace > 0 {
                        Text("Podés liberar")
                            .font(MomentsTypography.headlineMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                        
                        Text(Self.todayReviewSubtitle(itemCount: viewModel.cleanupItemCount))
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
                MomentsAccentLinkLabel(
                    title: viewModel.cleanupItemCount > 0
                        ? "Revisar \(MomentsPluralization.photos(min(viewModel.cleanupItemCount, DailyReviewBatch.size)))"
                        : "Revisar ahora"
                )
            }
            .buttonStyle(.plain)
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
                itemCount: min(count, DailyReviewBatch.size),
                estimatedSize: size,
                photos: Array(photos.prefix(DailyReviewBatch.size)),
                onReview: { viewModel.reviewCleanup(category: category) },
                onQuickDelete: { viewModel.quickDelete(photos: Array(photos.prefix(DailyReviewBatch.size))) },
                totalCount: count,
                totalSize: size
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
    @Published var inventory: LibraryInventory = .empty
    
    var cleanupViewModel = CleanupViewModel()
    
    private var modelContext: ModelContext?
    private let importantDatesService = ImportantDatesService.shared
    
    var formattedCanFree: String {
        SpaceFormatting.string(from: canFreeSpace)
    }
    
    var formattedSpaceSaved: String {
        SpaceFormatting.string(from: totalSpaceSaved)
    }
    
    var formattedMetadataSize: String {
        SpaceFormatting.string(from: metadataSize)
    }
    
    var nextBatchBytes: Int64 {
        if inventory.todayBatchBytes > 0 {
            return inventory.todayBatchBytes
        }
        let photos = Array(cleanupViewModel.reviewQueue.prefix(DailyReviewBatch.size))
        if !photos.isEmpty {
            return photos.reduce(0) { $0 + $1.totalSize }
        }
        return metadataCategories.prefix(3).reduce(0) { $0 + $1.estimatedSize }
    }
    
    func refreshInventory() {
        guard let context = modelContext else { return }
        inventory = LibraryInventoryService.snapshot(from: context)
        canFreeSpace = inventory.totalReclaimableBytes
        cleanupItemCount = inventory.totalReclaimableItems
    }
    
    var topHumanReasons: [String] {
        metadataCategories.prefix(3).map(\.title)
    }
    
    var onThisDayPhotos: [PersistedPhoto]? {
        for card in feedCards {
            if case .onThisDay(let photos) = card.type {
                return photos
            }
        }
        return nil
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        cleanupViewModel.initialize(modelContext: modelContext)
        importantDatesService.initialize(modelContext: modelContext)
        
        loadSpaceSaved()
        if DesignTourSimulation.spaceSaved {
            totalSpaceSaved = DesignTourSimulation.previewSavedBytes
        }
        if DesignTourSimulation.emptyHome {
            metadataCategories = []
            feedCards = []
            canFreeSpace = 0
            cleanupItemCount = 0
            inventory = .empty
            return
        }
        // First paint must stay tappable. Inventory/makeQueue on a large
        // library used to freeze MainActor right after launch (266).
        Task { @MainActor in
            refreshInventory()
            loadMetadataCategories()
            await loadFeedCards()
        }
    }
    
    func refreshCategories() {
        refreshInventory()
        loadMetadataCategories()
        
        canFreeSpace = inventory.totalReclaimableBytes
        cleanupItemCount = inventory.totalReclaimableItems
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
        
        refreshInventory()
        canFreeSpace = inventory.totalReclaimableBytes
        cleanupItemCount = inventory.totalReclaimableItems
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
        
        refreshInventory()
        canFreeSpace = inventory.totalReclaimableBytes
        cleanupItemCount = inventory.totalReclaimableItems
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
        let batch = Array(photos.prefix(DailyReviewBatch.size))
        Task {
            for photo in batch {
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
    
    var isOnThisDay: Bool {
        if case .onThisDay = type { return true }
        return false
    }
    
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

enum DeviceStorage {
    struct Snapshot {
        let available: Int64
        let total: Int64
        var usedRatio: CGFloat {
            guard total > 0 else { return 0 }
            return min(1, CGFloat(total - available) / CGFloat(total))
        }
    }
    
    static func current() -> Snapshot {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])
        let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        return Snapshot(available: available, total: max(total, available))
    }
}

struct ScanClockIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    
    var body: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 36, weight: .medium, design: .rounded))
            .foregroundStyle(MomentsColors.accent)
            .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
            .animation(
                reduceMotion ? nil : .linear(duration: 2).repeatForever(autoreverses: false),
                value: spinning
            )
            .onAppear { spinning = !reduceMotion }
            .accessibilityIdentifier("home.scanClock.icon")
    }
}

struct TimelineViewClock: View {
    var body: some View {
        ScanClockIcon()
            .font(.body)
            .scaleEffect(0.45)
            .frame(width: 28, height: 28)
    }
}

struct ParallaxMemoryHero: View {
    let photos: [PersistedPhoto]
    let title: String
    
    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            ZStack(alignment: .bottomLeading) {
                if let first = photos.first {
                    AsyncPhotoThumbnail(localIdentifier: first.localIdentifier)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: 220 + max(0, minY / 8))
                        .clipped()
                        .offset(y: minY > 0 ? -minY / 6 : 0)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                Text(title)
                    .font(MomentsTypography.headlineLarge)
                    .foregroundStyle(.white)
                    .padding(MomentsSpacing.md)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: MomentsCorners.large))
        }
        .frame(height: 220)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: PersistedPhoto.self)
        .environmentObject(AppState())
}
