// ContentView.swift
// Vista principal con navegación por tabs

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var newPhotoCheck = NewPhotoCheckService.shared
    
    private var isTestingMode: Bool {
        if DesignTourSimulation.showOnboarding { return false }
        return ProcessInfo.processInfo.arguments.contains("-skipOnboarding") ||
        ProcessInfo.processInfo.arguments.contains("--uitesting") ||
        ProcessInfo.processInfo.environment["UI_TESTING"] == "1" ||
        ProcessInfo.processInfo.environment["UITEST_MODE"] == "1"
    }
    
    var body: some View {
        Group {
            if DesignTourSimulation.showOnboarding {
                OnboardingView()
            } else if isTestingMode {
                // Testing mode: skip onboarding, go directly to home
                MainTabView()
                    .onAppear {
                        appState.isLibraryAuthorized = true
                        appState.hasCompletedOnboarding = true
                        // Start background processing (non-blocking)
                        if !MomentsTestRuntime.shouldSkipLiveScan
                            && !FixturePhotoSeeder.isRequested
                            && !ActiveScanSimulation.isRequested
                            && !appState.isIndexing && !appState.isAnalyzing {
                            appState.startBackgroundIndexingAndAnalysis()
                        }
                    }
            } else if !appState.hasCompletedOnboarding {
                OnboardingView()
            } else {
                // After onboarding, ALWAYS show home immediately
                // Background processing runs in the background, never blocks UI
                MainTabView()
                    .onAppear {
                        // Ensure background processing is running
                        if appState.isLibraryAuthorized && !appState.isIndexing && !appState.isAnalyzing {
                            appState.startBackgroundIndexingAndAnalysis()
                        }
                    }
            }
        }
        .accessibilityIdentifier(isTestingMode ? "app.testing_mode" : "app.root")
        .sheet(isPresented: $appState.showProcessingSheet) {
            ProcessingStatusSheet()
        }
        .sheet(isPresented: $appState.showFirstRunExplanation) {
            FirstRunExplanationSheet()
        }
        .sheet(item: $newPhotoCheck.pending) { candidate in
            NewPhotoCheckSheet(candidate: candidate)
        }
        .sheet(isPresented: $appState.showDailyReview) {
            NavigationStack {
                TodayReviewView()
            }
            .accessibilityIdentifier("dailyReview.root")
        }
    }
}

// MARK: - First Run Explanation Sheet

struct FirstRunExplanationSheet: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: MomentsSpacing.xl) {
                        Spacer(minLength: MomentsSpacing.xl)
                        
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [MomentsColors.accent.opacity(0.3), MomentsColors.accent.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 140, height: 140)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 60, weight: .light))
                                .foregroundStyle(MomentsColors.accent)
                        }
                        
                        VStack(spacing: MomentsSpacing.md) {
                            Text("¿Qué vamos a hacer?")
                                .font(MomentsTypography.titleLarge)
                                .foregroundStyle(MomentsColors.textPrimary)
                                .multilineTextAlignment(.center)
                            
                            Text("Antes de empezar, te explicamos cómo funciona Moments.")
                                .font(MomentsTypography.bodyMedium)
                                .foregroundStyle(MomentsColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, MomentsSpacing.lg)
                        }
                        
                        VStack(alignment: .leading, spacing: MomentsSpacing.lg) {
                            ExplanationRow(
                                icon: "photo.on.rectangle.angled",
                                iconColor: .blue,
                                title: "Analizamos tus fotos",
                                description: "Detectamos fotos borrosas, duplicadas, capturas y más."
                            )
                            
                            ExplanationRow(
                                icon: "iphone",
                                iconColor: .green,
                                title: "Todo en tu dispositivo",
                                description: "Nada sale de tu iPhone. El análisis es 100% privado."
                            )
                            
                            ExplanationRow(
                                icon: "arrow.triangle.2.circlepath",
                                iconColor: .orange,
                                title: "Continúa en segundo plano",
                                description: "El análisis sigue aunque cierres la app. Es más rápido con el teléfono cargando."
                            )
                            
                            ExplanationRow(
                                icon: "bell.badge",
                                iconColor: MomentsColors.accent,
                                title: "Te avisamos cuando termine",
                                description: "Recibirás una notificación cuando tu biblioteca esté lista."
                            )
                            
                            ExplanationRow(
                                icon: "hand.raised",
                                iconColor: .pink,
                                title: "Vos decidís qué borrar",
                                description: "Te sugerimos fotos para eliminar, pero la decisión es tuya."
                            )
                        }
                        .padding(.horizontal, MomentsSpacing.screenHorizontal)
                        
                        Spacer(minLength: MomentsSpacing.xl)
                    }
                }
                
                VStack {
                    Spacer()
                    
                    Button {
                        appState.dismissFirstRunExplanation()
                    } label: {
                        Text("Empezar")
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
                    .accessibilityIdentifier("firstRun.startButton")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.dismissFirstRunExplanation()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("firstRun.explanation")
    }
}

struct ExplanationRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: MomentsSpacing.md) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(MomentsTypography.headlineSmall)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                Text(description)
                    .font(MomentsTypography.bodySmall)
                    .foregroundStyle(MomentsColors.textSecondary)
            }
        }
    }
}

// MARK: - Processing Status Sheet (friendly "long processing" screen)

struct ProcessingStatusSheet: View {
    @EnvironmentObject var appState: AppState
    @State private var showNotificationPrompt = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: MomentsSpacing.xl) {
                    Spacer()
                    
                    // Friendly icon
                    ZStack {
                        Circle()
                            .fill(MomentsColors.accent.opacity(0.15))
                            .frame(width: 140, height: 140)
                        
                        if appState.isIndexing || appState.isAnalyzing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(2)
                                .tint(MomentsColors.accent)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(MomentsColors.accent)
                        }
                    }
                    
                    VStack(spacing: MomentsSpacing.sm) {
                        if appState.isIndexing {
                            Text("Organizando tu biblioteca...")
                                .font(MomentsTypography.titleMedium)
                                .foregroundStyle(MomentsColors.textPrimary)
                            
                            Text("\(MomentsPluralization.photos(appState.totalPhotosIndexed)) encontradas")
                                .font(MomentsTypography.bodyMedium)
                                .foregroundStyle(MomentsColors.textSecondary)
                        } else if appState.isAnalyzing {
                            Text("Analizando tus fotos...")
                                .font(MomentsTypography.titleMedium)
                                .foregroundStyle(MomentsColors.textPrimary)
                            
                            Text("Esto puede tardar unos minutos")
                                .font(MomentsTypography.bodyMedium)
                                .foregroundStyle(MomentsColors.textSecondary)
                            
                            Text("\(appState.totalPhotosAnalyzed) / \(appState.totalPhotosToAnalyze)")
                                .font(MomentsTypography.bodyMedium)
                                .foregroundStyle(MomentsColors.textTertiary)
                        } else {
                            Text("¡Listo!")
                                .font(MomentsTypography.titleMedium)
                                .foregroundStyle(MomentsColors.textPrimary)
                            
                            if appState.estimatedSpaceSavings > 0 {
                                let gbSavings = Double(appState.estimatedSpaceSavings) / 1_000_000_000.0
                                Text("Encontramos \(String(format: "%.1f GB", gbSavings)) para liberar")
                                    .font(MomentsTypography.bodyMedium)
                                    .foregroundStyle(MomentsColors.textSecondary)
                            }
                        }
                    }
                    
                    // Progress bar
                    if appState.isIndexing || appState.isAnalyzing {
                        let progress = appState.isIndexing ? appState.indexingProgress : appState.analysisProgress
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(MomentsColors.accent)
                            .padding(.horizontal, MomentsSpacing.xl)
                    }
                    
                    Spacer()
                    
                    // Notification pre-prompt
                    if appState.shouldShowNotificationPrompt && !showNotificationPrompt {
                        Button {
                            showNotificationPrompt = true
                        } label: {
                            HStack(spacing: MomentsSpacing.sm) {
                                Image(systemName: "bell.badge")
                                Text("¿Te aviso cuando esté listo?")
                            }
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.accent)
                            .padding(.vertical, MomentsSpacing.sm)
                            .padding(.horizontal, MomentsSpacing.md)
                            .background(MomentsColors.accent.opacity(0.1))
                            .cornerRadius(20)
                        }
                        .accessibilityIdentifier("processing.notificationPrompt")
                    }
                    
                    // "Seguí usando Moments" button
                    Button {
                        dismiss()
                    } label: {
                        Text("Seguí usando Moments")
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
                    .accessibilityIdentifier("processing.continueButton")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                }
            }
        }
        .alert("¿Te aviso cuando esté listo?", isPresented: $showNotificationPrompt) {
            Button("Sí, avisame") {
                Task {
                    _ = await appState.requestNotificationPermission()
                }
            }
            Button("No, gracias", role: .cancel) {}
        } message: {
            Text("Te vamos a enviar una notificación cuando terminemos de analizar tu biblioteca.")
        }
        .accessibilityIdentifier("processing.sheet")
    }
}

/// Hidden accessibility probe so UI tests can read scan progress even when
/// the 1×1 overlay would otherwise be omitted from the tree.
struct ScanProgressProbe: View {
    @EnvironmentObject var appState: AppState
    
    private var isActive: Bool {
        appState.isIndexing || appState.isAnalyzing || ActiveScanSimulation.isRequested
    }
    
    private var progress: Double {
        if appState.isIndexing { return appState.indexingProgress }
        if appState.isAnalyzing { return appState.analysisProgress }
        return ActiveScanSimulation.isRequested ? max(appState.analysisProgress, 0.10) : 0
    }
    
    var body: some View {
        Group {
            if isActive {
                Text(String(format: "%.4f", progress))
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 8, height: 8)
                    .accessibilityIdentifier("scan.progress")
                    .accessibilityLabel("Progreso del análisis")
                    .accessibilityValue(String(format: "%.4f", progress))
                    .accessibilityHidden(false)
                    .accessibilityElement(children: .ignore)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    /// Local selection so scan-progress `@Published` ticks on `AppState` cannot
    /// rebuild TabView and snap back to Home (266: tabs/Asistente unresponsive).
    @State private var tab: AppState.AppTab = .home
    
    var body: some View {
        TabView(selection: $tab) {
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
        .onAppear {
            tab = appState.selectedTab
            TabBarChrome.apply()
        }
        .onChange(of: tab) { _, newValue in
            if appState.selectedTab != newValue {
                appState.selectedTab = newValue
            }
        }
        .onChange(of: appState.selectedTab) { _, newValue in
            if tab != newValue {
                tab = newValue
            }
        }
        .overlay(alignment: .topLeading) {
            ScanProgressProbe()
        }
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
        
        var navigationTitle: String {
            switch self {
            case .timeline: return String(localized: "timeline_title")
            case .people: return String(localized: "people_title")
            case .places: return String(localized: "places_title")
            case .dates: return String(localized: "fechas_title")
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
            .navigationTitle(selectedSection.navigationTitle)
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
            MomentsAliveBackground(intensity: 0.85)
            
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingPageView(
                        iconName: "externaldrive.badge.minus",
                        iconGradient: [MomentsColors.accent, MomentsColors.accentSecondary],
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.root")
        .accessibilityProbe("onboarding.root")
    }
    
    private func requestAccess() {
        isRequesting = true
        Task {
            let granted = await appState.requestAuthorization()
            if granted {
                // Request notification permission for daily review
                // This is non-blocking - user can skip and we continue
                _ = await DailyReviewService.shared.requestNotificationPermission()
                
                // Complete onboarding and go directly to home
                // Background processing starts automatically in completeOnboarding()
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

// MARK: - Scanning View (Legacy - kept for UI tests only)
// This view is NO LONGER shown in the normal flow
// After onboarding, users go directly to home with background processing

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
                    
                    if appState.isIndexing || appState.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(2)
                            .tint(MomentsColors.accent)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 72, weight: .light))
                            .foregroundStyle(MomentsColors.accent)
                    }
                }
                
                VStack(spacing: MomentsSpacing.sm) {
                    if appState.isIndexing {
                        Text("Organizando tu biblioteca...")
                            .font(MomentsTypography.titleMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                        
                        Text("\(MomentsPluralization.photos(appState.totalPhotosIndexed)) encontradas")
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                            .accessibilityIdentifier("scanning.count")
                        
                        ProgressView(value: appState.indexingProgress)
                            .progressViewStyle(.linear)
                            .tint(MomentsColors.accent)
                            .padding(.horizontal, MomentsSpacing.xl)
                            .accessibilityIdentifier("scanning.progress")
                    } else if appState.isAnalyzing {
                        Text("Analizando...")
                            .font(MomentsTypography.titleMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                        
                        Text("\(appState.totalPhotosAnalyzed) / \(appState.totalPhotosToAnalyze)")
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                            .accessibilityIdentifier("scanning.count")
                    } else {
                        Text("¡Listo!")
                            .font(MomentsTypography.titleMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                            .accessibilityIdentifier("scanning.complete")
                    }
                }
                
                Spacer()
            }
        }
        .accessibilityIdentifier("scanning.root")
    }
}

// MARK: - Repaso del Día (Daily Review)

struct RepasoDelDiaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var lowValuePhotos: [PersistedPhoto] = []
    @State private var selectedPhotos: Set<String> = []
    @State private var showTagSheet = false
    @State private var showReminderSheet = false
    @State private var selectedPhotoForAction: PersistedPhoto?
    @State private var newTagName = ""
    @State private var reminderDate = Date().addingTimeInterval(86400) // Tomorrow
    @State private var reminderNote = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                if lowValuePhotos.isEmpty {
                    VStack(spacing: MomentsSpacing.lg) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(MomentsColors.accent)
                        
                        Text("¡Todo limpio!")
                            .font(MomentsTypography.titleMedium)
                            .foregroundStyle(MomentsColors.textPrimary)
                        
                        Text("No hay fotos de bajo valor de hoy")
                            .font(MomentsTypography.bodyMedium)
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Summary header
                        VStack(spacing: MomentsSpacing.sm) {
                            Text("Fotos de hoy con bajo valor")
                                .font(MomentsTypography.titleSmall)
                                .foregroundStyle(MomentsColors.textPrimary)
                            
                            Text("\(MomentsPluralization.photos(lowValuePhotos.count)) • \(selectedPhotos.count) seleccionadas")
                                .font(MomentsTypography.bodySmall)
                                .foregroundStyle(MomentsColors.textSecondary)
                        }
                        .padding(.vertical, MomentsSpacing.md)
                        
                        // Photo grid
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2)
                            ], spacing: 2) {
                                ForEach(lowValuePhotos, id: \.id) { photo in
                                    RepasoPhotoCell(
                                        photo: photo,
                                        isSelected: selectedPhotos.contains(photo.id),
                                        onTap: { toggleSelection(photo) },
                                        onLongPress: { showActionsFor(photo) }
                                    )
                                }
                            }
                        }
                        
                        // Action buttons
                        VStack(spacing: MomentsSpacing.sm) {
                            HStack(spacing: MomentsSpacing.md) {
                                Button {
                                    selectAll()
                                } label: {
                                    Text("Seleccionar todo")
                                        .font(MomentsTypography.labelMedium)
                                        .foregroundStyle(MomentsColors.accent)
                                }
                                
                                Spacer()
                                
                                Button {
                                    deselectAll()
                                } label: {
                                    Text("Deseleccionar")
                                        .font(MomentsTypography.labelMedium)
                                        .foregroundStyle(MomentsColors.textSecondary)
                                }
                            }
                            .padding(.horizontal, MomentsSpacing.screenHorizontal)
                            
                            HStack(spacing: MomentsSpacing.md) {
                                Button {
                                    keepSelected()
                                } label: {
                                    Text("Conservar")
                                        .font(MomentsTypography.buttonMedium)
                                        .foregroundStyle(MomentsColors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, MomentsSpacing.sm)
                                        .background(MomentsColors.bgTertiary)
                                        .cornerRadius(MomentsCorners.medium)
                                }
                                
                                Button {
                                    deleteSelected()
                                } label: {
                                    Text("Eliminar \(selectedPhotos.count)")
                                        .font(MomentsTypography.buttonMedium)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, MomentsSpacing.sm)
                                        .background(Color.red)
                                        .cornerRadius(MomentsCorners.medium)
                                }
                            }
                            .padding(.horizontal, MomentsSpacing.screenHorizontal)
                            .padding(.bottom, MomentsSpacing.lg)
                        }
                        .padding(.top, MomentsSpacing.md)
                        .background(MomentsColors.bgSecondary)
                    }
                }
            }
            .navigationTitle("Repaso del día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onAppear { loadTodaysLowValuePhotos() }
        .sheet(isPresented: $showTagSheet) {
            AddTagSheet(
                tagName: $newTagName,
                photo: selectedPhotoForAction,
                onSave: { addTagToPhoto() }
            )
        }
        .sheet(isPresented: $showReminderSheet) {
            AddReminderSheet(
                reminderDate: $reminderDate,
                note: $reminderNote,
                photo: selectedPhotoForAction,
                onSave: { addReminderToPhoto() }
            )
        }
        .accessibilityIdentifier("repasoDia.root")
    }
    
    private func loadTodaysLowValuePhotos() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? Date()
        
        let descriptor = FetchDescriptor<PersistedPhoto>(
            predicate: #Predicate { photo in
                photo.creationDate != nil &&
                photo.creationDate! >= startOfToday &&
                photo.creationDate! < endOfToday &&
                photo.cleanupCategoryRaw != "none" &&
                photo.cleanupCategoryRaw != nil
            },
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
        
        lowValuePhotos = (try? modelContext.fetch(descriptor)) ?? []
        selectedPhotos = Set(lowValuePhotos.map { $0.id })
    }
    
    private func toggleSelection(_ photo: PersistedPhoto) {
        if selectedPhotos.contains(photo.id) {
            selectedPhotos.remove(photo.id)
        } else {
            selectedPhotos.insert(photo.id)
        }
    }
    
    private func selectAll() {
        selectedPhotos = Set(lowValuePhotos.map { $0.id })
    }
    
    private func deselectAll() {
        selectedPhotos.removeAll()
    }
    
    private func showActionsFor(_ photo: PersistedPhoto) {
        selectedPhotoForAction = photo
    }
    
    private func keepSelected() {
        // Remove from cleanup suggestions
        for photo in lowValuePhotos where selectedPhotos.contains(photo.id) {
            photo.cleanupCategoryRaw = CleanupCategoryType.none.rawValue
            photo.isProtected = true
            photo.protectionReasonRaw = ProtectionReason.userProtected.rawValue
        }
        try? modelContext.save()
        loadTodaysLowValuePhotos()
    }
    
    private func deleteSelected() {
        // Add to pending trash
        for photo in lowValuePhotos where selectedPhotos.contains(photo.id) {
            let trashItem = PendingTrashItem(
                photoId: photo.id,
                localIdentifier: photo.localIdentifier,
                sourceCategory: photo.cleanupCategoryRaw,
                estimatedFileSize: photo.estimatedFileSize ?? 0
            )
            modelContext.insert(trashItem)
        }
        try? modelContext.save()
        loadTodaysLowValuePhotos()
    }
    
    private func addTagToPhoto() {
        guard let photo = selectedPhotoForAction, !newTagName.isEmpty else { return }
        
        // Find or create tag
        let descriptor = FetchDescriptor<PhotoTag>(
            predicate: #Predicate { $0.name == newTagName }
        )
        
        let tag: PhotoTag
        if let existing = try? modelContext.fetch(descriptor).first {
            tag = existing
        } else {
            tag = PhotoTag(name: newTagName)
            modelContext.insert(tag)
        }
        
        tag.addPhoto(photo.id)
        try? modelContext.save()
        
        newTagName = ""
        showTagSheet = false
    }
    
    private func addReminderToPhoto() {
        guard let photo = selectedPhotoForAction else { return }
        
        let reminder = PhotoReminder(
            photoId: photo.id,
            localIdentifier: photo.localIdentifier,
            reminderDate: reminderDate,
            note: reminderNote.isEmpty ? nil : reminderNote
        )
        modelContext.insert(reminder)
        try? modelContext.save()
        
        // Schedule notification
        Task {
            await appState.schedulePhotoReminder(reminder)
        }
        
        reminderNote = ""
        reminderDate = Date().addingTimeInterval(86400)
        showReminderSheet = false
    }
}

struct RepasoPhotoCell: View {
    let photo: PersistedPhoto
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(MomentsColors.bgTertiary)
                .aspectRatio(1, contentMode: .fill)
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MomentsColors.accent)
                    .padding(4)
            }
            
            // Category badge
            VStack {
                Spacer()
                HStack {
                    if let category = CleanupCategoryType(rawValue: photo.cleanupCategoryRaw ?? "none"),
                       category != .none {
                        Image(systemName: category.iconName)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .onTapGesture { onTap() }
        .onLongPressGesture { onLongPress() }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isSelected ? MomentsColors.accent : Color.clear, lineWidth: 2)
        )
    }
}

struct AddTagSheet: View {
    @Binding var tagName: String
    let photo: PersistedPhoto?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var existingTags: [PhotoTag] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: MomentsSpacing.lg) {
                    TextField("Nombre de la etiqueta", text: $tagName)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(MomentsColors.bgTertiary)
                        .cornerRadius(MomentsCorners.medium)
                        .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    
                    if !existingTags.isEmpty {
                        VStack(alignment: .leading, spacing: MomentsSpacing.sm) {
                            Text("Etiquetas existentes")
                                .font(MomentsTypography.labelSmall)
                                .foregroundStyle(MomentsColors.textSecondary)
                                .padding(.horizontal, MomentsSpacing.screenHorizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: MomentsSpacing.xs) {
                                    ForEach(existingTags, id: \.id) { tag in
                                        Button {
                                            tagName = tag.name
                                        } label: {
                                            Text(tag.name)
                                                .font(MomentsTypography.labelMedium)
                                                .foregroundStyle(MomentsColors.textPrimary)
                                                .padding(.horizontal, MomentsSpacing.sm)
                                                .padding(.vertical, MomentsSpacing.xs)
                                                .background(MomentsColors.bgTertiary)
                                                .cornerRadius(MomentsCorners.small)
                                        }
                                    }
                                }
                                .padding(.horizontal, MomentsSpacing.screenHorizontal)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top, MomentsSpacing.lg)
            }
            .navigationTitle("Agregar etiqueta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave()
                        dismiss()
                    }
                    .disabled(tagName.isEmpty)
                }
            }
        }
        .onAppear {
            existingTags = (try? modelContext.fetch(FetchDescriptor<PhotoTag>())) ?? []
        }
    }
}

struct AddReminderSheet: View {
    @Binding var reminderDate: Date
    @Binding var note: String
    let photo: PersistedPhoto?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: MomentsSpacing.lg) {
                    // Quick options
                    VStack(alignment: .leading, spacing: MomentsSpacing.sm) {
                        Text("Recordarme")
                            .font(MomentsTypography.labelSmall)
                            .foregroundStyle(MomentsColors.textSecondary)
                        
                        HStack(spacing: MomentsSpacing.sm) {
                            QuickReminderButton(title: "Mañana") {
                                reminderDate = Date().addingTimeInterval(86400)
                            }
                            QuickReminderButton(title: "En 3 días") {
                                reminderDate = Date().addingTimeInterval(86400 * 3)
                            }
                            QuickReminderButton(title: "En 1 semana") {
                                reminderDate = Date().addingTimeInterval(86400 * 7)
                            }
                        }
                    }
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    
                    DatePicker(
                        "Fecha y hora",
                        selection: $reminderDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .tint(MomentsColors.accent)
                    .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    
                    TextField("Nota (opcional)", text: $note)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(MomentsColors.bgTertiary)
                        .cornerRadius(MomentsCorners.medium)
                        .padding(.horizontal, MomentsSpacing.screenHorizontal)
                    
                    Spacer()
                }
                .padding(.top, MomentsSpacing.lg)
            }
            .navigationTitle("Agregar recordatorio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QuickReminderButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MomentsTypography.labelMedium)
                .foregroundStyle(MomentsColors.accent)
                .padding(.horizontal, MomentsSpacing.sm)
                .padding(.vertical, MomentsSpacing.xs)
                .background(MomentsColors.accent.opacity(0.1))
                .cornerRadius(MomentsCorners.small)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
