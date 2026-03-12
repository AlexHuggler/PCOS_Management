import SwiftUI
import Foundation

struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var purchaseSucceeded = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroSymbolSize = 48
    @ScaledMetric(relativeTo: .caption) private var freeColumnWidth = 50
    @ScaledMetric(relativeTo: .caption) private var premiumColumnWidth = 70

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacing24) {
                    heroSection
                    featureComparison
                    productCards
                    restoreButton
                    legalDisclaimer
                }
                .padding(AppTheme.spacing16)
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if subscriptionManager.isLoading {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                        ProgressView("Please wait...")
                            .padding(AppTheme.spacing24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { subscriptionManager.errorMessage != nil },
                set: { if !$0 { subscriptionManager.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(subscriptionManager.errorMessage ?? "An unknown error occurred.")
            }
            .sensoryFeedback(.success, trigger: purchaseSucceeded)
            .task {
                await subscriptionManager.load()
                await subscriptionManager.checkSubscriptionStatus()
                appState.isPremium = subscriptionManager.isPremium
            }
            .onChange(of: subscriptionManager.isPremium) { _, isPremium in
                appState.isPremium = isPremium
                if isPremium {
                    purchaseSucceeded = true
                    dismiss()
                }
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: AppTheme.spacing12) {
            Image(systemName: "sparkles")
                .font(.system(size: heroSymbolSize))
                .foregroundStyle(AppTheme.coralAccent)
                .symbolEffect(.pulse)

            Text("Unlock Premium")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Get the full CycleBalance experience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if subscriptionManager.isLocalTestMode {
                Label("Local Test Mode", systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, AppTheme.spacing8)
                    .padding(.vertical, AppTheme.spacing4)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(.top, AppTheme.spacing16)
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            AppTheme.sectionHeader("What's Included")

            VStack(spacing: 0) {
                featureComparisonHeader
                Divider()
                featureRow("Basic cycle tracking", free: true, premium: true)
                Divider()
                featureRow("Symptom logging", free: true, premium: true)
                Divider()
                featureRow("Calendar view", free: true, premium: true)
                Divider()
                featureRow("Insights engine", free: false, premium: true)
                Divider()
                featureRow("PDF reports", free: false, premium: true)
                Divider()
                featureRow("Charts & trends", free: false, premium: true)
                Divider()
                featureRow("HealthKit sync", free: false, premium: true)
                Divider()
                featureRow("Priority support", free: false, premium: true)
            }
            .cardStyle()
        }
    }

    private var featureComparisonHeader: some View {
        HStack {
            Text("Feature")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Free")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: freeColumnWidth * 0.8, idealWidth: freeColumnWidth, alignment: .center)

            Text("Premium")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.coralAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: premiumColumnWidth * 0.8, idealWidth: premiumColumnWidth, alignment: .center)
        }
        .padding(.bottom, AppTheme.spacing8)
    }

    private func featureRow(_ name: String, free: Bool, premium: Bool) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: free ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(free ? AppTheme.sage : Color(.tertiaryLabel))
                .frame(minWidth: freeColumnWidth * 0.8, idealWidth: freeColumnWidth, alignment: .center)

            Image(systemName: premium ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(premium ? AppTheme.coralAccent : Color(.tertiaryLabel))
                .frame(minWidth: premiumColumnWidth * 0.8, idealWidth: premiumColumnWidth, alignment: .center)
        }
        .padding(.vertical, AppTheme.spacing8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(free ? "included in Free" : "not in Free"), \(premium ? "included in Premium" : "not in Premium")")
    }

    // MARK: - Product Cards

    private var productCards: some View {
        VStack(spacing: AppTheme.spacing12) {
            if subscriptionManager.products.isEmpty && !subscriptionManager.isLoading {
                ContentUnavailableView {
                    Label("Subscriptions Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Unable to load subscription options. Please check your connection and try again.")
                }
                .frame(height: 150)
            } else {
                if let monthly = subscriptionManager.monthlyProduct {
                    productCard(for: monthly, badge: nil)
                }

                if let yearly = subscriptionManager.yearlyProduct {
                    let savingsBadge = monthlySavingsText(yearly: yearly)
                    productCard(for: yearly, badge: savingsBadge)
                }
            }
        }
    }

    private func productCard(for product: BillingProduct, badge: String?) -> some View {
        return Button {
            Task {
                do {
                    try await subscriptionManager.purchase(product)
                } catch {
                    // SubscriptionManager already logs and sets errorMessage for UI alerts.
                }
            }
        } label: {
            VStack(spacing: AppTheme.spacing8) {
                HStack {
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(product.displayPriceWithPeriod)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let badge {
                        Text(badge)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppTheme.spacing8)
                            .padding(.vertical, AppTheme.spacing4)
                            .background(AppTheme.coralAccent, in: Capsule())
                    }
                }
            }
            .padding(AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(product.id == Self.yearlyHighlight ? AppTheme.coralAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
        .accessibilityHint(badge ?? "")
    }

    private static let yearlyHighlight = SubscriptionManager.yearlyProductID

    // MARK: - Restore

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await subscriptionManager.restore() }
        }
        .font(.subheadline)
        .foregroundStyle(AppTheme.accentColor)
    }

    // MARK: - Legal

    private var legalDisclaimer: some View {
        VStack(spacing: AppTheme.spacing4) {
            Text("Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage your subscriptions in your Apple ID settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: AppTheme.spacing16) {
                Link("Privacy Policy", destination: URL(string: "https://cyclebalance.app/privacy")!)
                    .font(.caption2)
                Link("Terms of Service", destination: URL(string: "https://cyclebalance.app/terms")!)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, AppTheme.spacing16)
    }

    // MARK: - Helpers

    private func monthlySavingsText(yearly: BillingProduct) -> String? {
        guard let monthly = subscriptionManager.monthlyProduct else { return nil }
        guard let monthlyAnnualized = monthly.annualizedPrice else { return nil }
        let savings = monthlyAnnualized - yearly.price
        guard savings > 0 else { return nil }
        let percent = Int((NSDecimalNumber(decimal: savings / monthlyAnnualized).doubleValue * 100.0).rounded())
        return "Save \(percent)%"
    }
}

#Preview {
    PaywallView()
}
