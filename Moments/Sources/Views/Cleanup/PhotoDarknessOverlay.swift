// PhotoDarknessOverlay.swift
// Friendly labels on black frames and underexposed-but-visible photos.

import SwiftUI

struct PhotoDarknessOverlay: View {
    let classification: PhotoLuminanceClass
    
    var body: some View {
        switch classification {
        case .blackFrame:
            ZStack {
                Color.black.opacity(0.35)
                VStack(spacing: MomentsSpacing.sm) {
                    Image(systemName: "moon.zzz.fill")
                        .font(MomentsTypography.displaySmall)
                        .symbolRenderingMode(.hierarchical)
                    Text(PhotoLuminanceClass.blackFrameTitle)
                        .font(MomentsTypography.headlineMedium)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("review.blackFrameLabel")
                        .accessibilityLabel(PhotoLuminanceClass.blackFrameTitle)
                    Text(PhotoLuminanceClass.blackFrameSubtitle)
                        .font(MomentsTypography.bodySmall)
                        .multilineTextAlignment(.center)
                        .opacity(0.9)
                        .accessibilityIdentifier("review.blackFrameSubtitle")
                }
                .foregroundStyle(.white)
                .padding(MomentsSpacing.md)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("review.blackFrameLabel")
            .accessibilityLabel(PhotoLuminanceClass.blackFrameTitle)
        case .dark:
            VStack {
                HStack {
                    Label(PhotoLuminanceClass.darkBadgeTitle, systemImage: "moon.fill")
                        .font(MomentsTypography.labelMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial.opacity(0.35), in: Capsule())
                        .background(Color.black.opacity(0.45), in: Capsule())
                    Spacer()
                }
                .padding(12)
                Spacer()
            }
            .allowsHitTesting(false)
            .accessibilityIdentifier("review.darkBadge")
            .accessibilityLabel(PhotoLuminanceClass.darkBadgeTitle)
        case .normal:
            EmptyView()
        }
    }
}

struct PhotoLoadFailureOverlay: View {
    let onRetry: () -> Void
    
    var body: some View {
        ZStack {
            MomentsColors.bgTertiary
            VStack(spacing: MomentsSpacing.sm) {
                Image(systemName: "eye.slash")
                    .font(MomentsTypography.displaySmall)
                    .foregroundStyle(MomentsColors.textSecondary)
                Text(PhotoLuminanceClass.loadFailureTitle)
                    .font(MomentsTypography.headlineMedium)
                    .foregroundStyle(MomentsColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("photo.thumb.failed")
                Button(PhotoLuminanceClass.loadFailureRetryTitle, action: onRetry)
                    .momentsSecondaryButton(fullWidth: false)
                    .accessibilityIdentifier("photo.thumb.retry")
            }
            .padding(MomentsSpacing.md)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo.thumb.failed")
    }
}
