// FirstRunAnalyzingView.swift
// Calm full-screen while the first library analysis runs. No partial cleanup offers.

import SwiftUI

struct FirstRunAnalyzingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var appeared = true
    
    static let title = "Estamos conociendo tus fotos"
    static let bodyCopy = "Esto tarda unos 10 minutos. Podés cerrar la app y seguir con lo tuyo: te avisamos cuando esté listo para limpiar y etiquetar."
    static let softProgressLabel = "Aprendiendo de tu biblioteca…"
    
    static let launchArgument = "-simulateFirstScan"
    
    static var isSimulated: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
    
    private var isUITesting: Bool {
        ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
    }
    
    var body: some View {
        ZStack {
            MomentsColors.bgPrimary.ignoresSafeArea()
            
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("home.root")
            
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("firstRun.root")
            
            VStack(spacing: MomentsSpacing.lg) {
                Spacer()
                
                FirstRunClockIllustration()
                    .frame(width: 140, height: 140)
                
                Text(Self.title)
                    .font(MomentsTypography.displaySmall)
                    .foregroundStyle(MomentsColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("firstRun.title")
                
                Text(Self.bodyCopy)
                    .font(MomentsTypography.bodyLarge)
                    .foregroundStyle(MomentsColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("firstRun.message")
                
                VStack(spacing: MomentsSpacing.sm) {
                    ProgressView(value: softProgress)
                        .tint(MomentsColors.accent)
                        .accessibilityIdentifier("firstRun.softProgress")
                    Text(Self.softProgressLabel)
                        .font(MomentsTypography.labelMedium)
                        .foregroundStyle(MomentsColors.textTertiary)
                        .accessibilityIdentifier("firstRun.softProgressLabel")
                }
                .padding(.top, MomentsSpacing.sm)
                
                if appState.notificationsAuthorized {
                    Label("Te vamos a avisar", systemImage: "bell.fill")
                        .font(MomentsTypography.labelLarge)
                        .foregroundStyle(MomentsColors.accent)
                        .accessibilityIdentifier("firstRun.notifyEnabled")
                } else {
                    Button {
                        Task {
                            _ = await appState.requestNotificationPermission()
                        }
                    } label: {
                        Text("Avisame cuando esté listo")
                    }
                    .momentsAccentButton()
                    .accessibilityIdentifier("firstRun.notifyButton")
                }
                
                Spacer()
            }
            .padding(.horizontal, MomentsSpacing.xl)
            .offset(y: appeared || reduceMotion ? 0 : 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("firstRun.screen")
        .onAppear {
            MomentsMotion.animate(reduceMotion: reduceMotion) {
                appeared = true
            }
            if !isUITesting && !appState.notificationsAuthorized {
                Task {
                    _ = await appState.requestNotificationPermission()
                }
            }
        }
    }
    
    /// Soft bar without exposing raw 1100/7781. Clamp so it never looks empty or done.
    private var softProgress: Double {
        let raw = appState.isIndexing ? appState.indexingProgress : appState.analysisProgress
        if raw <= 0 { return 0.12 }
        return min(0.92, max(0.12, raw))
    }
}

struct FirstRunClockIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false
    @State private var pulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(MomentsColors.accent.opacity(0.12))
                .scaleEffect(pulsing && !reduceMotion ? 1.08 : 1.0)
            Circle()
                .stroke(MomentsColors.accent.opacity(0.25), lineWidth: 3)
                .padding(10)
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 56, weight: .medium, design: .rounded))
                .foregroundStyle(MomentsColors.accentGradient)
                .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
        }
        .onAppear {
            if reduceMotion {
                spinning = false
                pulsing = false
            } else {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    spinning = true
                }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .accessibilityIdentifier("firstRun.clock")
        .accessibilityLabel("Reloj amistoso, seguimos conociendo tus fotos")
    }
}

enum FirstRunCopy {
    static let title = FirstRunAnalyzingView.title
    static let body = FirstRunAnalyzingView.bodyCopy
    
    static func containsRawLibraryCount(_ text: String) -> Bool {
        let pattern = #"\b\d{3,}\s*/\s*\d{3,}\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
    
    static let analysisCompleteNotificationTitle = "Moments ya está listo"
    static let analysisCompleteNotificationBody = "Ya podés limpiar y etiquetar tus fotos."
}
