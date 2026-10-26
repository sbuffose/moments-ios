// SearchView.swift
// Vista de búsqueda con barra de búsqueda, filtros y resultados

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var searchService = SearchService()
    @StateObject private var viewModel = SearchViewModel()
    
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var selectedFilters = SearchService.SearchFilters()
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar and filters
                searchHeader
                
                // Content
                if searchText.isEmpty && selectedFilters.isEmpty {
                    emptySearchView
                } else if searchService.isSearching {
                    loadingView
                } else if viewModel.results.isEmpty {
                    noResultsView
                } else {
                    resultsView
                }
            }
            .navigationTitle(Text("search_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            searchService.initialize(modelContext: modelContext)
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await performSearch()
            }
        }
        .onChange(of: selectedFilters) { _, _ in
            Task {
                await performSearch()
            }
        }
    }
    
    // MARK: - Search Header
    
    private var searchHeader: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("search_placeholder", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isSearchFocused)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                Button {
                    showFilters.toggle()
                } label: {
                    Image(systemName: selectedFilters.isEmpty ? "slider.horizontal.3" : "slider.horizontal.3")
                        .foregroundStyle(selectedFilters.isEmpty ? .secondary : .tint)
                }
            }
            .padding(.horizontal)
            
            // Filter chips
            if !selectedFilters.isEmpty || showFilters {
                filterChipsView
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Filter Chips
    
    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Date filters
                FilterChip(
                    title: "search_filter_today",
                    isSelected: selectedFilters.dateRange == .today,
                    action: {
                        selectedFilters.dateRange = selectedFilters.dateRange == .today ? nil : .today
                    }
                )
                
                FilterChip(
                    title: "search_filter_this_week",
                    isSelected: selectedFilters.dateRange == .thisWeek,
                    action: {
                        selectedFilters.dateRange = selectedFilters.dateRange == .thisWeek ? nil : .thisWeek
                    }
                )
                
                FilterChip(
                    title: "search_filter_this_month",
                    isSelected: selectedFilters.dateRange == .thisMonth,
                    action: {
                        selectedFilters.dateRange = selectedFilters.dateRange == .thisMonth ? nil : .thisMonth
                    }
                )
                
                FilterChip(
                    title: "search_filter_this_year",
                    isSelected: selectedFilters.dateRange == .thisYear,
                    action: {
                        selectedFilters.dateRange = selectedFilters.dateRange == .thisYear ? nil : .thisYear
                    }
                )
                
                Divider()
                    .frame(height: 20)
                
                // Type filters
                FilterChip(
                    title: "search_filter_photos",
                    icon: "photo",
                    isSelected: selectedFilters.types.contains(.photo),
                    action: {
                        toggleTypeFilter(.photo)
                    }
                )
                
                FilterChip(
                    title: "search_filter_videos",
                    icon: "video",
                    isSelected: selectedFilters.types.contains(.video),
                    action: {
                        toggleTypeFilter(.video)
                    }
                )
                
                FilterChip(
                    title: "search_filter_screenshots",
                    icon: "rectangle.on.rectangle",
                    isSelected: selectedFilters.types.contains(.screenshot),
                    action: {
                        toggleTypeFilter(.screenshot)
                    }
                )
                
                FilterChip(
                    title: "search_filter_documents",
                    icon: "doc.text",
                    isSelected: selectedFilters.types.contains(.document),
                    action: {
                        toggleTypeFilter(.document)
                    }
                )
            }
            .padding(.horizontal)
        }
    }
    
    private func toggleTypeFilter(_ type: SearchService.SearchFilters.PhotoType) {
        if selectedFilters.types.contains(type) {
            selectedFilters.types.removeAll { $0 == type }
        } else {
            selectedFilters.types.append(type)
        }
    }
    
    // MARK: - Empty Search View
    
    private var emptySearchView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Suggestions
                VStack(alignment: .leading, spacing: 12) {
                    Text("search_suggestions_title")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        SearchSuggestionButton(title: "search_suggestion_beach", icon: "sun.max") {
                            searchText = "playa"
                        }
                        SearchSuggestionButton(title: "search_suggestion_food", icon: "fork.knife") {
                            searchText = "comida"
                        }
                        SearchSuggestionButton(title: "search_suggestion_family", icon: "person.2") {
                            searchText = "familia"
                        }
                        SearchSuggestionButton(title: "search_suggestion_travel", icon: "airplane") {
                            searchText = "viaje"
                        }
                        SearchSuggestionButton(title: "search_suggestion_receipts", icon: "receipt") {
                            searchText = "ticket"
                        }
                        SearchSuggestionButton(title: "search_suggestion_pets", icon: "pawprint") {
                            searchText = "perro"
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Recent searches
                if !searchService.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("search_recent_title")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button("search_clear_recent") {
                                searchService.clearRecentSearches()
                            }
                            .font(.caption)
                        }
                        .padding(.horizontal)
                        
                        ForEach(searchService.recentSearches, id: \.self) { query in
                            Button {
                                searchText = query
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    
                                    Text(query)
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.top)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Text("search_searching")
                .foregroundStyle(.secondary)
                .padding(.top)
            Spacer()
        }
    }
    
    // MARK: - No Results View
    
    private var noResultsView: some View {
        ContentUnavailableView {
            Label("search_no_results_title", systemImage: "magnifyingglass")
        } description: {
            Text("search_no_results_description \(searchText)")
        }
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("search_results_count \(viewModel.results.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
                    ForEach(viewModel.results) { result in
                        NavigationLink {
                            PhotoDetailView(photo: result.photo)
                        } label: {
                            SearchResultCell(result: result)
                        }
                    }
                }
            }
            .padding(.top)
        }
    }
    
    // MARK: - Search
    
    private func performSearch() async {
        let results = await searchService.search(query: searchText, filters: selectedFilters)
        await MainActor.run {
            viewModel.results = results
        }
    }
}

// MARK: - Search Result Cell

struct SearchResultCell: View {
    let result: SearchService.SearchResult
    
    var body: some View {
        AsyncPhotoThumbnail(localIdentifier: result.photo.localIdentifier)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if !result.matchedFields.isEmpty {
                    matchIndicator
                }
            }
    }
    
    @ViewBuilder
    private var matchIndicator: some View {
        HStack(spacing: 2) {
            ForEach(Array(Set(result.matchedFields.map { fieldIcon($0) })).prefix(3), id: \.self) { icon in
                Image(systemName: icon)
                    .font(.caption2)
            }
        }
        .foregroundStyle(.white)
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        .padding(4)
    }
    
    private func fieldIcon(_ field: SearchService.SearchResult.MatchedField) -> String {
        switch field {
        case .label: return "tag"
        case .ocr: return "text.viewfinder"
        case .place: return "mappin"
        case .date: return "calendar"
        case .person: return "person"
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: LocalizedStringKey
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - Search Suggestion Button

struct SearchSuggestionButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Photo Detail View (placeholder)

struct PhotoDetailView: View {
    let photo: PersistedPhoto
    
    var body: some View {
        VStack {
            AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier, targetSize: CGSize(width: 600, height: 600))
                .aspectRatio(contentMode: .fit)
            
            if let date = photo.creationDate {
                Text(date, style: .date)
                    .foregroundStyle(.secondary)
            }
            
            if let placeName = photo.placeName {
                Label(placeName, systemImage: "mappin")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Foto")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - View Model

@MainActor
class SearchViewModel: ObservableObject {
    @Published var results: [SearchService.SearchResult] = []
}

#Preview {
    SearchView()
        .modelContainer(for: PersistedPhoto.self)
}
