import StoreKit
import SwiftUI
import UIKit

/// The active subscription as StoreKit reports it on this device. Used only for display.
struct ActiveSubscriptionSummary: Equatable, Sendable {
    let productID: String
    let expirationDate: Date?
    let willAutoRenew: Bool?
}

/// Reads the current entitlement straight from StoreKit 2. This works for both billing backends
/// because RevenueCat purchases are ordinary App Store transactions on the device.
@MainActor
enum ActiveSubscriptionLoader {
    static func load(productIDs: Set<String>) async -> ActiveSubscriptionSummary? {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            return ActiveSubscriptionSummary(
                productID: transaction.productID,
                expirationDate: transaction.expirationDate,
                willAutoRenew: await willAutoRenew(for: transaction)
            )
        }
        return nil
    }

    private static func willAutoRenew(for transaction: StoreKit.Transaction) async -> Bool? {
        guard let groupID = transaction.subscriptionGroupID,
              let statuses = try? await Product.SubscriptionInfo.status(for: groupID) else { return nil }
        for status in statuses {
            if case .verified(let renewalInfo) = status.renewalInfo,
               renewalInfo.currentProductID == transaction.productID {
                return renewalInfo.willAutoRenew
            }
        }
        return nil
    }
}

/// B2: what subscribers see instead of the paywall. "Manage subscription" opens the App Store
/// subscription sheet (AppStore.showManageSubscriptions); no path shows a subscriber the paywall.
struct SubscriptionStatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var products: [BillingProduct] = []
    @State private var summary: ActiveSubscriptionSummary?
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var language: AppLanguage { appState.selectedAppLanguage }

    private var activeProduct: BillingProduct? {
        let activeID = summary?.productID
        return products.first { $0.id == activeID }
            ?? products.first { subscriptionManager.purchasedProductIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                planCard
                    .listRowInsets(EdgeInsets(top: AppTheme.spacing16, leading: AppTheme.spacing16, bottom: AppTheme.spacing16, trailing: AppTheme.spacing16))
            }

            Section {
                Button(action: openManageSubscriptions) {
                    row(
                        title: L10n.string("Manage subscription", defaultValue: "Manage subscription", language: language),
                        subtitle: L10n.string("Opens your Apple Account subscriptions", defaultValue: "Opens your Apple Account subscriptions", language: language),
                        tint: AppTheme.accentColor
                    )
                }
                .accessibilityIdentifier("subscription.manage")

                Button(action: restore) {
                    HStack {
                        row(
                            title: L10n.string("Restore purchases", defaultValue: "Restore purchases", language: language),
                            subtitle: nil,
                            tint: AppTheme.primaryText
                        )
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(isRestoring)
                .accessibilityIdentifier("subscription.restore")

                NavigationLink {
                    PremiumIncludedView(language: language)
                } label: {
                    Text(L10n.string("What's included", defaultValue: "What's included", language: language))
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("subscription.included")
            } footer: {
                Text(L10n.string(
                    "Cancel or change plans in Settings › Apple Account › Subscriptions. Your data stays on your iPhone either way.",
                    defaultValue: "Cancel or change plans in Settings › Apple Account › Subscriptions. Your data stays on your iPhone either way.",
                    language: language
                ))
                .appFont(.footnote)
            }
        }
        .tint(AppTheme.accentColor)
        .navigationTitle(L10n.string("Subscription", defaultValue: "Subscription", language: language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
        .accessibilityIdentifier("screen.subscription")
        .task { await load() }
        .alert(
            L10n.string("Restore purchases", defaultValue: "Restore purchases", language: language),
            isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })
        ) {
            Button(L10n.string("OK", defaultValue: "OK", language: language), role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var planCard: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "leaf")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                        .fill(AppTheme.accentColor.opacity(AppTheme.opacityLight))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("CycleBalance Premium", defaultValue: "CycleBalance Premium", language: language))
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                if let activeProduct {
                    Text(L10n.format(
                        "%@ · %@",
                        defaultValue: "%@ · %@",
                        language: language,
                        activeProduct.planTitle(language: language),
                        activeProduct.displayPricePerPeriod(language: language)
                    ))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                if let renewalText {
                    Text(renewalText)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.accentColor)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("subscription.plan_card")
    }

    private var renewalText: String? {
        guard let date = summary?.expirationDate else { return nil }
        let formatted = date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(appState.renderLocale))
        if summary?.willAutoRenew == false {
            return L10n.format("Ends %@", defaultValue: "Ends %@", language: language, formatted)
        }
        return L10n.format("Renews %@", defaultValue: "Renews %@", language: language, formatted)
    }

    private func row(title: String, subtitle: String?, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(tint)
                if let subtitle {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Spacer(minLength: AppTheme.spacing8)
            Image(systemName: "chevron.right")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func load() async {
        products = (try? await subscriptionManager.loadProducts()) ?? []
        summary = await ActiveSubscriptionLoader.load(
            productIDs: [SubscriptionManager.monthlyProductID, SubscriptionManager.yearlyProductID]
        )
    }

    private func openManageSubscriptions() {
        AppAnalytics.shared.track(.manageSubscriptionOpened)
        Task {
            let scene = UIApplication.shared.connectedScenes
                .first { $0.activationState == .foregroundActive } as? UIWindowScene
            if let scene {
                do {
                    try await AppStore.showManageSubscriptions(in: scene)
                    return
                } catch {
                    // Fall through to the App Store web page.
                }
            }
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                openURL(url)
            }
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await subscriptionManager.restorePurchases()
                await subscriptionManager.checkSubscriptionStatus()
                appState.isPremium = subscriptionManager.isPremium
                AppAnalytics.shared.track(.restoreCompleted(result: subscriptionManager.isPremium ? .restored : .nothingToRestore))
                restoreMessage = subscriptionManager.isPremium
                    ? L10n.string("Your purchases are up to date.", defaultValue: "Your purchases are up to date.", language: language)
                    : L10n.string("No Premium subscription found for this Apple Account.", defaultValue: "No Premium subscription found for this Apple Account.", language: language)
                await load()
            } catch {
                AppAnalytics.shared.track(.restoreCompleted(result: .failed))
                restoreMessage = L10n.string("Check your connection and try again — your logs are safe.", defaultValue: "Check your connection and try again — your logs are safe.", language: language)
            }
        }
    }
}

/// Premium-only features, for subscribers who want to see what their plan includes.
private struct PremiumIncludedView: View {
    private struct Item: Identifiable {
        let id: String
        let systemImage: String
        let title: String
    }

    let language: AppLanguage

    private var items: [Item] {
        [
            Item(id: "logs", systemImage: "fork.knife", title: L10n.string("Meal, glucose & supplement logs, linked to symptoms", defaultValue: "Meal, glucose & supplement logs, linked to symptoms", language: language)),
            Item(id: "insights", systemImage: "chart.bar.xaxis", title: L10n.string("Deeper insights: sleep, activity, meals", defaultValue: "Deeper insights: sleep, activity, meals", language: language)),
            Item(id: "reports", systemImage: "doc.text", title: L10n.string("Unlimited appointment-ready PDF reports", defaultValue: "Unlimited appointment-ready PDF reports", language: language)),
            Item(id: "photos", systemImage: "photo", title: L10n.string("Private photo journal for skin & hair", defaultValue: "Private photo journal for skin & hair", language: language)),
        ]
    }

    var body: some View {
        List {
            ForEach(items) { item in
                Label {
                    Text(item.title).appFont(.body)
                } icon: {
                    Image(systemName: item.systemImage).foregroundStyle(AppTheme.accentColor)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
        }
        .navigationTitle(L10n.string("What's included", defaultValue: "What's included", language: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
