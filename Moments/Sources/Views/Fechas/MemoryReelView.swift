// MemoryReelView.swift
// Vista de recuerdos de años anteriores para fechas importantes

import SwiftUI
import SwiftData
import Photos

struct MemoryReelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let importantDate: PersistedImportantDate
    
    @StateObject private var importantDatesService = ImportantDatesService.shared
    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var notificationService = NotificationService.shared
    
    @State private var photosByYear: [Int: [PersistedPhoto]] = [:]
    @State private var isLoading = true
    @State private var selectedYear: Int?
    @State private var showCalendarConfirmation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    if isLoading {
                        loadingView
                    } else if photosByYear.isEmpty {
                        emptyView
                    } else {
                        memoriesSection
                    }
                    
                    actionsSection
                }
                .padding()
            }
            .navigationTitle(Text("memory_reel_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("memory_reel_added_to_calendar", isPresented: $showCalendarConfirmation) {
                Button("OK", role: .cancel) {}
            }
        }
        .onAppear {
            importantDatesService.initialize(modelContext: modelContext)
            calendarService.initialize(modelContext: modelContext)
            notificationService.initialize(modelContext: modelContext)
            Task {
                await loadPhotos()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(colorForDateType.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: importantDate.dateType.iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(colorForDateType)
            }
            
            VStack(spacing: 8) {
                Text(titleText)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let days = importantDate.daysUntilNext {
                    Text(daysText(days))
                        .font(.headline)
                        .foregroundStyle(colorForDateType)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("memory_reel_loading")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }
    
    // MARK: - Empty
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("memory_reel_no_photos")
                .font(.headline)
            
            Text("memory_reel_no_photos_description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
    }
    
    // MARK: - Memories
    
    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("memory_reel_memories_title")
                .font(.headline)
            
            ForEach(sortedYears, id: \.self) { year in
                YearMemorySection(
                    year: year,
                    photos: photosByYear[year] ?? [],
                    importantDate: importantDate
                )
            }
        }
    }
    
    private var sortedYears: [Int] {
        photosByYear.keys.sorted(by: >)
    }
    
    // MARK: - Actions
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.vertical)
            
            if !calendarService.hasCalendarEvent(for: importantDate) {
                Button {
                    Task {
                        let success = await calendarService.addToCalendar(importantDate: importantDate)
                        if success {
                            showCalendarConfirmation = true
                        }
                    }
                } label: {
                    Label("memory_reel_add_calendar", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("memory_reel_in_calendar")
                        .foregroundStyle(.secondary)
                }
            }
            
            if importantDate.notificationEnabled {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.orange)
                    Text("memory_reel_notifications_on")
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        notificationService.disableNotification(for: importantDate.id)
                    } label: {
                        Text("memory_reel_turn_off")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            } else {
                Button {
                    Task {
                        if notificationService.authorizationStatus != .authorized {
                            _ = await notificationService.requestAuthorization()
                        }
                        await notificationService.enableNotification(for: importantDate.id)
                    }
                } label: {
                    Label("memory_reel_enable_notifications", systemImage: "bell.badge.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var colorForDateType: Color {
        switch importantDate.dateType {
        case .birthday: return .pink
        case .wedding, .anniversary: return .red
        case .childBirthday: return .orange
        case .other: return .blue
        }
    }
    
    private var titleText: String {
        let emoji = importantDate.dateType.notificationEmoji
        switch importantDate.dateType {
        case .birthday, .childBirthday:
            return "\(emoji) Cumpleaños de \(importantDate.displayName)"
        case .wedding:
            return "\(emoji) Boda de \(importantDate.displayName)"
        case .anniversary:
            return "\(emoji) Aniversario de \(importantDate.displayName)"
        case .other:
            return importantDate.displayName
        }
    }
    
    private var subtitleText: String {
        let date = importantDate.displayDate
        switch importantDate.dateType {
        case .birthday, .childBirthday:
            if let year = importantDate.year {
                let currentYear = Calendar.current.component(.year, from: Date())
                let age = currentYear - year
                return "Cada \(date) • \(age) años"
            }
            return "Cada \(date)"
        case .wedding, .anniversary:
            if let year = importantDate.year {
                return "\(date)/\(year)"
            }
            return "Cada \(date)"
        case .other:
            return date
        }
    }
    
    private func daysText(_ days: Int) -> String {
        switch days {
        case 0: return "¡Es hoy! 🎉"
        case 1: return "¡Mañana!"
        default: return "Faltan \(days) días"
        }
    }
    
    private func loadPhotos() async {
        isLoading = true
        photosByYear = await importantDatesService.getPhotosFromPreviousYears(for: importantDate)
        isLoading = false
    }
}

// MARK: - Year Memory Section

struct YearMemorySection: View {
    let year: Int
    let photos: [PersistedPhoto]
    let importantDate: PersistedImportantDate
    
    @State private var selectedPhotoIndex: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(yearTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(photos.count) fotos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                            .cornerRadius(8)
                            .onTapGesture {
                                selectedPhotoIndex = index
                            }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(item: Binding(
            get: { selectedPhotoIndex.map { SelectedPhotoIndex(index: $0) } },
            set: { selectedPhotoIndex = $0?.index }
        )) { selected in
            PhotoGalleryView(photos: photos, initialIndex: selected.index)
        }
    }
    
    private var yearTitle: String {
        switch importantDate.dateType {
        case .birthday, .childBirthday:
            if let birthYear = importantDate.year {
                let age = year - birthYear
                return "\(year) • \(age) años"
            }
            return "\(year)"
        case .wedding, .anniversary:
            if let weddingYear = importantDate.year {
                let anniversary = year - weddingYear
                if anniversary == 0 {
                    return "\(year) • La boda"
                }
                return "\(year) • \(anniversary)º aniversario"
            }
            return "\(year)"
        case .other:
            return "\(year)"
        }
    }
}

struct SelectedPhotoIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Photo Gallery View

struct PhotoGalleryView: View {
    let photos: [PersistedPhoto]
    let initialIndex: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    
    init(photos: [PersistedPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    FullPhotoView(localIdentifier: photo.localIdentifier)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("\(currentIndex + 1) de \(photos.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .background(.black)
        }
    }
}

// MARK: - Full Photo View

struct FullPhotoView: View {
    let localIdentifier: String
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadFullImage()
        }
    }
    
    private func loadFullImage() {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            isLoading = false
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(width: UIScreen.main.bounds.width * 2, height: UIScreen.main.bounds.height * 2)
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                self.image = result
                self.isLoading = false
            }
        }
    }
}

#Preview {
    MemoryReelView(importantDate: PersistedImportantDate(
        dateType: .birthday,
        source: .photos,
        month: 3,
        day: 14,
        personName: "Juan"
    ))
    .modelContainer(for: PersistedPhoto.self)
}
