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
        navigationBar.tintColor = AppTheme.isBotanicalJournal ? AppTheme.botanicalForestRGB.uiColor : nil

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance
        tabBar.tintColor = AppTheme.isBotanicalJournal ? AppTheme.botanicalForestRGB.uiColor : nil
        tabBar.unselectedItemTintColor = AppTheme.isBotanicalJournal
            ? AppTheme.botanicalForestAltRGB.uiColor.withAlphaComponent(0.62)
            : nil

        applyVisibleTabBarAppearance(tabAppearance)
        DispatchQueue.main.async {
            applyVisibleTabBarAppearance(tabAppearance)
        }
    }

    static func navigationBarAppearance(option: FontOption? = nil) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        applyNavigationTypography(to: appearance, option: option)
        return appearance
    }

    static func navigationBarScrollEdgeAppearance(option: FontOption? = nil) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        applyNavigationTypography(to: appearance, option: option)
        return appearance
    }

    static func tabBarAppearance(option: FontOption? = nil) -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

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
    static func chromeTextAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if AppTheme.isBotanicalJournal {
            attributes[.foregroundColor] = AppTheme.botanicalForestRGB.uiColor
        }
        return attributes
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

        guard AppTheme.isBotanicalJournal else {
            return
        }

        appearance.normal.iconColor = AppTheme.botanicalForestAltRGB.uiColor.withAlphaComponent(0.62)
        appearance.normal.titleTextAttributes[.foregroundColor] = AppTheme.botanicalForestAltRGB.uiColor.withAlphaComponent(0.72)
        appearance.selected.iconColor = AppTheme.botanicalForestRGB.uiColor
        appearance.selected.titleTextAttributes[.foregroundColor] = AppTheme.botanicalForestRGB.uiColor
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
            tabBar.tintColor = AppTheme.isBotanicalJournal ? AppTheme.botanicalForestRGB.uiColor : nil
            tabBar.unselectedItemTintColor = AppTheme.isBotanicalJournal
                ? AppTheme.botanicalForestAltRGB.uiColor.withAlphaComponent(0.62)
                : nil
        }

        for subview in view.subviews {
            applyTabBarAppearance(appearance, in: subview)
        }
    }
}
