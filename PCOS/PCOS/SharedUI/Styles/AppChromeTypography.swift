import SwiftUI
import UIKit

@MainActor
enum AppChromeTypography {
    static func apply(option: FontOption? = nil) {
        let standardNavigationAppearance = navigationBarAppearance(option: option)
        let scrollEdgeNavigationAppearance = navigationBarScrollEdgeAppearance(option: option)
        let tabAppearance = tabBarAppearance(option: option)

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = standardNavigationAppearance
        navigationBar.compactAppearance = standardNavigationAppearance
        navigationBar.scrollEdgeAppearance = scrollEdgeNavigationAppearance
        navigationBar.compactScrollEdgeAppearance = standardNavigationAppearance
        navigationBar.tintColor = chromeTintColor

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance
        tabBar.tintColor = chromeTintColor
        tabBar.unselectedItemTintColor = chromeUnselectedTintColor

        applyVisibleChromeAppearance(tabAppearance, navigation: standardNavigationAppearance, scrollEdge: scrollEdgeNavigationAppearance)
        DispatchQueue.main.async {
            applyVisibleChromeAppearance(tabAppearance, navigation: standardNavigationAppearance, scrollEdge: scrollEdgeNavigationAppearance)
        }
    }

    static func navigationBarAppearance(option: FontOption? = nil) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        applyBackground(to: appearance)
        applyNavigationTypography(to: appearance, option: option)
        return appearance
    }

    static func navigationBarScrollEdgeAppearance(option: FontOption? = nil) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        applyScrollEdgeBackground(to: appearance)
        applyNavigationTypography(to: appearance, option: option)
        return appearance
    }

    static func tabBarAppearance(option: FontOption? = nil) -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        applyBackground(to: appearance)

        let titleAttributes = tabBarTitleTextAttributes(option: option)
        applyTabBarTypography(to: appearance.stackedLayoutAppearance, titleAttributes: titleAttributes)
        applyTabBarTypography(to: appearance.inlineLayoutAppearance, titleAttributes: titleAttributes)
        applyTabBarTypography(to: appearance.compactInlineLayoutAppearance, titleAttributes: titleAttributes)

        return appearance
    }

    static func navigationInlineTitleTextAttributes(option: FontOption? = nil) -> [NSAttributedString.Key: Any] {
        chromeTextAttributes(
            font: AppTheme.uiHeadingFont(.headline, weight: .regular, option: option)
        )
    }

    static func navigationLargeTitleTextAttributes(option: FontOption? = nil) -> [NSAttributedString.Key: Any] {
        chromeTextAttributes(
            font: AppTheme.uiHeadingFont(.largeTitle, weight: .regular, option: option)
        )
    }

    static func tabBarTitleTextAttributes(option: FontOption? = nil) -> [NSAttributedString.Key: Any] {
        chromeTextAttributes(
            font: AppTheme.uiFont(.caption2, weight: .medium, option: option)
        )
    }
}

private extension AppChromeTypography {
    static func adaptiveColor(_ role: AppTheme.CompanionColorRole, fallback: UIColor) -> UIColor {
        let theme = AppearancePreferences.shared.themeOption
        guard [.calm, .lunarCalm, .botanicalJournal].contains(theme) else { return fallback }
        return UIColor { traits in AppTheme.companionUIColor(theme: theme, role: role, traits: traits) }
    }

    static var chromeTintColor: UIColor? {
        adaptiveColor(.accent, fallback: UIColor(AppTheme.accentColor))
    }

    static var chromeUnselectedTintColor: UIColor? {
        adaptiveColor(.secondaryText, fallback: UIColor(AppTheme.secondaryText))
    }

    static func chromeTextAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: adaptiveColor(.primaryText, fallback: UIColor(AppTheme.primaryText))]
    }

    static func applyBackground(to appearance: UINavigationBarAppearance) {
        appearance.backgroundColor = adaptiveColor(.background, fallback: UIColor(AppTheme.warmNeutral))
    }

    static func applyScrollEdgeBackground(to appearance: UINavigationBarAppearance) {
        appearance.backgroundColor = adaptiveColor(.background, fallback: UIColor(AppTheme.warmNeutral)).withAlphaComponent(0.72)
        appearance.shadowColor = .clear
    }

    static func applyBackground(to appearance: UITabBarAppearance) {
        appearance.backgroundColor = adaptiveColor(.background, fallback: UIColor(AppTheme.warmNeutral))
    }

    static func applyNavigationTypography(
        to appearance: UINavigationBarAppearance,
        option: FontOption?
    ) {
        appearance.titleTextAttributes = navigationInlineTitleTextAttributes(option: option)
        appearance.largeTitleTextAttributes = navigationLargeTitleTextAttributes(option: option)
    }

    static func applyTabBarTypography(
        to appearance: UITabBarItemAppearance,
        titleAttributes: [NSAttributedString.Key: Any]
    ) {
        appearance.normal.titleTextAttributes = titleAttributes
        appearance.selected.titleTextAttributes = titleAttributes
        appearance.disabled.titleTextAttributes = titleAttributes
        appearance.focused.titleTextAttributes = titleAttributes

        appearance.normal.iconColor = chromeUnselectedTintColor
        appearance.normal.titleTextAttributes[.foregroundColor] = chromeUnselectedTintColor
        appearance.selected.iconColor = chromeTintColor
        appearance.selected.titleTextAttributes[.foregroundColor] = chromeTintColor
    }

    static func applyVisibleChromeAppearance(_ appearance: UITabBarAppearance, navigation: UINavigationBarAppearance, scrollEdge: UINavigationBarAppearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else {
                continue
            }

            for window in windowScene.windows {
                applyChromeAppearance(appearance, navigation: navigation, scrollEdge: scrollEdge, in: window)
            }
        }
    }

    static func applyChromeAppearance(_ appearance: UITabBarAppearance, navigation: UINavigationBarAppearance, scrollEdge: UINavigationBarAppearance, in view: UIView) {
        if let navigationBar = view as? UINavigationBar {
            navigationBar.standardAppearance = navigation
            navigationBar.compactAppearance = navigation
            navigationBar.scrollEdgeAppearance = scrollEdge
            navigationBar.compactScrollEdgeAppearance = navigation
            navigationBar.tintColor = chromeTintColor
        }
        if let tabBar = view as? UITabBar {
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = chromeTintColor
            tabBar.unselectedItemTintColor = chromeUnselectedTintColor
        }

        for subview in view.subviews {
            applyChromeAppearance(appearance, navigation: navigation, scrollEdge: scrollEdge, in: subview)
        }
    }
}
