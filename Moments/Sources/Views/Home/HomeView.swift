// HomeView.swift
// Home feed with proactive cards - space savings, moments, cataloging

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("home.root")
                
                ScrollView {
                    VStack(spacing: MomentsSpacing.lg) {
                        // Header
                        headerSection
                        
                        // Space card
                        if viewModel.canFreeSpace > 0 {
                            spaceCard
                        }
                        
                        // Proactive cards feed
                        ForEach(viewModel.feedCards) { card in
                            FeedCardView(card: card, viewModel: viewModel)
                        }
                        
                        // Empty state when no content
                        if viewModel.canFreeSpace == 0 && viewModel.feedCards.isEmpty {
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
                    Text("Moments")
                        .font(MomentsTypography.headlineLarge)
                        .foregroundStyle(MomentsColors.textPrimary)
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
    
    // MARK: - Space Card
    
    private var spaceCard: some View {
        VStack(spacing: MomentsSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MomentsSpacing.xs) {
                    Text("Liberá espacio")
                        .font(MomentsTypography.headlineMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                    
                    Text("\(viewModel.cleanupItemCount) elementos para revisar")
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.formattedCanFree)
                        .font(MomentsTypography.numberMedium)
                        .foregroundStyle(MomentsColors.accent)
                    
                    Text("disponibles")
                        .font(MomentsTypography.labelSmall)
                        .foregroundStyle(MomentsColors.textTertiary)
                }
            }
            
            // Preview thumbnails
            if !viewModel.cleanupPreviewPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.cleanupPreviewPhotos, id: \.id) { photo in
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
                    Text("Revisar ahora")
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
                subtitle: "\(photos.count) fotos de esta fecha",
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

// MARK: - Home View Model

@MainActor
class HomeViewModel: ObservableObject {
    @Published var feedCards: [HomeFeedCard] = []
    @Published var canFreeSpace: Int64 = 0
    @Published var totalSpaceSaved: Int64 = 0
    @Published var cleanupItemCount: Int = 0
    @Published var cleanupPreviewPhotos: [PersistedPhoto] = []
    
    var cleanupViewModel = CleanupViewModel()
    
    private var modelContext: ModelContext?
    private let importantDatesService = ImportantDatesService.shared
    
    var formattedCanFree: String {
        ByteCountFormatter.string(fromByteCount: canFreeSpace, countStyle: .file)
    }
    
    var formattedSpaceSaved: String {
        ByteCountFormatter.string(fromByteCount: totalSpaceSaved, countStyle: .file)
    }
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        cleanupViewModel.initialize(modelContext: modelContext)
        importantDatesService.initialize(modelContext: modelContext)
        
        loadSpaceSaved()
        
        Task {
            await loadFeedCards()
        }
    }
    
    private func loadSpaceSaved() {
        totalSpaceSaved = Int64(UserDefaults.standard.integer(forKey: "totalSpaceSaved"))
    }
    
    private func loadFeedCards() async {
        guard let context = modelContext else { return }
        
        var cards: [HomeFeedCard] = []
        
        // Update cleanup stats
        canFreeSpace = cleanupViewModel.estimatedSpaceFreed
        cleanupItemCount = cleanupViewModel.totalCleanupItems
        cleanupPreviewPhotos = Array(cleanupViewModel.categories.flatMap { $0.photos }.prefix(10))
        
        // On This Day
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
        
        // Upcoming dates
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
        
        // Latest trip
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
        
        // Cataloging questions
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
        .preferredColorScheme(.dark)
        .modelContainer(for: PersistedPhoto.self)
}
