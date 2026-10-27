// MonthlyRecapView.swift
// Animated story-style pager for "Tu mes en fotos" monthly recap

import SwiftUI
import SwiftData
import Photos
import MapKit

struct MonthlyRecapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var recapService = MonthlyRecapService.shared
    
    let month: Int?
    let year: Int?
    
    @State private var recap: MonthlyRecapData?
    @State private var currentPage = 0
    @State private var isLoading = true
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var isExportingVideo = false
    
    private var totalPages: Int {
        guard let recap = recap else { return 0 }
        var count = 2 // Intro + Summary
        if !recap.highlights.isEmpty { count += 1 }
        if !recap.topPlaces.isEmpty { count += 1 }
        if !recap.mostSeenPeople.isEmpty { count += 1 }
        if !recap.trips.isEmpty { count += 1 }
        if recap.busiestDay != nil { count += 1 }
        return count
    }
    
    init(month: Int? = nil, year: Int? = nil) {
        self.month = month
        self.year = year
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                loadingView
            } else if let recap = recap {
                recapContent(recap)
            } else {
                emptyView
            }
        }
        .onAppear {
            recapService.initialize(modelContext: modelContext)
            loadRecap()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: MomentsSpacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Preparando tu recap...")
                .font(MomentsTypography.bodyMedium)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: MomentsSpacing.lg) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.5))
            
            Text("No hay fotos este mes")
                .font(MomentsTypography.headlineMedium)
                .foregroundStyle(.white)
            
            Text("Tomá algunas fotos y volvé a ver tu recap")
                .font(MomentsTypography.bodyMedium)
                .foregroundStyle(.white.opacity(0.7))
            
            Button {
                dismiss()
            } label: {
                Text("Cerrar")
                    .font(MomentsTypography.buttonMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, MomentsSpacing.xl)
                    .padding(.vertical, MomentsSpacing.sm)
                    .background(.white.opacity(0.2))
                    .cornerRadius(20)
            }
            .padding(.top, MomentsSpacing.lg)
        }
    }
    
    // MARK: - Recap Content
    
    @ViewBuilder
    private func recapContent(_ recap: MonthlyRecapData) -> some View {
        TabView(selection: $currentPage) {
            introPage(recap)
                .tag(0)
            
            if !recap.highlights.isEmpty {
                highlightsPage(recap)
                    .tag(1)
            }
            
            if !recap.topPlaces.isEmpty {
                placesPage(recap)
                    .tag(2)
            }
            
            if !recap.mostSeenPeople.isEmpty {
                peoplePage(recap)
                    .tag(3)
            }
            
            if !recap.trips.isEmpty {
                tripsPage(recap)
                    .tag(4)
            }
            
            if recap.busiestDay != nil {
                busiestDayPage(recap)
                    .tag(5)
            }
            
            summaryPage(recap)
                .tag(totalPages - 1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            progressBar
        }
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .overlay(alignment: .bottom) {
            navigationControls(recap)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 && currentPage < totalPages - 1 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentPage += 1
                        }
                    } else if value.translation.width > 50 && currentPage > 0 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentPage -= 1
                        }
                    }
                }
        )
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index <= currentPage ? Color.white : Color.white.opacity(0.3))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, MomentsSpacing.lg)
        .padding(.top, 60)
    }
    
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.3))
                .clipShape(Circle())
        }
        .padding(.top, 52)
        .padding(.trailing, MomentsSpacing.md)
    }
    
    // MARK: - Navigation Controls
    
    private func navigationControls(_ recap: MonthlyRecapData) -> some View {
        HStack(spacing: MomentsSpacing.lg) {
            if currentPage == totalPages - 1 {
                Button {
                    Task {
                        await exportAsImage(recap)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Compartir")
                    }
                    .font(MomentsTypography.buttonMedium)
                    .foregroundStyle(.black)
                    .padding(.horizontal, MomentsSpacing.xl)
                    .padding(.vertical, MomentsSpacing.md)
                    .background(.white)
                    .cornerRadius(MomentsCorners.large)
                }
            } else {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentPage += 1
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Siguiente")
                        Image(systemName: "arrow.right")
                    }
                    .font(MomentsTypography.buttonMedium)
                    .foregroundStyle(.black)
                    .padding(.horizontal, MomentsSpacing.xl)
                    .padding(.vertical, MomentsSpacing.md)
                    .background(.white)
                    .cornerRadius(MomentsCorners.large)
                }
            }
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Pages
    
    private func introPage(_ recap: MonthlyRecapData) -> some View {
        ZStack {
            if let highlight = recap.highlights.first {
                KenBurnsImage(localIdentifier: highlight.localIdentifier)
            } else {
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            
            VStack(spacing: MomentsSpacing.md) {
                Spacer()
                
                Text("Tu \(recap.monthName.lowercased())")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("en fotos")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                
                Text("\(recap.totalPhotos) momentos capturados")
                    .font(MomentsTypography.bodyMedium)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, MomentsSpacing.sm)
                
                Spacer()
                Spacer()
            }
        }
    }
    
    private func highlightsPage(_ recap: MonthlyRecapData) -> some View {
        ZStack {
            if let highlight = recap.highlights.first {
                KenBurnsImage(localIdentifier: highlight.localIdentifier, direction: .up)
            }
            
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack {
                Text("Tus mejores fotos")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 100)
                
                Spacer()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recap.highlights.prefix(6)) { highlight in
                            AsyncPhotoThumbnail(localIdentifier: highlight.localIdentifier)
                                .frame(width: 100, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, MomentsSpacing.lg)
                }
                
                Spacer()
                Spacer()
            }
        }
    }
    
    private func placesPage(_ recap: MonthlyRecapData) -> some View {
        ZStack {
            if let place = recap.topPlaces.first,
               let photoId = place.representativePhotoId {
                KenBurnsPhotoById(photoId: photoId)
            } else {
                Color.black
            }
            
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(spacing: MomentsSpacing.lg) {
                Text("Tus lugares")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 100)
                
                Spacer()
                
                VStack(spacing: MomentsSpacing.md) {
                    ForEach(recap.topPlaces.prefix(4)) { place in
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.white)
                            
                            Text(place.name)
                                .font(MomentsTypography.bodyLarge)
                                .foregroundStyle(.white)
                            
                            Spacer()
                            
                            Text("\(place.photoCount) fotos")
                                .font(MomentsTypography.labelMedium)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, MomentsSpacing.lg)
                    }
                }
                
                if !recap.topPlaces.isEmpty {
                    MiniMapView(places: recap.topPlaces)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, MomentsSpacing.lg)
                }
                
                Spacer()
                Spacer()
            }
        }
    }
    
    private func peoplePage(_ recap: MonthlyRecapData) -> some View {
        ZStack {
            LinearGradient(
                colors: [.orange.opacity(0.8), .pink.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: MomentsSpacing.lg) {
                Text("Las personas que más viste")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 100)
                
                Spacer()
                
                VStack(spacing: MomentsSpacing.lg) {
                    ForEach(recap.mostSeenPeople.prefix(5)) { person in
                        HStack(spacing: MomentsSpacing.md) {
                            Circle()
                                .fill(.white.opacity(0.3))
                                .frame(width: 50, height: 50)
                                .overlay {
                                    Text(String(person.name.prefix(1)))
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                    .font(MomentsTypography.headlineSmall)
                                    .foregroundStyle(.white)
                                
                                Text("\(person.photoCount) fotos juntos")
                                    .font(MomentsTypography.labelMedium)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, MomentsSpacing.xl)
                    }
                }
                
                Spacer()
                Spacer()
            }
        }
    }
    
    private func tripsPage(_ recap: MonthlyRecapData) -> some View {
        ZStack {
            if let trip = recap.trips.first,
               let coverId = trip.coverPhotoId {
                KenBurnsPhotoById(photoId: coverId, direction: .left)
            } else {
                LinearGradient(
                    colors: [.blue, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(spacing: MomentsSpacing.lg) {
                Text("Tus viajes")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 100)
                
                Spacer()
                
                VStack(spacing: MomentsSpacing.lg) {
                    ForEach(recap.trips) { trip in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "airplane")
                                    .foregroundStyle(.white)
                                
                                Text(trip.destination)
                                    .font(MomentsTypography.headlineMedium)
                                    .foregroundStyle(.white)
                            }
                            
                            Text("\(trip.durationDays) días • \(trip.photoCount) fotos")
                                .font(MomentsTypography.bodySmall)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MomentsSpacing.md)
                        .background(.white.opacity(0.15))
                        .cornerRadius(MomentsCorners.medium)
                        .padding(.horizontal, MomentsSpacing.lg)
                    }
                }
                
                Spacer()
                Spacer()
            }
        }
    }
    
    private func busiestDayPage(_ recap: MonthlyRecapData) -> some View {
        ZStack {
            LinearGradient(
                colors: [.purple, .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: MomentsSpacing.xl) {
                Spacer()
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.8))
                
                if let busiest = recap.busiestDay {
                    let formatter = DateFormatter()
                    let _ = formatter.locale = Locale(identifier: "es-AR")
                    let _ = formatter.dateFormat = "EEEE d 'de' MMMM"
                    
                    Text("Tu día más activo")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    
                    Text(formatter.string(from: busiest.date))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("\(busiest.photoCount) fotos")
                        .font(.system(size: 48, weight: .heavy))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                Spacer()
            }
        }
    }
    
    private func summaryPage(_ recap: MonthlyRecapData) -> some View {
        ZStack {
            if let highlight = recap.highlights.last {
                KenBurnsImage(localIdentifier: highlight.localIdentifier, direction: .down)
            } else {
                LinearGradient(
                    colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            LinearGradient(
                colors: [.black.opacity(0.8), .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(spacing: MomentsSpacing.xl) {
                Spacer()
                
                Text("Cómo fue tu \(recap.monthName.lowercased())")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text(recap.narrative)
                    .font(MomentsTypography.bodyLarge)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MomentsSpacing.xl)
                
                if recap.spaceFreedBytes > 1_000_000 {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        
                        Text("Liberaste \(recap.formattedSpaceFreed) con Moments")
                            .font(MomentsTypography.labelMedium)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.top, MomentsSpacing.md)
                }
                
                Spacer()
                Spacer()
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadRecap() {
        Task {
            if let month = month, let year = year {
                recap = await recapService.generateRecap(for: month, year: year)
            } else {
                recap = await recapService.generatePreviousMonthRecap()
            }
            isLoading = false
        }
    }
    
    private func exportAsImage(_ recap: MonthlyRecapData) async {
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap))
        renderer.scale = 3.0
        
        if let uiImage = renderer.uiImage {
            shareImage = uiImage
            showShareSheet = true
        }
    }
}

// MARK: - Ken Burns Image

struct KenBurnsImage: View {
    let localIdentifier: String
    var direction: KenBurnsDirection = .right
    
    @State private var image: UIImage?
    @State private var isAnimating = false
    
    enum KenBurnsDirection {
        case up, down, left, right
    }
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width * 1.2, height: geometry.size.height * 1.2)
                    .scaleEffect(isAnimating ? 1.15 : 1.0)
                    .offset(animationOffset(for: geometry.size))
                    .animation(
                        .easeInOut(duration: 8)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            } else {
                Color.black
            }
        }
        .clipped()
        .onAppear {
            loadImage()
            withAnimation {
                isAnimating = true
            }
        }
    }
    
    private func animationOffset(for size: CGSize) -> CGSize {
        let amount: CGFloat = isAnimating ? 30 : 0
        switch direction {
        case .up: return CGSize(width: 0, height: -amount)
        case .down: return CGSize(width: 0, height: amount)
        case .left: return CGSize(width: -amount, height: 0)
        case .right: return CGSize(width: amount, height: 0)
        }
    }
    
    private func loadImage() {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(width: 1200, height: 1600)
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                self.image = result
            }
        }
    }
}

struct KenBurnsPhotoById: View {
    let photoId: String
    var direction: KenBurnsImage.KenBurnsDirection = .right
    
    @Environment(\.modelContext) private var modelContext
    @State private var localIdentifier: String?
    
    var body: some View {
        Group {
            if let identifier = localIdentifier {
                KenBurnsImage(localIdentifier: identifier, direction: direction)
            } else {
                Color.black
            }
        }
        .onAppear {
            loadPhoto()
        }
    }
    
    private func loadPhoto() {
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { $0.id == photoId }
        )
        
        if let photo = try? modelContext.fetch(descriptor).first {
            localIdentifier = photo.localIdentifier
        }
    }
}

// MARK: - Mini Map View

struct MiniMapView: View {
    let places: [MonthlyRecapPlace]
    
    var body: some View {
        if !places.isEmpty {
            Map {
                ForEach(places) { place in
                    Marker(place.name, coordinate: CLLocationCoordinate2D(
                        latitude: place.latitude,
                        longitude: place.longitude
                    ))
                    .tint(.blue)
                }
            }
            .mapStyle(.standard)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Recap Share Card

struct RecapShareCard: View {
    let recap: MonthlyRecapData
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Mi \(recap.monthName.lowercased()) en fotos")
                .font(.system(size: 32, weight: .bold))
            
            Text("\(recap.totalPhotos) momentos")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            
            if !recap.topPlaces.isEmpty {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                    Text(recap.topPlaces.map { $0.name }.prefix(3).joined(separator: ", "))
                }
                .font(.system(size: 18))
            }
            
            if !recap.mostSeenPeople.isEmpty {
                HStack {
                    Image(systemName: "person.2.fill")
                    Text("Con " + recap.mostSeenPeople.map { $0.name }.prefix(2).joined(separator: " y "))
                }
                .font(.system(size: 18))
            }
            
            Text(recap.narrative)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            
            Text("Moments")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 20)
        }
        .padding(40)
        .frame(width: 400, height: 600)
        .background(
            LinearGradient(
                colors: [.white, Color(.systemGray6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MonthlyRecapView()
        .modelContainer(for: PersistedPhoto.self)
}
