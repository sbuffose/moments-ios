// MomentsComponents.swift
// Reusable UI components: Cards, Chips, Buttons

import SwiftUI
import UIKit

// MARK: - Photo Grid Card

struct PhotoGridCard: View {
    let title: String
    let subtitle: String?
    let photos: [PersistedPhoto]
    var columns: Int = 3
    var maxPhotos: Int = 6
    var action: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.sm) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MomentsTypography.headlineMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(MomentsTypography.bodySmall)
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                }
                
                Spacer()
                
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(MomentsColors.textTertiary)
                }
            }
            
            // Photo grid
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)
            
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(photos.prefix(maxPhotos), id: \.id) { photo in
                    AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .cornerRadius(8)
                }
            }
        }
        .momentsCard()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .clipped()
        .onTapGesture {
            MomentsHaptics.light()
            action?()
        }
    }
}

// MARK: - Cleanup Batch Card

struct CleanupBatchCard: View {
    let title: String
    let itemCount: Int
    let estimatedSize: String
    let photos: [PersistedPhoto]
    let onReview: () -> Void
    let onQuickDelete: () -> Void
    
    @State private var showConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.md) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MomentsTypography.headlineMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                    
                    Text("\(itemCount) elementos · \(estimatedSize)")
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textSecondary)
                }
                
                Spacer()
                
                Text(estimatedSize)
                    .font(MomentsTypography.numberSmall)
                    .foregroundStyle(MomentsColors.accent)
            }
            
            // Photo preview
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos.prefix(8), id: \.id) { photo in
                        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            
            // Actions
            HStack(spacing: MomentsSpacing.sm) {
                Button {
                    MomentsHaptics.light()
                    onReview()
                } label: {
                    HStack {
                        Image(systemName: "eye")
                        Text("Revisar")
                    }
                }
                .momentsSecondaryButton()
                
                Button {
                    MomentsHaptics.warning()
                    showConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Eliminar todo")
                    }
                }
                .momentsAccentButton()
            }
        }
        .momentsCard()
        .confirmationDialog("¿Eliminar \(itemCount) elementos?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Eliminar \(itemCount) elementos", role: .destructive) {
                MomentsHaptics.success()
                onQuickDelete()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se liberarán \(estimatedSize). Esta acción no se puede deshacer.")
        }
    }
}

// MARK: - Date Reminder Card

struct DateReminderCard: View {
    let importantDate: PersistedImportantDate
    let previewPhotos: [PersistedPhoto]
    var onTap: (() -> Void)?
    var onAddCalendar: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.md) {
            // Header with days countdown
            HStack(alignment: .top) {
                // Date badge
                VStack(spacing: 0) {
                    Text(monthAbbrev)
                        .font(MomentsTypography.labelSmall)
                        .foregroundStyle(colorForType)
                    Text("\(importantDate.day)")
                        .font(MomentsTypography.numberSmall)
                        .foregroundStyle(MomentsColors.textPrimary)
                }
                .frame(width: 50, height: 50)
                .background(colorForType.opacity(0.15))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(importantDate.displayName)
                        .font(MomentsTypography.headlineMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                    
                    Text(eventTypeText)
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textSecondary)
                }
                
                Spacer()
                
                if let days = importantDate.daysUntilNext {
                    DaysCountdownBadge(days: days)
                }
            }
            
            // Photo preview if available
            if !previewPhotos.isEmpty {
                HStack(spacing: -12) {
                    ForEach(previewPhotos.prefix(4), id: \.id) { photo in
                        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(MomentsColors.bgCard, lineWidth: 3))
                    }
                    
                    Spacer()
                }
            }
            
            // Actions
            HStack(spacing: MomentsSpacing.sm) {
                if let onAddCalendar = onAddCalendar {
                    Button {
                        MomentsHaptics.light()
                        onAddCalendar()
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text("Agregar")
                        }
                    }
                    .momentsSecondaryButton()
                }
                
                if let onTap = onTap {
                    Button {
                        MomentsHaptics.light()
                        onTap()
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Ver recuerdos")
                        }
                    }
                    .momentsAccentButton()
                }
            }
        }
        .momentsCard()
    }
    
    private var monthAbbrev: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        guard importantDate.month > 0 && importantDate.month <= 12 else { return "" }
        return formatter.shortMonthSymbols[importantDate.month - 1].uppercased()
    }
    
    private var colorForType: Color {
        switch importantDate.dateType {
        case .birthday, .childBirthday, .friendBirthday: return .pink
        case .wedding, .anniversary: return .red
        case .other: return MomentsColors.accent
        }
    }
    
    private var eventTypeText: String {
        switch importantDate.dateType {
        case .birthday, .friendBirthday: return "Cumpleaños"
        case .childBirthday: return "Cumpleaños"
        case .wedding: return "Aniversario de boda"
        case .anniversary: return "Aniversario"
        case .other: return "Fecha especial"
        }
    }
}

struct DaysCountdownBadge: View {
    let days: Int
    
    var body: some View {
        Text(text)
            .font(MomentsTypography.labelMedium)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .cornerRadius(20)
    }
    
    private var text: String {
        switch days {
        case 0: return "¡Hoy!"
        case 1: return "Mañana"
        default: return MomentsPluralization.days(days)
        }
    }
    
    private var backgroundColor: Color {
        switch days {
        case 0: return .green.opacity(0.2)
        case 1...3: return .orange.opacity(0.2)
        default: return MomentsColors.bgTertiary
        }
    }
    
    private var foregroundColor: Color {
        switch days {
        case 0: return .green
        case 1...3: return .orange
        default: return MomentsColors.textSecondary
        }
    }
}

// MARK: - Cataloging Question Card

struct CatalogingQuestionCard: View {
    let question: String
    let subtitle: String?
    let photos: [PersistedPhoto]
    let options: [CatalogOption]
    var onDismiss: (() -> Void)?
    
    struct CatalogOption: Identifiable {
        let id = UUID()
        let title: String
        let action: () -> Void
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: MomentsSpacing.md) {
            // Question
            VStack(alignment: .leading, spacing: 4) {
                Text(question)
                    .font(MomentsTypography.headlineMedium)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textSecondary)
                }
            }
            
            // Photos
            if !photos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(photos.prefix(4), id: \.id) { photo in
                        AsyncPhotoThumbnail(localIdentifier: photo.localIdentifier)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer()
                }
            }
            
            // Options
            VStack(spacing: MomentsSpacing.xs) {
                ForEach(options) { option in
                    Button {
                        MomentsHaptics.selection()
                        option.action()
                    } label: {
                        Text(option.title)
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, MomentsSpacing.sm)
                            .padding(.horizontal, MomentsSpacing.md)
                            .background(MomentsColors.bgTertiary)
                            .cornerRadius(10)
                    }
                }
            }
            
            // Dismiss
            if let onDismiss = onDismiss {
                Button {
                    MomentsHaptics.light()
                    onDismiss()
                } label: {
                    Text("Ahora no")
                        .font(MomentsTypography.bodySmall)
                        .foregroundStyle(MomentsColors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .momentsCard()
    }
}

// MARK: - Chip

struct MomentsChip: View {
    let label: String
    var icon: String?
    var isSelected: Bool = false
    var action: (() -> Void)?
    
    var body: some View {
        Button {
            MomentsHaptics.selection()
            action?()
        } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(MomentsTypography.labelMedium)
            }
            .foregroundStyle(isSelected ? .white : MomentsColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected 
                    ? AnyShapeStyle(MomentsColors.accentGradient)
                    : AnyShapeStyle(MomentsColors.bgTertiary)
            )
            .cornerRadius(20)
        }
        .accessibilityIdentifier(label)
        .buttonStyle(.plain)
    }
}

// MARK: - Space Stat Card

struct SpaceStatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    var icon: String = "externaldrive"
    var color: Color = MomentsColors.accent
    
    var body: some View {
        VStack(spacing: MomentsSpacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 70, height: 70)
                
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
            }
            
            VStack(spacing: 4) {
                Text(value)
                    .font(MomentsTypography.numberMedium)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                Text(title)
                    .font(MomentsTypography.bodySmall)
                    .foregroundStyle(MomentsColors.textSecondary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(MomentsTypography.labelSmall)
                        .foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .momentsCard()
    }
}

// MARK: - Assistant Message Bubble

struct AssistantMessageBubble: View {
    let message: String
    let isUser: Bool
    
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            
            Text(message)
                .font(MomentsTypography.bodyMedium)
                .foregroundStyle(isUser ? .white : MomentsColors.textPrimary)
                .padding(.horizontal, MomentsSpacing.md)
                .padding(.vertical, MomentsSpacing.sm)
                .background(
                    isUser 
                        ? AnyShapeStyle(MomentsColors.accentGradient)
                        : AnyShapeStyle(MomentsColors.bgTertiary)
                )
                .cornerRadius(18)
            
            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Loading Indicator

struct MomentsLoadingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(MomentsColors.accent)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - Pluralization Helpers

enum SpaceFormatting {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : bytes >= 1_000_000 ? [.useMB] : [.useKB, .useMB]
        formatter.formattingContext = .standalone
        if let locale = Locale(identifier: "es_AR") as Locale? {
            formatter.numberFormatter.locale = locale
        }
        return formatter.string(fromByteCount: bytes)
    }
    
    static func pendingLiberationLabel(bytes: Int64) -> String {
        "Vas a liberar \(string(from: bytes))"
    }
    
    static func recentlyDeletedSummary(bytes: Int64) -> String {
        "Liberaste \(string(from: bytes)). Se recupera el espacio al vaciar Eliminados recientemente (o solo en 30 días)"
    }
    
    static let recentlyDeletedHowTo = "Fotos > Álbumes > Eliminados recientemente > Eliminar todo"
    
    static let photosAppURL = URL(string: "photos-redirect://")
}

struct RecentlyDeletedHintView: View {
    var bytes: Int64?
    var showsOpenPhotosButton: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bytes {
                Text(SpaceFormatting.recentlyDeletedSummary(bytes: bytes))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Se recupera el espacio al vaciar Eliminados recientemente (o solo en 30 días)")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(SpaceFormatting.recentlyDeletedHowTo)
                .font(.caption)
                .foregroundStyle(.secondary)
            if showsOpenPhotosButton, let url = SpaceFormatting.photosAppURL {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Abrir Fotos", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("space.openPhotos")
            }
        }
        .accessibilityIdentifier("space.recentlyDeletedHint")
    }
}

enum MomentsPluralization {
    static func photos(_ count: Int) -> String {
        count == 1 ? "\(count) foto" : "\(count) fotos"
    }
    
    static func people(_ count: Int) -> String {
        count == 1 ? "\(count) persona" : "\(count) personas"
    }
    
    static func elements(_ count: Int) -> String {
        count == 1 ? "\(count) elemento" : "\(count) elementos"
    }
    
    static func days(_ count: Int) -> String {
        count == 1 ? "\(count) día" : "\(count) días"
    }
    
    static func items(_ count: Int) -> String {
        count == 1 ? "\(count) elemento" : "\(count) elementos"
    }
    
    static func videos(_ count: Int) -> String {
        count == 1 ? "\(count) video" : "\(count) videos"
    }
    
    static func deletePhotos(_ count: Int) -> String {
        count == 1 ? "Eliminar \(count) foto" : "Eliminar \(count) fotos"
    }
    
    static func deleteOthers(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "Borrar la otra", comment: "Delete the other (singular)")
        } else {
            return String(localized: "Borrar las otras \(count)", comment: "Delete the other N photos")
        }
    }
    
    static func photosConserved(_ count: Int) -> String {
        count == 1 ? "\(count) foto conservada" : "\(count) fotos conservadas"
    }
    
    static func photosToReview(_ count: Int) -> String {
        count == 1 ? "\(count) foto" : "\(count) fotos"
    }
}
