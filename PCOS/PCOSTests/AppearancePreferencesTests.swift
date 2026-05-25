import Testing
import Foundation
import SwiftUI
import UIKit
@testable import PCOS

@Suite("Appearance Preferences", .serialized)
@MainActor
struct AppearancePreferencesTests {
    @Test("Theme and font selections persist across launches")
    func selectionsPersist() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppearancePreferences(defaults: defaults)
        for themeOption in ThemeOption.allCases {
            preferences.setThemeOption(themeOption)
            preferences.setFontOption(.newYork)

            let reloadedPreferences = AppearancePreferences(defaults: defaults)
            #expect(reloadedPreferences.themeOption == themeOption)
            #expect(reloadedPreferences.fontOption == .newYork)
        }

        for fontOption in FontOption.allCases {
            preferences.setThemeOption(.fruitGrove)
            preferences.setFontOption(fontOption)

            let reloadedPreferences = AppearancePreferences(defaults: defaults)
            #expect(reloadedPreferences.themeOption == .fruitGrove)
            #expect(reloadedPreferences.fontOption == fontOption)
        }
    }

    @Test("Fresh installs default to Botanical Journal with SF Pro body text")
    func freshInstallDefaultsToBotanicalJournal() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppearancePreferences(defaults: defaults)

        #expect(preferences.themeOption == .botanicalJournal)
        #expect(preferences.fontOption == .systemDefault)
    }

    @Test("Changing appearance options refreshes the render key")
    func changesRefreshRenderKey() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppearancePreferences(defaults: defaults)
        let initialRenderKey = preferences.renderKey
        preferences.setThemeOption(.sunrise)
        #expect(preferences.renderKey != initialRenderKey)

        let secondRenderKey = preferences.renderKey
        preferences.setFontOption(.rounded)
        #expect(preferences.renderKey != secondRenderKey)
    }

    @Test("Launch themes include an accessible high-contrast option")
    func highContrastThemeExists() {
        #expect(ThemeOption.allCases.count == 8)
        #expect(ThemeOption.allCases.first == .botanicalJournal)
        #expect(ThemeOption.allCases.contains(.botanicalJournal))
        #expect(ThemeOption.allCases.contains(.highContrast))
        #expect(ThemeOption.allCases.contains(.botanicalMist))
        #expect(ThemeOption.allCases.contains(.blushMoonrise))
        #expect(ThemeOption.allCases.contains(.fruitGrove))
        #expect(ThemeOption.highContrast.isHighContrast)
        #expect(FontOption.allCases == [.systemDefault, .rounded, .didot, .newYork, .cormorantGaramond, .sfMono, .baskerville])
    }

    @Test("Stored legacy font raw values remain compatible")
    func legacyStoredFontValuesRemainCompatible() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyPayload = #"{"themeOption":"sage","fontOption":"rounded"}"#.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: "appearance.preferences")

        let preferences = AppearancePreferences(defaults: defaults)
        #expect(preferences.themeOption == .sage)
        #expect(preferences.fontOption == .rounded)
    }

    @Test("Stored SF Pro selections remain explicit instead of migrating")
    func storedSystemDefaultFontRemainsCompatible() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyPayload = #"{"themeOption":"ocean","fontOption":"systemDefault"}"#.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: "appearance.preferences")

        let preferences = AppearancePreferences(defaults: defaults)
        #expect(preferences.themeOption == .ocean)
        #expect(preferences.fontOption == .systemDefault)
    }

    @Test("Stored New York selections remain explicit instead of migrating")
    func storedNewYorkFontRemainsCompatible() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyPayload = #"{"themeOption":"sunrise","fontOption":"newYork"}"#.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: "appearance.preferences")

        let preferences = AppearancePreferences(defaults: defaults)
        #expect(preferences.themeOption == .sunrise)
        #expect(preferences.fontOption == .newYork)
    }

    @Test("Image-inspired theme palettes expose valid RGB values")
    func imageInspiredThemePalettesExposeValidRGBValues() {
        for themeOption in [ThemeOption.botanicalJournal, .botanicalMist, .blushMoonrise, .fruitGrove] {
            let values = rgbValues(in: themeOption.palette)

            #expect(values.count == 39)
            for value in values {
                #expect(value >= 0)
                #expect(value <= 1)
            }
        }
    }

    @Test("Botanical Journal palette matches the soft wellness art direction")
    func botanicalJournalPaletteMatchesArtDirection() {
        let palette = ThemeOption.botanicalJournal.palette

        #expect(palette.accent.matches(hex: 0x173D36))
        #expect(palette.sage.matches(hex: 0x9EAD91))
        #expect(palette.coral.matches(hex: 0xC7798E))
        #expect(palette.warmNeutralLight.matches(hex: 0xFFF8EF))
        #expect(AppTheme.botanicalLavenderRGB.matches(hex: 0x8E78B8))
        #expect(AppTheme.botanicalGoldRGB.matches(hex: 0xE6B75F))
    }

    @Test("Botanical Journal keeps body text SF Pro while headings resolve to serif")
    func botanicalJournalTypographyPolicy() {
        #expect(AppTheme.resolvedBodyFontOption(themeOption: .botanicalJournal, selectedFontOption: .baskerville) == .systemDefault)
        #expect(AppTheme.resolvedHeadingFontOption(themeOption: .botanicalJournal, selectedFontOption: .systemDefault).rawValue == "cormorantGaramond")
        #expect(AppTheme.resolvedBodyFontOption(themeOption: .sage, selectedFontOption: .baskerville) == .baskerville)
        #expect(AppTheme.resolvedHeadingFontOption(themeOption: .sage, selectedFontOption: .baskerville) == .baskerville)

        let sharedPreferences = AppearancePreferences.shared
        let originalTheme = sharedPreferences.themeOption
        let originalFont = sharedPreferences.fontOption
        sharedPreferences.setThemeOption(.botanicalJournal)
        sharedPreferences.setFontOption(.systemDefault)
        defer {
            sharedPreferences.setThemeOption(originalTheme)
            sharedPreferences.setFontOption(originalFont)
        }

        let headingFont = AppTheme.uiHeadingFont(.title, weight: .regular)
        let bodyFont = AppTheme.uiFont(.body, weight: .regular)
        #expect("\(headingFont.familyName) \(headingFont.fontName)".localizedCaseInsensitiveContains("Cormorant"))
        #expect(!"\(bodyFont.familyName) \(bodyFont.fontName)".localizedCaseInsensitiveContains("Cormorant"))
    }

    @Test("Botanical Journal display fonts are registered in the app bundle")
    func botanicalJournalDisplayFontsAreRegistered() throws {
        let infoPlistURL = try appInfoPlistURL()
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )
        let fontFiles = try #require(plist["UIAppFonts"] as? [String])

        #expect(fontFiles.contains("CormorantGaramond-Regular.ttf"))
        #expect(fontFiles.contains("CormorantGaramond-SemiBold.ttf"))
        #expect(fontFiles.contains("CormorantGaramond-Italic.ttf"))

        for fontFile in fontFiles where fontFile.hasPrefix("CormorantGaramond") {
            let fontURL = try fontResourceURL(fileName: fontFile)
            #expect(FileManager.default.fileExists(atPath: fontURL.path))
        }
    }

    @Test("Botanical Journal source-inspired asset set is complete")
    func botanicalJournalSourceInspiredAssetsExist() throws {
        let assetsURL = try assetCatalogURL()
        let expectedAssetNames = [
            "botanical-corner-sprig",
            "botanical-watercolor-wash",
            "botanical-divider",
            "botanical-lavender-sprig",
            "botanical-rosebud-branch",
            "botanical-sage-leaves",
            "botanical-moon-phase-row",
            "botanical-sparkles",
            "botanical-flower-emblem",
            "botanical-supplement-jar",
            "botanical-calendar-illustration",
            "botanical-meal-bowl",
            "botanical-glucose-drop",
        ]

        for assetName in expectedAssetNames {
            let assetURL = assetsURL.appendingPathComponent("\(assetName).imageset")
            let imageURL = assetURL.appendingPathComponent("\(assetName).png")
            let contentsURL = assetURL.appendingPathComponent("Contents.json")
            #expect(FileManager.default.fileExists(atPath: assetURL.path))
            #expect(FileManager.default.fileExists(atPath: imageURL.path))
            #expect(FileManager.default.fileExists(atPath: contentsURL.path))
        }
    }

    @Test("Botanical Journal core poster surfaces avoid top-emblem clutter")
    func botanicalJournalCorePosterSurfacesAvoidTopEmblemClutter() throws {
        let appThemeSource = try String(contentsOf: try appSourceURL("SharedUI/Styles/AppTheme.swift"), encoding: .utf8)
        let contentSource = try String(contentsOf: try appSourceURL("App/ContentView.swift"), encoding: .utf8)
        let todaySource = try String(contentsOf: try appSourceURL("Features/Cycle/Views/TodayView.swift"), encoding: .utf8)
        let settingsSource = try String(contentsOf: try appSourceURL("App/SettingsView.swift"), encoding: .utf8)

        #expect(appThemeSource.contains("var emblemAssetName: String? = nil"))
        #expect(!todaySource.contains(#"Image("botanical-flower-emblem")"#))
        #expect(!contentSource.contains(#"emblemAssetName: "botanical-flower-emblem""#))
        #expect(!settingsSource.contains(#"emblemAssetName: "botanical-flower-emblem""#))

        for source in [contentSource, todaySource, settingsSource] {
            #expect(!source.contains("botanical-app-emblem"))
        }

        #expect(!contentSource.contains(#"botanicalAssetName: "botanical-moon-phase-row""#))
        #expect(!todaySource.contains("BotanicalMoonPhaseDivider"))
    }

    @Test("Botanical Journal top botanicals stay inside the poster safe area")
    func botanicalJournalTopBotanicalsStayInsidePosterSafeArea() throws {
        let appThemeSource = try String(contentsOf: try appSourceURL("SharedUI/Styles/AppTheme.swift"), encoding: .utf8)

        #expect(appThemeSource.contains("private var topOrnamentInset"))
        #expect(!appThemeSource.contains(".padding(.top, -36)"))
        #expect(!appThemeSource.contains(".padding(.top, -30)"))
        #expect(!appThemeSource.contains(".padding(.top, -90)"))
    }

    @Test("Botanical Journal background ornaments fade cropped artwork edges")
    func botanicalJournalBackgroundOrnamentsFadeCroppedArtworkEdges() throws {
        let appThemeSource = try String(contentsOf: try appSourceURL("SharedUI/Styles/AppTheme.swift"), encoding: .utf8)
        let calendarSource = try String(contentsOf: try appSourceURL("Features/Cycle/Views/CalendarMonthView.swift"), encoding: .utf8)

        #expect(appThemeSource.contains("private struct BotanicalEdgeFadeMask"))
        #expect(appThemeSource.contains("private struct BotanicalEdgeFadeModifier"))
        #expect(appThemeSource.contains("private struct BotanicalArtworkPlateFadeMask"))
        #expect(appThemeSource.contains("func botanicalEdgeFade(horizontal:"))
        #expect(appThemeSource.contains("func botanicalArtworkPlateFade("))
        #expect(appThemeSource.contains("ornamentOffset("))
        #expect(appThemeSource.contains("private var topLeftOrnamentTopInset"))
        #expect(appThemeSource.contains("private var topLeftOrnamentLeadingInset"))
        #expect(appThemeSource.contains(".botanicalArtworkPlateFade("))
        #expect(appThemeSource.contains("horizontalFadeStart: 0.18"))
        #expect(appThemeSource.contains("verticalFadeStart: 0.26"))
        #expect(appThemeSource.contains("botanicalEdgeFade(horizontal: .leading, vertical: .bottom"))
        #expect(appThemeSource.contains("botanicalEdgeFade(horizontal: .trailing, vertical: .top"))
        #expect(appThemeSource.contains("botanicalEdgeFade(horizontal: .leading, vertical: .top"))
        #expect(appThemeSource.contains("botanicalEdgeFade(horizontal: .leading"))
        #expect(appThemeSource.contains(#"Image("botanical-corner-sprig")"#))
        #expect(appThemeSource.contains(#"Image("botanical-sage-leaves")"#))
        #expect(appThemeSource.contains(#"Image("botanical-lavender-sprig")"#))
        #expect(appThemeSource.contains(#"Image("botanical-rosebud-branch")"#))
        #expect(calendarSource.contains("BotanicalScreenBackground(style: .dashboard)"))
    }

    @Test("Botanical Journal launcher icon files remain configured")
    func botanicalJournalLauncherIconFilesRemainConfigured() throws {
        let iconSetURL = try assetCatalogURL()
            .appendingPathComponent("AppIcon.appiconset")
        let contentsData = try Data(contentsOf: iconSetURL.appendingPathComponent("Contents.json"))
        let contents = try #require(
            JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
        )
        let images = try #require(contents["images"] as? [[String: Any]])
        let filenames = images.compactMap { $0["filename"] as? String }

        #expect(filenames == [
            "App Icon 1024x1024.png",
            "App Icon 1024x1024 1.png",
            "App Icon 1024x1024 2.png",
        ])

        for filename in filenames {
            #expect(FileManager.default.fileExists(atPath: iconSetURL.appendingPathComponent(filename).path))
        }
    }

    @Test("Botanical custom tab bar covers every main tab")
    func botanicalCustomTabBarCoversMainTabs() throws {
        let contentSource = try String(contentsOf: try appSourceURL("App/ContentView.swift"), encoding: .utf8)

        #expect(contentSource.contains("BotanicalTabBar"))
        for tab in ["today", "calendar", "track", "insights", "settings"] {
            #expect(contentSource.contains("tab.\(tab)"))
        }
    }

    @Test("Botanical custom tab bar leaves scrollable bottom content unobscured")
    func botanicalCustomTabBarLeavesScrollableBottomContentUnobscured() throws {
        let appThemeSource = try String(contentsOf: try appSourceURL("SharedUI/Styles/AppTheme.swift"), encoding: .utf8)
        let calendarSource = try String(contentsOf: try appSourceURL("Features/Cycle/Views/CalendarMonthView.swift"), encoding: .utf8)
        let contentSource = try String(contentsOf: try appSourceURL("App/ContentView.swift"), encoding: .utf8)

        #expect(appThemeSource.contains("static var botanicalScrollableBottomPadding: CGFloat"))
        #expect(appThemeSource.contains("isBotanicalJournal ? 126 : 0"))
        #expect(calendarSource.contains(".padding(.bottom, AppTheme.botanicalScrollableBottomPadding)"))
        #expect(calendarSource.contains(#".accessibilityIdentifier("calendar.cycle_details.card")"#))
        #expect(contentSource.contains(".padding(.bottom, AppTheme.botanicalScrollableBottomPadding)"))
        #expect(contentSource.contains(#"accessibilityIdentifier: "tracking.card.photo""#))
    }

    @Test("Typography resolver returns fonts for common text styles")
    func typographyResolverSupportsCommonTextStyles() {
        let styles: [(Font.TextStyle, Font.Weight)] = [
            (.body, .regular),
            (.headline, .semibold),
            (.caption, .regular),
        ]

        for option in FontOption.allCases {
            for (style, weight) in styles {
                let resolvedFont = AppTheme.uiFont(style, weight: weight, option: option)
                #expect(!resolvedFont.fontName.isEmpty)
                #expect(resolvedFont.pointSize > 0)
            }
        }
    }

    @Test("Named and designed font options map to the expected families")
    func fontOptionsMapToExpectedFamilies() {
        let expectations: [(FontOption, String)] = [
            (.rounded, "Rounded"),
            (.didot, "Didot"),
            (.newYork, "NewYork"),
            (.cormorantGaramond, "Cormorant"),
            (.sfMono, "Mono"),
            (.baskerville, "Baskerville"),
        ]

        for (option, expectedFragment) in expectations {
            let resolvedFont = AppTheme.uiFont(.headline, weight: .semibold, option: option)
            let searchableName = "\(resolvedFont.familyName) \(resolvedFont.fontName)"
            #expect(searchableName.localizedCaseInsensitiveContains(expectedFragment))
        }
    }

    @Test("Chrome typography resolves navigation and tab fonts for all app font options")
    func chromeTypographySupportsAllFontOptions() {
        for option in FontOption.allCases {
            let navigationAppearance = AppChromeTypography.navigationBarAppearance(option: option)
            let tabAppearance = AppChromeTypography.tabBarAppearance(option: option)

            let inlineTitleFont = navigationAppearance.titleTextAttributes[.font] as? UIFont
            let largeTitleFont = navigationAppearance.largeTitleTextAttributes[.font] as? UIFont
            let stackedTabFont = tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes[.font] as? UIFont
            let inlineTabFont = tabAppearance.inlineLayoutAppearance.selected.titleTextAttributes[.font] as? UIFont

            #expect(inlineTitleFont != nil)
            #expect(largeTitleFont != nil)
            #expect(stackedTabFont != nil)
            #expect(inlineTabFont != nil)
            #expect(!(inlineTitleFont?.fontName.isEmpty ?? true))
            #expect(!(largeTitleFont?.fontName.isEmpty ?? true))
            #expect(!(stackedTabFont?.fontName.isEmpty ?? true))
            #expect(!(inlineTabFont?.fontName.isEmpty ?? true))
        }
    }

    @Test("UI test launch override persists the requested appearance options")
    func uiTestLaunchOverridePersistsAppearanceOptions() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppearancePreferences(defaults: defaults)
        CycleBalanceApp.applyUITestAppearanceOverrideIfNeeded(
            arguments: [
                "UITestMode",
                "-appearance.fontOption", FontOption.didot.rawValue,
                "-appearance.themeOption", ThemeOption.fruitGrove.rawValue,
            ],
            appearancePreferences: preferences
        )

        #expect(preferences.fontOption == .didot)
        #expect(preferences.themeOption == .fruitGrove)

        let reloadedPreferences = AppearancePreferences(defaults: defaults)
        #expect(reloadedPreferences.fontOption == .didot)
        #expect(reloadedPreferences.themeOption == .fruitGrove)
    }

    @Test("Onboarding text uses app typography instead of direct font modifiers")
    func onboardingTextUsesAppTypography() throws {
        let onboardingViewsURL = try TestHelpers.projectRoot(from: #filePath)
            .appendingPathComponent("PCOS/PCOS/Features/Onboarding/Views")
        let viewURLs = try FileManager.default.contentsOfDirectory(
            at: onboardingViewsURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }

        let allowedIconFontLines: Set<String> = [
            "GuidedActionView.swift:.font(.system(size: iconSize))",
            "RatingPromptView.swift:.font(.system(size: iconSize))",
            "ResultsView.swift:.font(.system(size: iconSize))",
            "HowAppHelpsView.swift:.font(.system(size: 48))",
            "OnboardingCompletionView.swift:.font(.system(size: iconSize))",
            "PermissionsStepView.swift:.font(.system(size: iconSize))",
        ]
        var directFontLines: [String] = []

        for viewURL in viewURLs {
            let source = try String(contentsOf: viewURL, encoding: .utf8)
            for line in source.components(separatedBy: .newlines) {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLine.contains(".font(") else {
                    continue
                }
                directFontLines.append("\(viewURL.lastPathComponent):\(trimmedLine)")
            }
        }

        #expect(Set(directFontLines) == allowedIconFontLines)
    }
}

private extension AppearancePreferencesTests {
    func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppearancePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    func appInfoPlistURL() throws -> URL {
        try TestHelpers.projectRoot(from: #filePath)
            .appendingPathComponent("PCOS/PCOS/Info.plist")
    }

    func assetCatalogURL() throws -> URL {
        try TestHelpers.projectRoot(from: #filePath)
            .appendingPathComponent("PCOS/PCOS/Assets.xcassets")
    }

    func fontResourceURL(fileName: String) throws -> URL {
        try TestHelpers.projectRoot(from: #filePath)
            .appendingPathComponent("PCOS/PCOS/Resources/Fonts")
            .appendingPathComponent(fileName)
    }

    func appSourceURL(_ relativePath: String) throws -> URL {
        try TestHelpers.projectRoot(from: #filePath)
            .appendingPathComponent("PCOS/PCOS")
            .appendingPathComponent(relativePath)
    }

    func rgbValues(in palette: ThemePalette) -> [Double] {
        [
            palette.accent,
            palette.sage,
            palette.coral,
            palette.warmNeutralLight,
            palette.warmNeutralDark,
            palette.flowSpottingLight,
            palette.flowLightLight,
            palette.flowMediumLight,
            palette.flowHeavyLight,
            palette.flowSpottingDark,
            palette.flowLightDark,
            palette.flowMediumDark,
            palette.flowHeavyDark,
        ].flatMap { [$0.red, $0.green, $0.blue] }
    }
}

private extension ThemeRGB {
    func matches(hex: UInt32, tolerance: Double = 0.001) -> Bool {
        let expected = ThemeRGB(hex: hex)
        return abs(red - expected.red) <= tolerance
            && abs(green - expected.green) <= tolerance
            && abs(blue - expected.blue) <= tolerance
    }
}
