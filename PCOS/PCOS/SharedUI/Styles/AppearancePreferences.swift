import Observation
import SwiftUI
import UIKit

enum ThemeOption: String, CaseIterable, Identifiable, Codable {
    case botanicalJournal
    case sage
    case sunrise
    case ocean
    case botanicalMist
    case blushMoonrise
    case fruitGrove
    case highContrast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .botanicalJournal:
            L10n.string("Botanical Journal", defaultValue: "Botanical Journal")
        case .sage:
            L10n.string("Sage Bloom", defaultValue: "Sage Bloom")
        case .sunrise:
            L10n.string("Sunrise Clay", defaultValue: "Sunrise Clay")
        case .ocean:
            L10n.string("Tidepool", defaultValue: "Tidepool")
        case .botanicalMist:
            L10n.string("Botanical Mist", defaultValue: "Botanical Mist")
        case .blushMoonrise:
            L10n.string("Blush Moonrise", defaultValue: "Blush Moonrise")
        case .fruitGrove:
            L10n.string("Fruit Grove", defaultValue: "Fruit Grove")
        case .highContrast:
            L10n.string("High Contrast", defaultValue: "High Contrast")
        }
    }

    var isHighContrast: Bool {
        self == .highContrast
    }

    var palette: ThemePalette {
        switch self {
        case .botanicalJournal:
            ThemePalette(
                accent: .init(hex: 0x173D36),
                sage: .init(hex: 0x9EAD91),
                coral: .init(hex: 0xC7798E),
                warmNeutralLight: .init(hex: 0xFFF8EF),
                warmNeutralDark: .init(hex: 0x171E1A),
                flowSpottingLight: .init(hex: 0xF1D4D8),
                flowLightLight: .init(hex: 0xD9A0AD),
                flowMediumLight: .init(hex: 0xC7798E),
                flowHeavyLight: .init(hex: 0x9B4E66),
                flowSpottingDark: .init(hex: 0xC98E9C),
                flowLightDark: .init(hex: 0xB86F82),
                flowMediumDark: .init(hex: 0x9B5067),
                flowHeavyDark: .init(hex: 0x75374C)
            )
        case .sage:
            ThemePalette(
                accent: .init(red: 0.384, green: 0.498, blue: 0.478),
                sage: .init(red: 0.384, green: 0.498, blue: 0.478),
                coral: .init(red: 0.906, green: 0.486, blue: 0.416),
                warmNeutralLight: .init(red: 0.973, green: 0.965, blue: 0.949),
                warmNeutralDark: .init(red: 0.12, green: 0.11, blue: 0.10),
                flowSpottingLight: .init(red: 0.886, green: 0.690, blue: 0.667),
                flowLightLight: .init(red: 0.831, green: 0.506, blue: 0.475),
                flowMediumLight: .init(red: 0.737, green: 0.337, blue: 0.310),
                flowHeavyLight: .init(red: 0.600, green: 0.200, blue: 0.180),
                flowSpottingDark: .init(red: 0.75, green: 0.55, blue: 0.53),
                flowLightDark: .init(red: 0.70, green: 0.42, blue: 0.40),
                flowMediumDark: .init(red: 0.63, green: 0.30, blue: 0.28),
                flowHeavyDark: .init(red: 0.52, green: 0.18, blue: 0.16)
            )
        case .sunrise:
            ThemePalette(
                accent: .init(red: 0.615, green: 0.365, blue: 0.278),
                sage: .init(red: 0.623, green: 0.553, blue: 0.345),
                coral: .init(red: 0.812, green: 0.389, blue: 0.247),
                warmNeutralLight: .init(red: 0.985, green: 0.956, blue: 0.918),
                warmNeutralDark: .init(red: 0.15, green: 0.12, blue: 0.10),
                flowSpottingLight: .init(red: 0.906, green: 0.761, blue: 0.647),
                flowLightLight: .init(red: 0.859, green: 0.588, blue: 0.463),
                flowMediumLight: .init(red: 0.773, green: 0.416, blue: 0.302),
                flowHeavyLight: .init(red: 0.627, green: 0.271, blue: 0.204),
                flowSpottingDark: .init(red: 0.80, green: 0.64, blue: 0.53),
                flowLightDark: .init(red: 0.72, green: 0.49, blue: 0.38),
                flowMediumDark: .init(red: 0.63, green: 0.36, blue: 0.28),
                flowHeavyDark: .init(red: 0.52, green: 0.24, blue: 0.18)
            )
        case .ocean:
            ThemePalette(
                accent: .init(red: 0.169, green: 0.420, blue: 0.565),
                sage: .init(red: 0.263, green: 0.576, blue: 0.557),
                coral: .init(red: 0.898, green: 0.447, blue: 0.357),
                warmNeutralLight: .init(red: 0.947, green: 0.973, blue: 0.980),
                warmNeutralDark: .init(red: 0.09, green: 0.13, blue: 0.16),
                flowSpottingLight: .init(red: 0.773, green: 0.835, blue: 0.886),
                flowLightLight: .init(red: 0.592, green: 0.725, blue: 0.812),
                flowMediumLight: .init(red: 0.420, green: 0.620, blue: 0.733),
                flowHeavyLight: .init(red: 0.251, green: 0.486, blue: 0.620),
                flowSpottingDark: .init(red: 0.55, green: 0.70, blue: 0.80),
                flowLightDark: .init(red: 0.40, green: 0.59, blue: 0.72),
                flowMediumDark: .init(red: 0.29, green: 0.47, blue: 0.61),
                flowHeavyDark: .init(red: 0.20, green: 0.35, blue: 0.50)
            )
        case .botanicalMist:
            ThemePalette(
                accent: .init(hex: 0x244F43),
                sage: .init(hex: 0x8F9A7C),
                coral: .init(hex: 0xE9A38A),
                warmNeutralLight: .init(hex: 0xFBF4ED),
                warmNeutralDark: .init(hex: 0x171E1A),
                flowSpottingLight: .init(hex: 0xE9C9C8),
                flowLightLight: .init(hex: 0xD9928A),
                flowMediumLight: .init(hex: 0xB95F66),
                flowHeavyLight: .init(hex: 0x873A43),
                flowSpottingDark: .init(hex: 0xC98F91),
                flowLightDark: .init(hex: 0xB76C70),
                flowMediumDark: .init(hex: 0x984C55),
                flowHeavyDark: .init(hex: 0x74333C)
            )
        case .blushMoonrise:
            ThemePalette(
                accent: .init(hex: 0x237987),
                sage: .init(hex: 0xAFC4B7),
                coral: .init(hex: 0xE97FA6),
                warmNeutralLight: .init(hex: 0xFFF8FB),
                warmNeutralDark: .init(hex: 0x17171A),
                flowSpottingLight: .init(hex: 0xF5CCD8),
                flowLightLight: .init(hex: 0xEA9AB2),
                flowMediumLight: .init(hex: 0xD96F92),
                flowHeavyLight: .init(hex: 0xA94467),
                flowSpottingDark: .init(hex: 0xD89AAE),
                flowLightDark: .init(hex: 0xC57691),
                flowMediumDark: .init(hex: 0xA95676),
                flowHeavyDark: .init(hex: 0x843852)
            )
        case .fruitGrove:
            ThemePalette(
                accent: .init(hex: 0xB95C61),
                sage: .init(hex: 0x87906E),
                coral: .init(hex: 0xE7A28D),
                warmNeutralLight: .init(hex: 0xFFF7EC),
                warmNeutralDark: .init(hex: 0x1B1714),
                flowSpottingLight: .init(hex: 0xF2C1BD),
                flowLightLight: .init(hex: 0xDD8584),
                flowMediumLight: .init(hex: 0xC55B61),
                flowHeavyLight: .init(hex: 0x933A45),
                flowSpottingDark: .init(hex: 0xD69693),
                flowLightDark: .init(hex: 0xBE696D),
                flowMediumDark: .init(hex: 0x9E4C56),
                flowHeavyDark: .init(hex: 0x75313F)
            )
        case .highContrast:
            ThemePalette(
                accent: .init(red: 0.086, green: 0.239, blue: 0.612),
                sage: .init(red: 0.102, green: 0.345, blue: 0.290),
                coral: .init(red: 0.773, green: 0.220, blue: 0.071),
                warmNeutralLight: .init(red: 0.992, green: 0.992, blue: 0.984),
                warmNeutralDark: .init(red: 0.06, green: 0.06, blue: 0.06),
                flowSpottingLight: .init(red: 0.902, green: 0.718, blue: 0.635),
                flowLightLight: .init(red: 0.827, green: 0.506, blue: 0.424),
                flowMediumLight: .init(red: 0.714, green: 0.337, blue: 0.255),
                flowHeavyLight: .init(red: 0.545, green: 0.192, blue: 0.118),
                flowSpottingDark: .init(red: 0.82, green: 0.62, blue: 0.56),
                flowLightDark: .init(red: 0.72, green: 0.42, blue: 0.34),
                flowMediumDark: .init(red: 0.62, green: 0.30, blue: 0.22),
                flowHeavyDark: .init(red: 0.52, green: 0.20, blue: 0.14)
            )
        }
    }
}

enum FontOption: String, CaseIterable, Identifiable, Codable {
    case systemDefault
    case rounded
    case didot
    case newYork
    case cormorantGaramond
    case sfMono
    case baskerville

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemDefault:
            L10n.string("SF Pro", defaultValue: "SF Pro")
        case .rounded:
            L10n.string("SF Pro Rounded", defaultValue: "SF Pro Rounded")
        case .didot:
            L10n.string("Didot", defaultValue: "Didot")
        case .newYork:
            L10n.string("New York", defaultValue: "New York")
        case .cormorantGaramond:
            L10n.string("Cormorant Garamond", defaultValue: "Cormorant Garamond")
        case .sfMono:
            L10n.string("SF Mono", defaultValue: "SF Mono")
        case .baskerville:
            L10n.string("Baskerville", defaultValue: "Baskerville")
        }
    }

    var systemDesign: UIFontDescriptor.SystemDesign? {
        switch self {
        case .systemDefault:
            nil
        case .rounded:
            .rounded
        case .didot:
            nil
        case .newYork:
            .serif
        case .cormorantGaramond:
            nil
        case .sfMono:
            .monospaced
        case .baskerville:
            nil
        }
    }

    func postScriptName(for weight: Font.Weight) -> String? {
        switch self {
        case .systemDefault, .rounded, .newYork, .sfMono:
            nil
        case .cormorantGaramond:
            switch weight {
            case .medium:
                "CormorantGaramond-Medium"
            case .semibold:
                "CormorantGaramond-SemiBold"
            case .bold, .heavy, .black:
                "CormorantGaramond-Bold"
            case .light, .thin, .ultraLight:
                "CormorantGaramond-Light"
            default:
                "CormorantGaramond-Regular"
            }
        case .didot:
            switch weight {
            case .semibold, .bold, .heavy, .black:
                "Didot-Bold"
            default:
                "Didot"
            }
        case .baskerville:
            switch weight {
            case .medium, .semibold:
                "Baskerville-SemiBold"
            case .bold, .heavy, .black:
                "Baskerville-Bold"
            default:
                "Baskerville"
            }
        }
    }
}

struct ThemePalette: Sendable, Equatable {
    let accent: ThemeRGB
    let sage: ThemeRGB
    let coral: ThemeRGB
    let warmNeutralLight: ThemeRGB
    let warmNeutralDark: ThemeRGB
    let flowSpottingLight: ThemeRGB
    let flowLightLight: ThemeRGB
    let flowMediumLight: ThemeRGB
    let flowHeavyLight: ThemeRGB
    let flowSpottingDark: ThemeRGB
    let flowLightDark: ThemeRGB
    let flowMediumDark: ThemeRGB
    let flowHeavyDark: ThemeRGB
}

struct ThemeRGB: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

extension ThemeRGB {
    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255.0
        green = Double((hex >> 8) & 0xFF) / 255.0
        blue = Double(hex & 0xFF) / 255.0
    }
}

private struct AppearanceSelection: Codable, Equatable {
    var themeOption: ThemeOption
    var fontOption: FontOption

    static let `default` = AppearanceSelection(
        themeOption: .botanicalJournal,
        fontOption: .systemDefault
    )
}

@Observable
final class AppearancePreferences {
    nonisolated(unsafe) static let shared = AppearancePreferences()
    private static let settingsKey = "appearance.preferences"

    private let defaults: UserDefaults

    var themeOption: ThemeOption {
        didSet { persistAndRefresh() }
    }

    var fontOption: FontOption {
        didSet { persistAndRefresh() }
    }

    var renderKey = UUID()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.settingsKey),
           let selection = try? JSONDecoder().decode(AppearanceSelection.self, from: data) {
            themeOption = selection.themeOption
            fontOption = selection.fontOption
        } else {
            themeOption = AppearanceSelection.default.themeOption
            fontOption = AppearanceSelection.default.fontOption
        }
    }

    var palette: ThemePalette {
        themeOption.palette
    }

    func setThemeOption(_ option: ThemeOption) {
        themeOption = option
    }

    func setFontOption(_ option: FontOption) {
        fontOption = option
    }
}

private extension AppearancePreferences {
    func persistAndRefresh() {
        let selection = AppearanceSelection(
            themeOption: themeOption,
            fontOption: fontOption
        )

        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: Self.settingsKey)
        }

        renderKey = UUID()
    }
}
