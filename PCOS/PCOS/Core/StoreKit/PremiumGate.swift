import SwiftUI

struct PremiumGateModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .overlay {
                if !appState.allowsPremiumAccess {
                    PremiumGateOverlay {
                        appState.presentPremiumPaywall()
                    }
                }
            }
    }
}

private struct PremiumGateOverlay: View {
    let unlockAction: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).opacity(0.6)
                .background(.ultraThinMaterial)

            Button(action: unlockAction) {
                VStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "sparkles")
                        .appFont(.title2)
                        .foregroundStyle(AppTheme.coralAccent)
                        .accessibilityHidden(true)

                    VStack(spacing: AppTheme.spacing4) {
                        Text(L10n.string("Premium Feature", defaultValue: "Premium Feature"))
                            .appFont(.headline)
                            .foregroundStyle(.primary)

                        Text(
                            L10n.string(
                                "Unlock this feature and more with CycleBalance Premium.",
                                defaultValue: "Unlock this feature and more with CycleBalance Premium."
                            )
                        )
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }

                    Label(
                        L10n.string("Unlock Premium", defaultValue: "Unlock Premium"),
                        systemImage: "sparkles"
                    )
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.spacing16)
                    .padding(.vertical, AppTheme.spacing8)
                    .background(Capsule().fill(AppTheme.accentColor))
                }
                .padding(AppTheme.spacing16)
                .frame(maxWidth: 280)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                        .stroke(AppTheme.accentColor.opacity(AppTheme.opacityStrong), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                L10n.string("Premium Feature", defaultValue: "Premium Feature")
            )
            .accessibilityHint(
                L10n.string(
                    "Unlock this feature and more with CycleBalance Premium.",
                    defaultValue: "Unlock this feature and more with CycleBalance Premium."
                )
            )
            .accessibilityIdentifier("premium_gate.unlock")
        }
    }
}

extension View {
    func premiumGated() -> some View {
        modifier(PremiumGateModifier())
    }
}
