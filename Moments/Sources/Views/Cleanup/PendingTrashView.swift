// PendingTrashView.swift
// Final review screen before actual deletion

import SwiftUI
import SwiftData

struct PendingTrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var deletionService = DeletionService()
    
    @State private var trashItems: [PendingTrashItem] = []
    @State private var showDeleteConfirmation = false
    @State private var showResult = false
    @State private var deletionResult: DeletionResult?
    @State private var isDeleting = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                if trashItems.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        // Header stats
                        headerStats
                        
                        // Photo grid
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4)
                            ], spacing: 4) {
                                ForEach(trashItems, id: \.id) { item in
                                    TrashItemCell(
                                        item: item,
                                        isSelected: item.isSelected,
                                        onToggle: { toggleSelection(item) }
                                    )
                                }
                            }
                            .padding(.horizontal, MomentsSpacing.screenHorizontal)
                            .padding(.vertical, MomentsSpacing.md)
                        }
                        
                        // Bottom action bar
                        bottomBar
                    }
                }
            }
            .navigationTitle(Text("trash_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if !trashItems.isEmpty {
                        Button {
                            let allSelected = trashItems.allSatisfy { $0.isSelected }
                            trashItems.forEach { $0.isSelected = !allSelected }
                        } label: {
                            Text(trashItems.allSatisfy { $0.isSelected } ? "Deseleccionar" : "Seleccionar todo")
                                .font(MomentsTypography.labelMedium)
                        }
                    }
                }
            }
            .onAppear {
                deletionService.initialize(modelContext: modelContext)
                loadTrashItems()
            }
            .alert("trash_confirm_title", isPresented: $showDeleteConfirmation) {
                Button("trash_cancel", role: .cancel) { }
                Button("trash_confirm", role: .destructive) {
                    Task {
                        await executeDelete()
                    }
                }
            } message: {
                let count = trashItems.filter { $0.isSelected }.count
                Text("trash_confirm_message \(count)")
            }
            .sheet(isPresented: $showResult) {
                if let result = deletionResult {
                    DeletionResultView(result: result, onDismiss: {
                        showResult = false
                        loadTrashItems()
                    })
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: MomentsSpacing.lg) {
            Image(systemName: "trash.slash")
                .font(.system(size: 64))
                .foregroundStyle(MomentsColors.textTertiary)
            
            Text("trash_empty")
                .font(MomentsTypography.headlineMedium)
                .foregroundStyle(MomentsColors.textPrimary)
            
            Button {
                dismiss()
            } label: {
                Text("Volver")
            }
            .momentsSecondaryButton()
        }
    }
    
    // MARK: - Header Stats
    
    private var headerStats: some View {
        VStack(spacing: MomentsSpacing.xs) {
            let selectedCount = trashItems.filter { $0.isSelected }.count
            let selectedSize = trashItems.filter { $0.isSelected }.reduce(0) { $0 + $1.estimatedFileSize }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("trash_review_before_delete")
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textSecondary)
                    
                    Text("trash_items_count \(selectedCount)")
                        .font(MomentsTypography.headlineMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Tamaño")
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textSecondary)
                    
                    Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))
                        .font(MomentsTypography.numberMedium)
                        .foregroundStyle(MomentsColors.accent)
                }
            }
            .padding(.horizontal, MomentsSpacing.screenHorizontal)
            .padding(.vertical, MomentsSpacing.md)
            .background(MomentsColors.bgSecondary)
            
            // Warning about recoverable deletion
            HStack(spacing: MomentsSpacing.xs) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                
                Text("Se moverán a Eliminados recientemente. Podés recuperarlas durante 30 días.")
                    .font(MomentsTypography.caption)
                    .foregroundStyle(MomentsColors.textSecondary)
            }
            .padding(.horizontal, MomentsSpacing.screenHorizontal)
            .padding(.vertical, MomentsSpacing.sm)
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        VStack(spacing: MomentsSpacing.sm) {
            let selectedCount = trashItems.filter { $0.isSelected }.count
            
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                        Text("Borrar \(selectedCount) elementos")
                    }
                }
            }
            .momentsDestructiveButton()
            .disabled(selectedCount == 0 || isDeleting)
            
            Button {
                Task {
                    await deletionService.clearTrash()
                    loadTrashItems()
                }
            } label: {
                Text("Vaciar papelera sin borrar")
                    .font(MomentsTypography.labelMedium)
                    .foregroundStyle(MomentsColors.textSecondary)
            }
        }
        .padding(.horizontal, MomentsSpacing.screenHorizontal)
        .padding(.vertical, MomentsSpacing.md)
        .background(MomentsColors.bgSecondary)
    }
    
    // MARK: - Actions
    
    private func loadTrashItems() {
        trashItems = deletionService.getPendingTrashItems()
    }
    
    private func toggleSelection(_ item: PendingTrashItem) {
        item.isSelected.toggle()
        // Force view update
        trashItems = deletionService.getPendingTrashItems()
    }
    
    private func executeDelete() async {
        isDeleting = true
        deletionResult = await deletionService.executeAndVerifyDeletion()
        isDeleting = false
        showResult = true
    }
}

// MARK: - Trash Item Cell

struct TrashItemCell: View {
    let item: PendingTrashItem
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncPhotoThumbnail(localIdentifier: item.localIdentifier)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .overlay(
                    isSelected ? Color.black.opacity(0.3) : Color.clear
                )
            
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isSelected ? MomentsColors.accent : .white.opacity(0.8))
                .padding(6)
                .shadow(radius: 2)
        }
        .onTapGesture {
            MomentsHaptics.selection()
            onToggle()
        }
    }
}

// MARK: - Deletion Result View

struct DeletionResultView: View {
    let result: DeletionResult
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: MomentsSpacing.xl) {
            Spacer()
            
            if result.success {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                
                Text("trash_success_title")
                    .font(MomentsTypography.displaySmall)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                Text("Liberaste \(result.freedSpaceFormatted)")
                    .font(MomentsTypography.headlineMedium)
                    .foregroundStyle(MomentsColors.accent)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
                
                Text("Parcialmente completado")
                    .font(MomentsTypography.displaySmall)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                if let error = result.error {
                    Text(error)
                        .font(MomentsTypography.bodyMedium)
                        .foregroundStyle(MomentsColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                if result.deletedCount > 0 {
                    Text("Se borraron \(result.deletedCount) de \(result.deletedCount + result.failedCount)")
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textTertiary)
                }
            }
            
            Spacer()
            
            Button {
                MomentsHaptics.success()
                onDismiss()
            } label: {
                Text("Continuar")
            }
            .momentsAccentButton()
            .padding(.horizontal, MomentsSpacing.screenHorizontal)
            .padding(.bottom, MomentsSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MomentsColors.bgPrimary)
    }
}

// MARK: - Button Modifier for Destructive Action

extension View {
    func momentsDestructiveButton() -> some View {
        self
            .font(MomentsTypography.labelLarge)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .cornerRadius(14)
    }
}
