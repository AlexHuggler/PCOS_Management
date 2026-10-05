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

    @Test("Fresh installs default to Calm in light mode")
    func freshInstallDefaultsToLunarCalm() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppearancePreferences(defaults: defaults)

        #expect(preferences.themeOption == .calm)
        #expect(preferences.colorMode == .light)
        #expect(preferences.preferredColorScheme == .light)
        #expect(preferences.fontOption == .systemDefault)
        #expect(preferences.availableThemeOptions.first == .calm)
    }

    @Test("Existing users without a saved appearance keep following the system; fresh installs stay light")
    func existingUsersKeepSystemColorMode() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "onboarding.hasCompletedOnboarding")
        #expect(AppearancePreferences(defaults: defaults).colorMode == .system)

        let (freshDefaults, freshSuiteName) = makeDefaults()
        defer { freshDefaults.removePersistentDomain(forName: freshSuiteName) }
        #expect(AppearancePreferences(defaults: freshDefaults).colorMode == .light)
        // Completing onboarding later does not flip a fresh install back to the system setting.
        freshDefaults.set(true, forKey: "onboarding.hasCompletedOnboarding")
        #expect(AppearancePreferences(defaults: freshDefaults).colorMode == .light)
    }

    @Test("Legacy saved themes keep their original color mode")
    func legacyColorModeMigration() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for theme in [ThemeOption.lunarCalm, .botanicalJournal, .sage] {
            let payload = "{\"themeOption\":\"\(theme.rawValue)\",\"fontOption\":\"rounded\"}"
            defaults.set(payload.data(using: .utf8), forKey: "appearance.preferences")
            let preferences = AppearancePreferences(defaults: defaults)
            #expect(preferences.themeOption == theme)
            #expect(preferences.colorMode == (theme == .lunarCalm ? .dark : .light))
            preferences.colorMode = .system
            #expect(AppearancePreferences(defaults: defaults).colorMode == .system)
        }
    }

    @Test("Color mode persists independently of theme changes")
    func independentColorMode() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppearancePreferences(defaults: defaults)
        for mode in AppearanceColorMode.allCases {
            preferences.colorMode = mode
            let key = preferences.renderKey
            preferences.themeOption = .botanicalJournal
            preferences.themeOption = .lunarCalm
            #expect(preferences.renderKey != key)
            #expect(preferences.colorMode == mode)
            #expect(AppearancePreferences(defaults: defaults).colorMode == mode)
        }
    }

    @Test("Companion semantic text and accent meet normal text contrast in each mode")
    func companionContrast() {
        func luminance(_ color: UIColor) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func linear(_ value: CGFloat) -> Double { let v = Double(value); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        for theme in [ThemeOption.calm, .lunarCalm, .botanicalJournal] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast)])
                    for surface in [AppTheme.CompanionColorRole.background, .surface, .raisedSurface] {
                        let background = luminance(AppTheme.companionUIColor(theme: theme, role: surface, traits: traits))
                        for role in [AppTheme.CompanionColorRole.primaryText, .secondaryText, .accent] {
                            let foreground = luminance(AppTheme.companionUIColor(theme: theme, role: role, traits: traits))
                            #expect((max(foreground, background) + 0.05) / (min(foreground, background) + 0.05) >= 4.5)
                        }
                    }
                    let button = luminance(AppTheme.companionUIColor(theme: theme, role: .accent, traits: traits))
                    let label = luminance(AppTheme.companionUIColor(theme: theme, role: .ctaText, traits: traits))
                    #expect((max(button, label) + 0.05) / (min(button, label) + 0.05) >= 4.5)
                }
            }
        }
    }

    @Test("Navigation title and background adapt when light and dark traits change")
    func navigationColorsFollowTraits() throws {
        let preferences = AppearancePreferences.shared
        let original = preferences.themeOption
        defer { preferences.setThemeOption(original) }
        for theme in [ThemeOption.calm, .lunarCalm, .botanicalJournal] {
            preferences.setThemeOption(theme)
            let appearance = AppChromeTypography.navigationBarAppearance()
            let title = try #require(appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor)
            let background = try #require(appearance.backgroundColor)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                #expect(title.resolvedColor(with: traits) == AppTheme.companionUIColor(theme: theme, role: .primaryText, traits: traits))
                #expect(background.resolvedColor(with: traits) == AppTheme.companionUIColor(theme: theme, role: .background, traits: traits))
            }
        }
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

    @Test("Launch themes include Lunar Calm first and an accessible high-contrast option")
    func highContrastThemeExists() {
        #expect(ThemeOption.allCases.count == 10)
        #expect(ThemeOption.allCases.first == .calm)
        #expect(ThemeOption.allCases.contains(.botanicalJournal))
        #expect(ThemeOption.allCases.contains(.lunarCalm))
        #expect(ThemeOption.allCases.contains(.highContrast))
        #expect(ThemeOption.allCases.contains(.botanicalMist))
        #expect(ThemeOption.allCases.contains(.blushMoonrise))
        #expect(ThemeOption.allCases.contains(.fruitGrove))
        #expect(ThemeOption.highContrast.isHighContrast)
        #expect(FontOption.allCases == [.systemDefault, .rounded, .didot, .newYork, .cormorantGaramond, .sfMono, .baskerville])
    }

    @Test("Lunar Calm is a public default theme choice")
    func lunarCalmIsPublicDefaultThemeChoice() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppearancePreferences(defaults: defaults)

        #expect(preferences.availableThemeOptions.first == .calm)
        #expect(preferences.availableThemeOptions.contains(.lunarCalm))
        #expect(!preferences.experimentalThemeControlVisible)
        #expect(preferences.availableThemeOptions.contains(.botanicalJournal))
        #expect(preferences.availableThemeOptions.contains(.highContrast))
    }

    @Test("Internal theme lab control can still be enabled")
    func internalThemeLabControlCanStillBeEnabled() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "appearance.enableExperimentalThemes")
        let preferences = AppearancePreferences(defaults: defaults)

        #expect(preferences.availableThemeOptions.contains(.lunarCalm))
        #expect(preferences.experimentalThemeControlVisible)
    }

    @Test("Simulator review builds expose the internal theme lab outside tests")
    func simulatorReviewBuildsExposeInternalThemeLabOutsideTests() throws {
        let source = try String(contentsOf: try appSourceURL("SharedUI/Styles/AppearancePreferences.swift"), encoding: .utf8)

        #expect(source.contains("isInternalReviewRuntime"))
        #expect(source.contains("#if targetEnvironment(simulator)"))
        #expect(source.contains("XCTestConfigurationFilePath"))
        #expect(source.contains("return true"))
    }

    @Test("Lunar Calm requests dark appearance while stable themes stay light")
    func lunarCalmRequestsDarkAppearance() {
        #expect(ThemeOption.botanicalJournal.preferredColorScheme == .light)
        #expect(ThemeOption.highContrast.preferredColorScheme == .light)
        #expect(ThemeOption.lunarCalm.preferredColorScheme == .dark)
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
        for themeOption in [ThemeOption.botanicalJournal, .botanicalMist, .blushMoonrise, .fruitGrove, .lunarCalm] {
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

    @Test("Lunar Calm palette matches the moonlit concept direction")
    func lunarCalmPaletteMatchesConceptDirection() {
        let palette = ThemeOption.lunarCalm.palette

        #expect(palette.accent.matches(hex: 0x68E0D4))
        #expect(palette.sage.matches(hex: 0xB8A7F5))
        #expect(palette.coral.matches(hex: 0xFFAAA0))
        #expect(palette.warmNeutralLight.matches(hex: 0x05060D))
        #expect(palette.warmNeutralDark.matches(hex: 0x05060D))
        #expect(AppTheme.lunarCalmPeachRGB.matches(hex: 0xFFD4A3))
        #expect(AppTheme.lunarCalmSurfaceRGB.matches(hex: 0x151621))
    }

    @Test("Lunar Calm home hero ring matches the luminous cycle reference")
    func lunarCalmHomeHeroRingMatchesReferenceStyle() throws {
        let todaySource = try String(contentsOf: try appSourceURL("Features/Cycle/Views/TodayView.swift"), encoding: .utf8)
        let appThemeSource = try String(contentsOf: try appSourceURL("SharedUI/Styles/AppTheme.swift"), encoding: .utf8)

        #expect(appThemeSource.contains("struct CycleHeroRingPalette"))
        #expect(appThemeSource.contains("static var cycleHeroRingPalette: CycleHeroRingPalette"))
        #expect(appThemeSource.contains("static var lunarCalmCycleTrackGradient"))
        #expect(appThemeSource.contains("let silkColors: [Color]"))
        #expect(todaySource.contains("AppTheme.cycleHeroRingPalette"))
        #expect(todaySource.contains("SilkCometRingModel("))
        #expect(todaySource.contains("let lineWidth = max(size * 0.05, 13)"))
        #expect(todaySource.contains("let trackWidth = max(size * 0.012, 2.5)"))
        #expect(todaySource.contains("RingMotionStyle.resolved(reduceMotion: reduceMotion)"))
        #expect(!todaySource.contains(#"Image(systemName: "sparkle")"#))
    }

    @Test("Appearance changes keep the native navigation root mounted")
    func appearanceChangesKeepNavigationMounted() throws {
        let source = try String(contentsOf: try appSourceURL("App/ContentView.swift"), encoding: .utf8)
        #expect(!AppTheme.usesCustomTabBar)
        // This source boundary guards identity: state behavior itself is exercised by routing tests.
        #expect(source.contains("TabView(selection:"))
        #expect(!source.contains(".id(contentRenderIdentity)"))
        #expect(!source.contains(".id(appearancePreferences.renderKey)"))
        #expect(!source.contains("BotanicalTabBar("))
    }

    @Test("Botanical Journal keeps body text SF Pro while headings resolve to serif")
    func botanicalJournalTypographyPolicy() {
        #expect(AppTheme.resolvedBodyFontOption(themeOption: .botanicalJournal, selectedFontOption: .baskerville) == .systemDefault)
        #expect(AppTheme.resolvedHeadingFontOption(themeOption: .botanicalJournal, selectedFontOption: .systemDefault).rawValue == "cormorantGaramond")
        #expect(AppTheme.resolvedBodyFontOption(themeOption: .lunarCalm, selectedFontOption: .baskerville) == .systemDefault)
        #expect(AppTheme.resolvedHeadingFontOption(themeOption: .lunarCalm, selectedFontOption: .systemDefault).rawValue == "cormorantGaramond")
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

    @Test("Native navigation exposes all five named tabs")
    func nativeNavigationCoversMainTabs() throws {
        let source = try String(contentsOf: try appSourceURL("App/ContentView.swift"), encoding: .utf8)
        #expect(AppTab.allCases.map(\.rawValue) == ["today", "calendar", "track", "insights", "settings"])
        for tab in AppTab.allCases {
            #expect(!tab.title(for: .en).isEmpty)
            #expect(!tab.systemImage.isEmpty)
            #expect(source.contains(".tag(AppTab.\(tab.rawValue))"))
        }
    }

    @Test("Native tab safe areas do not add custom-bar clearance")
    func nativeTabSafeAreasAvoidExtraClearance() {
        #expect(!AppTheme.usesCustomTabBar)
        #expect(AppTheme.botanicalScrollableBottomPadding == 0)
    }

    @Test("Track uses native list rows with one logger sheet")
    func trackingUsesNativeRowsAndSinglePresentation() throws {
        let source = try String(contentsOf: try appSourceURL("App/ContentView.swift"), encoding: .utf8)
        #expect(source.contains("List {"))
        #expect(source.contains(".sheet(item: $activeLogger"))
        #expect(!source.contains("showingLogMeal = false"))
        #expect(!source.contains("BotanicalTabButton"))
    }

    @Test("Native tab chrome keeps theme typography")
    func nativeTabChromeKeepsThemeTypography() {
        let appearance = AppChromeTypography.tabBarAppearance(option: .systemDefault)
        let selected = appearance.stackedLayoutAppearance.selected
        #expect(selected.titleTextAttributes[.font] is UIFont)
        #expect(selected.iconColor != nil)
    }

    @Test("Check-in has one form workflow across appearance choices")
    func checkInHasOneFormWorkflow() throws {
        let source = try String(contentsOf: try appSourceURL("Features/Symptoms/Views/SymptomLogView.swift"), encoding: .utf8)
        // CategoryChip is shared with PhotoJournal and may retain appearance-specific decoration.
        let checkInSource = source.components(separatedBy: "struct CategoryChip").first ?? source
        #expect(checkInSource.contains("Form {"))
        #expect(checkInSource.contains("DailyCheckInService(modelContext:"))
        #expect(!checkInSource.contains("usesPremiumEditorStyling"))
        #expect(!checkInSource.contains("lunarMoodSelection"))
    }

    @Test("Premium editor styling is shared by core data-entry logs")
    func premiumEditorStylingIsSharedByCoreDataEntryLogs() throws {
        let appThemeSource = try String(contentsOf: try appSourceURL("SharedUI/Styles/AppTheme.swift"), encoding: .utf8)
        let cycleLogSource = try String(contentsOf: try appSourceURL("Features/Cycle/Views/CycleLogView.swift"), encoding: .utf8)
        let symptomLogSource = try String(contentsOf: try appSourceURL("Features/Symptoms/Views/SymptomLogView.swift"), encoding: .utf8)
        let ovulationLogSource = try String(contentsOf: try appSourceURL("Features/Cycle/Views/OvulationLogView.swift"), encoding: .utf8)
        let bloodSugarLogSource = try String(contentsOf: try appSourceURL("Features/BloodSugar/Views/BloodSugarLogView.swift"), encoding: .utf8)
        let bloodSugarHistorySource = try String(contentsOf: try appSourceURL("Features/BloodSugar/Views/BloodSugarHistoryView.swift"), encoding: .utf8)
        let mealLogSource = try String(contentsOf: try appSourceURL("Features/Meals/Views/MealLogView.swift"), encoding: .utf8)
        let mealHistorySource = try String(contentsOf: try appSourceURL("Features/Meals/Views/MealHistoryView.swift"), encoding: .utf8)
        let mealDetailSource = try String(contentsOf: try appSourceURL("Features/Meals/Views/MealDetailView.swift"), encoding: .utf8)
        let mealScanSource = try String(contentsOf: try appSourceURL("Features/Meals/MealScan/Views/MealScanFlowView.swift"), encoding: .utf8)
        let supplementLogSource = try String(contentsOf: try appSourceURL("Features/Supplements/Views/SupplementLogView.swift"), encoding: .utf8)
        let supplementHistorySource = try String(contentsOf: try appSourceURL("Features/Supplements/Views/SupplementHistoryView.swift"), encoding: .utf8)
        let photoGallerySource = try String(contentsOf: try appSourceURL("Features/PhotoJournal/Views/PhotoGalleryView.swift"), encoding: .utf8)
        let photoCaptureSource = try String(contentsOf: try appSourceURL("Features/PhotoJournal/Views/PhotoCaptureView.swift"), encoding: .utf8)
        let photoComparisonSource = try String(contentsOf: try appSourceURL("Features/PhotoJournal/Views/PhotoComparisonView.swift"), encoding: .utf8)
        let pregnancyActivationSource = try String(contentsOf: try appSourceURL("Features/Pregnancy/PregnancyActivationView.swift"), encoding: .utf8)
        let pregnancyEndSource = try String(contentsOf: try appSourceURL("Features/Pregnancy/PregnancyEndView.swift"), encoding: .utf8)
        let pregnancyDashboardSource = try String(contentsOf: try appSourceURL("Features/Pregnancy/PregnancyDashboardCard.swift"), encoding: .utf8)
        let pregnancyCalendarSource = try String(contentsOf: try appSourceURL("Features/Pregnancy/PregnancyCalendarOverlay.swift"), encoding: .utf8)
        let reportConfigSource = try String(contentsOf: try appSourceURL("Features/Reports/Views/ReportConfigView.swift"), encoding: .utf8)
        let evidenceDisclosureSource = try String(contentsOf: try appSourceURL("SharedUI/Components/EvidenceDisclosureSheet.swift"), encoding: .utf8)
        let notificationSettingsSource = try String(contentsOf: try appSourceURL("Core/Notifications/NotificationSettingsView.swift"), encoding: .utf8)
        let healthKitSettingsSource = try String(contentsOf: try appSourceURL("Core/HealthKit/HealthKitSettingsView.swift"), encoding: .utf8)

        #expect(appThemeSource.contains("static var premiumEditorAccentGradient"))
        #expect(appThemeSource.contains("static var premiumEditorBackground"))
        #expect(cycleLogSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(cycleLogSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(symptomLogSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(symptomLogSource.contains(".tint(AppTheme.accentColor)"))
        #expect(ovulationLogSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(ovulationLogSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(bloodSugarLogSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(bloodSugarLogSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(bloodSugarHistorySource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(bloodSugarHistorySource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!bloodSugarHistorySource.contains("AppTheme.isLunarCalm"))
        #expect(mealLogSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(mealLogSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(mealHistorySource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(mealHistorySource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(mealDetailSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(mealDetailSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(mealScanSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(mealScanSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(supplementLogSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(supplementLogSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!supplementLogSource.contains("AppTheme.isLunarCalm"))
        #expect(supplementHistorySource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(supplementHistorySource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!supplementHistorySource.contains("AppTheme.isLunarCalm"))
        #expect(photoGallerySource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(photoGallerySource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!photoGallerySource.contains("AppTheme.isLunarCalm"))
        #expect(photoCaptureSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(photoCaptureSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!photoCaptureSource.contains("AppTheme.isLunarCalm"))
        #expect(photoComparisonSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(photoComparisonSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!photoComparisonSource.contains("AppTheme.isLunarCalm"))
        #expect(pregnancyActivationSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(pregnancyActivationSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!pregnancyActivationSource.contains("AppTheme.isLunarCalm"))
        #expect(pregnancyEndSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(pregnancyEndSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!pregnancyEndSource.contains("AppTheme.isLunarCalm"))
        #expect(pregnancyDashboardSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(pregnancyDashboardSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!pregnancyDashboardSource.contains("AppTheme.isLunarCalm"))
        #expect(pregnancyCalendarSource.contains("AppTheme.usesPremiumEditorStyling"))
        #expect(pregnancyCalendarSource.contains("AppTheme.premiumEditorAccentGradient"))
        #expect(!pregnancyCalendarSource.contains("AppTheme.isLunarCalm"))

        for source in [reportConfigSource, evidenceDisclosureSource, notificationSettingsSource, healthKitSettingsSource] {
            #expect(source.contains("AppTheme.usesPremiumEditorStyling"))
            #expect(source.contains("AppTheme.premiumEditorAccentGradient"))
            #expect(source.contains("AppTheme.premiumEditorCTAForeground"))
            #expect(!source.contains("AppTheme.isLunarCalm"))
        }
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
                "-appearance.themeOption", ThemeOption.lunarCalm.rawValue,
            ],
            appearancePreferences: preferences
        )

        #expect(preferences.fontOption == .didot)
        #expect(preferences.themeOption == .lunarCalm)

        let reloadedPreferences = AppearancePreferences(defaults: defaults)
        #expect(reloadedPreferences.fontOption == .didot)
        #expect(reloadedPreferences.themeOption == .lunarCalm)
    }

    @Test("Manual launch override keeps Lunar Calm public without enabling experimental controls")
    func manualLaunchOverrideKeepsLunarCalmPublicWithoutEnablingExperimentalControls() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppearancePreferences(defaults: defaults)
        CycleBalanceApp.applyAppearanceLaunchOverridesIfNeeded(
            arguments: [
                "-appearance.themeOption", ThemeOption.lunarCalm.rawValue,
            ],
            appearancePreferences: preferences
        )

        #expect(preferences.themeOption == .lunarCalm)
        #expect(!preferences.experimentalThemesEnabled)
        #expect(preferences.availableThemeOptions.contains(.lunarCalm))
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
                guard trimmedLine.contains(".font("), !trimmedLine.contains("Image(systemName: symbol)") else {
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
