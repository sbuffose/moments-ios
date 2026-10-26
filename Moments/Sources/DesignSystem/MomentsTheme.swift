// MomentsTheme.swift
// Design system: Colors, Typography, Spacing - Dark-first premium design

import SwiftUI

// MARK: - Theme Colors

struct MomentsColors {
    // Backgrounds (dark-first)
    static let backgroundPrimary = Color("BackgroundPrimary")
    static let backgroundSecondary = Color("BackgroundSecondary")
    static let backgroundTertiary = Color("BackgroundTertiary")
    static let backgroundCard = Color("BackgroundCard")
    
    // Adaptive colors with fallbacks
    static var bgPrimary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark 
                ? UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) // Pure black
                : UIColor.systemBackground
        })
    }
    
    static var bgSecondary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark 
                ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0) // Graphite
                : UIColor.secondarySystemBackground
        })
    }
    
    static var bgTertiary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark 
                ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) // Lighter graphite
                : UIColor.tertiarySystemBackground
        })
    }
    
    static var bgCard: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark 
                ? UIColor(red: 0.1, green: 0.1, blue: 0.11, alpha: 1.0)
                : UIColor.systemBackground
        })
    }
    
    // Text colors
    static var textPrimary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? .white : .label
        })
    }
    
    static var textSecondary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark 
                ? UIColor(white: 0.6, alpha: 1.0)
                : UIColor.secondaryLabel
        })
    }
    
    static var textTertiary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark 
                ? UIColor(white: 0.4, alpha: 1.0)
                : UIColor.tertiaryLabel
        })
    }
    
    // Accent - Vivid blue with gradient capability
    static let accent = Color(red: 0.2, green: 0.5, blue: 1.0) // Vivid blue
    static let accentSecondary = Color(red: 0.4, green: 0.3, blue: 0.95) // Purple tint
    
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var accentGradientSubtle: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.8), accentSecondary.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Semantic colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    
    // Card border/shadow
    static var cardBorder: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark 
                ? UIColor(white: 0.15, alpha: 1.0)
                : UIColor.separator
        })
    }
}

// MARK: - Typography

struct MomentsTypography {
    // Display titles - Large, bold
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .default)
    static let displaySmall = Font.system(size: 24, weight: .bold, design: .default)
    
    // Title - semantic aliases
    static let titleLarge = Font.system(size: 28, weight: .bold, design: .default)
    static let titleMedium = Font.system(size: 22, weight: .semibold, design: .default)
    static let titleSmall = Font.system(size: 18, weight: .semibold, design: .default)
    
    // Headlines
    static let headlineLarge = Font.system(size: 20, weight: .semibold, design: .default)
    static let headlineMedium = Font.system(size: 17, weight: .semibold, design: .default)
    static let headlineSmall = Font.system(size: 15, weight: .semibold, design: .default)
    
    // Body
    static let bodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
    
    // Labels
    static let labelLarge = Font.system(size: 15, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 13, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)
    
    // Buttons
    static let buttonLarge = Font.system(size: 17, weight: .semibold, design: .default)
    static let buttonMedium = Font.system(size: 15, weight: .semibold, design: .default)
    static let buttonSmall = Font.system(size: 13, weight: .semibold, design: .default)
    
    // Monospace for numbers
    static let numberLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    static let numberMedium = Font.system(size: 32, weight: .bold, design: .rounded)
    static let numberSmall = Font.system(size: 20, weight: .semibold, design: .rounded)
}

// MARK: - Spacing

struct MomentsSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    
    // Card specific
    static let cardPadding: CGFloat = 20
    static let cardRadius: CGFloat = 20
    static let cardSpacing: CGFloat = 16
    
    // Screen margins
    static let screenHorizontal: CGFloat = 20
    static let screenVertical: CGFloat = 16
}

// MARK: - Corner Radius

struct MomentsCorners {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let card: CGFloat = 20
}

// MARK: - Animations

struct MomentsAnimation {
    static let springResponse: Double = 0.4
    static let springDamping: Double = 0.75
    
    static var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
    
    static var springFast: Animation {
        .spring(response: 0.3, dampingFraction: 0.7)
    }
    
    static var springSlow: Animation {
        .spring(response: 0.6, dampingFraction: 0.8)
    }
    
    static var easeOut: Animation {
        .easeOut(duration: 0.25)
    }
}

// MARK: - Haptics

struct MomentsHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Shadow

struct MomentsShadow {
    static func card(_ colorScheme: ColorScheme) -> some View {
        EmptyView()
            .shadow(
                color: colorScheme == .dark 
                    ? Color.black.opacity(0.5) 
                    : Color.black.opacity(0.08),
                radius: colorScheme == .dark ? 20 : 12,
                x: 0,
                y: colorScheme == .dark ? 8 : 4
            )
    }
}

// MARK: - View Modifiers

struct MomentsCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var padding: CGFloat = MomentsSpacing.cardPadding
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MomentsColors.bgCard)
            .cornerRadius(MomentsSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: MomentsSpacing.cardRadius)
                    .stroke(MomentsColors.cardBorder, lineWidth: colorScheme == .dark ? 1 : 0)
            )
            .shadow(
                color: colorScheme == .dark 
                    ? Color.black.opacity(0.4) 
                    : Color.black.opacity(0.06),
                radius: colorScheme == .dark ? 16 : 12,
                x: 0,
                y: colorScheme == .dark ? 6 : 4
            )
    }
}

struct MomentsAccentButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MomentsTypography.headlineMedium)
            .foregroundStyle(.white)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, MomentsSpacing.md)
            .padding(.horizontal, MomentsSpacing.lg)
            .background(
                MomentsColors.accentGradient
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .cornerRadius(14)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(MomentsAnimation.springFast, value: configuration.isPressed)
    }
}

struct MomentsSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    var isFullWidth: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MomentsTypography.headlineMedium)
            .foregroundStyle(MomentsColors.textPrimary)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, MomentsSpacing.md)
            .padding(.horizontal, MomentsSpacing.lg)
            .background(MomentsColors.bgTertiary)
            .cornerRadius(14)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(MomentsAnimation.springFast, value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func momentsCard(padding: CGFloat = MomentsSpacing.cardPadding) -> some View {
        modifier(MomentsCardStyle(padding: padding))
    }
    
    func momentsAccentButton(fullWidth: Bool = true) -> some View {
        buttonStyle(MomentsAccentButtonStyle(isFullWidth: fullWidth))
    }
    
    func momentsSecondaryButton(fullWidth: Bool = true) -> some View {
        buttonStyle(MomentsSecondaryButtonStyle(isFullWidth: fullWidth))
    }
}
