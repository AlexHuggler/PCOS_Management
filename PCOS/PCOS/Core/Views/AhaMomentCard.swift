import SwiftUI

struct AhaMomentCard: View {
    let moment: AhaMoment

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .top, spacing: AppTheme.spacing8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.coralAccent)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(moment.title)
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(.primary)

                    Text(moment.body)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Label(moment.nextAction, systemImage: "arrow.forward.circle.fill")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.sage)
                .fixedSize(horizontal: false, vertical: true)

            if let premiumDetail = moment.premiumDetail {
                Text(premiumDetail)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, AppTheme.spacing4)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("aha_moment.card")
    }
}

/// Immersive-shell variant of the insight card: sparkle header, insight copy,
/// and a decorative theme-gradient moonscape. Renders with the active theme's
/// editor tokens so it adapts to every palette.
struct ImmersiveInsightCard: View {
    let moment: AhaMoment

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "sparkles")
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)

                Text(L10n.string("Insight for you", defaultValue: "Insight for you"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: AppTheme.spacing16) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(moment.title)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(moment.body)
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(moment.nextAction, systemImage: "arrow.forward.circle.fill")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AppTheme.spacing4)
                }

                Spacer(minLength: 0)

                decorativeMoonscape
            }
        }
        .padding(AppTheme.spacing20)
        .premiumCardDecoration()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.lunar.insight")
    }

    private var decorativeMoonscape: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(AppTheme.premiumEditorAccentGradient)
                .frame(width: 32, height: 32)
                .offset(x: 6, y: -28)

            Ellipse()
                .fill(AppTheme.sage.opacity(0.5))
                .frame(width: 66, height: 30)
                .offset(x: -16, y: 10)

            Ellipse()
                .fill(AppTheme.premiumEditorSecondaryAccentColor.opacity(0.4))
                .frame(width: 66, height: 24)
                .offset(x: 18, y: 8)
        }
        .frame(width: 72, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
        .accessibilityHidden(true)
    }
}
