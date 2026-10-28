// MomentsTheme.swift
// Design system: sage/terracotta on warm cream, rounded type, Reduce Motion.

import SwiftUI
import UIKit

// MARK: - Theme Colors

struct MomentsColors {
    static let backgroundPrimary = Color("BackgroundPrimary")
    static let backgroundSecondary = Color("BackgroundSecondary")
    static let backgroundTertiary = Color("BackgroundTertiary")
    static let backgroundCard = Color("BackgroundCard")
    
    /// Warm cream (light) / deep green-grey, never black (dark).
    static let lightCream = UIColor(red: 0.965, green: 0.945, blue: 0.902, alpha: 1.0)
    static let darkGreenGrey = UIColor(red: 0.118, green: 0.157, blue: 0.137, alpha: 1.0)
    static let sageUIColor = UIColor(red: 0.310, green: 0.478, blue: 0.376, alpha: 1.0)
    static let terracottaUIColor = UIColor(red: 0.761, green: 0.365, blue: 0.227, alpha: 1.0)
    
    static var bgPrimary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? darkGreenGrey
                : lightCream
        })
    }
    
    static var bgSecondary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.21, blue: 0.18, alpha: 1.0)
                : UIColor(red: 0.945, green: 0.922, blue: 0.870, alpha: 1.0)
        })
    }
    
    static var bgTertiary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.20, green: 0.26, blue: 0.22, alpha: 1.0)
                : UIColor(red: 0.922, green: 0.894, blue: 0.835, alpha: 1.0)
        })
    }
    
    static var bgCard: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.175, green: 0.225, blue: 0.196, alpha: 1.0)
                : UIColor(red: 0.988, green: 0.973, blue: 0.945, alpha: 1.0)
        })
    }
    
    static var textPrimary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.95, green: 0.96, blue: 0.93, alpha: 1.0)
                : UIColor(red: 0.16, green: 0.20, blue: 0.17, alpha: 1.0)
        })
    }
    
    static var textSecondary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.72, green: 0.76, blue: 0.70, alpha: 1.0)
                : UIColor(red: 0.36, green: 0.40, blue: 0.34, alpha: 1.0)
        })
    }
    
    static var textTertiary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.52, green: 0.58, blue: 0.52, alpha: 1.0)
                : UIColor(red: 0.50, green: 0.54, blue: 0.47, alpha: 1.0)
        })
    }
    
    /// Soft sage — primary.
    static let accent = Color(red: 0.310, green: 0.478, blue: 0.376)
    /// Warm terracotta — accent / CTAs.
    static let accentSecondary = Color(red: 0.761, green: 0.365, blue: 0.227)
    
    static func pastelChip(for category: CleanupCategoryType) -> Color {
        switch category {
        case .screenshot, .screenRecording: return Color(red: 0.86, green: 0.93, blue: 0.88)
        case .blurry, .underexposed: return Color(red: 0.93, green: 0.90, blue: 0.84)
        case .overexposed: return Color(red: 0.98, green: 0.90, blue: 0.82)
        case .duplicate, .nearDuplicate, .burst: return Color(red: 0.84, green: 0.92, blue: 0.86)
        case .document, .receipt, .qrCode: return Color(red: 0.97, green: 0.88, blue: 0.82)
        case .livePhoto: return Color(red: 0.90, green: 0.93, blue: 0.86)
        default: return Color(red: 0.92, green: 0.93, blue: 0.88)
        }
    }
    
    static func relativeLuminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
    
    static func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat {
        let l1 = relativeLuminance(foreground)
        let l2 = relativeLuminance(background)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var accentGradientSubtle: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.85), accentSecondary.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static let success = Color(red: 0.31, green: 0.55, blue: 0.38)
    static let warning = Color(red: 0.76, green: 0.42, blue: 0.22)
    static let error = Color.red
    static let info = Color(red: 0.36, green: 0.50, blue: 0.42)
    
    static var cardBorder: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(red: 0.82, green: 0.78, blue: 0.70, alpha: 1.0)
        })
    }
}

// MARK: - UI-test appearance override (never hard-codes system dark)

enum UITestAppearance {
    static let darkArgument = "-uiAppearanceDark"
    static let lightArgument = "-uiAppearanceLight"
    
    static var override: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains(darkArgument) { return ColorScheme.dark }
        if args.contains(lightArgument) { return ColorScheme.light }
        return nil
    }
}

// MARK: - Typography (SF Pro Rounded + Dynamic Type)

struct MomentsTypography {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: .rounded).weight(weight)
    }
    
    static let displayLarge = rounded(.largeTitle, weight: .bold)
    static let displayMedium = rounded(.title, weight: .bold)
    static let displaySmall = rounded(.title2, weight: .bold)
    
    static let titleLarge = rounded(.title, weight: .bold)
    static let titleMedium = rounded(.title2, weight: .semibold)
    static let titleSmall = rounded(.title3, weight: .semibold)
    
    static let headlineLarge = rounded(.title3, weight: .semibold)
    static let headlineMedium = rounded(.headline, weight: .semibold)
    static let headlineSmall = rounded(.headline, weight: .semibold)
    
    static let bodyLarge = rounded(.body, weight: .regular)
    static let bodyMedium = rounded(.body, weight: .regular)
    static let bodySmall = rounded(.callout, weight: .regular)
    
    static let labelLarge = rounded(.callout, weight: .medium)
    static let labelMedium = rounded(.subheadline, weight: .medium)
    static let labelSmall = rounded(.caption, weight: .medium)
    
    static let buttonLarge = rounded(.body, weight: .semibold)
    static let buttonMedium = rounded(.callout, weight: .semibold)
    static let buttonSmall = rounded(.subheadline, weight: .semibold)
    
    static let numberLarge = rounded(.largeTitle, weight: .bold)
    static let numberMedium = rounded(.title, weight: .bold)
    static let numberSmall = rounded(.title3, weight: .semibold)
}

// MARK: - Spacing

struct MomentsSpacing {
    static let xxs: CGFloat = 6
    static let xs: CGFloat = 10
    static let sm: CGFloat = 14
    static let md: CGFloat = 20
    static let lg: CGFloat = 28
    static let xl: CGFloat = 36
    static let xxl: CGFloat = 56
    
    static let cardPadding: CGFloat = 24
    static let cardRadius: CGFloat = 24
    static let cardSpacing: CGFloat = 20
    
    static let screenHorizontal: CGFloat = 24
    static let screenVertical: CGFloat = 20
}

// MARK: - Corner Radius

struct MomentsCorners {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let card: CGFloat = 24
}

// MARK: - Animations + Reduce Motion

struct MomentsAnimation {
    static let springResponse: Double = 0.5
    static let springDamping: Double = 0.82
    
    static var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
    
    static var springFast: Animation {
        .spring(response: 0.32, dampingFraction: 0.78)
    }
    
    static var springSlow: Animation {
        .spring(response: 0.7, dampingFraction: 0.86)
    }
    
    static var easeOut: Animation {
        .easeOut(duration: 0.25)
    }
}

enum MomentsMotion {
    static func spring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : MomentsAnimation.spring
    }
    
    static func entrance(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.58, dampingFraction: 0.86)
    }
    
    static func animate(reduceMotion: Bool, _ body: @escaping () -> Void) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, body)
        } else {
            withAnimation(entrance(reduceMotion: false), body)
        }
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
                    ? Color.black.opacity(0.35)
                    : Color.black.opacity(0.06),
                radius: colorScheme == .dark ? 18 : 14,
                x: 0,
                y: colorScheme == .dark ? 8 : 5
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MomentsColors.bgCard)
            .cornerRadius(MomentsSpacing.cardRadius)
            .overlay(
                RoundedRectangle(cornerRadius: MomentsSpacing.cardRadius)
                    .stroke(MomentsColors.cardBorder, lineWidth: colorScheme == .dark ? 1 : 0)
            )
            .shadow(
                color: colorScheme == .dark
                    ? Color.black.opacity(0.3)
                    : Color.black.opacity(0.06),
                radius: colorScheme == .dark ? 16 : 14,
                x: 0,
                y: colorScheme == .dark ? 6 : 5
            )
    }
}

struct MomentsAccentButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MomentsTypography.headlineMedium)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, MomentsSpacing.md)
            .padding(.horizontal, MomentsSpacing.lg)
            .background(
                MomentsColors.accentGradient
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .cornerRadius(16)
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
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.vertical, MomentsSpacing.md)
            .padding(.horizontal, MomentsSpacing.lg)
            .background(MomentsColors.bgTertiary)
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(MomentsAnimation.springFast, value: configuration.isPressed)
    }
}

/// Styled label for NavigationLink. Never apply ButtonStyle to a NavigationLink —
/// it swallows the tap (dim without navigate).
struct MomentsAccentLinkLabel: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(MomentsTypography.headlineMedium)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MomentsSpacing.md)
            .padding(.horizontal, MomentsSpacing.lg)
            .background(MomentsColors.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Button label that never hyphenates mid-word (`Revi-sar`, `Elimi-nar`).
struct UnbrokenActionLabel: View {
    let title: String
    var systemImage: String? = nil
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            labeledStack(axis: .horizontal)
            labeledStack(axis: .vertical)
        }
    }
    
    @ViewBuilder
    private func labeledStack(axis: Axis) -> some View {
        let text = Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .truncationMode(.tail)
            .fixedSize(horizontal: axis == .vertical, vertical: true)
        if axis == .horizontal {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                text
            }
        } else {
            VStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                text
            }
        }
    }
}

// MARK: - View Extensions

struct MomentsEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                MomentsMotion.animate(reduceMotion: reduceMotion) {
                    shown = true
                }
            }
    }
}

extension View {
    func momentsEntrance() -> some View {
        modifier(MomentsEntrance())
    }
    
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
