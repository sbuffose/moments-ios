// TimelineView.swift
// Vista de línea de tiempo

import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = TimelineViewModel()
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.sections.isEmpty {
                emptyStateView
            } else {
                timelineContent
            }
        }
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: MomentsSpacing.md) {
            ProgressView()
                .tint(MomentsColors.accent)
            Text("timeline_loading")
                .font(MomentsTypography.bodyMedium)
                .foregroundStyle(MomentsColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MomentsColors.bgPrimary.ignoresSafeArea())
    }
    
    private var emptyStateView: some View {
        VStack(spacing: MomentsSpacing.md) {
            Image(systemName: "calendar")
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .foregroundStyle(MomentsColors.accent)
            Text("timeline_empty_title")
                .font(MomentsTypography.headlineMedium)
                .foregroundStyle(MomentsColors.textPrimary)
            Text("timeline_empty_description")
                .font(MomentsTypography.bodyMedium)
                .foregroundStyle(MomentsColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MomentsSpacing.screenHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MomentsColors.bgPrimary.ignoresSafeArea())
    }
    
    private var timelineContent: some View {
        ScrollView {
            LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                // On This Day Section
                if !viewModel.onThisDayMemories.isEmpty {
                    onThisDaySection
                }
                
                if !viewModel.photoTags.isEmpty {
                    tagsSection
                }
                
                // Trips Section
                if !viewModel.trips.isEmpty {
                    tripsSection
                }
                
                // Timeline Sections
                ForEach(viewModel.sections) { section in
                    timelineSection(section)
                }
            }
            .padding()
        }
    }
    
    // MARK: - On This Day
    
    private var onThisDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(MomentsColors.accentSecondary)
                Text("timeline_on_this_day")
                    .font(MomentsTypography.headlineMedium)
                    .foregroundStyle(MomentsColors.textPrimary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.onThisDayMemories) { memory in
                        OnThisDayCard(memory: memory)
                    }
                }
            }
        }
        .padding(.bottom)
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundStyle(MomentsColors.accent)
                Text("Etiquetas")
                    .font(.headline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.photoTags, id: \.id) { tag in
                        Text(tag.name)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(MomentsColors.accent.opacity(0.14), in: Capsule())
                            .accessibilityIdentifier("moments.tag.\(tag.id)")
                            .accessibilityLabel(tag.name)
                    }
                }
            }
        }
        .padding(.bottom)
        .accessibilityIdentifier("moments.tags")
    }
    
    // MARK: - Trips
    
    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "airplane")
                    .foregroundStyle(.blue)
                Text("timeline_trips")
                    .font(.headline)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.trips) { trip in
                        TripCard(trip: trip)
                    }
                }
            }
        }
        .padding(.bottom)
    }
    
    // MARK: - Timeline Section
    
    private func timelineSection(_ section: TimelineViewModel.TimelineSectionItem) -> some View {
        Section {
            ForEach(section.moments) { moment in
                NavigationLink {
                    MomentDetailView(moment: moment)
                } label: {
                    MomentRow(moment: moment)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(moment.coverPhotoId == nil ? "moment.row" : "moment.row.thumb.loaded")
            }
        } header: {
            HStack {
                if let monthName = section.monthName {
                    Text("\(monthName) \(String(section.year))")
                        .font(.title3)
                        .fontWeight(.bold)
                } else {
                    Text("\(String(section.year))")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                Text("timeline_photos_count \(section.totalPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
        }
    }
}

// MARK: - Moment Row

struct MomentRow: View {
    let moment: TimelineViewModel.MomentItem
    
    var body: some View {
        HStack(spacing: 12) {
            if let coverPhotoId = moment.coverPhotoId {
                AsyncPhotoThumbnail(localIdentifier: coverPhotoId)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("moment.row.thumbnail")
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(moment.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let locationName = moment.locationName {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                        Text(locationName)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Label("\(moment.photoCount)", systemImage: "photo")
                    
                    if moment.durationDays > 1 {
                        Label("\(moment.durationDays) días", systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if moment.isTrip {
                Image(systemName: "airplane")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(moment.coverPhotoId == nil ? "moment.row" : "moment.row.thumb.loaded")
    }
}

// MARK: - On This Day Card

struct OnThisDayCard: View {
    let memory: TimelineViewModel.OnThisDayMemoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let firstPhoto = memory.photos.first {
                AsyncPhotoThumbnail(localIdentifier: firstPhoto.localIdentifier)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Text(memory.yearsAgo == 1 ? "Hace 1 año" : "Hace \(memory.yearsAgo) años")
                .font(.caption)
                .fontWeight(.medium)
            
            Text(MomentsPluralization.photos(memory.photos.count))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 150)
    }
}

// MARK: - Trip Card

struct TripCard: View {
    let trip: TimelineViewModel.TripItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let coverPhotoId = trip.coverPhotoId {
                AsyncPhotoThumbnail(localIdentifier: coverPhotoId)
                    .frame(width: 200, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.black.opacity(0.5), .clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading) {
                            Text(trip.destination)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(8)
                    }
            }
            
            let formatter = DateFormatter()
            HStack {
                Text(formatDateRange(trip.startDate, trip.endDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(MomentsPluralization.photos(trip.photoCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 200)
    }
    
    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

// MARK: - Moment Detail View

struct MomentDetailView: View {
    let moment: TimelineViewModel.MomentItem
    
    @Environment(\.modelContext) private var modelContext
    @State private var photos: [PersistedPhoto] = []
    @State private var selectedPhoto: PersistedPhoto?
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(moment.title)
                        .font(MomentsTypography.displaySmall)
                        .foregroundStyle(MomentsColors.textPrimary)
                    
                    if let subtitle = moment.subtitle {
                        Text(subtitle)
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                    
                    HStack {
                        Image(systemName: "calendar")
                        Text(formatDate(moment.startDate))
                        
                        if let locationName = moment.locationName {
                            Text("·")
                            Image(systemName: "location.fill")
                            Text(locationName)
                        }
                    }
                    .font(MomentsTypography.labelMedium)
                    .foregroundStyle(MomentsColors.textSecondary)
                }
                .padding(.horizontal)
                
                // Photo Grid
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos, id: \.id) { photo in
                        PhotoGridItem(photo: photo) {
                            selectedPhoto = photo
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(MomentsColors.bgPrimary.ignoresSafeArea())
        .accessibilityIdentifier("moments.detail")
        .task {
            await loadPhotos()
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
    }
    
    private func loadPhotos() async {
        let ids = moment.photoIds
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        
        do {
            var fetchedPhotos = try modelContext.fetch(descriptor)
            fetchedPhotos.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            photos = fetchedPhotos
        } catch {
            print("Error loading moment photos: \(error)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Photo Detail View

struct PhotoDetailView: View {
    let photo: PersistedPhoto
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            AsyncFullPhoto(localIdentifier: photo.localIdentifier)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    TimelineView()
        .modelContainer(for: PersistedPhoto.self)
}
