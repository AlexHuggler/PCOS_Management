import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case en
    case ja
    case it
    case ko
    case fr
    case de
    case nl

    static let defaultsKey = "app.language"
    static let appleLanguagesDefaultsKey = "AppleLanguages"
    static let appleLocaleDefaultsKey = "AppleLocale"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            L10n.string("System Default", defaultValue: "System Default")
        case .en:
            "English"
        case .ja:
            "日本語"
        case .it:
            "Italiano"
        case .ko:
            "한국어"
        case .fr:
            "Français"
        case .de:
            "Deutsch"
        case .nl:
            "Nederlands"
        }
    }

    var languageIdentifier: String? {
        switch self {
        case .system:
            nil
        case .en:
            "en"
        case .ja:
            "ja"
        case .it:
            "it"
        case .ko:
            "ko"
        case .fr:
            "fr"
        case .de:
            "de"
        case .nl:
            "nl"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .en:
            "en_US"
        case .ja:
            "ja_JP"
        case .it:
            "it_IT"
        case .ko:
            "ko_KR"
        case .fr:
            "fr_FR"
        case .de:
            "de_DE"
        case .nl:
            "nl_NL"
        }
    }

    static func stored(defaults: UserDefaults = .standard) -> AppLanguage {
        guard
            let rawValue = defaults.string(forKey: defaultsKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }

        return language
    }

    static func launchSnapshot(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppLanguage {
        guard !hasExplicitLaunchOverride(in: arguments) else {
            return .system
        }

        return stored(defaults: defaults)
    }

    func persist(defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(rawValue, forKey: Self.defaultsKey)
        }
    }

    func applyLaunchOverride(defaults: UserDefaults = .standard) {
        guard
            let languageIdentifier,
            let localeIdentifier
        else {
            defaults.removeObject(forKey: Self.appleLanguagesDefaultsKey)
            defaults.removeObject(forKey: Self.appleLocaleDefaultsKey)
            return
        }

        defaults.set([languageIdentifier], forKey: Self.appleLanguagesDefaultsKey)
        defaults.set(localeIdentifier, forKey: Self.appleLocaleDefaultsKey)
    }

    static func hasExplicitLaunchOverride(in arguments: [String]) -> Bool {
        arguments.contains("-AppleLanguages") || arguments.contains("-AppleLocale")
    }
}

enum L10n {
    private struct OverrideContext {
        let appLanguage: AppLanguage
        let preferredLanguages: [String]
    }

    private final class OverrideStore: @unchecked Sendable {
        private static let stackKey = "PCOS.L10n.OverrideStore.stack"

        func withValue<R>(
            _ context: OverrideContext,
            operation: () throws -> R
        ) rethrows -> R {
            var stack = currentStack()
            stack.append(context)
            setCurrentStack(stack)

            defer {
                var stack = currentStack()
                _ = stack.popLast()
                setCurrentStack(stack)
            }

            return try operation()
        }

        func current() -> OverrideContext? {
            currentStack().last
        }

        private func currentStack() -> [OverrideContext] {
            Thread.current.threadDictionary[Self.stackKey] as? [OverrideContext] ?? []
        }

        private func setCurrentStack(_ stack: [OverrideContext]) {
            if stack.isEmpty {
                Thread.current.threadDictionary.removeObject(forKey: Self.stackKey)
            } else {
                Thread.current.threadDictionary[Self.stackKey] = stack
            }
        }
    }

    static let supportedLanguageIdentifiers = ["ja", "it", "ko", "fr", "de", "nl"]
    static let allLanguageIdentifiers = ["en"] + supportedLanguageIdentifiers
    private static let overrideStore = OverrideStore()

    static func withOverrides<R>(
        appLanguage: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages,
        operation: () throws -> R
    ) rethrows -> R {
        try overrideStore.withValue(
            OverrideContext(
                appLanguage: appLanguage,
                preferredLanguages: preferredLanguages
            ),
            operation: operation
        )
    }

    static func string(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    static func inflected(_ resource: LocalizedStringResource) -> String {
        String(AttributedString(localized: resource).inflected().characters)
    }

    static func accessibilityFlow(
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        string(
            "flow",
            defaultValue: "flow",
            language: language,
            preferredLanguages: preferredLanguages
        )
    }

    static func accessibilityToday(
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        string(
            "today",
            defaultValue: "today",
            language: language,
            preferredLanguages: preferredLanguages
        )
    }

    static func accessibilityPeriod(
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        string(
            "period",
            defaultValue: "period",
            language: language,
            preferredLanguages: preferredLanguages
        )
    }

    static func accessibilityPredictedPeriod(
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        string(
            "predicted period",
            defaultValue: "predicted period",
            language: language,
            preferredLanguages: preferredLanguages
        )
    }

    static func flowDescription(
        for intensity: FlowIntensity,
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        switch intensity {
        case .none:
            string(
                "No flow",
                defaultValue: "No flow",
                language: language,
                preferredLanguages: preferredLanguages
            )
        case .spotting:
            string(
                "Very light, occasional drops",
                defaultValue: "Very light, occasional drops",
                language: language,
                preferredLanguages: preferredLanguages
            )
        case .light:
            string(
                "Light flow, minimal pad or tampon use",
                defaultValue: "Light flow, minimal pad or tampon use",
                language: language,
                preferredLanguages: preferredLanguages
            )
        case .medium:
            string(
                "Moderate, regular pad or tampon use",
                defaultValue: "Moderate, regular pad or tampon use",
                language: language,
                preferredLanguages: preferredLanguages
            )
        case .heavy:
            string(
                "Heavy flow, frequent pad or tampon changes",
                defaultValue: "Heavy flow, frequent pad or tampon changes",
                language: language,
                preferredLanguages: preferredLanguages
            )
        }
    }

    static func flowAccessibilityLabel(
        for intensity: FlowIntensity,
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        let resolvedPreferredLanguages = preferredLanguages ?? currentPreferredLanguages()
        let flowName = format(
            "%@ flow",
            defaultValue: "%@ flow",
            table: nil,
            language: language,
            preferredLanguages: resolvedPreferredLanguages,
            intensity.displayName
        )
        return "\(flowName) — \(flowDescription(for: intensity, language: language, preferredLanguages: resolvedPreferredLanguages))"
    }

    static func flowAccessibilityHint(
        for intensity: FlowIntensity,
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        format(
            "Double tap to select %@ flow intensity",
            defaultValue: "Double tap to select %@ flow intensity",
            table: nil,
            language: language,
            preferredLanguages: preferredLanguages,
            intensity.displayName
        )
    }

    static func decimal(
        _ value: Double,
        fractionDigits: Int = 1,
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        value.formatted(
            .number
                .locale(locale(for: language, preferredLanguages: preferredLanguages))
                .precision(.fractionLength(fractionDigits))
        )
    }

    static func integer(
        _ value: Int,
        language: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        value.formatted(
            .number.locale(locale(for: language, preferredLanguages: preferredLanguages))
        )
    }

    static func bundle(for languageIdentifier: String, base: Bundle = .main) -> Bundle? {
        guard let path = base.path(forResource: languageIdentifier, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    static func resolvedLanguageIdentifier(
        for appLanguage: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        let resolvedAppLanguage = appLanguage ?? currentAppLanguage()
        let resolvedPreferredLanguages = preferredLanguages ?? currentPreferredLanguages()

        if let explicitLanguage = resolvedAppLanguage.languageIdentifier {
            return explicitLanguage
        }

        for preferredLanguage in resolvedPreferredLanguages {
            let normalized = normalizedLanguageIdentifier(from: preferredLanguage)
            if allLanguageIdentifiers.contains(normalized) {
                return normalized
            }
        }

        return "en"
    }

    /// Resolves the locale used for dates, numbers, units and first weekday.
    ///
    /// The language comes from the app-language setting (or the first supported preferred
    /// language), while the region always comes from the device so an English speaker in the UK,
    /// a German speaker in Switzerland, or a Spanish speaker whose language the app does not ship
    /// yet still sees their own date order, 12/24h clock and week start. Strings continue to fall
    /// back to English through the bundle when a language is not shipped.
    static func locale(
        for appLanguage: AppLanguage? = nil,
        preferredLanguages: [String]? = nil,
        deviceLocale: Locale = .current
    ) -> Locale {
        let resolvedAppLanguage = appLanguage ?? currentAppLanguage()
        let resolvedPreferredLanguages = preferredLanguages ?? currentPreferredLanguages()

        if let languageIdentifier = resolvedAppLanguage.languageIdentifier {
            let defaultRegion = resolvedAppLanguage.localeIdentifier.flatMap { Locale(identifier: $0).region }
            return makeLocale(
                languageCode: languageIdentifier,
                region: deviceLocale.region ?? defaultRegion,
                deviceLocale: deviceLocale
            )
        }

        for preferredLanguage in resolvedPreferredLanguages {
            let normalized = normalizedLanguageIdentifier(from: preferredLanguage)
            guard allLanguageIdentifiers.contains(normalized) else { continue }
            let preferredLocale = Locale(identifier: preferredLanguage.replacingOccurrences(of: "-", with: "_"))
            return makeLocale(
                languageCode: normalized,
                region: preferredLocale.region ?? deviceLocale.region,
                deviceLocale: deviceLocale
            )
        }

        return deviceLocale
    }

    private static func makeLocale(languageCode: String, region: Locale.Region?, deviceLocale: Locale) -> Locale {
        var components = Locale.Components(locale: deviceLocale)
        components.languageComponents = Locale.Language.Components(languageCode: Locale.LanguageCode(languageCode))
        components.languageComponents.region = region
        return Locale(components: components)
    }

    static func bundle(
        for appLanguage: AppLanguage,
        base: Bundle = .main,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bundle {
        let languageIdentifier = resolvedLanguageIdentifier(
            for: appLanguage,
            preferredLanguages: preferredLanguages
        )
        return bundle(for: languageIdentifier, base: base) ?? base
    }

    static func string(
        _ key: String,
        defaultValue: String? = nil,
        table: String? = nil,
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil
    ) -> String {
        let fallback = defaultValue ?? key
        let resolvedAppLanguage = language ?? currentAppLanguage()
        let resolvedPreferredLanguages = preferredLanguages ?? currentPreferredLanguages()
        let languageIdentifier = resolvedLanguageIdentifier(
            for: resolvedAppLanguage,
            preferredLanguages: resolvedPreferredLanguages
        )
        let languageBundle = bundle(for: languageIdentifier, base: base)

        // The project ships English as development language without an explicit en.lproj.
        // Force an English fallback string when en is requested to avoid device-locale bleed-through.
        if languageIdentifier == "en", languageBundle == nil {
            return fallback
        }

        let resolvedBundle = languageBundle ?? base
        let localized = resolvedBundle.localizedString(forKey: key, value: fallback, table: table)

        if localized == key, resolvedBundle != base {
            return base.localizedString(forKey: key, value: fallback, table: table)
        }

        return localized
    }

    static func format(
        _ key: String,
        defaultValue: String? = nil,
        table: String? = nil,
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let resolvedAppLanguage = language ?? currentAppLanguage()
        let resolvedPreferredLanguages = preferredLanguages ?? currentPreferredLanguages()
        let format = string(
            key,
            defaultValue: defaultValue,
            table: table,
            language: resolvedAppLanguage,
            base: base,
            preferredLanguages: resolvedPreferredLanguages
        )
        return String(
            format: format,
            locale: locale(for: resolvedAppLanguage, preferredLanguages: resolvedPreferredLanguages),
            arguments: arguments
        )
    }

    static func resolvedAppLanguage(_ explicitLanguage: AppLanguage? = nil) -> AppLanguage {
        explicitLanguage ?? currentAppLanguage()
    }

    static func resolvedPreferredLanguages(_ explicitLanguages: [String]? = nil) -> [String] {
        explicitLanguages ?? currentPreferredLanguages()
    }

    private static func currentAppLanguage() -> AppLanguage {
        overrideStore.current()?.appLanguage ?? AppLanguage.stored()
    }

    private static func currentPreferredLanguages() -> [String] {
        overrideStore.current()?.preferredLanguages ?? Locale.preferredLanguages
    }

    private static func normalizedLanguageIdentifier(from rawValue: String) -> String {
        let separatorSet = CharacterSet(charactersIn: "-_")
        let components = rawValue
            .lowercased()
            .components(separatedBy: separatorSet)
        return components.first ?? rawValue.lowercased()
    }
}
