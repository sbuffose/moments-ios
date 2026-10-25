// CleanupView.swift
// Vista principal de limpieza

import SwiftUI
import SwiftData

struct CleanupView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CleanupViewModel()
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.categories.isEmpty {
                    emptyStateView
                } else {
                    categoriesListView
                }
            }
            .navigationTitle(Text("cleanup_title"))
            .toolbar {
                if !viewModel.categories.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await viewModel.loadCleanupSuggestions()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.initialize(modelContext: modelContext)
        }
        .alert("cleanup_error_title", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Subviews
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("cleanup_analyzing")
                .foregroundStyle(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("cleanup_empty_title", systemImage: "sparkles")
        } description: {
            Text("cleanup_empty_description")
        }
    }
    
    private var categoriesListView: some View {
        List {
            Section {
                summaryCard
            }
            
            Section {
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
            } header: {
                Text("cleanup_categories_header")
            }
        }
    }
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                
                VStack(alignment: .leading) {
                    Text("cleanup_summary_title")
                        .font(.headline)
                    
                    Text("cleanup_summary_space \(viewModel.formattedSize(viewModel.estimatedSpaceFreed))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            let totalItems = viewModel.categories.reduce(0) { $0 + $1.count }
            Text("cleanup_summary_items \(totalItems)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category Row

struct CleanupCategoryRow: View {
    let category: CleanupViewModel.CleanupCategoryItem
    @ObservedObject var viewModel: CleanupViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(category.localizedKey))
                    .font(.body)
                
                Text("\(category.count) elementos · \(viewModel.formattedSize(category.estimatedSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(category.count)")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
            // Selector de modo
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
    
    private var swipeReviewView: some View {
        VStack {
            if currentIndex < category.photos.count {
                let photo = category.photos[currentIndex]
                
                SwipeablePhotoCard(
                    photo: photo,
                    onKeep: {
                        withAnimation {
                            viewModel.selectedPhotos.remove(photo.id)
                            currentIndex += 1
                        }
                    },
                    onDelete: {
                        withAnimation {
                            viewModel.selectedPhotos.insert(photo.id)
                            currentIndex += 1
                        }
                    }
                )
                .padding()
                
                HStack(spacing: 40) {
                    Button {
                        viewModel.selectedPhotos.remove(photo.id)
                        currentIndex += 1
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                    }
                    
                    Button {
                        viewModel.selectedPhotos.insert(photo.id)
                        currentIndex += 1
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 40)
                
                Text("swipe_progress \(currentIndex + 1) \(category.photos.count)")
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

// MARK: - Photo Cell

struct CleanupPhotoCell: View {
    let photo: PersistedPhoto
    let isSelected: Bool
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
        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier, targetSize: CGSize(width: 500, height: 500))
            .aspectRatio(contentMode: .fit)
            .cornerRadius(16)
            .shadow(radius: 8)
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
}

#Preview {
    CleanupView()
        .modelContainer(for: PersistedPhoto.self)
}
