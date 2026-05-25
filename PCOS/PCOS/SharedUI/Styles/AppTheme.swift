import SwiftUI
import UIKit

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

    static var isBotanicalJournal: Bool {
        appearance.themeOption == .botanicalJournal
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
        isBotanicalJournal
            ? Color(red: 1, green: 250.0 / 255.0, blue: 242.0 / 255.0).opacity(0.78)
            : Color(.secondarySystemGroupedBackground)
    }

    static var groupedBackground: Color {
        isBotanicalJournal ? warmNeutral : Color(.systemGroupedBackground)
    }

    static var primaryText: Color {
        isBotanicalJournal ? botanicalForestRGB.color : .primary
    }

    static var secondaryText: Color {
        isBotanicalJournal ? botanicalForestAltRGB.color.opacity(0.72) : .secondary
    }

    static var lavenderAccent: Color {
        botanicalLavenderRGB.color
    }

    static var roseAccent: Color {
        botanicalRoseRGB.color
    }

    static var softGoldAccent: Color {
        botanicalGoldRGB.color
    }

    static var cardBorder: Color {
        isBotanicalJournal
            ? botanicalRoseSoftRGB.color.opacity(0.34)
            : Color.secondary.opacity(0.12)
    }

    static var dividerColor: Color {
        isBotanicalJournal
            ? botanicalSageRGB.color.opacity(0.38)
            : Color.secondary.opacity(0.18)
    }

    static var cardShadowColor: Color {
        isBotanicalJournal
            ? botanicalRoseRGB.color.opacity(0.14)
            : Color.black.opacity(0.06)
    }

    static var defaultCardCornerRadius: CGFloat {
        isBotanicalJournal ? 28 : cornerRadiusMedium
    }

    static var largeCardCornerRadius: CGFloat {
        isBotanicalJournal ? 32 : cornerRadiusXL
    }

    static var botanicalScrollableBottomPadding: CGFloat {
        isBotanicalJournal ? 126 : 0
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
        themeOption == .botanicalJournal ? .systemDefault : selectedFontOption
    }

    static func resolvedHeadingFontOption(
        themeOption: ThemeOption,
        selectedFontOption: FontOption
    ) -> FontOption {
        themeOption == .botanicalJournal ? .cormorantGaramond : selectedFontOption
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
                        .frame(width: 44, height: 44)
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
        } else {
            content
                .padding(AppTheme.spacing16)
                .background(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .fill(AppTheme.cardBackground)
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
        BotanicalPosterBackground(style: style)
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
            } else {
                HStack(spacing: AppTheme.spacing8) {
                    Rectangle()
                        .fill(AppTheme.dividerColor)
                        .frame(height: 1)
                    Image(systemName: "circle.fill")
                        .appFont(.caption2)
                        .foregroundStyle(AppTheme.dividerColor)
                    Rectangle()
                        .fill(AppTheme.dividerColor)
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
    var size: CGFloat = 48

    var body: some View {
        BotanicalIllustrationBadge(systemImage: systemImage, color: color, size: size)
    }
}

struct BotanicalIllustrationBadge: View {
    var assetName: String?
    var systemImage: String?
    var color: Color = AppTheme.accentColor
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AppTheme.isBotanicalJournal
                        ? AppTheme.botanicalCreamAltRGB.color.opacity(0.76)
                        : color.opacity(AppTheme.opacityLight)
                )

            Circle()
                .fill(color.opacity(AppTheme.isBotanicalJournal ? 0.12 : 0))

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
                    color.opacity(AppTheme.isBotanicalJournal ? 0.24 : 0),
                    lineWidth: AppTheme.isBotanicalJournal ? 0.8 : 0
                )
        )
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
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.botanicalCreamRGB.color.opacity(0.74))
                            .shadow(color: AppTheme.botanicalRoseRGB.color.opacity(0.13), radius: 14, y: 8)
                    )
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
