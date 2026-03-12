import SwiftUI

struct PremiumGateModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !appState.isPremium {
                    ZStack {
                        Color(.systemBackground)
                            .opacity(0.8)

                        VStack(spacing: AppTheme.spacing16) {
                            Image(systemName: "lock.fill")
                                .font(.largeTitle)
                                .foregroundStyle(AppTheme.accentColor)

                            Text("Premium Feature")
                                .font(.headline)

                            Text("Unlock this feature and more with CycleBalance Premium.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.spacing24)

                            Button("Unlock Premium") {
                                showPaywall = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.coralAccent)
                            .sensoryFeedback(.selection, trigger: showPaywall)
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
    }
}

extension View {
    func premiumGated() -> some View {
        modifier(PremiumGateModifier())
    }
}
