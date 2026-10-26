// ContentView.swift
// Vista principal con navegación por tabs

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var shouldSkipOnboarding: Bool = false
    
    var body: some View {
        Group {
            if shouldSkipOnboarding {
                if !appState.hasCompletedInitialScan {
                    ScanningView()
                } else {
                    MainTabView()
                }
            } else if !appState.isLibraryAuthorized {
                OnboardingView()
            } else if !appState.hasCompletedInitialScan {
                ScanningView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            checkLaunchArguments()
        }
    }
    
    private func checkLaunchArguments() {
        if CommandLine.arguments.contains("-skipOnboarding") {
            shouldSkipOnboarding = true
            appState.isLibraryAuthorized = true
            appState.hasCompletedInitialScan = true
        }
        if CommandLine.arguments.contains("-resetState") {
            UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label(String(localized: "tab_home"), systemImage: AppState.AppTab.home.icon)
                }
                .tag(AppState.AppTab.home)
                .accessibilityIdentifier("home_tab")
            
            AssistantView()
                .tabItem {
                    Label(String(localized: "tab_assistant"), systemImage: AppState.AppTab.assistant.icon)
                }
                .tag(AppState.AppTab.assistant)
                .accessibilityIdentifier("assistant_tab")
            
            MomentsListView()
                .tabItem {
                    Label(String(localized: "tab_moments"), systemImage: AppState.AppTab.moments.icon)
                }
                .tag(AppState.AppTab.moments)
                .accessibilityIdentifier("moments_tab")
            
            SettingsView()
                .tabItem {
                    Label(String(localized: "tab_settings"), systemImage: AppState.AppTab.settings.icon)
                }
                .tag(AppState.AppTab.settings)
                .accessibilityIdentifier("settings_tab")
        }
        .tint(MomentsColors.accent)
        .accessibilityIdentifier("main_tab_view")
    }
}

// MARK: - Moments List View

struct MomentsListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: MomentsSection = .timeline
    
    enum MomentsSection: String, CaseIterable {
        case timeline, people, places, dates
        
        var localizedName: String {
            switch self {
            case .timeline: return String(localized: "tab_timeline")
            case .people: return String(localized: "tab_people")
            case .places: return String(localized: "tab_places")
            case .dates: return String(localized: "tab_fechas")
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MomentsSpacing.xs) {
                        ForEach(MomentsSection.allCases, id: \.self) { section in
                            MomentsChip(
                                label: section.localizedName,
                                isSelected: selectedSection == section,
                                action: {
                                    withAnimation(MomentsAnimation.spring) {
                                        selectedSection = section
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    .padding(.vertical, MomentsSpacing.sm)
                }
                
                Group {
                    switch selectedSection {
                    case .timeline:
                        TimelineView()
                    case .people:
                        PeopleView()
                    case .places:
                        PlacesView()
                    case .dates:
                        FechasView()
                    }
                }
            }
            .navigationTitle(Text(String(localized: "tab_moments")))
            .background(MomentsColors.bgPrimary)
        }
    }
}

// MARK: - Onboarding View (Dark Premium)

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    @State private var isRequesting = false
    
    var body: some View {
        ZStack {
            MomentsColors.bgPrimary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingPageView(
                        iconName: "externaldrive.badge.minus",
                        iconGradient: [Color.blue, Color.purple],
                        titleKey: "onboarding_page1_title",
                        subtitleKey: "onboarding_page1_subtitle",
                        highlights: [
                            ("trash.slash", "onboarding_page1_highlight1"),
                            ("photo.stack", "onboarding_page1_highlight2"),
                            ("sparkles", "onboarding_page1_highlight3")
                        ]
                    )
                    .tag(0)
                    
                    OnboardingPageView(
                        iconName: "heart.text.square",
                        iconGradient: [Color.pink, Color.orange],
                        titleKey: "onboarding_page2_title",
                        subtitleKey: "onboarding_page2_subtitle",
                        highlights: [
                            ("clock.arrow.circlepath", "onboarding_page2_highlight1"),
                            ("gift", "onboarding_page2_highlight2"),
                            ("airplane", "onboarding_page2_highlight3")
                        ]
                    )
                    .tag(1)
                    
                    OnboardingPageView(
                        iconName: "lock.iphone",
                        iconGradient: [Color.green, Color.teal],
                        titleKey: "onboarding_page3_title",
                        subtitleKey: "onboarding_page3_subtitle",
                        highlights: [
                            ("iphone", "onboarding_page3_highlight1"),
                            ("network.slash", "onboarding_page3_highlight2"),
                            ("hand.raised.fill", "onboarding_page3_highlight3")
                        ]
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                
                VStack(spacing: MomentsSpacing.md) {
                    if currentPage < 2 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        } label: {
                            Text(String(localized: "onboarding_continue"))
                                .font(MomentsTypography.buttonLarge)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, MomentsSpacing.md)
                                .background(
                                    LinearGradient(
                                        colors: [MomentsColors.accent, MomentsColors.accent.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(MomentsCorners.large)
                        }
                        .accessibilityIdentifier("onboarding_continue_button")
                        
                        Button {
                            withAnimation {
                                currentPage = 2
                            }
                        } label: {
                            Text(String(localized: "onboarding_skip"))
                                .font(MomentsTypography.labelMedium)
                                .foregroundStyle(MomentsColors.textSecondary)
                        }
                        .accessibilityIdentifier("onboarding_skip_button")
                    } else {
                        Button {
                            requestAccess()
                        } label: {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, MomentsSpacing.md)
                            } else {
                                HStack(spacing: MomentsSpacing.sm) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                    Text(String(localized: "onboarding_allow_access"))
                                }
                                .font(MomentsTypography.buttonLarge)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, MomentsSpacing.md)
                            }
                        }
                        .background(
                            LinearGradient(
                                colors: [MomentsColors.accent, MomentsColors.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(MomentsCorners.large)
                        .accessibilityIdentifier("onboarding_start_button")
                        .disabled(isRequesting)
                        
                        Text(String(localized: "onboarding_privacy_footer"))
                            .font(MomentsTypography.labelSmall)
                            .foregroundStyle(MomentsColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, MomentsSpacing.screenHorizontal)
                .padding(.bottom, MomentsSpacing.xl)
            }
        }
    }
    
    private func requestAccess() {
        isRequesting = true
        Task {
            _ = await appState.requestAuthorization()
            isRequesting = false
        }
    }
}

struct OnboardingPageView: View {
    let iconName: String
    let iconGradient: [Color]
    let titleKey: String
    let subtitleKey: String
    let highlights: [(icon: String, text: String)]
    
    var body: some View {
        VStack(spacing: MomentsSpacing.xl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: iconGradient.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                
                Image(systemName: iconName)
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: iconGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: MomentsSpacing.sm) {
                Text(String(localized: String.LocalizationValue(titleKey)))
                    .font(MomentsTypography.titleLarge)
                    .foregroundStyle(MomentsColors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text(String(localized: String.LocalizationValue(subtitleKey)))
                    .font(MomentsTypography.bodyMedium)
                    .foregroundStyle(MomentsColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MomentsSpacing.lg)
            }
            
            VStack(alignment: .leading, spacing: MomentsSpacing.md) {
                ForEach(highlights, id: \.icon) { highlight in
                    HStack(spacing: MomentsSpacing.md) {
                        Image(systemName: highlight.icon)
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: iconGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32)
                        
                        Text(String(localized: String.LocalizationValue(highlight.text)))
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                    }
                }
            }
            .padding(.horizontal, MomentsSpacing.xl)
            .padding(.top, MomentsSpacing.md)
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Scanning View (Dark Premium)

struct ScanningView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            MomentsColors.bgPrimary.ignoresSafeArea()
            
            VStack(spacing: MomentsSpacing.xl) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(MomentsColors.accent.opacity(0.15))
                        .frame(width: 160, height: 160)
                    
                    if appState.isScanning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(2)
                            .tint(MomentsColors.accent)
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 72, weight: .light))
                            .foregroundStyle(MomentsColors.accent)
                    }
                }
                
                VStack(spacing: MomentsSpacing.sm) {
                    Text(appState.isScanning 
                         ? String(localized: "scanning_in_progress") 
                         : String(localized: "scanning_ready"))
                        .font(MomentsTypography.titleMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                    
                    if appState.isScanning {
                        Text(String(localized: "scanning_photos_count \(appState.totalPhotosIndexed)"))
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                        
                        ProgressView(value: appState.scanProgress)
                            .progressViewStyle(.linear)
                            .tint(MomentsColors.accent)
                            .padding(.horizontal, MomentsSpacing.xl)
                    } else {
                        Text(String(localized: "scanning_description"))
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, MomentsSpacing.lg)
                    }
                }
                
                Spacer()
                
                if !appState.isScanning {
                    Button {
                        appState.startScan()
                    } label: {
                        Text(String(localized: "scanning_start_button"))
                            .font(MomentsTypography.buttonLarge)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MomentsSpacing.md)
                            .background(
                                LinearGradient(
                                    colors: [MomentsColors.accent, MomentsColors.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(MomentsCorners.large)
                    }
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    .padding(.bottom, MomentsSpacing.xl)
                    .accessibilityIdentifier("start_scan_button")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
