import SwiftUI

struct PregnancyDashboardCard: View {
    let gestationalText: String?
    let postpartumDayCount: Int?
    let lifecycleMode: LifecycleMode

    var body: some View {
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
}
