// MonthlyRecapView.swift
// Tarjetas de historia compartibles para "Tu mes en fotos"

import SwiftUI

struct MonthlyRecapView: View {
    let recap: MonthlyRecap
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                recapCard(title: recap.title, body: recap.narrative)
                recapCard(title: MomentsPluralization.photos(recap.photoCount), body: recap.subtitle)
                recapCard(title: "Lugares", body: "\(recap.placeCount) lugares en tu \(recap.monthName)")
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier("recap.storyCards")
        .toolbar {
            ShareLink(item: "\(recap.title)\n\(recap.narrative)") {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
        }
        .navigationTitle(recap.title)
    }
    
    private func recapCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(MomentsTypography.titleMedium)
                .foregroundStyle(.white)
            Text(body)
                .font(MomentsTypography.bodyMedium)
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
        }
        .padding(24)
        .frame(width: 280, height: 420, alignment: .topLeading)
        .background(MomentsColors.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(radius: 12, y: 6)
    }
}
