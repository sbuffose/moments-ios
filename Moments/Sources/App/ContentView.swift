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

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            
            VStack(spacing: 16) {
                Text("onboarding_title")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("onboarding_subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                FeatureRow(icon: "sparkles", title: "onboarding_feature_cleanup")
                FeatureRow(icon: "magnifyingglass", title: "onboarding_feature_search")
                FeatureRow(icon: "calendar", title: "onboarding_feature_timeline")
                FeatureRow(icon: "map", title: "onboarding_feature_places")
                FeatureRow(icon: "person.2", title: "onboarding_feature_people")
            }
            .padding()
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    requestAccess()
                } label: {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("onboarding_allow_access")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)
                
                Text("onboarding_privacy_note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
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

struct FeatureRow: View {
    let icon: String
    let title: LocalizedStringKey
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            Text(title)
                .font(.body)
            
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
