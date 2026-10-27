// MomentsTheme.swift
// Design system: Colors, Typography, Spacing - Light/Dark adaptive design

import SwiftUI

// MARK: - Theme Colors
// All colors centralized in Assets.xcassets/Colors with light/dark variants

struct MomentsColors {
    // Primary backgrounds from asset catalog
    // Light: very light warm-gray (#FAFAFA)
    // Dark: lifted surface (#1C1C1E) - not pure black
    static let bgPrimary = Color("Colors/BackgroundPrimary")
    
    // Secondary backgrounds
    // Light: light warm-gray (#F5F5F5)
    // Dark: lifted secondary (#2C2C2E)
    static let bgSecondary = Color("Colors/BackgroundSecondary")
    
    // Tertiary backgrounds
    // Light: slightly darker warm-gray (#EDEDED)
    // Dark: lifted tertiary (#3A3A3A)
    static let bgTertiary = Color("Colors/BackgroundTertiary")
    
    // Card backgrounds
    // Light: white for elevated cards with soft shadows
    // Dark: slightly lighter than primary (#232325)
    static let bgCard = Color("Colors/BackgroundCard")
    
    // Text colors with WCAG AA compliance
    // Primary: black in light, white in dark
    static let textPrimary = Color("Colors/TextPrimary")
    
    // Secondary: gray (0.44) in light, high-contrast (0.75) in dark for WCAG AA
    static let textSecondary = Color("Colors/TextSecondary")
    
    // Tertiary: lighter gray in both modes
    static let textTertiary = Color("Colors/TextTertiary")
    
    // Card styling
    static let cardBorder = Color("Colors/CardBorder")
    static let cardShadow = Color("Colors/CardShadow")
    
    // Legacy aliases for backward compatibility
    static var backgroundPrimary: Color { bgPrimary }
    static var backgroundSecondary: Color { bgSecondary }
    static var backgroundTertiary: Color { bgTertiary }
    static var backgroundCard: Color { bgCard }
    
    // Accent - Vivid blue-to-purple gradient for primary actions
    static let accent = Color(red: 0.2, green: 0.5, blue: 1.0)
    static let accentSecondary = Color(red: 0.4, green: 0.3, blue: 0.95)
    
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
                    ? Color.black.opacity(0.3) 
                    : Color.black.opacity(0.06),
                radius: colorScheme == .dark ? 12 : 16,
                x: 0,
                y: colorScheme == .dark ? 4 : 6
            )
    }
    
    static func cardLight() -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.06), 16, 0, 6)
    }
    
    static func cardDark() -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.3), 12, 0, 4)
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
                    .stroke(MomentsColors.cardBorder, lineWidth: colorScheme == .dark ? 1 : 0.5)
            )
            .shadow(
                color: colorScheme == .dark 
                    ? Color.black.opacity(0.3) 
                    : Color.black.opacity(0.08),
                radius: colorScheme == .dark ? 12 : 20,
                x: 0,
                y: colorScheme == .dark ? 4 : 8
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
