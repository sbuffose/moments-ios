// MomentsAliveChrome.swift
// Animated backgrounds, confetti, counters, rings, shimmer, mascot.

import SwiftUI

struct MomentsAliveBackground: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Double = 0
    
    var body: some View {
        ZStack {
            MomentsColors.bgPrimary
            blob(color: MomentsColors.freshGreen, x: 0.12, y: 0.18, size: 280, drift: 18)
            blob(color: MomentsColors.coral, x: 0.86, y: 0.22, size: 240, drift: -16)
            blob(color: MomentsColors.sunnyYellow, x: 0.22, y: 0.78, size: 220, drift: 14)
            blob(color: MomentsColors.skyBlue, x: 0.82, y: 0.72, size: 260, drift: -12)
            blob(color: MomentsColors.accentSecondary, x: 0.50, y: 0.46, size: 180, drift: 10)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
    
    private func blob(color: Color, x: CGFloat, y: CGFloat, size: CGFloat, drift: CGFloat) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(color.opacity((colorScheme == .dark ? 0.40 : 0.48) * intensity))
                .frame(width: size, height: size)
                .blur(radius: 28)
                .position(
                    x: geo.size.width * x + (reduceMotion ? 0 : drift * phase),
                    y: geo.size.height * y + (reduceMotion ? 0 : -drift * phase)
                )
        }
    }
}

struct MomentsConfettiBurst: View {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let pieces: [(Color, CGFloat, CGFloat, Double)] = [
        (MomentsColors.freshGreen, -40, -90, -18),
        (MomentsColors.coral, 36, -80, 14),
        (MomentsColors.sunnyYellow, -8, -110, 8),
        (MomentsColors.skyBlue, 52, -60, -10),
        (MomentsColors.accentSecondary, -56, -70, 16),
        (MomentsColors.accent, 12, -100, -6),
        (MomentsColors.coral, -24, -50, 20),
        (MomentsColors.sunnyYellow, 44, -96, -22)
    ]
    
    var body: some View {
        ZStack {
            ForEach(pieces.indices, id: \.self) { index in
                let piece = pieces[index]
                Capsule()
                    .fill(piece.0)
                    .frame(width: 8, height: 18)
                    .rotationEffect(.degrees(isActive ? piece.3 : 0))
                    .offset(
                        x: isActive && !reduceMotion ? piece.1 : 0,
                        y: isActive && !reduceMotion ? piece.2 : 0
                    )
                    .opacity(isActive ? (reduceMotion ? 0.35 : 1) : 0)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : MomentsAnimation.springSlow, value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AnimatedByteCounter: View {
    let bytes: Int64
    var identifier: String = "review.animatedCounter"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Int64 = 0
    
    var body: some View {
        Text(SpaceFormatting.string(from: displayed))
            .font(MomentsTypography.numberMedium)
            .foregroundStyle(MomentsColors.freshGreen)
            .monospacedDigit()
            .accessibilityIdentifier(identifier)
            .onAppear { animate(to: bytes) }
            .onChange(of: bytes) { _, newValue in animate(to: newValue) }
    }
    
    private func animate(to target: Int64) {
        if reduceMotion {
            displayed = target
            return
        }
        displayed = 0
        let steps = 12
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.03) {
                displayed = target * Int64(step) / Int64(steps)
            }
        }
    }
}

struct MomentsProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(MomentsColors.bgTertiary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    MomentsColors.accentGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

struct MomentsShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(MomentsColors.bgTertiary)
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        MomentsColors.sunnyYellow.opacity(0.35),
                        MomentsColors.skyBlue.opacity(0.25),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 180)
            )
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

struct MomentsMascot: View {
    var body: some View {
        Text("🌞")
            .font(.system(size: 44))
            .accessibilityLabel(String(localized: "humor_mascot"))
            .accessibilityIdentifier("moments.mascot")
    }
}

struct MomentsCategoryGlyph: View {
    let systemName: String
    let color: Color
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.18), in: Circle())
    }
}

struct MomentsBouncyButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? (reduceMotion ? 0.98 : 0.90) : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.08) : MomentsAnimation.springFast, value: configuration.isPressed)
    }
}

struct HomeCardBreathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: reduceMotion ? 0 : (lifted ? -3 : 3))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    lifted = true
                }
            }
    }
}

/// Tiny text the UI-test host can query. Color.clear overlays never enter the AX tree.
struct AccessibilityProbe: View {
    let id: String
    var label: String? = nil
    
    var body: some View {
        Text(label ?? id)
            .font(.system(size: 1))
            .foregroundStyle(.white.opacity(0.012))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(id)
            .accessibilityLabel(label ?? id)
            .accessibilityValue(label ?? id)
            .allowsHitTesting(false)
    }
}

extension View {
    func homeCardBreathing() -> some View {
        modifier(HomeCardBreathing())
    }
    
    func accessibilityProbe(_ id: String) -> some View {
        overlay(alignment: .topLeading) {
            AccessibilityProbe(id: id)
        }
    }
}
