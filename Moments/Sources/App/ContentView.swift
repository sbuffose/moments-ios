// ContentView.swift
// Vista principal con navegación por tabs

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    private var isTestingMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboarding") ||
        ProcessInfo.processInfo.arguments.contains("--uitesting") ||
        ProcessInfo.processInfo.environment["UI_TESTING"] == "1" ||
        ProcessInfo.processInfo.environment["UITEST_MODE"] == "1"
    }
    
    var body: some View {
        Group {
            if isTestingMode {
                if !appState.hasCompletedInitialIndexing {
                    ScanningView()
                        .onAppear {
                            appState.isLibraryAuthorized = true
                            appState.hasCompletedOnboarding = true
                            if !appState.isIndexing {
                                appState.startScan()
                            }
                        }
                } else {
                    MainTabView()
                }
            } else if !appState.hasCompletedOnboarding {
                OnboardingView()
            } else if !appState.hasCompletedInitialIndexing {
                ScanningView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(isTestingMode ? "app.testing_mode" : "app.root")
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
                .accessibilityIdentifier("tab.home")
            
            AssistantView()
                .tabItem {
                    Label(String(localized: "tab_assistant"), systemImage: AppState.AppTab.assistant.icon)
                }
                .tag(AppState.AppTab.assistant)
                .accessibilityIdentifier("tab.assistant")
            
            MomentsListView()
                .tabItem {
                    Label(String(localized: "tab_moments"), systemImage: AppState.AppTab.moments.icon)
                }
                .tag(AppState.AppTab.moments)
                .accessibilityIdentifier("tab.moments")
            
            SettingsView()
                .tabItem {
                    Label(String(localized: "tab_settings"), systemImage: AppState.AppTab.settings.icon)
                }
                .tag(AppState.AppTab.settings)
                .accessibilityIdentifier("tab.settings")
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
        
        var accessibilityId: String {
            switch self {
            case .timeline: return "moments.timeline"
            case .people: return "moments.people"
            case .places: return "moments.places"
            case .dates: return "fechas.root"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("moments.root")
                
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
                            .accessibilityIdentifier("chip.\(section.rawValue)")
                        }
                    }
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    .padding(.vertical, MomentsSpacing.sm)
                }
                
                Group {
                    switch selectedSection {
                    case .timeline:
                        TimelineView()
                            .accessibilityIdentifier("moments.timeline.content")
                    case .people:
                        PeopleView()
                            .accessibilityIdentifier("moments.people.content")
                    case .places:
                        PlacesView()
                            .accessibilityIdentifier("moments.places.content")
                    case .dates:
                        FechasView()
                            .accessibilityIdentifier("fechas.content")
                    }
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
                    .accessibilityIdentifier("onboarding.page1")
                    
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
                    .accessibilityIdentifier("onboarding.page2")
                    
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
                    .accessibilityIdentifier("onboarding.page3")
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
                        .accessibilityIdentifier("onboarding.continue")
                        
                        Button {
                            withAnimation {
                                currentPage = 2
                            }
                        } label: {
                            Text(String(localized: "onboarding_skip"))
                                .font(MomentsTypography.labelMedium)
                                .foregroundStyle(MomentsColors.textSecondary)
                        }
                        .accessibilityIdentifier("onboarding.skip")
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
                        .accessibilityIdentifier("onboarding.allowAccess")
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
        .accessibilityIdentifier("onboarding.root")
    }
    
    private func requestAccess() {
        isRequesting = true
        Task {
            let granted = await appState.requestAuthorization()
            if granted {
                appState.completeOnboarding()
            }
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
                    
                    if appState.isIndexing {
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
                    Text(appState.isIndexing 
                         ? String(localized: "scanning_in_progress") 
                         : String(localized: "scanning_ready"))
                        .font(MomentsTypography.titleMedium)
                        .foregroundStyle(MomentsColors.textPrimary)
                        .accessibilityIdentifier(appState.isIndexing ? "scanning.inProgress" : "scanning.ready")
                    
                    if appState.isIndexing {
                        Text(String(localized: "scanning_photos_count \(appState.totalPhotosIndexed)"))
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                            .accessibilityIdentifier("scanning.count")
                        
                        ProgressView(value: appState.indexingProgress)
                            .progressViewStyle(.linear)
                            .tint(MomentsColors.accent)
                            .padding(.horizontal, MomentsSpacing.xl)
                            .accessibilityIdentifier("scanning.progress")
                    } else {
                        Text(String(localized: "scanning_description"))
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, MomentsSpacing.lg)
                    }
                }
                
                Spacer()
                
                if !appState.isIndexing {
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
                    .accessibilityIdentifier("scanning.startButton")
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier(appState.hasCompletedInitialIndexing ? "scanning.complete" : "scanning.root")
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
