// TagPhotoSheet.swift
// Review tagging: people, Familia/Amigos/Viajes, and suggested trips.
// In-app SwiftData tags only — never PhotoKit albums.

import SwiftUI
import SwiftData

struct TagReviewButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label("Etiquetar", systemImage: "tag")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MomentsColors.accent)
        }
        .accessibilityIdentifier("review.tagButton")
        .accessibilityLabel("Etiquetar")
    }
}

struct TagPhotoSheet: View {
    let photos: [PersistedPhoto]
    var onTagged: ([String]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var data = ReviewTagSheetData(people: [], categories: ReviewTagOption.fixedCategories, trips: [])
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            List {
                if !data.people.isEmpty {
                    Section("Personas") {
                        ForEach(data.people) { option in
                            tagRow(option)
                        }
                    }
                }
                Section("Categorías") {
                    ForEach(data.categories) { option in
                        tagRow(option)
                    }
                }
                if !data.trips.isEmpty {
                    Section("Viajes") {
                        ForEach(data.trips) { option in
                            tagRow(option)
                        }
                    }
                }
            }
            .navigationTitle("Etiquetar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Etiquetar") { confirm() }
                        .disabled(selected.isEmpty)
                        .accessibilityIdentifier("review.tagConfirm")
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
        .accessibilityIdentifier("review.tagSheet")
        .task { await load() }
    }
    
    @ViewBuilder
    private func tagRow(_ option: ReviewTagOption) -> some View {
        Button {
            if selected.contains(option.id) {
                selected.remove(option.id)
            } else {
                selected.insert(option.id)
            }
        } label: {
            HStack(spacing: MomentsSpacing.sm) {
                if option.kind == .person {
                    if let faceId = option.facePhotoLocalIdentifier {
                        AsyncPhotoThumbnail(localIdentifier: faceId, targetSize: CGSize(width: 44, height: 44))
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(MomentsColors.accent)
                    }
                } else {
                    Image(systemName: option.kind == .trip ? "airplane" : "tag.fill")
                        .foregroundStyle(MomentsColors.accent)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .foregroundStyle(MomentsColors.textPrimary)
                    if let subtitle = option.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                }
                Spacer()
                if selected.contains(option.id) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(MomentsColors.accent)
                }
            }
        }
        .accessibilityIdentifier(accessibilityId(for: option))
        .accessibilityAddTraits(selected.contains(option.id) ? [.isButton, .isSelected] : .isButton)
    }
    
    private func accessibilityId(for option: ReviewTagOption) -> String {
        switch option.id {
        case ReviewTagOption.familia.id: return "review.tag.familia"
        case ReviewTagOption.amigos.id: return "review.tag.amigos"
        case ReviewTagOption.viajes.id: return "review.tag.viajes"
        default:
            if option.kind == .person { return "review.tag.person" }
            if option.kind == .trip { return "review.tag.trip" }
            return "review.tag.\(option.id)"
        }
    }
    
    private func load() async {
        let loaded = await ReviewTagService.sheetData(
            photos: photos,
            context: modelContext
        )
        data = loaded
        selected = Set(loaded.allOptions.filter(\.isPreselected).map(\.id))
        isLoading = false
    }
    
    private func confirm() {
        let chosen = data.allOptions.filter { selected.contains($0.id) }
        ReviewTagService.apply(options: chosen, to: photos, context: modelContext)
        onTagged(photos.map(\.id))
        dismiss()
    }
}
