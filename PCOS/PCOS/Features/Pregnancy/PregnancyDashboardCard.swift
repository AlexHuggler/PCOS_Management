import SwiftUI

struct PregnancyDashboardCard: View {
    let gestationalText: String?
    let postpartumDayCount: Int?
    let lifecycleMode: LifecycleMode

    var body: some View {
        if AppTheme.usesPremiumEditorStyling {
            lunarBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        VStack(spacing: AppTheme.spacing12) {
            if lifecycleMode == .pregnant {
                if let gestationalText {
                    Text(gestationalText)
                        .appFont(.largeTitle, weight: .bold)
                        .foregroundStyle(AppTheme.accentColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.string("Pregnancy Mode", defaultValue: "Pregnancy Mode"))
                        .appFont(.title, weight: .semibold)
                        .multilineTextAlignment(.center)
                }
            } else if lifecycleMode == .postpartum {
                if let days = postpartumDayCount {
                    Text(
                        L10n.format(
                            "Postpartum — Day %lld",
                            defaultValue: "Postpartum — Day %lld",
                            Int64(days)
                        )
                    )
                    .appFont(.largeTitle, weight: .bold)
                    .foregroundStyle(AppTheme.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.string("Postpartum", defaultValue: "Postpartum"))
                        .appFont(.title, weight: .semibold)
                        .multilineTextAlignment(.center)
                }

                Text(L10n.string(
                    "Log your first period to resume cycle tracking.",
                    defaultValue: "Log your first period to resume cycle tracking."
                ))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing32)
        .cardStyle(cornerRadius: AppTheme.cornerRadiusXL)
    }

    private var lunarBody: some View {
        VStack(spacing: AppTheme.spacing16) {
            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: lifecycleMode == .postpartum ? "sparkles" : "heart.fill")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 50, height: 50)
            .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.22), radius: 16, y: 8)
            .accessibilityHidden(true)

            if lifecycleMode == .pregnant {
                Text(gestationalText ?? L10n.string("Pregnancy Mode", defaultValue: "Pregnancy Mode"))
                    .appHeadingFont(.largeTitle, weight: .regular)
                    .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.string(
                    "Cycle predictions are paused while your history stays safe.",
                    defaultValue: "Cycle predictions are paused while your history stays safe."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            } else if lifecycleMode == .postpartum {
                if let days = postpartumDayCount {
                    Text(
                        L10n.format(
                            "Postpartum — Day %lld",
                            defaultValue: "Postpartum — Day %lld",
                            Int64(days)
                        )
                    )
                    .appHeadingFont(.largeTitle, weight: .regular)
                    .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.string("Postpartum", defaultValue: "Postpartum"))
                        .appHeadingFont(.largeTitle, weight: .regular)
                        .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                        .multilineTextAlignment(.center)
                }

                Text(L10n.string(
                    "Log your first period to resume cycle tracking.",
                    defaultValue: "Log your first period to resume cycle tracking."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing24)
        .padding(.horizontal, AppTheme.spacing16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL, style: .continuous)
                        .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.9)
                )
        )
        .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pregnancy_dashboard.lunar.card")
    }
}
