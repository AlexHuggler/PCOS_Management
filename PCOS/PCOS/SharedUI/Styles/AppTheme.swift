import SwiftUI
import UIKit

struct CycleHeroRingPalette {
    let trackGradient: AngularGradient
    /// Four silk colors, tail → tip.
    let silkColors: [Color]
    let tipCoreColor: Color
    let tipGlowColor: Color
    let innerShadowColor: Color
    let usesGlowBlend: Bool
    /// 0 for the standard zero-fade tail; lifted for High Contrast legibility.
    let tailFloorOpacity: Double
    /// High Contrast uses a solid marker dot instead of a bloom.
    let showsTipBloom: Bool
}

/// CycleBalance design system. The default Botanical Journal theme uses soft
/// botanical wellness colors while preserving legacy theme choices.
enum AppTheme {
    private static var appearance: AppearancePreferences { .shared }
    private static var palette: ThemePalette { appearance.palette }

    // MARK: - Botanical Journal Tokens

    static let botanicalForestRGB = ThemeRGB(hex: 0x173D36)
    static let botanicalForestAltRGB = ThemeRGB(hex: 0x20483F)
    static let botanicalLavenderRGB = ThemeRGB(hex: 0x8E78B8)
    static let botanicalLavenderSoftRGB = ThemeRGB(hex: 0xA899CF)
    static let botanicalRoseRGB = ThemeRGB(hex: 0xC7798E)
    static let botanicalRoseSoftRGB = ThemeRGB(hex: 0xD9A0AD)
    static let botanicalSageRGB = ThemeRGB(hex: 0x9EAD91)
    static let botanicalSageSoftRGB = ThemeRGB(hex: 0xB8C4AA)
    static let botanicalGoldRGB = ThemeRGB(hex: 0xE6B75F)
    static let botanicalCreamRGB = ThemeRGB(hex: 0xFFF8EF)
    static let botanicalCreamAltRGB = ThemeRGB(hex: 0xFAF1E8)

    // MARK: - Lunar Calm Tokens

    static let lunarCalmBackgroundRGB = ThemeRGB(hex: 0x05060D)
    static let lunarCalmBackgroundAltRGB = ThemeRGB(hex: 0x0B0C15)
    static let lunarCalmSurfaceRGB = ThemeRGB(hex: 0x151621)
    static let lunarCalmRaisedSurfaceRGB = ThemeRGB(hex: 0x1B1C28)
    static let lunarCalmBorderRGB = ThemeRGB(hex: 0x30313F)
    static let lunarCalmPrimaryTextRGB = ThemeRGB(hex: 0xF7F2EE)
    static let lunarCalmSecondaryTextRGB = ThemeRGB(hex: 0xCBC7D2)
    static let lunarCalmMutedTextRGB = ThemeRGB(hex: 0x9692A3)
    static let lunarCalmTealRGB = ThemeRGB(hex: 0x68E0D4)
    static let lunarCalmCoralRGB = ThemeRGB(hex: 0xFFAAA0)
    static let lunarCalmPeachRGB = ThemeRGB(hex: 0xFFD4A3)
    static let lunarCalmLavenderRGB = ThemeRGB(hex: 0xB8A7F5)
    static let lunarCalmBlueRGB = ThemeRGB(hex: 0x6DB9E8)
    static let lunarCalmRoseRGB = ThemeRGB(hex: 0xE77D91)
    static let lunarCalmGoldRGB = ThemeRGB(hex: 0xFFC86D)

    static var isBotanicalJournal: Bool {
        appearance.themeOption == .botanicalJournal
    }

    static var isLunarCalm: Bool {
        appearance.themeOption == .lunarCalm
    }

    static var usesCustomTabBar: Bool {
        true
    }

    static var usesImmersiveHomeShell: Bool {
        usesCustomTabBar
    }

    static var usesImmersivePresentation: Bool {
        isLunarCalm
    }

    static var usesPremiumEditorStyling: Bool {
        isEditorialTheme
    }

    static var isEditorialTheme: Bool {
        !appearance.themeOption.isHighContrast
    }

    static var preferredColorScheme: ColorScheme {
        appearance.preferredColorScheme
    }

    static var lunarCalmGradient: LinearGradient {
        LinearGradient(
            colors: [
                lunarCalmTealRGB.color,
                lunarCalmLavenderRGB.color,
                lunarCalmCoralRGB.color,
                lunarCalmPeachRGB.color,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var lunarCalmCycleGradient: LinearGradient {
        LinearGradient(
            colors: [
                ThemeRGB(hex: 0x3CBFD2).color,
                lunarCalmTealRGB.color,
                ThemeRGB(hex: 0xF6B8D1).color,
                ThemeRGB(hex: 0xFFC78F).color,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var lunarCalmCycleTrackGradient: AngularGradient {
        AngularGradient(
            colors: [
                lunarCalmBorderRGB.color.opacity(0.72),
                lunarCalmSurfaceRGB.color.opacity(0.34),
                lunarCalmBorderRGB.color.opacity(0.54),
                lunarCalmBackgroundAltRGB.color.opacity(0.82),
                lunarCalmBorderRGB.color.opacity(0.72),
            ],
            center: .center,
            startAngle: .degrees(180),
            endAngle: .degrees(540)
        )
    }

    static var cycleHeroRingPalette: CycleHeroRingPalette {
        if isLunarCalm {
            return CycleHeroRingPalette(
                trackGradient: lunarCalmCycleTrackGradient,
                silkColors: [
                    lunarCalmTealRGB.color,
                    lunarCalmLavenderRGB.color,
                    lunarCalmCoralRGB.color,
                    lunarCalmPeachRGB.color,
                ],
                tipCoreColor: ThemeRGB(hex: 0xFFF6E8).color,
                tipGlowColor: lunarCalmPeachRGB.color,
                innerShadowColor: lunarCalmBackgroundRGB.color.opacity(0.46),
                usesGlowBlend: true,
                tailFloorOpacity: 0,
                showsTipBloom: true
            )
        }

        if appearance.themeOption.isHighContrast {
            return CycleHeroRingPalette(
                trackGradient: AngularGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.55),
                    ],
                    center: .center,
                    startAngle: .degrees(180),
                    endAngle: .degrees(540)
                ),
                silkColors: [
                    palette.accent.color,
                    palette.accent.color,
                    palette.accent.color,
                    palette.accent.color,
                ],
                tipCoreColor: palette.coral.color,
                tipGlowColor: palette.coral.color,
                innerShadowColor: Color.black.opacity(0.24),
                usesGlowBlend: false,
                tailFloorOpacity: 0.35,
                showsTipBloom: false
            )
        }

        return CycleHeroRingPalette(
            trackGradient: AngularGradient(
                colors: [
                    cardBorder.opacity(0.5),
                    premiumEditorSurface.opacity(0.28),
                    cardBorder.opacity(0.34),
                    premiumEditorRaisedSurface.opacity(0.42),
                    cardBorder.opacity(0.5),
                ],
                center: .center,
                startAngle: .degrees(180),
                endAngle: .degrees(540)
            ),
            silkColors: [
                palette.sage.color,
                premiumEditorAccentColor,
                premiumEditorSecondaryAccentColor,
                softGoldAccent,
            ],
            tipCoreColor: Color.white,
            tipGlowColor: premiumEditorSecondaryAccentColor,
            innerShadowColor: cardBorder.opacity(0.28),
            usesGlowBlend: true,
            tailFloorOpacity: 0,
            showsTipBloom: true
        )
    }

    static var lunarCalmBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                lunarCalmTealRGB.color.opacity(0.8),
                lunarCalmLavenderRGB.color.opacity(0.54),
                lunarCalmCoralRGB.color.opacity(0.58),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var themeAccentGradient: LinearGradient {
        if isLunarCalm {
            lunarCalmGradient
        } else {
            LinearGradient(
                colors: [
                    palette.accent.color,
                    palette.sage.color,
                    palette.coral.color,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static var themeBorderGradient: LinearGradient {
        if isLunarCalm {
            lunarCalmBorderGradient
        } else {
            LinearGradient(
                colors: [
                    palette.accent.color.opacity(appearance.themeOption.isHighContrast ? 0.72 : 0.34),
                    palette.sage.color.opacity(appearance.themeOption.isHighContrast ? 0.62 : 0.22),
                    palette.coral.color.opacity(appearance.themeOption.isHighContrast ? 0.54 : 0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static var premiumEditorAccentGradient: LinearGradient {
        isLunarCalm ? lunarCalmGradient : themeAccentGradient
    }

    static var premiumEditorBorderGradient: LinearGradient {
        isLunarCalm ? lunarCalmBorderGradient : themeBorderGradient
    }

    static var premiumEditorBackground: Color {
        if isLunarCalm {
            lunarCalmBackgroundRGB.color
        } else {
            warmNeutral
        }
    }

    static var premiumEditorSurface: Color {
        if isLunarCalm {
            lunarCalmSurfaceRGB.color.opacity(0.82)
        } else {
            cardBackground.opacity(isBotanicalJournal ? 0.84 : 0.94)
        }
    }

    static var premiumEditorRaisedSurface: Color {
        if isLunarCalm {
            lunarCalmRaisedSurfaceRGB.color
        } else if isBotanicalJournal {
            botanicalCreamAltRGB.color.opacity(0.92)
        } else {
            palette.warmNeutralLight.color.opacity(0.92)
        }
    }

    static var premiumEditorBorder: Color {
        if isLunarCalm {
            lunarCalmBorderRGB.color
        } else {
            cardBorder
        }
    }

    static var premiumEditorAccentColor: Color {
        isLunarCalm ? lunarCalmTealRGB.color : accentColor
    }

    static var premiumEditorSecondaryAccentColor: Color {
        isLunarCalm ? lunarCalmPeachRGB.color : coralAccent
    }

    static var premiumEditorWarningAccentColor: Color {
        isLunarCalm ? lunarCalmCoralRGB.color : roseAccent
    }

    static var premiumEditorCTAForeground: Color {
        isLunarCalm ? lunarCalmBackgroundRGB.color : .white
    }

    // MARK: - Primary Colors

    /// User-selected accent color
    static var accentColor: Color { palette.accent.color }

    /// Secondary accent used across cards and icons
    static var sage: Color { palette.sage.color }

    /// Soft coral for highlights and CTAs
    static var coralAccent: Color { palette.coral.color }

    /// Warm neutral for backgrounds — adaptive for dark mode
    static var warmNeutral: Color {
        Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                    ? palette.warmNeutralDark.uiColor
                    : palette.warmNeutralLight.uiColor
        }
        )
    }

    // MARK: - Flow Intensity Colors (adaptive for dark mode)

    static var flowSpotting: Color {
        Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                    ? palette.flowSpottingDark.uiColor
                    : palette.flowSpottingLight.uiColor
        }
        )
    }
    static var flowLight: Color {
        Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                    ? palette.flowLightDark.uiColor
                    : palette.flowLightLight.uiColor
        }
        )
    }
    static var flowMedium: Color {
        Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                    ? palette.flowMediumDark.uiColor
                    : palette.flowMediumLight.uiColor
        }
        )
    }
    static var flowHeavy: Color {
        Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                    ? palette.flowHeavyDark.uiColor
                    : palette.flowHeavyLight.uiColor
        }
        )
    }

    // MARK: - Semantic Colors

    static var cardBackground: Color {
        if isBotanicalJournal {
            Color(red: 1, green: 250.0 / 255.0, blue: 242.0 / 255.0).opacity(0.78)
        } else if isLunarCalm {
            lunarCalmSurfaceRGB.color.opacity(0.82)
        } else if appearance.themeOption.isHighContrast {
            Color.white.opacity(0.98)
        } else {
            palette.warmNeutralLight.color.opacity(0.86)
        }
    }

    static var groupedBackground: Color {
        warmNeutral
    }

    static var primaryText: Color {
        if isBotanicalJournal {
            botanicalForestRGB.color
        } else if isLunarCalm {
            lunarCalmPrimaryTextRGB.color
        } else if appearance.themeOption.isHighContrast {
            Color.black
        } else {
            palette.accent.color
        }
    }

    static var secondaryText: Color {
        if isBotanicalJournal {
            botanicalForestAltRGB.color.opacity(0.72)
        } else if isLunarCalm {
            lunarCalmSecondaryTextRGB.color
        } else if appearance.themeOption.isHighContrast {
            Color.black.opacity(0.72)
        } else {
            // Pale sage accents (e.g. Blush Moonrise) need darkening to stay
            // legible as text on light backgrounds.
            palette.sage.darkened(by: 0.32).color.opacity(0.92)
        }
    }

    static var lavenderAccent: Color {
        isLunarCalm ? lunarCalmLavenderRGB.color : botanicalLavenderRGB.color
    }

    static var roseAccent: Color {
        isLunarCalm ? lunarCalmRoseRGB.color : botanicalRoseRGB.color
    }

    static var softGoldAccent: Color {
        isLunarCalm ? lunarCalmGoldRGB.color : botanicalGoldRGB.color
    }

    static var cardBorder: Color {
        if isBotanicalJournal {
            botanicalRoseSoftRGB.color.opacity(0.34)
        } else if isLunarCalm {
            lunarCalmBorderRGB.color.opacity(0.92)
        } else if appearance.themeOption.isHighContrast {
            palette.accent.color.opacity(0.78)
        } else {
            palette.sage.color.opacity(0.26)
        }
    }

    static var dividerColor: Color {
        if isBotanicalJournal {
            botanicalSageRGB.color.opacity(0.38)
        } else if isLunarCalm {
            lunarCalmBorderRGB.color.opacity(0.82)
        } else if appearance.themeOption.isHighContrast {
            palette.accent.color.opacity(0.7)
        } else {
            palette.sage.color.opacity(0.32)
        }
    }

    static var cardShadowColor: Color {
        if isBotanicalJournal {
            botanicalRoseRGB.color.opacity(0.14)
        } else if isLunarCalm {
            Color.black.opacity(0.42)
        } else if appearance.themeOption.isHighContrast {
            Color.black.opacity(0.12)
        } else {
            palette.accent.color.opacity(0.11)
        }
    }

    static var defaultCardCornerRadius: CGFloat {
        if isBotanicalJournal {
            28
        } else if isLunarCalm {
            cornerRadiusLarge
        } else if appearance.themeOption.isHighContrast {
            cornerRadiusMedium
        } else {
            cornerRadiusLarge
        }
    }

    static var largeCardCornerRadius: CGFloat {
        if isBotanicalJournal {
            32
        } else if isLunarCalm {
            cornerRadiusXL
        } else if appearance.themeOption.isHighContrast {
            cornerRadiusLarge
        } else {
            cornerRadiusXL
        }
    }

    static let botanicalCustomTabBarBottomClearance: CGFloat = 126
    static let botanicalTabIconFrame = CGSize(width: 28, height: 22)
    static let botanicalTabMinHeight: CGFloat = 56
    static let botanicalTabLabelSpacing: CGFloat = 3
    static let botanicalTabItemVerticalPadding: CGFloat = 8
    static let botanicalBadgeDefaultSize: CGFloat = 48
    static let botanicalBadgeCompactSize: CGFloat = 44
    static let botanicalCardSparkleSize: CGFloat = 44
    static let botanicalPosterEmblemSize: CGFloat = 72
    static let lunarPosterEmblemSize: CGFloat = 64

    static var botanicalScrollableBottomPadding: CGFloat {
        usesCustomTabBar ? botanicalCustomTabBarBottomClearance : 0
    }

    // MARK: - Severity Colors

    static func severityColor(for level: Int) -> Color {
        switch level {
        case 1: .green
        case 2: sage
        case 3: .orange
        case 4: coralAccent
        case 5: .red
        default: .secondary
        }
    }

    // MARK: - Spacing Scale

    /// 4pt — tight inner spacing (icon gaps, dot grids)
    static let spacing4: CGFloat = 4
    /// 8pt — standard inner spacing (chip padding, grid gaps)
    static let spacing8: CGFloat = 8
    /// 12pt — component spacing (card content gaps)
    static let spacing12: CGFloat = 12
    /// 16pt — section spacing (screen-edge padding, between cards)
    static let spacing16: CGFloat = 16
    /// 20pt — airy card spacing for editorial surfaces
    static let spacing20: CGFloat = 20
    /// 24pt — large spacing (card vertical padding)
    static let spacing24: CGFloat = 24
    /// 32pt — hero spacing (hero card padding)
    static let spacing32: CGFloat = 32

    // MARK: - Corner Radius Scale

    /// 8pt — small elements (chips, thumbnails, mini badges)
    static let cornerRadiusSmall: CGFloat = 8
    /// 12pt — standard cards, text fields, list rows
    static let cornerRadiusMedium: CGFloat = 12
    /// 16pt — large cards, modal sheets
    static let cornerRadiusLarge: CGFloat = 16
    /// 20pt — hero cards, feature panels
    static let cornerRadiusXL: CGFloat = 20

    // MARK: - Opacity Scale

    /// 0.08 — subtle tint (disabled states, faint backgrounds)
    static let opacitySubtle: Double = 0.08
    /// 0.12 — default chip / pill fill
    static let opacityLight: Double = 0.12
    /// 0.18 — selected chip / hover emphasis
    static let opacityMedium: Double = 0.18
    /// 0.3 — strong overlay (dimmed backgrounds, active emphasis)
    static let opacityStrong: Double = 0.3

    // MARK: - Typography Scale

    /// Display large — hero numbers (cycle day count)
    static var displayLarge: Font { font(.largeTitle, weight: .bold) }
    /// Heading medium — card titles, section headers
    static var headingMedium: Font { font(.headline, weight: .semibold) }
    /// Body regular — standard content text
    static var bodyRegular: Font { font(.subheadline) }
    /// Caption small — secondary info, timestamps
    static var captionSmall: Font { font(.caption) }
    /// Caption tiny — tertiary labels, metadata
    static var captionTiny: Font { font(.caption2) }

    // MARK: - Typography Helpers

    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular, option: FontOption? = nil) -> Font {
        Font(uiFont(style, weight: weight, option: option))
    }

    static func uiFont(_ style: Font.TextStyle, weight: Font.Weight = .regular, option: FontOption? = nil) -> UIFont {
        let resolvedOption = option ?? resolvedBodyFontOption(
            themeOption: appearance.themeOption,
            selectedFontOption: appearance.fontOption
        )
        return resolvedUIFont(style, weight: weight, option: resolvedOption)
    }

    static func headingFont(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular,
        option: FontOption? = nil
    ) -> Font {
        Font(uiHeadingFont(style, weight: weight, option: option))
    }

    static func uiHeadingFont(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular,
        option: FontOption? = nil
    ) -> UIFont {
        let resolvedOption = option ?? resolvedHeadingFontOption(
            themeOption: appearance.themeOption,
            selectedFontOption: appearance.fontOption
        )
        return resolvedUIFont(style, weight: weight, option: resolvedOption)
    }

    static func resolvedBodyFontOption(
        themeOption: ThemeOption,
        selectedFontOption: FontOption
    ) -> FontOption {
        switch themeOption {
        case .botanicalJournal, .lunarCalm:
            .systemDefault
        default:
            selectedFontOption
        }
    }

    static func resolvedHeadingFontOption(
        themeOption: ThemeOption,
        selectedFontOption: FontOption
    ) -> FontOption {
        switch themeOption {
        case .botanicalJournal, .lunarCalm:
            .cormorantGaramond
        default:
            selectedFontOption
        }
    }

    static func resolvedUIFont(
        _ style: Font.TextStyle,
        weight: Font.Weight,
        option resolvedOption: FontOption
    ) -> UIFont {
        let uiTextStyle = uiTextStyle(for: style)
        let basePointSize = baseFontPointSize(for: uiTextStyle)

        if let postScriptName = resolvedOption.postScriptName(for: weight),
           let customFont = UIFont(name: postScriptName, size: basePointSize) {
            return UIFontMetrics(forTextStyle: uiTextStyle).scaledFont(for: customFont)
        }

        var descriptor = UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: uiTextStyle,
            compatibleWith: defaultContentSizeTraits
        ).addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: uiFontWeight(for: weight)]
        ])

        if let design = resolvedOption.systemDesign,
           let designedDescriptor = descriptor.withDesign(design) {
            descriptor = designedDescriptor
        }

        let systemFont = UIFont(descriptor: descriptor, size: basePointSize)
        return UIFontMetrics(forTextStyle: uiTextStyle).scaledFont(for: systemFont)
    }

    static func sectionHeader(_ text: String) -> some View {
        Text(text)
            .appHeadingFont(.headline, weight: .regular)
            .foregroundStyle(primaryText)
    }

    private static let defaultContentSizeTraits = UITraitCollection(preferredContentSizeCategory: .large)

    private static func baseFontPointSize(for style: UIFont.TextStyle) -> CGFloat {
        UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: style,
            compatibleWith: defaultContentSizeTraits
        ).pointSize
    }

    private static func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle:
            .largeTitle
        case .title:
            .title1
        case .title2:
            .title2
        case .title3:
            .title3
        case .headline:
            .headline
        case .body:
            .body
        case .callout:
            .callout
        case .subheadline:
            .subheadline
        case .footnote:
            .footnote
        case .caption:
            .caption1
        case .caption2:
            .caption2
        @unknown default:
            .body
        }
    }

    private static func uiFontWeight(for weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight:
            .ultraLight
        case .thin:
            .thin
        case .light:
            .light
        case .regular:
            .regular
        case .medium:
            .medium
        case .semibold:
            .semibold
        case .bold:
            .bold
        case .heavy:
            .heavy
        case .black:
            .black
        default:
            .regular
        }
    }
}

// MARK: - Card Style ViewModifier

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        let resolvedCornerRadius = cornerRadius ?? AppTheme.defaultCardCornerRadius

        if AppTheme.isBotanicalJournal {
            content
                .padding(AppTheme.spacing20)
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(AppTheme.cardBackground)
                )
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.botanicalCreamRGB.color.opacity(0.52),
                                    AppTheme.botanicalRoseSoftRGB.color.opacity(0.11),
                                    AppTheme.botanicalLavenderSoftRGB.color.opacity(0.1),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(alignment: .topTrailing) {
                    Image("botanical-sparkles")
                        .resizable()
                        .scaledToFit()
                        .frame(width: AppTheme.botanicalCardSparkleSize, height: AppTheme.botanicalCardSparkleSize)
                        .opacity(0.34)
                        .padding(8)
                        .accessibilityHidden(true)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    AppTheme.botanicalRoseSoftRGB.color.opacity(0.4),
                                    AppTheme.botanicalSageSoftRGB.color.opacity(0.3),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: AppTheme.cardShadowColor, radius: 18, x: 0, y: 10)
        } else if AppTheme.isLunarCalm {
            content
                .padding(AppTheme.spacing16)
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(AppTheme.cardBackground)
                )
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.lunarCalmRaisedSurfaceRGB.color.opacity(0.86),
                                    AppTheme.lunarCalmSurfaceRGB.color.opacity(0.76),
                                    AppTheme.lunarCalmBackgroundAltRGB.color.opacity(0.92),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkle")
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.lunarCalmPeachRGB.color.opacity(0.72))
                        .padding(AppTheme.spacing12)
                        .accessibilityHidden(true)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.lunarCalmBorderGradient, lineWidth: 0.9)
                        .opacity(0.68)
                )
                .shadow(color: AppTheme.cardShadowColor, radius: 22, x: 0, y: 12)
        } else if AppTheme.isEditorialTheme {
            content
                .padding(AppTheme.spacing16)
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(AppTheme.cardBackground)
                )
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accentColor.opacity(0.08),
                                    AppTheme.sage.opacity(0.06),
                                    AppTheme.coralAccent.opacity(0.08),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.themeBorderGradient, lineWidth: 0.8)
                        .opacity(0.74)
                )
                .shadow(color: AppTheme.cardShadowColor, radius: 16, x: 0, y: 9)
        } else {
            content
                .padding(AppTheme.spacing16)
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(AppTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.cardBorder, lineWidth: 1.1)
                )
        }
    }
}

enum BotanicalPosterBackgroundStyle {
    case dense
    case dashboard
    case quiet
}

enum BotanicalPosterDividerStyle {
    case ornamental
    case moon
    case none
}

struct BotanicalScreenBackground: View {
    var style: BotanicalPosterBackgroundStyle = .dashboard

    var body: some View {
        GeometryReader { proxy in
            BotanicalPosterBackground(style: style)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

struct BotanicalPosterBackground: View {
    var style: BotanicalPosterBackgroundStyle = .dashboard

    private var ornamentOpacity: Double {
        switch style {
        case .dense: 0.52
        case .dashboard: 0.42
        case .quiet: 0.28
        }
    }

    private var ornamentScale: CGFloat {
        switch style {
        case .dense: 1.06
        case .dashboard: 0.92
        case .quiet: 0.74
        }
    }

    private var topOrnamentInset: CGFloat {
        switch style {
        case .dense: 18
        case .dashboard: 24
        case .quiet: 32
        }
    }

    private var topLeftOrnamentTopInset: CGFloat {
        switch style {
        case .dense: topOrnamentInset
        case .dashboard: 8
        case .quiet: topOrnamentInset
        }
    }

    private var topLeftOrnamentLeadingInset: CGFloat {
        switch style {
        case .dense: -58
        case .dashboard: -86
        case .quiet: -58
        }
    }

    private var floatingSideOrnamentInset: CGFloat {
        switch style {
        case .dense: 96
        case .dashboard: 116
        case .quiet: 132
        }
    }

    private func ornamentOffset(_ value: CGFloat) -> CGFloat {
        value * ornamentScale
    }

    var body: some View {
        ZStack {
            AppTheme.warmNeutral

            if AppTheme.isBotanicalJournal {
                LinearGradient(
                    colors: [
                        AppTheme.botanicalCreamRGB.color,
                        AppTheme.botanicalCreamAltRGB.color.opacity(0.94),
                        AppTheme.botanicalCreamRGB.color,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image("botanical-watercolor-wash")
                    .resizable()
                    .scaledToFill()
                    .opacity(style == .quiet ? 0.14 : 0.24)
                    .blendMode(.multiply)

                Image("botanical-corner-sprig")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220 * ornamentScale)
                    .botanicalArtworkPlateFade(
                        horizontal: .trailing,
                        vertical: .bottom,
                        horizontalFadeStart: 0.18,
                        verticalFadeStart: 0.26
                    )
                    .opacity(ornamentOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, topLeftOrnamentTopInset)
                    .padding(.leading, ornamentOffset(topLeftOrnamentLeadingInset))

                Image("botanical-sage-leaves")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 205 * ornamentScale)
                    .botanicalEdgeFade(horizontal: .leading, vertical: .bottom, fadeFraction: 0.26)
                    .opacity(ornamentOpacity * 0.82)
                    .rotationEffect(.degrees(12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, topOrnamentInset + ornamentOffset(10))
                    .padding(.trailing, ornamentOffset(-72))

                Image("botanical-lavender-sprig")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250 * ornamentScale)
                    .botanicalEdgeFade(horizontal: .trailing, vertical: .top, fadeFraction: 0.24)
                    .opacity(ornamentOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, ornamentOffset(-68))
                    .padding(.leading, ornamentOffset(-52))

                Image("botanical-rosebud-branch")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 230 * ornamentScale)
                    .botanicalEdgeFade(horizontal: .leading, vertical: .top, fadeFraction: 0.26)
                    .opacity(ornamentOpacity * 0.92)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.bottom, ornamentOffset(-64))
                    .padding(.trailing, ornamentOffset(-58))

                Image("botanical-sparkles")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72)
                    .opacity(style == .quiet ? 0.16 : 0.28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.leading, 210)
                    .padding(.bottom, 160)

                Image("botanical-rosebud-branch")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 155 * ornamentScale)
                    .botanicalEdgeFade(horizontal: .leading, fadeFraction: 0.28)
                    .opacity(style == .dense ? 0.22 : 0.14)
                    .rotationEffect(.degrees(-10))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, ornamentOffset(-92))
                    .padding(.top, floatingSideOrnamentInset)
            } else if AppTheme.isLunarCalm {
                LinearGradient(
                    colors: [
                        AppTheme.lunarCalmBackgroundRGB.color,
                        AppTheme.lunarCalmBackgroundAltRGB.color,
                        AppTheme.lunarCalmBackgroundRGB.color,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .stroke(AppTheme.lunarCalmTealRGB.color.opacity(style == .dense ? 0.34 : 0.22), lineWidth: 46)
                    .frame(width: 360 * ornamentScale, height: 360 * ornamentScale)
                    .blur(radius: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, ornamentOffset(-210))
                    .padding(.bottom, ornamentOffset(-180))

                Circle()
                    .stroke(AppTheme.lunarCalmPeachRGB.color.opacity(style == .quiet ? 0.18 : 0.28), lineWidth: 54)
                    .frame(width: 340 * ornamentScale, height: 340 * ornamentScale)
                    .blur(radius: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, ornamentOffset(-220))
                    .padding(.bottom, ornamentOffset(-148))

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.lunarCalmLavenderRGB.color.opacity(0.18),
                                AppTheme.lunarCalmTealRGB.color.opacity(0.08),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 130
                        )
                    )
                    .frame(width: 260, height: 260)
                    .blur(radius: 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 40)
                    .padding(.trailing, -88)

                Image(systemName: "sparkle")
                    .font(.system(size: style == .quiet ? 12 : 16, weight: .regular))
                    .foregroundStyle(AppTheme.lunarCalmPeachRGB.color.opacity(0.78))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, style == .dense ? 84 : 112)
                    .padding(.trailing, 52)

                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppTheme.lunarCalmPeachRGB.color.opacity(0.58))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.leading, 220)
                    .padding(.bottom, 190)
            } else if AppTheme.isEditorialTheme {
                LinearGradient(
                    colors: [
                        AppTheme.warmNeutral,
                        AppTheme.sage.opacity(0.10),
                        AppTheme.warmNeutral,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Rectangle()
                    .fill(AppTheme.themeAccentGradient.opacity(style == .quiet ? 0.08 : 0.12))
                    .frame(height: 190 * ornamentScale)
                    .rotationEffect(.degrees(-12))
                    .blur(radius: 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, -96)
                    .padding(.horizontal, -90)

                Rectangle()
                    .fill(AppTheme.coralAccent.opacity(style == .dense ? 0.12 : 0.08))
                    .frame(height: 180 * ornamentScale)
                    .rotationEffect(.degrees(11))
                    .blur(radius: 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, -104)
                    .padding(.horizontal, -90)
            } else {
                Color.white
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private enum BotanicalHorizontalFadeEdge {
    case none
    case leading
    case trailing
}

private enum BotanicalVerticalFadeEdge {
    case none
    case top
    case bottom
}

private struct BotanicalEdgeFadeMask: View {
    let horizontal: BotanicalHorizontalFadeEdge
    let vertical: BotanicalVerticalFadeEdge
    let fadeFraction: CGFloat

    private var clampedFadeFraction: CGFloat {
        Swift.min(Swift.max(fadeFraction, 0.02), 0.45)
    }

    var body: some View {
        Rectangle()
            .fill(.white)
            .mask(horizontalMask)
            .mask(verticalMask)
    }

    @ViewBuilder
    private var horizontalMask: some View {
        switch horizontal {
        case .none:
            Rectangle().fill(.white)
        case .leading:
            LinearGradient(
                gradient: Gradient(stops: leadingFadeStops),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .trailing:
            LinearGradient(
                gradient: Gradient(stops: trailingFadeStops),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    @ViewBuilder
    private var verticalMask: some View {
        switch vertical {
        case .none:
            Rectangle().fill(.white)
        case .top:
            LinearGradient(
                gradient: Gradient(stops: leadingFadeStops),
                startPoint: .top,
                endPoint: .bottom
            )
        case .bottom:
            LinearGradient(
                gradient: Gradient(stops: trailingFadeStops),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var leadingFadeStops: [Gradient.Stop] {
        [
            Gradient.Stop(color: .white.opacity(0), location: 0),
            Gradient.Stop(color: .white, location: clampedFadeFraction),
            Gradient.Stop(color: .white, location: 1),
        ]
    }

    private var trailingFadeStops: [Gradient.Stop] {
        [
            Gradient.Stop(color: .white, location: 0),
            Gradient.Stop(color: .white, location: 1 - clampedFadeFraction),
            Gradient.Stop(color: .white.opacity(0), location: 1),
        ]
    }
}

private struct BotanicalArtworkPlateFadeMask: View {
    let horizontal: BotanicalHorizontalFadeEdge
    let vertical: BotanicalVerticalFadeEdge
    let horizontalFadeStart: CGFloat
    let verticalFadeStart: CGFloat

    private var clampedHorizontalFadeStart: CGFloat {
        Swift.min(Swift.max(horizontalFadeStart, 0.08), 0.82)
    }

    private var clampedVerticalFadeStart: CGFloat {
        Swift.min(Swift.max(verticalFadeStart, 0.08), 0.82)
    }

    var body: some View {
        Rectangle()
            .fill(.white)
            .mask(horizontalMask)
            .mask(verticalMask)
    }

    @ViewBuilder
    private var horizontalMask: some View {
        switch horizontal {
        case .none:
            Rectangle().fill(.white)
        case .leading:
            LinearGradient(
                gradient: Gradient(stops: leadingFadeStops(fadeEnd: 1 - clampedHorizontalFadeStart)),
                startPoint: .leading,
                endPoint: .trailing
            )
        case .trailing:
            LinearGradient(
                gradient: Gradient(stops: trailingFadeStops(fadeStart: clampedHorizontalFadeStart)),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    @ViewBuilder
    private var verticalMask: some View {
        switch vertical {
        case .none:
            Rectangle().fill(.white)
        case .top:
            LinearGradient(
                gradient: Gradient(stops: leadingFadeStops(fadeEnd: 1 - clampedVerticalFadeStart)),
                startPoint: .top,
                endPoint: .bottom
            )
        case .bottom:
            LinearGradient(
                gradient: Gradient(stops: trailingFadeStops(fadeStart: clampedVerticalFadeStart)),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func leadingFadeStops(fadeEnd: CGFloat) -> [Gradient.Stop] {
        let midpoint = fadeEnd * 0.56

        return [
            Gradient.Stop(color: .white.opacity(0), location: 0),
            Gradient.Stop(color: .white.opacity(0.28), location: midpoint),
            Gradient.Stop(color: .white, location: fadeEnd),
            Gradient.Stop(color: .white, location: 1),
        ]
    }

    private func trailingFadeStops(fadeStart: CGFloat) -> [Gradient.Stop] {
        let midpoint = fadeStart + ((1 - fadeStart) * 0.58)

        return [
            Gradient.Stop(color: .white, location: 0),
            Gradient.Stop(color: .white, location: fadeStart),
            Gradient.Stop(color: .white.opacity(0.22), location: midpoint),
            Gradient.Stop(color: .white.opacity(0), location: 1),
        ]
    }
}

private struct BotanicalEdgeFadeModifier: ViewModifier {
    let horizontal: BotanicalHorizontalFadeEdge
    let vertical: BotanicalVerticalFadeEdge
    let fadeFraction: CGFloat

    func body(content: Content) -> some View {
        content.mask(
            BotanicalEdgeFadeMask(
                horizontal: horizontal,
                vertical: vertical,
                fadeFraction: fadeFraction
            )
        )
    }
}

private struct BotanicalArtworkPlateFadeModifier: ViewModifier {
    let horizontal: BotanicalHorizontalFadeEdge
    let vertical: BotanicalVerticalFadeEdge
    let horizontalFadeStart: CGFloat
    let verticalFadeStart: CGFloat

    func body(content: Content) -> some View {
        content.mask(
            BotanicalArtworkPlateFadeMask(
                horizontal: horizontal,
                vertical: vertical,
                horizontalFadeStart: horizontalFadeStart,
                verticalFadeStart: verticalFadeStart
            )
        )
    }
}

private extension View {
    func botanicalEdgeFade(horizontal: BotanicalHorizontalFadeEdge = .none, vertical: BotanicalVerticalFadeEdge = .none, fadeFraction: CGFloat = 0.24) -> some View {
        modifier(
            BotanicalEdgeFadeModifier(
                horizontal: horizontal,
                vertical: vertical,
                fadeFraction: fadeFraction
            )
        )
    }

    func botanicalArtworkPlateFade(
        horizontal: BotanicalHorizontalFadeEdge = .none,
        vertical: BotanicalVerticalFadeEdge = .none,
        horizontalFadeStart: CGFloat = 0.22,
        verticalFadeStart: CGFloat = 0.28
    ) -> some View {
        modifier(
            BotanicalArtworkPlateFadeModifier(
                horizontal: horizontal,
                vertical: vertical,
                horizontalFadeStart: horizontalFadeStart,
                verticalFadeStart: verticalFadeStart
            )
        )
    }
}

struct BotanicalDivider: View {
    var width: CGFloat = 260

    var body: some View {
        BotanicalOrnamentalDivider(width: width)
    }
}

struct BotanicalOrnamentalDivider: View {
    var width: CGFloat = 260

    var body: some View {
        Group {
            if AppTheme.isBotanicalJournal {
                Image("botanical-divider")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: width)
            } else if AppTheme.isLunarCalm {
                HStack(spacing: AppTheme.spacing8) {
                    Rectangle()
                        .fill(AppTheme.lunarCalmCycleGradient)
                        .frame(height: 1.2)
                    Image(systemName: "moon.fill")
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.lunarCalmPeachRGB.color)
                    Rectangle()
                        .fill(AppTheme.lunarCalmCycleGradient)
                        .frame(height: 1.2)
                }
                .frame(maxWidth: width)
            } else {
                HStack(spacing: AppTheme.spacing8) {
                    Rectangle()
                        .fill(AppTheme.themeAccentGradient)
                        .frame(height: 1)
                    Image(systemName: AppTheme.isEditorialTheme ? "sparkle" : "circle.fill")
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.accentColor)
                    Rectangle()
                        .fill(AppTheme.themeAccentGradient)
                        .frame(height: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct BotanicalMoonPhaseDivider: View {
    var width: CGFloat = 250

    var body: some View {
        Group {
            if AppTheme.isBotanicalJournal {
                Image("botanical-moon-phase-row")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: width)
                    .opacity(0.76)
            } else if AppTheme.isLunarCalm {
                HStack(spacing: AppTheme.spacing8) {
                    Image(systemName: "moon.fill")
                    Image(systemName: "circle.lefthalf.filled")
                    Image(systemName: "circle.fill")
                    Image(systemName: "circle.righthalf.filled")
                    Image(systemName: "moon")
                }
                .appFont(.caption2)
                .foregroundStyle(AppTheme.lunarCalmCycleGradient)
                .frame(maxWidth: width)
            } else {
                BotanicalOrnamentalDivider(width: width)
            }
        }
        .accessibilityHidden(true)
    }
}

struct BotanicalIconBadge: View {
    let systemImage: String
    var color: Color = AppTheme.accentColor
    var size: CGFloat = AppTheme.botanicalBadgeDefaultSize

    var body: some View {
        BotanicalIllustrationBadge(systemImage: systemImage, color: color, size: size)
    }
}

struct BotanicalIllustrationBadge: View {
    var assetName: String?
    var systemImage: String?
    var color: Color = AppTheme.accentColor
    var size: CGFloat = AppTheme.botanicalBadgeDefaultSize

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    badgeFillColor(color: color)
                )

            Circle()
                .fill(color.opacity(AppTheme.isBotanicalJournal ? 0.12 : AppTheme.isLunarCalm ? 0.16 : 0.08))

            if AppTheme.isBotanicalJournal, let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.11)
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .appFont(.title3)
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(
                    color.opacity(AppTheme.isBotanicalJournal ? 0.24 : AppTheme.isLunarCalm ? 0.42 : 0.26),
                    lineWidth: 0.8
                )
        )
    }

    private func badgeFillColor(color: Color) -> Color {
        if AppTheme.isBotanicalJournal {
            AppTheme.botanicalCreamAltRGB.color.opacity(0.76)
        } else if AppTheme.isLunarCalm {
            AppTheme.lunarCalmRaisedSurfaceRGB.color.opacity(0.92)
        } else if AppTheme.isEditorialTheme {
            color.opacity(0.12)
        } else {
            Color.white
        }
    }
}

struct BotanicalPosterCard<Content: View>: View {
    var cornerRadius: CGFloat = AppTheme.largeCardCornerRadius
    let content: Content

    init(cornerRadius: CGFloat = AppTheme.largeCardCornerRadius, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content.cardStyle(cornerRadius: cornerRadius)
    }
}

struct BotanicalPosterHeader: View {
    let title: String
    var subtitle: String?
    var emblemAssetName: String? = nil
    var dividerStyle: BotanicalPosterDividerStyle = .ornamental

    var body: some View {
        VStack(spacing: AppTheme.spacing12) {
            if AppTheme.isBotanicalJournal, let emblemAssetName {
                Image(emblemAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppTheme.botanicalPosterEmblemSize, height: AppTheme.botanicalPosterEmblemSize)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.botanicalCreamRGB.color.opacity(0.74))
                            .shadow(color: AppTheme.botanicalRoseRGB.color.opacity(0.13), radius: 14, y: 8)
                    )
                    .accessibilityHidden(true)
            } else if AppTheme.isLunarCalm {
                ZStack {
                    Circle()
                        .fill(AppTheme.lunarCalmGradient)
                    Image(systemName: "moon.stars.fill")
                        .appFont(.title2)
                        .foregroundStyle(AppTheme.lunarCalmBackgroundRGB.color)
                }
                .frame(width: AppTheme.lunarPosterEmblemSize, height: AppTheme.lunarPosterEmblemSize)
                .shadow(color: AppTheme.lunarCalmTealRGB.color.opacity(0.24), radius: 18, y: 8)
                .accessibilityHidden(true)
            }

            Text(title)
                .appHeadingFont(.largeTitle, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)

            switch dividerStyle {
            case .ornamental:
                BotanicalOrnamentalDivider(width: 230)
            case .moon:
                BotanicalMoonPhaseDivider(width: 230)
            case .none:
                EmptyView()
            }

            if let subtitle {
                Text(subtitle)
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct AppFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(AppTheme.font(style, weight: weight))
    }
}

struct AppHeadingFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(AppTheme.headingFont(style, weight: weight))
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat? = nil) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }

    nonisolated func appFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(AppFontModifier(style: style, weight: weight))
    }

    nonisolated func appHeadingFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(AppHeadingFontModifier(style: style, weight: weight))
    }
}
