// TabBarChrome.swift
// Standard tab bar without a floating selection pill / glass leftover.

import UIKit
import SwiftUI

enum TabBarChrome {
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowImage = UIImage()
        appearance.shadowColor = .clear
        
        let item = appearance.stackedLayoutAppearance
        item.normal.iconColor = UIColor.secondaryLabel
        item.selected.iconColor = UIColor(MomentsColors.accent)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(MomentsColors.accent)]
        
        // Kill the iOS selection indicator / liquid-glass pill that was
        // floating over the Asistente tab icon.
        UITabBar.appearance().selectionIndicatorImage = UIImage()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        
        NavigationBarChrome.apply()
    }
}

enum NavigationBarChrome {
    static func apply() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? MomentsColors.darkGreenGrey
                : MomentsColors.lightCream
        }
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: MomentsColors.textPrimaryUIColor
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: MomentsColors.textPrimaryUIColor
        ]
        
        let nav = UINavigationBar.appearance()
        nav.standardAppearance = appearance
        nav.scrollEdgeAppearance = appearance
        nav.compactAppearance = appearance
        nav.isTranslucent = false
    }
}
