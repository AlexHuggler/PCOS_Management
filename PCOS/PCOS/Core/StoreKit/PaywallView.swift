import Foundation
import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview

    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var billingProducts: [BillingProduct] = []
    @State private var isLoadingProducts = false
    @State private var activePurchaseProductID: String?
    @State private var isRestoringPurchases = false
    @State private var loadErrorMessage: String?
    @State private var alertErrorMessage: String?

    private static let privacyPolicyURL = URL(string: "https://cyclebalance.app/privacy")!
    private static let termsOfServiceURL = URL(string: "https://cyclebalance.app/terms")!

    private var paywallLanguage: AppLanguage {
        appState.selectedAppLanguage
    }

    private var paywallFeatures: [PaywallFeature] {
        PaywallCopy.features(for: paywallLanguage)
    }

    private var backendMode: BillingBackendMode {
        subscriptionManager.backendMode
    }

    private var isLocalStoreKit: Bool {
        backendMode == .localStoreKit
    }

    private var monthlyProduct: BillingProduct? {
        billingProducts.first(where: { $0.id == SubscriptionManager.monthlyProductID })
    }

    private var yearlyProduct: BillingProduct? {
        billingProducts.first(where: { $0.id == SubscriptionManager.yearlyProductID })
    }

    private var isBusy: Bool {
        activePurchaseProductID != nil || isRestoringPurchases
    }

    private var yearlySavingsText: String? {
        guard
            let monthlyPrice = monthlyProduct?.annualizedPrice.map({ NSDecimalNumber(decimal: $0).doubleValue }),
            let yearlyPrice = yearlyProduct?.annualizedPrice.map({ NSDecimalNumber(decimal: $0).doubleValue }),
            monthlyPrice > 0,
            yearlyPrice > 0,
            yearlyPrice < monthlyPrice
        else {
            return nil
        }

        let savingsPercent = Int((((monthlyPrice - yearlyPrice) / monthlyPrice) * 100).rounded())
        guard savingsPercent > 0 else { return nil }

        return L10n.format(
            "Save %lld%%",
            defaultValue: "Save %lld%%",
            language: paywallLanguage,
            Int64(savingsPercent)
        )
    }

    var body: some View {
        ZStack {
            if appState.showsSubscriptionUI {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    PaywallTopBar(language: paywallLanguage, closeAction: closePaywall)

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .accessibilityIdentifier("screen.paywall")
            } else {
                Color.clear
                    .ignoresSafeArea()
            }
        }
        .task {
            guard appState.showsSubscriptionUI else {
                closePaywall()
                return
            }

            await loadPaywallIfNeeded()
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("screen.paywall")
        .alert(PaywallCopy.errorTitle(for: paywallLanguage), isPresented: Binding(
            get: { alertErrorMessage != nil },
            set: { if !$0 { alertErrorMessage = nil } }
        )) {
            Button(PaywallCopy.okButton(for: paywallLanguage), role: .cancel) {}
        } message: {
            Text(alertErrorMessage ?? PaywallCopy.unknownError(for: paywallLanguage))
        }
    }

    @ViewBuilder
    private var content: some View {
        if billingProducts.isEmpty {
            if isLoadingProducts {
                ProgressView(PaywallCopy.loadingPremiumOptions(for: paywallLanguage))
                    .appFont(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("paywall.loading")
            } else {
                PaywallUnavailableState(
                    language: paywallLanguage,
                    message: loadErrorMessage ?? PaywallCopy.unableToLoadOptions(for: paywallLanguage),
                    retryAction: retryLoadingProducts
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    PaywallSparkleHeader(language: paywallLanguage)

                    if isLocalStoreKit {
                        PaywallLocalModeBadge(language: paywallLanguage)
                    }

                    PaywallFeatureComparisonCard(language: paywallLanguage, features: paywallFeatures)

                    VStack(spacing: AppTheme.spacing12) {
                        ForEach(billingProducts) { product in
                            PaywallPlanCard(
                                language: paywallLanguage,
                                product: product,
                                savingsText: product.id == SubscriptionManager.yearlyProductID ? yearlySavingsText : nil,
                                isRecommended: product.id == SubscriptionManager.yearlyProductID,
                                isProcessing: activePurchaseProductID == product.id,
                                isDisabled: isBusy,
                                purchaseAction: {
                                    purchase(product)
                                }
                            )
                        }
                    }

                    PaywallFooterLinks(
                        language: paywallLanguage,
                        isRestoring: isRestoringPurchases,
                        isDisabled: isBusy,
                        restoreAction: restorePurchases,
                        privacyPolicyURL: Self.privacyPolicyURL,
                        termsOfServiceURL: Self.termsOfServiceURL
                    )
                }
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.top, AppTheme.spacing12)
                .padding(.bottom, AppTheme.spacing32)
            }
        }
    }

    private func closePaywall() {
        dismiss()
    }

    private func retryLoadingProducts() {
        Task {
            await loadPaywallIfNeeded(forceReload: true)
        }
    }

    private func purchase(_ product: BillingProduct) {
        Task {
            await purchaseProduct(product)
        }
    }

    private func restorePurchases() {
        Task {
            await restoreExistingPurchases()
        }
    }

    private func loadPaywallIfNeeded(forceReload: Bool = false) async {
        guard forceReload || (!isLoadingProducts && billingProducts.isEmpty) else { return }

        isLoadingProducts = true
        loadErrorMessage = nil
        if forceReload {
            billingProducts = []
        }

        defer {
            isLoadingProducts = false
        }

        await subscriptionManager.checkSubscriptionStatus()
        appState.isPremium = subscriptionManager.isPremium

        do {
            billingProducts = try await subscriptionManager.loadProducts()
        } catch {
            loadErrorMessage = Self.userFacingMessage(
                for: error,
                fallback: PaywallCopy.unableToLoadOptions(for: paywallLanguage)
            )
        }
    }

    private func refreshPremiumStateAndDismissIfNeeded() async {
        await subscriptionManager.checkSubscriptionStatus()
        appState.isPremium = subscriptionManager.isPremium

        if subscriptionManager.isPremium {
            closePaywall()
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, requestReview: requestReview)
        } else if let statusMessage = subscriptionManager.statusMessage {
            alertErrorMessage = statusMessage
        }
    }

    private func purchaseProduct(_ product: BillingProduct) async {
        activePurchaseProductID = product.id
        defer {
            activePurchaseProductID = nil
        }

        do {
            let outcome = try await subscriptionManager.purchase(productID: product.id)
            switch outcome {
            case .success:
                await refreshPremiumStateAndDismissIfNeeded()
            case .pending:
                alertErrorMessage = PaywallCopy.purchasePending(for: paywallLanguage)
            case .cancelled:
                break
            }
        } catch {
            alertErrorMessage = Self.userFacingMessage(
                for: error,
                fallback: PaywallCopy.purchaseFailed(for: paywallLanguage)
            )
        }
    }

    private func restoreExistingPurchases() async {
        isRestoringPurchases = true
        defer {
            isRestoringPurchases = false
        }

        do {
            try await subscriptionManager.restorePurchases()
            await refreshPremiumStateAndDismissIfNeeded()
        } catch {
            alertErrorMessage = Self.userFacingMessage(
                for: error,
                fallback: PaywallCopy.restoreFailed(for: paywallLanguage)
            )
        }
    }

    private static func userFacingMessage(for error: Error, fallback: String) -> String {
        if let localizedError = error as? LocalizedError {
            if let description = localizedError.errorDescription, let suggestion = localizedError.recoverySuggestion {
                return "\(description) \(suggestion)"
            }

            if let description = localizedError.errorDescription {
                return description
            }
        }

        return fallback
    }
}

private enum PaywallCopy {
    static func errorTitle(for language: AppLanguage) -> String {
        string("Error", defaultValue: "Error", language: language)
    }

    static func okButton(for language: AppLanguage) -> String {
        string("OK", defaultValue: "OK", language: language)
    }

    static func unknownError(for language: AppLanguage) -> String {
        string(
            "An unknown error occurred.",
            defaultValue: "An unknown error occurred.",
            language: language
        )
    }

    static func loadingPremiumOptions(for language: AppLanguage) -> String {
        string(
            "Loading Premium Options...",
            defaultValue: "Loading Premium Options...",
            language: language
        )
    }

    static func unableToLoadOptions(for language: AppLanguage) -> String {
        string(
            "Unable to load subscription options. Please check your connection and try again.",
            defaultValue: "Unable to load subscription options. Please check your connection and try again.",
            language: language
        )
    }

    static func purchasePending(for language: AppLanguage) -> String {
        string(
            "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.",
            defaultValue: "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.",
            language: language
        )
    }

    static func purchaseFailed(for language: AppLanguage) -> String {
        string(
            "Purchase failed. Please try again.",
            defaultValue: "Purchase failed. Please try again.",
            language: language
        )
    }

    static func restoreFailed(for language: AppLanguage) -> String {
        string(
            "Could not restore purchases. Please try again.",
            defaultValue: "Could not restore purchases. Please try again.",
            language: language
        )
    }

    static func topBarTitle(for language: AppLanguage) -> String {
        string("Premium", defaultValue: "Premium", language: language)
    }

    static func closeButton(for language: AppLanguage) -> String {
        string("Close", defaultValue: "Close", language: language)
    }

    static func localTestMode(for language: AppLanguage) -> String {
        string("Local Test Mode", defaultValue: "Local Test Mode", language: language)
    }

    static func featureHeader(for language: AppLanguage) -> String {
        string("Feature", defaultValue: "Feature", language: language)
    }

    static func freeHeader(for language: AppLanguage) -> String {
        string("Free", defaultValue: "Free", language: language)
    }

    static func premiumHeader(for language: AppLanguage) -> String {
        string("Premium", defaultValue: "Premium", language: language)
    }

    static func restorePurchases(for language: AppLanguage) -> String {
        string("Restore Purchases", defaultValue: "Restore Purchases", language: language)
    }

    static func privacyPolicy(for language: AppLanguage) -> String {
        string("Privacy Policy", defaultValue: "Privacy Policy", language: language)
    }

    static func termsOfService(for language: AppLanguage) -> String {
        string("Terms of Service", defaultValue: "Terms of Service", language: language)
    }

    static func subscriptionsUnavailable(for language: AppLanguage) -> String {
        string("Subscriptions Unavailable", defaultValue: "Subscriptions Unavailable", language: language)
    }

    static func tryAgain(for language: AppLanguage) -> String {
        string("Try Again", defaultValue: "Try Again", language: language)
    }

    static func heroTitle(for language: AppLanguage) -> String {
        string("Unlock Premium", defaultValue: "Unlock Premium", language: language)
    }

    static func heroSubtitle(for language: AppLanguage) -> String {
        string(
            "Get the full CycleBalance experience",
            defaultValue: "Get the full CycleBalance experience",
            language: language
        )
    }

    static func features(for language: AppLanguage) -> [PaywallFeature] {
        [
            .init(
                id: "basic_cycle_tracking",
                title: string("Basic cycle tracking", defaultValue: "Basic cycle tracking", language: language),
                freeIncluded: true,
                premiumIncluded: true
            ),
            .init(
                id: "symptom_logging",
                title: string("Symptom logging", defaultValue: "Symptom logging", language: language),
                freeIncluded: true,
                premiumIncluded: true
            ),
            .init(
                id: "calendar_view",
                title: string("Calendar view", defaultValue: "Calendar view", language: language),
                freeIncluded: true,
                premiumIncluded: true
            ),
            .init(
                id: "apple_health_sync",
                title: string("Apple Health sync", defaultValue: "Apple Health sync", language: language),
                freeIncluded: true,
                premiumIncluded: true
            ),
            .init(
                id: "advanced_insights",
                title: string("Advanced insights", defaultValue: "Advanced insights", language: language),
                freeIncluded: false,
                premiumIncluded: true
            ),
            .init(
                id: "unlimited_pdf_reports",
                title: string("Unlimited PDF reports", defaultValue: "Unlimited PDF reports", language: language),
                freeIncluded: false,
                premiumIncluded: true
            ),
            .init(
                id: "meal_glucose_logging",
                title: string("Meal & glucose logging", defaultValue: "Meal & glucose logging", language: language),
                freeIncluded: false,
                premiumIncluded: true
            ),
            .init(
                id: "supplement_tracking",
                title: string("Supplement tracking", defaultValue: "Supplement tracking", language: language),
                freeIncluded: false,
                premiumIncluded: true
            ),
            .init(
                id: "photo_journal",
                title: string("Photo journal", defaultValue: "Photo journal", language: language),
                freeIncluded: false,
                premiumIncluded: true
            ),
            .init(
                id: "full_cycle_history",
                title: string("Full cycle history", defaultValue: "Full cycle history", language: language),
                freeIncluded: false,
                premiumIncluded: true
            ),
        ]
    }

    private static func string(_ key: String, defaultValue: String, language: AppLanguage) -> String {
        L10n.string(key, defaultValue: defaultValue, language: language)
    }
}

private struct PaywallTopBar: View {
    let language: AppLanguage
    let closeAction: () -> Void

    var body: some View {
        ZStack {
            Text(PaywallCopy.topBarTitle(for: language))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(.primary)

            HStack(spacing: AppTheme.spacing12) {
                Button(action: closeAction) {
                    Text(PaywallCopy.closeButton(for: language))
                        .appFont(.subheadline, weight: .medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("paywall.close")

                Spacer()
            }
        }
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.top, AppTheme.spacing12)
        .padding(.bottom, AppTheme.spacing12)
    }
}

private struct PaywallLocalModeBadge: View {
    let language: AppLanguage

    var body: some View {
        HStack {
            Spacer()

            Label(PaywallCopy.localTestMode(for: language), systemImage: "hammer.fill")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.coralAccent)
                .padding(.horizontal, AppTheme.spacing12)
                .padding(.vertical, AppTheme.spacing8)
                .background(
                    Capsule()
                        .fill(AppTheme.coralAccent.opacity(0.14))
                )

            Spacer()
        }
        .accessibilityIdentifier("paywall.local_test_mode")
    }
}

private struct PaywallFeatureComparisonCard: View {
    let language: AppLanguage
    let features: [PaywallFeature]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(PaywallCopy.featureHeader(for: language))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(PaywallCopy.freeHeader(for: language))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44)

                Text(PaywallCopy.premiumHeader(for: language))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.coralAccent)
                    .frame(width: 64)
            }
            .padding(.horizontal, AppTheme.spacing12)
            .padding(.top, AppTheme.spacing12)
            .padding(.bottom, AppTheme.spacing8)

            ForEach(features) { feature in
                PaywallFeatureRow(feature: feature)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                .fill(Color(.systemBackground))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.feature_table")
    }
}

private struct PaywallFeatureRow: View {
    let feature: PaywallFeature

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.leading, AppTheme.spacing12)

            HStack {
                Text(feature.title)
                    .appFont(.body)
                    .foregroundStyle(.primary)

                Spacer()

                PaywallInclusionIcon(
                    isIncluded: feature.freeIncluded,
                    accentColor: AppTheme.sage
                )
                .frame(width: 44)

                PaywallInclusionIcon(
                    isIncluded: feature.premiumIncluded,
                    accentColor: AppTheme.coralAccent
                )
                .frame(width: 64)
            }
            .padding(.horizontal, AppTheme.spacing12)
            .padding(.vertical, 13)
        }
        .accessibilityIdentifier("paywall.feature.\(feature.id)")
    }
}

private struct PaywallInclusionIcon: View {
    let isIncluded: Bool
    let accentColor: Color

    var body: some View {
        Image(systemName: isIncluded ? "checkmark.circle.fill" : "minus.circle")
            .appFont(.body, weight: .semibold)
            .foregroundStyle(isIncluded ? accentColor : .secondary.opacity(0.55))
            .accessibilityHidden(true)
    }
}

private struct PaywallPlanCard: View {
    let language: AppLanguage
    let product: BillingProduct
    let savingsText: String?
    let isRecommended: Bool
    let isProcessing: Bool
    let isDisabled: Bool
    let purchaseAction: () -> Void

    var body: some View {
        Button(action: purchaseAction) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                HStack(alignment: .center, spacing: AppTheme.spacing8) {
                    Text(product.paywallDisplayName(language: language))
                        .appFont(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: AppTheme.spacing8)

                    if let savingsText {
                        Text(savingsText)
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppTheme.spacing12)
                            .padding(.vertical, AppTheme.spacing8)
                            .background(
                                Capsule()
                                    .fill(AppTheme.coralAccent)
                            )
                    }
                }

                Text(product.displayPriceWithPeriod(language: language))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                    .stroke(
                        isRecommended ? AppTheme.coralAccent : Color.clear,
                        lineWidth: isRecommended ? 1.5 : 0
                    )
            )
            .overlay(alignment: .trailing) {
                if isProcessing {
                    ProgressView()
                        .padding(.trailing, AppTheme.spacing16)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier("paywall.plan.\(product.id)")
    }
}

private struct PaywallFooterLinks: View {
    let language: AppLanguage
    let isRestoring: Bool
    let isDisabled: Bool
    let restoreAction: () -> Void
    let privacyPolicyURL: URL
    let termsOfServiceURL: URL

    var body: some View {
        HStack(spacing: AppTheme.spacing8) {
            Button(action: restoreAction) {
                if isRestoring {
                    ProgressView()
                } else {
                    Text(PaywallCopy.restorePurchases(for: language))
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("paywall.restore")

            Text("\u{00B7}")
                .foregroundStyle(.secondary.opacity(0.5))

            Link(destination: privacyPolicyURL) {
                Text(PaywallCopy.privacyPolicy(for: language))
            }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("paywall.privacy_policy")

            Text("\u{00B7}")
                .foregroundStyle(.secondary.opacity(0.5))

            Link(destination: termsOfServiceURL) {
                Text(PaywallCopy.termsOfService(for: language))
            }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("paywall.terms_of_service")
        }
        .appFont(.caption, weight: .medium)
        .foregroundStyle(.secondary)
        .tint(.secondary)
        .frame(maxWidth: .infinity)
    }
}

private struct PaywallUnavailableState: View {
    let language: AppLanguage
    let message: String
    let retryAction: () -> Void

    var body: some View {
        AppEmptyStateView(
            title: PaywallCopy.subscriptionsUnavailable(for: language),
            message: message,
            systemImage: "exclamationmark.triangle"
        ) {
            Button(PaywallCopy.tryAgain(for: language), action: retryAction)
                .appFont(.subheadline, weight: .semibold)
        }
        .accessibilityIdentifier("paywall.unavailable")
    }
}

private struct PaywallFeature: Identifiable {
    let id: String
    let title: String
    let freeIncluded: Bool
    let premiumIncluded: Bool
}

private struct FourPointedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.35
        let pointCount = 4

        var path = Path()
        for i in 0..<(pointCount * 2) {
            let angle = (Double(i) * .pi / Double(pointCount)) - .pi / 2
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct PaywallSparkleHeader: View {
    let language: AppLanguage
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            ZStack {
                FourPointedStar()
                    .frame(width: 28, height: 28)

                FourPointedStar()
                    .frame(width: 14, height: 14)
                    .offset(x: 16, y: -18)

                FourPointedStar()
                    .frame(width: 10, height: 10)
                    .offset(x: -14, y: -12)
            }
            .foregroundStyle(AppTheme.coralAccent)
            .opacity(isPulsing ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
            .frame(width: 50, height: 50)
            .padding(.top, AppTheme.spacing8)

            Text(PaywallCopy.heroTitle(for: language))
                .appFont(.title2, weight: .bold)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("paywall.hero.title")

            Text(PaywallCopy.heroSubtitle(for: language))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("paywall.hero.subtitle")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.hero")
    }
}

#Preview {
    PaywallView()
}
