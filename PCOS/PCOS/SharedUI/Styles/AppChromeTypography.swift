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

        applyVisibleTabBarAppearance(tabAppearance)
        DispatchQueue.main.async {
            applyVisibleTabBarAppearance(tabAppearance)
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
    static var chromeTintColor: UIColor? {
        if AppTheme.isBotanicalJournal {
            AppTheme.botanicalForestRGB.uiColor
        } else if AppTheme.isLunarCalm {
            AppTheme.lunarCalmTealRGB.uiColor
        } else {
            UIColor(AppTheme.accentColor)
        }
    }

    static var chromeUnselectedTintColor: UIColor? {
        if AppTheme.isBotanicalJournal {
            AppTheme.botanicalForestAltRGB.uiColor.withAlphaComponent(0.62)
        } else if AppTheme.isLunarCalm {
            AppTheme.lunarCalmSecondaryTextRGB.uiColor.withAlphaComponent(0.68)
        } else {
            UIColor(AppTheme.secondaryText).withAlphaComponent(0.68)
        }
    }

    static func chromeTextAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if AppTheme.isBotanicalJournal {
            attributes[.foregroundColor] = AppTheme.botanicalForestRGB.uiColor
        } else if AppTheme.isLunarCalm {
            attributes[.foregroundColor] = AppTheme.lunarCalmPrimaryTextRGB.uiColor
        } else {
            attributes[.foregroundColor] = UIColor(AppTheme.primaryText)
        }
        return attributes
    }

    static func applyBackground(to appearance: UINavigationBarAppearance) {
        if AppTheme.isLunarCalm {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = AppTheme.lunarCalmBackgroundRGB.uiColor.withAlphaComponent(0.96)
            appearance.shadowColor = AppTheme.lunarCalmBorderRGB.uiColor.withAlphaComponent(0.62)
        } else if AppTheme.usesCustomTabBar {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(AppTheme.warmNeutral).withAlphaComponent(0.96)
            appearance.shadowColor = UIColor(AppTheme.dividerColor).withAlphaComponent(0.42)
        }
    }

    static func applyScrollEdgeBackground(to appearance: UINavigationBarAppearance) {
        if AppTheme.isLunarCalm {
            appearance.backgroundColor = AppTheme.lunarCalmBackgroundRGB.uiColor.withAlphaComponent(0.72)
            appearance.shadowColor = .clear
        } else if AppTheme.usesCustomTabBar {
            appearance.backgroundColor = UIColor(AppTheme.warmNeutral).withAlphaComponent(0.7)
            appearance.shadowColor = .clear
        }
    }

    static func applyBackground(to appearance: UITabBarAppearance) {
        if AppTheme.isLunarCalm {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = AppTheme.lunarCalmBackgroundRGB.uiColor.withAlphaComponent(0.96)
            appearance.shadowColor = AppTheme.lunarCalmBorderRGB.uiColor.withAlphaComponent(0.7)
        } else if AppTheme.usesCustomTabBar {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(AppTheme.warmNeutral).withAlphaComponent(0.96)
            appearance.shadowColor = UIColor(AppTheme.dividerColor).withAlphaComponent(0.5)
        }
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

        if AppTheme.isBotanicalJournal {
            appearance.normal.iconColor = AppTheme.botanicalForestAltRGB.uiColor.withAlphaComponent(0.62)
            appearance.normal.titleTextAttributes[.foregroundColor] = AppTheme.botanicalForestAltRGB.uiColor.withAlphaComponent(0.72)
            appearance.selected.iconColor = AppTheme.botanicalForestRGB.uiColor
            appearance.selected.titleTextAttributes[.foregroundColor] = AppTheme.botanicalForestRGB.uiColor
        } else if AppTheme.isLunarCalm {
            appearance.normal.iconColor = AppTheme.lunarCalmSecondaryTextRGB.uiColor.withAlphaComponent(0.66)
            appearance.normal.titleTextAttributes[.foregroundColor] = AppTheme.lunarCalmSecondaryTextRGB.uiColor.withAlphaComponent(0.72)
            appearance.selected.iconColor = AppTheme.lunarCalmTealRGB.uiColor
            appearance.selected.titleTextAttributes[.foregroundColor] = AppTheme.lunarCalmTealRGB.uiColor
        } else {
            appearance.normal.iconColor = UIColor(AppTheme.secondaryText).withAlphaComponent(0.68)
            appearance.normal.titleTextAttributes[.foregroundColor] = UIColor(AppTheme.secondaryText).withAlphaComponent(0.72)
            appearance.selected.iconColor = UIColor(AppTheme.accentColor)
            appearance.selected.titleTextAttributes[.foregroundColor] = UIColor(AppTheme.accentColor)
        }
    }

    static func applyVisibleTabBarAppearance(_ appearance: UITabBarAppearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else {
                continue
            }

            for window in windowScene.windows {
                applyTabBarAppearance(appearance, in: window)
            }
        }
    }

    static func applyTabBarAppearance(_ appearance: UITabBarAppearance, in view: UIView) {
        if let tabBar = view as? UITabBar {
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = chromeTintColor
            tabBar.unselectedItemTintColor = chromeUnselectedTintColor
        }

        for subview in view.subviews {
            applyTabBarAppearance(appearance, in: subview)
        }
    }
}
