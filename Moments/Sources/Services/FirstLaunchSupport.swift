// FirstLaunchSupport.swift
// Testable first-launch helpers: copy, progress, permissions, reset.

import Foundation

// MARK: - Launch flags

enum FirstLaunchFlags {
    static let resetArgument = "-resetFirstLaunch"
    static let showExplanationArgument = "-showFirstRunExplanation"
    static let grantPhotosArgument = "-grantPhotosAccess"
    static let recordPermissionsArgument = "-recordPermissionRequests"
    
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    
    static var resetRequested: Bool { args.contains(resetArgument) }
    static var showExplanation: Bool { args.contains(showExplanationArgument) }
    static var grantPhotos: Bool { args.contains(grantPhotosArgument) }
    static var recordPermissions: Bool { args.contains(recordPermissionsArgument) }
}

enum FirstLaunchReset {
    static let onboardingCompletedKey = "com.moments.hasCompletedOnboarding"
    static let notificationPromptShownKey = "com.moments.notificationPromptShown"
    static let analysisCompleteNotificationSentKey = "com.moments.analysisCompleteNotificationSent"
    static let firstRunExplanationShownKey = "com.moments.firstRunExplanationShown"
    static let initialAnalysisCompletedKey = "com.moments.hasCompletedInitialAnalysis"
    
    static var allKeys: [String] {
        [
            onboardingCompletedKey,
            notificationPromptShownKey,
            analysisCompleteNotificationSentKey,
            firstRunExplanationShownKey,
            initialAnalysisCompletedKey
        ]
    }
    
    static var isRequested: Bool { FirstLaunchFlags.resetRequested }
    
    static func apply(defaults: UserDefaults = .standard) {
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Permissions

enum PermissionKind: String, Equatable {
    case photos
    case notifications
}

enum FirstLaunchPermissionPolicy {
    /// The onboarding "Permitir acceso a Fotos" button requests Photos only.
    static func shouldRequestPhotos(fromOnboardingAllowButton: Bool) -> Bool {
        fromOnboardingAllowButton
    }
    
    /// Notifications wait for the explicit "Avisame cuando esté listo" CTA.
    static func shouldRequestNotifications(fromOnboardingAllowButton: Bool) -> Bool {
        !fromOnboardingAllowButton
    }
}

enum PermissionRequestRecorder {
    private static let lock = NSLock()
    private static var recorded: [PermissionKind] = []
    
    static var isEnabled: Bool {
        FirstLaunchFlags.recordPermissions || MomentsTestRuntime.isUITesting
    }
    
    static var all: [PermissionKind] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
    
    static var last: PermissionKind? { all.last }
    
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        recorded = []
    }
    
    static func record(_ kind: PermissionKind) {
        lock.lock()
        recorded.append(kind)
        lock.unlock()
    }
}

// MARK: - Progress

enum FirstRunProgress {
    /// Combines indexing + analysis so parallel / background work still moves the bar.
    static func rawProgress(
        overall: Double,
        indexing: Double,
        analysis: Double,
        isIndexing: Bool,
        isAnalyzing: Bool
    ) -> Double {
        if overall > 0 {
            return min(1, max(0, overall))
        }
        if isIndexing && isAnalyzing {
            return min(1, max(0, indexing * 0.45 + analysis * 0.55))
        }
        if isIndexing {
            return min(1, max(0, indexing * 0.45))
        }
        if isAnalyzing {
            return min(1, max(0, 0.45 + analysis * 0.55))
        }
        return 0
    }
    
    /// Maps real 0...1 onto a visible bar without flattening tiny library fractions.
    static func displayValue(raw: Double) -> Double {
        if raw <= 0 { return 0.04 }
        return min(0.96, 0.04 + raw * 0.92)
    }
    
    static func displayValue(
        overall: Double,
        indexing: Double,
        analysis: Double,
        isIndexing: Bool,
        isAnalyzing: Bool
    ) -> Double {
        displayValue(
            raw: rawProgress(
                overall: overall,
                indexing: indexing,
                analysis: analysis,
                isIndexing: isIndexing,
                isAnalyzing: isAnalyzing
            )
        )
    }
}

// MARK: - Timeline presentation

enum TimelineLoadPresentation: String, Equatable {
    case loading
    case analyzing
    case empty
    case content
    
    static func resolve(isLoading: Bool, hasSections: Bool, analysisInProgress: Bool) -> TimelineLoadPresentation {
        if hasSections { return .content }
        if analysisInProgress { return .analyzing }
        if isLoading { return .loading }
        return .empty
    }
}

// MARK: - Copy

enum OnboardingCopy {
    static let page1Title = String(localized: "onboarding_page1_title")
    static let page1Subtitle = String(localized: "onboarding_page1_subtitle")
    static let page2Title = String(localized: "onboarding_page2_title")
    static let page2Subtitle = String(localized: "onboarding_page2_subtitle")
    
    static let expectedPage1TitleES = "Liberá espacio sin perder lo importante"
    static let expectedPage1SubtitleES = "Tu teléfono lleno no es un problema, es una oportunidad."
    static let expectedPage2TitleES = "Reviví tus mejores momentos"
    static let expectedPage2SubtitleES = "Tus fotos cuentan historias. Dejá que las encuentres."
}

enum FirstRunExplanationCopy {
    static let title = "¿Qué vamos a hacer?"
    static let subtitle = "Antes de empezar, te explicamos cómo funciona Moments."
    static let start = "Empezar"
    
    struct Row: Equatable {
        let icon: String
        let title: String
        let description: String
    }
    
    static let rows: [Row] = [
        Row(
            icon: "photo.on.rectangle.angled",
            title: "Analizamos tus fotos",
            description: "Detectamos fotos borrosas, duplicadas, capturas y más."
        ),
        Row(
            icon: "iphone",
            title: "Todo en tu dispositivo",
            description: "Nada sale de tu iPhone. El análisis es 100% privado."
        ),
        Row(
            icon: "arrow.triangle.2.circlepath",
            title: "Continúa en segundo plano",
            description: "El análisis sigue aunque cierres la app. Es más rápido con el teléfono cargando."
        ),
        Row(
            icon: "bell.badge",
            title: "Te avisamos cuando termine",
            description: "Recibirás una notificación cuando tu biblioteca esté lista."
        ),
        Row(
            icon: "hand.raised",
            title: "Vos decidís qué borrar",
            description: "Te sugerimos fotos para eliminar, pero la decisión es tuya."
        )
    ]
    
    static var lastRow: Row { rows[rows.count - 1] }
    
    /// Space reserved under the scroll content so the last row clears the CTA.
    static let startButtonReserve: CGFloat = 108
}

enum TimelineInProgressCopy {
    static let title = "Tus momentos se están acomodando"
    static let body = "Estamos conociendo tus fotos. En un rato van a aparecer acá, agrupados con cariño."
}
