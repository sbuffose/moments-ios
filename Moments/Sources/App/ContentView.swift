// ContentView.swift
// Vista principal con navegación por tabs

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding = false
    
    var body: some View {
        Group {
            if !appState.isLibraryAuthorized {
                OnboardingView()
            } else if !appState.hasCompletedInitialScan {
                ScanningView()
            } else {
                MainTabView()
            }
        }
        .onAppear {
            checkFirstLaunch()
        }
    }
    
    private func checkFirstLaunch() {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            showOnboarding = true
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // Limpiar is now the hero/home tab
            CleanupView()
                .tabItem {
                    Label(String(localized: "tab_cleanup"), systemImage: AppState.AppTab.cleanup.icon)
                }
                .tag(AppState.AppTab.cleanup)
            
            SearchView()
                .tabItem {
                    Label(String(localized: "tab_search"), systemImage: AppState.AppTab.search.icon)
                }
                .tag(AppState.AppTab.search)
            
            FechasView()
                .tabItem {
                    Label(String(localized: "tab_fechas"), systemImage: AppState.AppTab.fechas.icon)
                }
                .tag(AppState.AppTab.fechas)
            
            TimelineView()
                .tabItem {
                    Label(String(localized: "tab_timeline"), systemImage: AppState.AppTab.timeline.icon)
                }
                .tag(AppState.AppTab.timeline)
            
            PeopleView()
                .tabItem {
                    Label(String(localized: "tab_people"), systemImage: AppState.AppTab.people.icon)
                }
                .tag(AppState.AppTab.people)
        }
        .tint(.primary)
    }
}

// MARK: - Onboarding View (Multi-screen)

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Screen 1: Save Space
                OnboardingPageView(
                    imageName: "externaldrive.badge.minus",
                    imageColor: .blue,
                    title: "onboarding_page1_title",
                    subtitle: "onboarding_page1_subtitle",
                    highlights: [
                        ("trash.slash", "onboarding_page1_highlight1"),
                        ("photo.stack", "onboarding_page1_highlight2"),
                        ("sparkles", "onboarding_page1_highlight3")
                    ]
                )
                .tag(0)
                
                // Screen 2: Relive Moments
                OnboardingPageView(
                    imageName: "heart.text.square",
                    imageColor: .pink,
                    title: "onboarding_page2_title",
                    subtitle: "onboarding_page2_subtitle",
                    highlights: [
                        ("clock.arrow.circlepath", "onboarding_page2_highlight1"),
                        ("gift", "onboarding_page2_highlight2"),
                        ("airplane", "onboarding_page2_highlight3")
                    ]
                )
                .tag(1)
                
                // Screen 3: Privacy
                OnboardingPageView(
                    imageName: "lock.iphone",
                    imageColor: .green,
                    title: "onboarding_page3_title",
                    subtitle: "onboarding_page3_subtitle",
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
            
            // Bottom section
            VStack(spacing: 16) {
                if currentPage < 2 {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        Text("onboarding_continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(14)
                    }
                    
                    Button {
                        withAnimation {
                            currentPage = 2
                        }
                    } label: {
                        Text("onboarding_skip")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        requestAccess()
                    } label: {
                        if isRequesting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("onboarding_allow_access")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .cornerRadius(14)
                        }
                    }
                    .disabled(isRequesting)
                    
                    Text("onboarding_privacy_footer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
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
    let imageName: String
    let imageColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let highlights: [(icon: String, text: LocalizedStringKey)]
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(imageColor.opacity(0.15))
                    .frame(width: 140, height: 140)
                
                Image(systemName: imageName)
                    .font(.system(size: 64))
                    .foregroundStyle(imageColor)
            }
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(highlights, id: \.icon) { highlight in
                    HStack(spacing: 16) {
                        Image(systemName: highlight.icon)
                            .font(.title3)
                            .foregroundStyle(imageColor)
                            .frame(width: 32)
                        
                        Text(highlight.text)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Scanning View

struct ScanningView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                if appState.isScanning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                }
            }
            
            VStack(spacing: 8) {
                Text(appState.isScanning ? "scanning_in_progress" : "scanning_ready")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if appState.isScanning {
                    Text("scanning_photos_count \(appState.totalPhotosIndexed)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    ProgressView(value: appState.scanProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 40)
                } else {
                    Text("scanning_description")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
            
            if !appState.isScanning {
                Button {
                    appState.startScan()
                } label: {
                    Text("scanning_start_button")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 32)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
