import SwiftUI
import Photos

struct NewPhotoCheckSheet: View {
    let candidate: NewPhotoCandidate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AsyncPhotoThumbnail(localIdentifier: candidate.localIdentifier, targetSize: CGSize(width: 360, height: 360))
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Text(candidate.reason)
                    .font(MomentsTypography.headlineMedium)
                if candidate.size > 0 {
                    Text(SpaceFormatting.string(from: candidate.size))
                        .foregroundStyle(MomentsColors.textSecondary)
                }
                HStack(spacing: 16) {
                    Button("Borrar") { applyKeep(false) }
                        .momentsAccentButton(fullWidth: true)
                    Button("Conservar") { applyKeep(true) }
                        .momentsSecondaryButton(fullWidth: true)
                }
            }
            .padding()
            .navigationTitle("Foto nueva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("newPhotoCheck.sheet")
        .presentationDetents([.medium, .large])
    }
    
    private func applyKeep(_ keep: Bool) {
        let vm = CleanupViewModel()
        vm.initialize(modelContext: modelContext)
        if keep {
            vm.keepPhoto(candidate.id, duration: .forever)
        } else {
            vm.markAsReviewed(candidate.id, delete: true)
            Task { await vm.deleteSelectedPhotos() }
        }
        NewPhotoCheckService.shared.pending = nil
        dismiss()
    }
}
