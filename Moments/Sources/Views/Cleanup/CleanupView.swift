// CleanupView.swift
// Vista principal de limpieza - Hero feature "Limpiar"

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
                } else if viewModel.totalCleanupItems == 0 {
                    emptyStateView
                } else {
                    mainCleanupView
                }
            }
            .navigationTitle(Text("cleanup_title"))
            .toolbar {
                if viewModel.totalCleanupItems > 0 {
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
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("cleanup_analyzing")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("cleanup_empty_title", systemImage: "sparkles")
        } description: {
            Text("cleanup_empty_description")
        }
    }
    
    // MARK: - Main Cleanup View
    
    private var mainCleanupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero CTA Card
                heroCTACard
                
                // Categories
                categoriesSection
            }
            .padding()
        }
    }
    
    // MARK: - Hero CTA Card
    
    private var heroCTACard: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
            }
            
            // Title
            VStack(spacing: 8) {
                Text("cleanup_hero_title")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("cleanup_hero_subtitle \(viewModel.totalCleanupItems)")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Size badge
            Text(viewModel.formattedSize(viewModel.estimatedSpaceFreed))
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.tint)
            
            Text("cleanup_hero_space_label")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Main CTA Button
            NavigationLink {
                CleanupReviewView(viewModel: viewModel)
            } label: {
                HStack {
                    Image(systemName: "hand.tap")
                    Text("cleanup_hero_cta")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(14)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
    }
    
    // MARK: - Categories Section
    
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("cleanup_categories_header")
                .font(.headline)
            
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
        }
    }
}

// MARK: - Cleanup Review View (All categories combined)

struct CleanupReviewView: View {
    @ObservedObject var viewModel: CleanupViewModel
    @State private var currentIndex = 0
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    private var allPhotos: [PersistedPhoto] {
        viewModel.categories.flatMap { $0.photos }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if currentIndex < allPhotos.count {
                // Progress indicator
                ProgressView(value: Double(currentIndex), total: Double(allPhotos.count))
                    .padding(.horizontal)
                    .padding(.top)
                
                Text("cleanup_review_progress \(currentIndex + 1) \(allPhotos.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                // Current photo category
                if let category = categoryFor(photo: allPhotos[currentIndex]) {
                    Label(LocalizedStringKey(category.localizedKey), systemImage: category.iconName)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                // Swipeable card
                SwipeablePhotoCard(
                    photo: allPhotos[currentIndex],
                    onKeep: {
                        withAnimation {
                            viewModel.selectedPhotos.remove(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    },
                    onDelete: {
                        withAnimation {
                            viewModel.selectedPhotos.insert(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    }
                )
                .padding()
                
                // Action buttons
                HStack(spacing: 60) {
                    // Keep button
                    Button {
                        withAnimation {
                            viewModel.selectedPhotos.remove(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    } label: {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.green)
                            Text("cleanup_keep")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Delete button
                    Button {
                        withAnimation {
                            viewModel.selectedPhotos.insert(allPhotos[currentIndex].id)
                            currentIndex += 1
                        }
                    } label: {
                        VStack {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.red)
                            Text("cleanup_delete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 40)
                
            } else {
                // Review complete
                reviewCompleteView
            }
        }
        .navigationTitle(Text("cleanup_review_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.selectedCount > 0 {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("cleanup_delete_selected \(viewModel.selectedCount)")
                        }
                    }
                }
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
                    dismiss()
                }
            }
            Button("cleanup_cancel", role: .cancel) {}
        } message: {
            Text("cleanup_delete_confirmation_message \(viewModel.formattedSize(viewModel.selectedSize))")
        }
    }
    
    private func categoryFor(photo: PersistedPhoto) -> CleanupCategoryType? {
        return photo.cleanupCategory != .none ? photo.cleanupCategory : nil
    }
    
    private var reviewCompleteView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 8) {
                Text("cleanup_review_complete_title")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if viewModel.selectedCount > 0 {
                    Text("cleanup_review_complete_selected \(viewModel.selectedCount)")
                        .foregroundStyle(.secondary)
                    
                    Text(viewModel.formattedSize(viewModel.selectedSize))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.tint)
                } else {
                    Text("cleanup_review_complete_none")
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if viewModel.selectedCount > 0 {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("cleanup_delete_selected \(viewModel.selectedCount)")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(14)
                }
                .padding(.horizontal)
            }
            
            Button {
                dismiss()
            } label: {
                Text("cleanup_done")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Category Row

struct CleanupCategoryRow: View {
    let category: CleanupViewModel.CleanupCategoryItem
    @ObservedObject var viewModel: CleanupViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(category.localizedKey))
                    .font(.body)
                    .foregroundStyle(.primary)
                
                Text("cleanup_category_count \(category.count) \(viewModel.formattedSize(category.estimatedSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
            // Mode selector
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
                        isBest: photo.isBestInGroup == true,
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
    var isBest: Bool = false
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
            .overlay(alignment: .topLeading) {
                if isBest {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .shadow(radius: 2)
                        .padding(6)
                }
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
