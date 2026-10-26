// PlacesView.swift
// Vista de lugares

import SwiftUI
import SwiftData
import MapKit

struct PlacesView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = PlacesViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.places.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle(Text("places_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Modo", selection: $viewModel.displayMode) {
                        Image(systemName: "map").tag(PlacesViewModel.DisplayMode.map)
                        Image(systemName: "list.bullet").tag(PlacesViewModel.DisplayMode.list)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("places_loading")
                .foregroundStyle(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("places_empty_title", systemImage: "map")
        } description: {
            Text("places_empty_description")
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if viewModel.displayMode == .map {
            mapView
        } else {
            listView
        }
    }
    
    // MARK: - Map View
    
    private var mapView: some View {
        ZStack(alignment: .bottom) {
            Map(position: .constant(.region(viewModel.mapRegion))) {
                ForEach(viewModel.clusters) { cluster in
                    if cluster.places.count == 1, let place = cluster.places.first {
                        Annotation(place.displayName, coordinate: cluster.coordinate) {
                            PlaceMapMarker(isSingle: true) {
                                viewModel.selectedPlace = place
                            }
                        }
                    } else {
                        Annotation("\(cluster.places.count)", coordinate: cluster.coordinate) {
                            PlaceMapMarker(isSingle: false, count: cluster.places.count) {
                                if let first = cluster.places.first {
                                    viewModel.selectPlace(first)
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea(edges: .top)
            .onChange(of: viewModel.mapRegion.span.latitudeDelta) { _, _ in
                viewModel.updateClusters()
            }
            
            if let selectedPlace = viewModel.selectedPlace {
                PlaceDetailCard(place: selectedPlace) {
                    viewModel.selectedPlace = nil
                }
                .padding()
                .transition(.move(edge: .bottom))
            }
        }
    }
    
    // MARK: - List View
    
    private var listView: some View {
        List {
            ForEach(viewModel.places) { place in
                NavigationLink {
                    PlaceDetailView(place: place)
                } label: {
                    PlaceRow(place: place)
                }
            }
        }
    }
}

// MARK: - Map Marker

struct PlaceMapMarker: View {
    let isSingle: Bool
    var count: Int = 1
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            if isSingle {
                VStack(spacing: 0) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .red)
                    
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .offset(y: -3)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 40, height: 40)
                    
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Place Detail Card

struct PlaceDetailCard: View {
    let place: PlacesViewModel.PlaceItem
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.displayName)
                        .font(.headline)
                    
                    if let city = place.city, !city.isEmpty {
                        Text(city)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 16) {
                Label("\(place.photoCount)", systemImage: "photo")
                Label("\(place.visitCount) visitas", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if !place.photoIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(place.photoIds.prefix(5), id: \.self) { photoId in
                            AsyncPhotoThumbnail(localIdentifier: photoId)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        if place.photoCount > 5 {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                
                                Text("+\(place.photoCount - 5)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Place Row

struct PlaceRow: View {
    let place: PlacesViewModel.PlaceItem
    
    var body: some View {
        HStack(spacing: 12) {
            if let firstPhotoId = place.photoIds.first {
                AsyncPhotoThumbnail(localIdentifier: firstPhotoId)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "mappin")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(place.displayName)
                    .font(.headline)
                
                if let city = place.city {
                    Text(city)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Label("\(place.photoCount)", systemImage: "photo")
                    Label("\(place.visitCount)", systemImage: "clock")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Place Detail View

struct PlaceDetailView: View {
    let place: PlacesViewModel.PlaceItem
    
    @Environment(\.modelContext) private var modelContext
    @State private var photos: [PersistedPhoto] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Map Preview
                Map(position: $cameraPosition) {
                    Marker(place.displayName, coordinate: place.coordinate)
                }
                .mapStyle(.standard)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .onAppear {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: place.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 8) {
                    if let address = place.address {
                        Label(address, systemImage: "location.fill")
                            .font(.subheadline)
                    }
                    
                    HStack(spacing: 16) {
                        Label("\(place.photoCount) fotos", systemImage: "photo")
                        Label("\(place.visitCount) visitas", systemImage: "calendar")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    
                    if let first = place.firstVisit, let last = place.lastVisit {
                        Text("Primera visita: \(formatDate(first))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Última visita: \(formatDate(last))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                
                // Photos
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos, id: \.id) { photo in
                        PhotoGridItem(photo: photo)
                    }
                }
            }
        }
        .navigationTitle(place.displayName)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadPhotos()
        }
    }
    
    private func loadPhotos() async {
        let ids = place.photoIds
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { ids.contains($0.localIdentifier) },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        do {
            photos = try modelContext.fetch(descriptor)
        } catch {
            print("Error loading place photos: \(error)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    PlacesView()
        .modelContainer(for: PersistedPlace.self)
}
