// AssistantView.swift
// Conversational assistant with command bar and rich cards

import SwiftUI
import SwiftData

struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var viewModel = AssistantViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ZStack {
            // Background
            MomentsColors.bgPrimary.ignoresSafeArea()
            
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("assistant.root")
                .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // Messages/Cards feed
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: MomentsSpacing.md) {
                            ForEach(viewModel.messages) { message in
                                MessageView(message: message, viewModel: viewModel)
                                    .id(message.id)
                            }
                            
                            if viewModel.isProcessing {
                                HStack {
                                    MomentsLoadingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal, MomentsSpacing.screenHorizontal)
                            }
                        }
                        .padding(.vertical, MomentsSpacing.md)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Keep chips on-screen so Asistente stays tappable during analysis
                // even after the welcome message arrives.
                if viewModel.messages.count <= 2 || isInputFocused {
                    suggestionsView
                }
                
                // Input bar
                inputBar
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant.root")
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
        }
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(MomentsColors.cardBorder)
            
            HStack(spacing: MomentsSpacing.sm) {
                // Text field
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(MomentsColors.accent)
                    
                    TextField("Preguntame algo...", text: $inputText)
                        .font(MomentsTypography.bodyMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .accessibilityIdentifier("assistant.input")
                        .onSubmit {
                            sendMessage()
                        }
                }
                .padding(.horizontal, MomentsSpacing.md)
                .padding(.vertical, MomentsSpacing.sm)
                .background(MomentsColors.bgTertiary)
                .cornerRadius(24)
                
                // Send button
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            inputText.isEmpty 
                                ? MomentsColors.textTertiary 
                                : MomentsColors.accent
                        )
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, MomentsSpacing.screenHorizontal)
            .padding(.vertical, MomentsSpacing.sm)
            .background(MomentsColors.bgSecondary)
        }
    }
    
    // MARK: - Suggestions
    
    private var suggestionsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MomentsSpacing.xs) {
                ForEach(viewModel.suggestions, id: \.self) { suggestion in
                    Button {
                        MomentsHaptics.selection()
                        inputText = suggestion
                        sendMessage()
                    } label: {
                        Text(suggestion)
                            .font(MomentsTypography.bodySmall)
                            .foregroundStyle(MomentsColors.textPrimary)
                            .padding(.horizontal, MomentsSpacing.sm)
                            .padding(.vertical, MomentsSpacing.xs)
                            .background(MomentsColors.bgTertiary)
                            .cornerRadius(16)
                    }
                    .accessibilityIdentifier("assistant.suggestion")
                }
            }
            .padding(.horizontal, MomentsSpacing.screenHorizontal)
            .padding(.vertical, MomentsSpacing.xs)
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        MomentsHaptics.light()
        
        let text = inputText
        inputText = ""
        isInputFocused = false
        
        Task {
            await viewModel.processMessage(text)
        }
    }
}

// MARK: - Message View

struct MessageView: View {
    let message: AssistantMessage
    @ObservedObject var viewModel: AssistantViewModel
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: MomentsSpacing.sm) {
            // Text bubble
            if let text = message.text, !text.isEmpty {
                AssistantMessageBubble(message: text, isUser: message.isUser)
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
            }
            
            // Rich card
            if let card = message.card {
                cardView(for: card)
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
            }
        }
    }
    
    @ViewBuilder
    private func cardView(for card: AssistantCard) -> some View {
        switch card {
        case .photoGrid(let title, let subtitle, let photos):
            PhotoGridCard(
                title: title,
                subtitle: subtitle,
                photos: photos,
                action: { viewModel.expandPhotoGrid(photos) }
            )
            
        case .cleanup(let title, let count, let size, let photos, let category):
            let batchPhotos = Array(photos.prefix(DailyReviewBatch.size))
            let batchBytes = batchPhotos.reduce(Int64(0)) { $0 + ($1.estimatedFileSize ?? 0) }
            CleanupBatchCard(
                title: title,
                itemCount: min(count, DailyReviewBatch.size),
                estimatedSize: SpaceFormatting.string(from: batchBytes),
                photos: batchPhotos,
                onReview: { viewModel.reviewCleanup(category: category) },
                onQuickDelete: { viewModel.quickDelete(photos: batchPhotos) },
                totalCount: count,
                totalSize: size
            )
            
        case .dateReminder(let date, let photos):
            DateReminderCard(
                importantDate: date,
                previewPhotos: photos,
                onTap: { viewModel.showDateMemories(date) },
                onAddCalendar: { viewModel.addToCalendar(date) }
            )
            
        case .spaceInfo(let canFree, let saved, let items):
            spaceInfoCard(canFree: canFree, saved: saved, items: items)
            
        case .catalogQuestion(let question, let subtitle, let photos, let options):
            CatalogingQuestionCard(
                question: question,
                subtitle: subtitle,
                photos: photos,
                options: options.map { opt in
                    CatalogingQuestionCard.CatalogOption(
                        title: opt.title,
                        action: { viewModel.answerCatalogQuestion(opt.id) }
                    )
                },
                onDismiss: { viewModel.dismissCatalogQuestion() }
            )
            
        case .memory(let title, let subtitle, let photos):
            memoryCard(title: title, subtitle: subtitle, photos: photos)
        }
    }
    
    private func spaceInfoCard(canFree: String, saved: String, items: Int) -> some View {
        HStack(spacing: MomentsSpacing.md) {
            SpaceStatCard(
                title: "Podés liberar",
                value: canFree,
                subtitle: "\(items) elementos",
                icon: "externaldrive.badge.minus",
                color: .blue
            )
            
            SpaceStatCard(
                title: "Ya liberaste",
                value: saved,
                subtitle: nil,
                icon: "checkmark.seal.fill",
                color: .green
            )
        }
    }
    
    private func memoryCard(title: String, subtitle: String?, photos: [PersistedPhoto]) -> some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.sm) {
            Text(title)
                .font(MomentsTypography.headlineMedium)
                .foregroundStyle(MomentsColors.textPrimary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(MomentsTypography.bodySmall)
                    .foregroundStyle(MomentsColors.textSecondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos.prefix(10), id: \.id) { photo in
                        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                            .frame(width: 120, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            
            Button {
                MomentsHaptics.light()
                viewModel.expandPhotoGrid(photos)
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Ver todo")
                }
            }
            .momentsSecondaryButton()
        }
        .momentsCard()
        .accessibilityIdentifier("assistant.answerCard")
    }
}

// MARK: - Assistant View Model

@MainActor
class AssistantViewModel: ObservableObject {
    @Published var messages: [AssistantMessage] = []
    @Published var isProcessing = false
    @Published var suggestions: [String] = []
    
    private var modelContext: ModelContext?
    private let intentParser = IntentParserService.shared
    private let cleanupViewModel = CleanupViewModel()
    private let importantDatesService = ImportantDatesService.shared
    
    private let defaultSuggestions = [
        "¿Cuánto espacio puedo liberar?",
        "Borrá las capturas de más de 3 meses",
        "Mostrame las fotos del último viaje",
        "¿Cuándo es el cumple de Sofía?",
        "Armame un recuerdo de las vacaciones"
    ]
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        suggestions = defaultSuggestions
        intentParser.initialize(modelContext: modelContext)
        cleanupViewModel.initialize(modelContext: modelContext)
        importantDatesService.initialize(modelContext: modelContext)
        
        Task {
            await loadProactiveCards()
        }
    }
    
    // MARK: - Process Message
    
    func processMessage(_ text: String) async {
        let userMessage = AssistantMessage(text: text, isUser: true)
        messages.append(userMessage)
        
        isProcessing = true
        
        let intent = await intentParser.parseIntent(text)
        
        let response = await handleIntent(intent)
        messages.append(response)
        
        isProcessing = false
    }
    
    // MARK: - Handle Intent
    
    private func handleIntent(_ intent: MomentsIntent) async -> AssistantMessage {
        switch intent {
        case .checkSpace:
            return handleCheckSpace()
            
        case .cleanup(let category, let olderThan):
            return await handleCleanup(category: category, olderThan: olderThan)
            
        case .search(let query, let filters):
            return await handleSearch(query: query, filters: filters)
            
        case .showDate(let personName):
            return await handleShowDate(personName: personName)
            
        case .showUpcomingDates:
            return await handleUpcomingDates()
            
        case .createMemory(let query):
            return await handleCreateMemory(query: query)
            
        case .showPhotos(let location, let date, let people):
            return await handleShowPhotos(location: location, date: date, people: people)
            
        case .showPerson(let name):
            return await handleShowPerson(name: name)
            
        case .monthlyRecap(let month, let year):
            return await handleMonthlyRecap(month: month, year: year)
            
        case .unknown(let text):
            return AssistantMessage(
                text: "No entendí bien. Probá preguntándome sobre tus fotos, espacio o fechas importantes.",
                isUser: false
            )
        }
    }
    
    private func handleMonthlyRecap(month: Int?, year: Int?) async -> AssistantMessage {
        let calendar = Calendar.current
        let now = Date()
        let resolvedMonth = month ?? calendar.component(.month, from: now)
        let resolvedYear = year ?? calendar.component(.year, from: now)
        let stats = MonthlyRecapService.statsSummary(month: resolvedMonth, year: resolvedYear, context: modelContext)
        let monthName = MonthlyRecapService.monthName(resolvedMonth)
        let narrative = await FoundationModelsClient.recapNarrative(monthName: monthName, stats: stats)
            ?? MonthlyRecapService.fallbackNarrative(monthName: monthName, stats: stats)
        return AssistantMessage(text: narrative, isUser: false)
    }
    
    private func handleCheckSpace() -> AssistantMessage {
        let inventory = modelContext.map { LibraryInventoryService.snapshot(from: $0) } ?? .empty
        let canFree = cleanupViewModel.formattedSize(inventory.totalReclaimableBytes)
        let saved = cleanupViewModel.formattedSize(Int64(UserDefaults.standard.integer(forKey: "totalSpaceSaved")))
        let items = inventory.totalReclaimableItems
        
        return AssistantMessage(
            text: "En el lote de hoy: \(cleanupViewModel.formattedSize(inventory.todayBatchBytes)) · en total podés liberar \(canFree)",
            isUser: false,
            card: .spaceInfo(canFree: canFree, saved: saved, items: items)
        )
    }
    
    private func handleCleanup(category: CleanupCategoryType?, olderThan: Date?) async -> AssistantMessage {
        guard let context = modelContext else {
            return AssistantMessage(text: "Error al acceder a las fotos.", isUser: false)
        }
        
        var photos: [PersistedPhoto] = []
        var title = "Fotos para limpiar"
        
        if let cat = category {
            let matchingCategory = cleanupViewModel.categories.first { $0.category == cat }
            photos = matchingCategory?.photos ?? []
            title = cat.displayName
        } else {
            photos = cleanupViewModel.categories.flatMap { $0.photos }
        }
        
        if let olderThan = olderThan {
            photos = photos.filter { ($0.creationDate ?? Date()) < olderThan }
            title += " (más antiguas)"
        }
        
        guard !photos.isEmpty else {
            return AssistantMessage(
                text: "No encontré fotos que coincidan con eso. ¡Tu biblioteca está bastante ordenada!",
                isUser: false
            )
        }
        
        let totalSizeBytes = photos.reduce(0) { $0 + ($1.estimatedFileSize ?? 0) }
        let size = cleanupViewModel.formattedSize(totalSizeBytes)
        let batch = Array(photos.prefix(DailyReviewBatch.size))
        
        return AssistantMessage(
            text: "Encontré \(photos.count) elementos. Te muestro el lote de hoy (\(batch.count)):",
            isUser: false,
            card: .cleanup(
                title: title,
                count: photos.count,
                size: size,
                photos: batch,
                category: category
            )
        )
    }
    
    private func handleSearch(query: String, filters: MomentsIntent.SearchFilters) async -> AssistantMessage {
        guard let context = modelContext else {
            return AssistantMessage(text: "Error al buscar.", isUser: false)
        }
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.analysisCompleted }
        )
        
        guard let allPhotos = try? context.fetch(descriptor) else {
            return AssistantMessage(text: "Error al buscar fotos.", isUser: false)
        }
        
        var results = allPhotos
        
        // Filter by location
        if let location = filters.location {
            let loc = location.lowercased()
            results = results.filter { photo in
                (photo.placeCity?.lowercased().contains(loc) ?? false) ||
                (photo.placeName?.lowercased().contains(loc) ?? false) ||
                (photo.placeCountry?.lowercased().contains(loc) ?? false)
            }
        }
        
        // Filter by date range
        if let dateRange = filters.dateRange {
            results = results.filter { photo in
                guard let date = photo.creationDate else { return false }
                return dateRange.contains(date)
            }
        }
        
        // Filter by query in labels
        let queryTerms = query.lowercased().split(separator: " ").map(String.init)
        if !queryTerms.isEmpty {
            results = results.filter { photo in
                let searchable = photo.searchableText
                return queryTerms.contains { searchable.contains($0) }
            }
        }
        
        results.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        
        guard !results.isEmpty else {
            return AssistantMessage(
                text: "No encontré fotos que coincidan con \"\(query)\". Probá con otros términos.",
                isUser: false
            )
        }
        
        let title = await MemoryTitleGenerator.shared.generateTitle(for: Array(results.prefix(20)))
        let subtitle = await MemoryTitleGenerator.shared.generateSummary(for: results)
        
        return AssistantMessage(
            text: "Encontré \(MomentsPluralization.photos(results.count)):",
            isUser: false,
            card: .photoGrid(
                title: title,
                subtitle: subtitle,
                photos: Array(results.prefix(9))
            )
        )
    }
    
    private func handleShowDate(personName: String?) async -> AssistantMessage {
        await importantDatesService.loadDetectedDates()
        
        if let name = personName {
            let searchName = name.lowercased()
            if let date = importantDatesService.detectedDates.first(where: {
                $0.personName?.lowercased().contains(searchName) ?? false
            }) {
                let photos = await getPhotosForDate(date)
                
                if let days = date.daysUntilNext {
                    let daysText = days == 0 ? "¡hoy!" : (days == 1 ? "mañana" : "en \(days) días")
                    return AssistantMessage(
                        text: "El cumpleaños de \(date.personName ?? name) es el \(date.displayDate), \(daysText)",
                        isUser: false,
                        card: .dateReminder(date: date, photos: photos)
                    )
                }
            }
            
            return AssistantMessage(
                text: "No tengo registrado el cumpleaños de \(name). ¿Querés agregarlo?",
                isUser: false
            )
        }
        
        return await handleUpcomingDates()
    }
    
    private func handleUpcomingDates() async -> AssistantMessage {
        let upcoming = await importantDatesService.getUpcomingDates(withinDays: 30)
        
        guard let next = upcoming.first else {
            return AssistantMessage(
                text: "No tenés fechas importantes en los próximos 30 días. ¡Un buen momento para agregar algunas!",
                isUser: false
            )
        }
        
        let photos = await getPhotosForDate(next)
        
        return AssistantMessage(
            text: "Tu próxima fecha importante:",
            isUser: false,
            card: .dateReminder(date: next, photos: photos)
        )
    }
    
    private func handleCreateMemory(query: String) async -> AssistantMessage {
        guard let context = modelContext else {
            return AssistantMessage(text: "Error al crear recuerdo.", isUser: false)
        }
        
        // Search for photos matching query
        let intent = await intentParser.parseIntent(query)
        
        if case .search(_, let filters) = intent {
            let response = await handleSearch(query: query, filters: filters)
            
            if case .photoGrid(let title, let subtitle, let photos) = response.card {
                return AssistantMessage(
                    text: "Armé este recuerdo para vos:",
                    isUser: false,
                    card: .memory(title: title, subtitle: subtitle, photos: photos)
                )
            }
        }
        
        return AssistantMessage(
            text: "No encontré suficientes fotos para crear un recuerdo de \"\(query)\". Probá con otra descripción.",
            isUser: false
        )
    }
    
    private func handleShowPhotos(location: String?, date: DateInterval?, people: [String]?) async -> AssistantMessage {
        var filters = MomentsIntent.SearchFilters()
        filters.location = location
        filters.dateRange = date
        filters.people = people
        
        return await handleSearch(query: "", filters: filters)
    }
    
    private func handleShowPerson(name: String) async -> AssistantMessage {
        guard let context = modelContext else {
            return AssistantMessage(text: "Error al buscar.", isUser: false)
        }
        
        let descriptor = FetchDescriptor<PersistedPerson>()
        guard let people = try? context.fetch(descriptor) else {
            return AssistantMessage(text: "Error al buscar personas.", isUser: false)
        }
        
        let searchName = name.lowercased()
        if let person = people.first(where: { $0.name?.lowercased().contains(searchName) ?? false }) {
            let photoIds = person.photoIdArray
            
            let photoDescriptor = FetchDescriptor<PersistedPhoto>()
            guard let allPhotos = try? context.fetch(photoDescriptor) else {
                return AssistantMessage(text: "Error al cargar fotos.", isUser: false)
            }
            
            let personPhotos = allPhotos.filter { photoIds.contains($0.id) }
            
            return AssistantMessage(
                text: "Fotos de \(person.name ?? name):",
                isUser: false,
                card: .photoGrid(
                    title: person.name ?? name,
                    subtitle: MomentsPluralization.photos(personPhotos.count),
                    photos: Array(personPhotos.prefix(9))
                )
            )
        }
        
        return AssistantMessage(
            text: "No encontré a nadie llamado \"\(name)\" en tus fotos.",
            isUser: false
        )
    }
    
    // MARK: - Helpers
    
    private func getPhotosForDate(_ date: PersistedImportantDate) async -> [PersistedPhoto] {
        guard let context = modelContext else { return [] }
        
        let photoIds = date.photoIdArray
        let descriptor = FetchDescriptor<PersistedPhoto>()
        
        guard let allPhotos = try? context.fetch(descriptor) else { return [] }
        
        return allPhotos.filter { photoIds.contains($0.id) }
    }
    
    // MARK: - Proactive Cards
    
    private func loadProactiveCards() async {
        // Add welcome message
        let welcomeMessage = AssistantMessage(
            text: "¡Hola! Soy tu asistente de Moments. Preguntame sobre tus fotos, fechas importantes, o decime qué querés limpiar.",
            isUser: false
        )
        messages.append(welcomeMessage)
        
        // Check for cleanup suggestions
        if let context = modelContext {
            await cleanupViewModel.loadCleanupSuggestions()
            let inventory = LibraryInventoryService.snapshot(from: context)
            if inventory.totalReclaimableItems > 0 {
                let topCategory = cleanupViewModel.categories.first
                let title = topCategory?.category.displayName ?? "Fotos para limpiar"
                let size = cleanupViewModel.formattedSize(inventory.totalReclaimableBytes)
                let preview = topCategory.map { Array($0.photos.prefix(DailyReviewBatch.size)) }
                    ?? []
                
                let cleanupMessage = AssistantMessage(
                    text: "Encontré algunas fotos que podrías limpiar. El lote de hoy son \(inventory.todayBatchItems):",
                    isUser: false,
                    card: .cleanup(
                        title: title,
                        count: inventory.totalReclaimableItems,
                        size: size,
                        photos: preview,
                        category: topCategory?.category
                    )
                )
                messages.append(cleanupMessage)
            }
        }
        
        // Check for upcoming dates
        let upcoming = await importantDatesService.getUpcomingDates(withinDays: 7)
        if let next = upcoming.first {
            let photos = await getPhotosForDate(next)
            
            let dateMessage = AssistantMessage(
                text: "No te olvides de esta fecha:",
                isUser: false,
                card: .dateReminder(date: next, photos: photos)
            )
            messages.append(dateMessage)
        }
        
        if let context = modelContext {
            CatalogingService.shared.initialize(modelContext: context)
            for prompt in CatalogingService.shared.frequentUnnamedPrompts() {
                messages.append(prompt)
            }
        }
    }
    
    // MARK: - Card Actions
    
    func expandPhotoGrid(_ photos: [PersistedPhoto]) {
        // Navigate to full photo grid
        MomentsHaptics.light()
    }
    
    func reviewCleanup(category: CleanupCategoryType?) {
        MomentsHaptics.light()
        // Navigate to cleanup review
    }
    
    func quickDelete(photos: [PersistedPhoto]) {
        MomentsHaptics.success()
        let batch = Array(photos.prefix(DailyReviewBatch.size))
        Task {
            for photo in batch {
                cleanupViewModel.selectedPhotos.insert(photo.id)
            }
            await cleanupViewModel.deleteSelectedPhotos()
            
            let response = AssistantMessage(
                text: "¡Listo! Eliminé \(batch.count) elementos del lote de hoy y liberé espacio.",
                isUser: false
            )
            messages.append(response)
        }
    }
    
    func showDateMemories(_ date: PersistedImportantDate) {
        MomentsHaptics.light()
        // Navigate to memory reel
    }
    
    func addToCalendar(_ date: PersistedImportantDate) {
        MomentsHaptics.success()
        Task {
            let calendarService = CalendarService.shared
            calendarService.initialize(modelContext: modelContext!)
            let success = await calendarService.addToCalendar(importantDate: date)
            
            let response = AssistantMessage(
                text: success ? "¡Agregado al calendario!" : "No pude agregar al calendario. ¿Me das permiso?",
                isUser: false
            )
            messages.append(response)
        }
    }
    
    func answerCatalogQuestion(_ optionId: String) {
        MomentsHaptics.selection()
        guard let context = modelContext else { return }
        CatalogingService.shared.initialize(modelContext: context)
        CatalogingService.shared.applyAnswer(optionId)
        messages.append(AssistantMessage(text: "Listo, lo guardé en tu catálogo.", isUser: false))
    }
    
    func dismissCatalogQuestion() {
        MomentsHaptics.light()
    }
}

// MARK: - Assistant Message Model

struct AssistantMessage: Identifiable {
    let id = UUID()
    let text: String?
    let isUser: Bool
    var card: AssistantCard?
    
    init(text: String?, isUser: Bool, card: AssistantCard? = nil) {
        self.text = text
        self.isUser = isUser
        self.card = card
    }
}

enum AssistantCard {
    case photoGrid(title: String, subtitle: String?, photos: [PersistedPhoto])
    case cleanup(title: String, count: Int, size: String, photos: [PersistedPhoto], category: CleanupCategoryType?)
    case dateReminder(date: PersistedImportantDate, photos: [PersistedPhoto])
    case spaceInfo(canFree: String, saved: String, items: Int)
    case catalogQuestion(question: String, subtitle: String?, photos: [PersistedPhoto], options: [CatalogOption])
    case memory(title: String, subtitle: String?, photos: [PersistedPhoto])
    
    struct CatalogOption {
        let id: String
        let title: String
    }
}

#Preview {
    AssistantView()
        .modelContainer(for: PersistedPhoto.self)
}
