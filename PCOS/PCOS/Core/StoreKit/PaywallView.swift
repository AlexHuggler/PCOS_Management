import Foundation
import os
import SwiftUI

// MARK: - Paywall (A10–A12, B1)

/// Contextual Premium paywall. Yearly is listed first and preselected; tapping a plan only selects
/// it and nothing is bought until "Continue". Renewal terms sit next to the button, and Restore,
/// Terms of Use and Privacy Policy are always visible. After a purchase the sheet shows
/// "Welcome to Premium" and then continues the action the user started.
struct PaywallView: View {
    private enum Stage {
        case plans
        case welcome
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var billingProducts: [BillingProduct] = []
    @State private var selectedProductID: String?
    @State private var isLoadingProducts = false
    @State private var activePurchaseProductID: String?
    @State private var isRestoringPurchases = false
    @State private var loadErrorMessage: String?
    @State private var notice: PaywallNotice?
    /// Set when a purchase is waiting for approval (Ask to Buy), so an approval that arrives while
    /// the paywall is open still lands on "Welcome to Premium" and the started action.
    @State private var pendingProductID: String?
    @State private var stage: Stage = .plans
    @State private var showComparison = false
    @State private var appearedAt = Date()
    @State private var didTrackView = false
    @State private var attemptedPurchase = false
    @State private var completedPurchase = false

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

    /// Yearly first, then Monthly, then anything else the offering returns.
    private var orderedProducts: [BillingProduct] {
        func rank(_ product: BillingProduct) -> Int {
            switch product.id {
            case SubscriptionManager.yearlyProductID: 0
            case SubscriptionManager.monthlyProductID: 1
            default: 2
            }
        }
        return billingProducts.sorted { rank($0) < rank($1) }
    }

    private var selectedProduct: BillingProduct? {
        billingProducts.first(where: { $0.id == selectedProductID }) ?? orderedProducts.first
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

        // Rounded down so the saving is never overstated.
        let savingsPercent = Int((((monthlyPrice - yearlyPrice) / monthlyPrice) * 100).rounded(.down))
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

                switch stage {
                case .plans:
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .accessibilityIdentifier("screen.paywall")
                case .welcome:
                    PremiumWelcomeView(
                        language: paywallLanguage,
                        reason: appState.premiumPaywallReason,
                        deferredLogger: appState.deferredLogger,
                        continueAction: closePaywall
                    )
                    .transition(.opacity)
                }
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

            trackViewIfNeeded()
            await loadPaywallIfNeeded()
        }
        .onDisappear(perform: trackDismissalIfNeeded)
        .onChange(of: subscriptionManager.isPremium) { _, isPremium in
            handleEntitlementChange(isPremium: isPremium)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert(alertTitle, isPresented: isAlertPresented) {
            Button(PaywallCopy.okButton(for: paywallLanguage), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if billingProducts.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    PaywallCloseButton(language: paywallLanguage, action: closePaywall)
                }
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.top, AppTheme.spacing12)

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
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    HStack {
                        Spacer()
                        PaywallCloseButton(language: paywallLanguage, action: closePaywall)
                    }

                    PaywallHeader(language: paywallLanguage, reason: appState.premiumPaywallReason)

                    if isLocalStoreKit {
                        PaywallLocalModeBadge(language: paywallLanguage)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                        ForEach(PaywallCopy.benefits(for: paywallLanguage)) { benefit in
                            PaywallBenefitRow(benefit: benefit)
                        }
                    }

                    DisclosureGroup(isExpanded: $showComparison) {
                        PaywallFeatureComparisonCard(language: paywallLanguage, features: paywallFeatures)
                            .padding(.top, AppTheme.spacing8)
                    } label: {
                        Text(PaywallCopy.comparePlans(for: paywallLanguage))
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.accentColor)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .tint(AppTheme.accentColor)
                    .accessibilityIdentifier("paywall.compare_plans")

                    VStack(spacing: AppTheme.spacing12) {
                        ForEach(orderedProducts) { product in
                            PaywallPlanCard(
                                language: paywallLanguage,
                                product: product,
                                badgeText: product.id == SubscriptionManager.yearlyProductID
                                    ? yearlySavingsText.map { PaywallCopy.bestValueBadge(savings: $0, language: paywallLanguage) }
                                    : nil,
                                isSelected: product.id == selectedProduct?.id,
                                isDisabled: isBusy,
                                selectAction: { select(product) }
                            )
                        }
                    }

                    PaywallReassurance(language: paywallLanguage)
                        .padding(.top, AppTheme.spacing8)
                }
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.top, AppTheme.spacing12)
                .padding(.bottom, AppTheme.spacing16)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                purchaseFooter
            }
        }
    }

    private var purchaseFooter: some View {
        VStack(spacing: AppTheme.spacing8) {
            if let product = selectedProduct {
                PaywallPrimaryButton(
                    title: PaywallCopy.continueButton(price: product.displayPricePerPeriod(language: paywallLanguage), language: paywallLanguage),
                    isProcessing: activePurchaseProductID == product.id,
                    isDisabled: isBusy,
                    action: purchaseSelectedPlan
                )
                .accessibilityIdentifier("paywall.continue")

                PaywallRenewalTerms(
                    text: PaywallCopy.renewalTerms(price: product.displayPricePerPeriod(language: paywallLanguage), language: paywallLanguage)
                )
            }

            PaywallFooterLinks(
                language: paywallLanguage,
                isRestoring: isRestoringPurchases,
                isDisabled: isBusy,
                restoreAction: restorePurchases,
                privacyPolicyURL: AppLinks.privacyPolicy,
                termsOfServiceURL: AppLinks.termsOfService
            )
        }
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.top, AppTheme.spacing12)
        .padding(.bottom, AppTheme.spacing8)
        .background(AppTheme.groupedBackground)
    }

    // MARK: Alerts

    // Every purchase alert is plain language: what happened, that her logs are safe, and what to
    // do next. Technical details go to the log, never into an alert, and no alert is titled Error.
    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { notice != nil },
            set: { isPresented in
                if !isPresented {
                    notice = nil
                }
            }
        )
    }

    private var alertTitle: String {
        notice?.title(for: paywallLanguage) ?? ""
    }

    private var alertMessage: String {
        notice?.message(for: paywallLanguage) ?? ""
    }

    // MARK: Actions

    private func closePaywall() {
        dismiss()
    }

    private func select(_ product: BillingProduct) {
        guard selectedProductID != product.id else { return }
        selectedProductID = product.id
        AppAnalytics.shared.track(.planSelected(plan: product.analyticsPlanName))
    }

    private func retryLoadingProducts() {
        Task {
            await loadPaywallIfNeeded(forceReload: true)
        }
    }

    private func purchaseSelectedPlan() {
        guard let product = selectedProduct else { return }
        purchase(product)
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

    private func trackViewIfNeeded() {
        guard !didTrackView else { return }
        didTrackView = true
        appearedAt = Date()
        AppAnalytics.shared.track(.paywallViewed(source: appState.premiumPaywallSource))
    }

    private func trackDismissalIfNeeded() {
        guard didTrackView, !completedPurchase else { return }
        AppAnalytics.shared.track(.paywallDismissed(
            source: appState.premiumPaywallSource,
            secondsVisible: max(0, Int(Date().timeIntervalSince(appearedAt))),
            attemptedPurchase: attemptedPurchase
        ))
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

        // Subscribers never see the paywall (B2); closing resumes any started action.
        if subscriptionManager.isPremium {
            completedPurchase = true
            closePaywall()
            return
        }

        do {
            billingProducts = try await subscriptionManager.loadProducts()
            if selectedProductID == nil {
                selectedProductID = yearlyProduct?.id ?? orderedProducts.first?.id
            }
        } catch {
            Logger.storeKit.error("Paywall products failed to load: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            // Debug builds keep the configuration detail for QA; customers see the plain message.
            loadErrorMessage = Self.userFacingMessage(
                for: error,
                fallback: PaywallCopy.unableToLoadOptions(for: paywallLanguage)
            )
            #else
            loadErrorMessage = PaywallCopy.unableToLoadOptions(for: paywallLanguage)
            #endif
        }
    }

    /// Ask to Buy approval (or a purchase on another device) while the paywall is open.
    private func handleEntitlementChange(isPremium: Bool) {
        guard isPremium, stage == .plans, appState.showsSubscriptionUI else { return }
        appState.isPremium = true
        completedPurchase = true
        if let productID = pendingProductID {
            AppAnalytics.shared.track(.purchaseCompleted(productID: productID, offer: .none))
            pendingProductID = nil
        }
        notice = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            stage = .welcome
        }
    }

    @discardableResult
    private func refreshPremiumStateAndDismissIfNeeded() async -> Bool {
        await subscriptionManager.checkSubscriptionStatus()
        appState.isPremium = subscriptionManager.isPremium

        if subscriptionManager.isPremium {
            completedPurchase = true
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                stage = .welcome
            }
            return true
        }
        if let statusMessage = subscriptionManager.statusMessage {
            Logger.storeKit.error("Premium is not active after refresh: \(statusMessage, privacy: .public)")
        }
        return false
    }

    private func purchaseProduct(_ product: BillingProduct) async {
        activePurchaseProductID = product.id
        attemptedPurchase = true
        AppAnalytics.shared.track(.purchaseStarted(productID: product.id))
        defer {
            activePurchaseProductID = nil
        }

        do {
            let outcome = try await subscriptionManager.purchase(productID: product.id)
            switch outcome {
            case .success:
                AppAnalytics.shared.track(.purchaseCompleted(productID: product.id, offer: .none))
                let isActive = await refreshPremiumStateAndDismissIfNeeded()
                if !isActive {
                    notice = .activationDelayed
                }
            case .pending:
                AppAnalytics.shared.track(.purchasePending(productID: product.id))
                pendingProductID = product.id
                notice = .pending
            case .cancelled:
                AppAnalytics.shared.track(.purchaseCancelled(productID: product.id))
            }
        } catch {
            AppAnalytics.shared.track(.purchaseFailed(code: Self.analyticsCode(for: error)))
            Logger.storeKit.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            notice = .purchaseFailed
        }
    }

    private func restoreExistingPurchases() async {
        isRestoringPurchases = true
        defer {
            isRestoringPurchases = false
        }

        do {
            try await subscriptionManager.restorePurchases()
            if await refreshPremiumStateAndDismissIfNeeded() {
                AppAnalytics.shared.track(.restoreCompleted(result: .restored))
            } else {
                AppAnalytics.shared.track(.restoreCompleted(result: .nothingToRestore))
                notice = .nothingToRestore
            }
        } catch {
            AppAnalytics.shared.track(.restoreCompleted(result: .failed))
            Logger.storeKit.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            notice = .restoreFailed
        }
    }

    static func userFacingMessage(for error: Error, fallback: String) -> String {
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

    /// Error domain and code only (no message text) for `purchase_failed`.
    static func analyticsCode(for error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}

// MARK: - Welcome to Premium (A12)

private struct PremiumWelcomeView: View {
    let language: AppLanguage
    let reason: PremiumPaywallReason
    let deferredLogger: LoggerShortcut?
    let continueAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentColor)
                    Image(systemName: "checkmark")
                        .appFont(.largeTitle, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                }
                .frame(width: 88, height: 88)
                .padding(.top, AppTheme.spacing32)
                .accessibilityHidden(true)

                Text(PaywallCopy.welcomeTitle(for: language))
                    .appHeadingFont(.title, weight: .bold)
                    .foregroundStyle(AppTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(PaywallCopy.welcomeSubtitle(for: language, deferredLogger: deferredLogger))
                    .appFont(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                    ForEach(PaywallCopy.welcomeHighlights(for: language)) { highlight in
                        HStack(spacing: AppTheme.spacing12) {
                            Image(systemName: highlight.systemImage)
                                .appFont(.subheadline, weight: .semibold)
                                .foregroundStyle(AppTheme.accentColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                                        .fill(AppTheme.accentColor.opacity(AppTheme.opacityLight))
                                )
                                .accessibilityHidden(true)
                            Text(highlight.title)
                                .appFont(.body)
                                .foregroundStyle(AppTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(AppTheme.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                        .fill(AppTheme.cardBackground)
                )
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: AppTheme.spacing12) {
                PaywallPrimaryButton(
                    title: PaywallCopy.welcomeButton(for: language, deferredLogger: deferredLogger),
                    isProcessing: false,
                    isDisabled: false,
                    action: continueAction
                )
                .accessibilityIdentifier("paywall.welcome.continue")

                Text(PaywallCopy.manageAnytime(for: language))
                    .appFont(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.top, AppTheme.spacing12)
            .padding(.bottom, AppTheme.spacing8)
            .background(AppTheme.groupedBackground)
        }
        .accessibilityIdentifier("screen.premium_welcome")
    }
}

// MARK: - Copy

private enum PaywallNotice: Equatable {
    case pending
    case nothingToRestore
    case activationDelayed
    case purchaseFailed
    case restoreFailed

    func title(for language: AppLanguage) -> String {
        switch self {
        case .pending:
            L10n.string("Waiting for approval", defaultValue: "Waiting for approval", language: language)
        case .nothingToRestore:
            L10n.string("Nothing to restore", defaultValue: "Nothing to restore", language: language)
        case .activationDelayed:
            L10n.string("Almost there", defaultValue: "Almost there", language: language)
        case .purchaseFailed:
            L10n.string("Purchase didn't go through", defaultValue: "Purchase didn't go through", language: language)
        case .restoreFailed:
            L10n.string("Restore didn't go through", defaultValue: "Restore didn't go through", language: language)
        }
    }

    func message(for language: AppLanguage) -> String {
        switch self {
        case .pending:
            L10n.string(
                "Premium turns on by itself once it's approved.",
                defaultValue: "Premium turns on by itself once it's approved.",
                language: language
            )
        case .nothingToRestore:
            L10n.string(
                "No Premium subscription found for this Apple Account.",
                defaultValue: "No Premium subscription found for this Apple Account.",
                language: language
            )
        case .purchaseFailed:
            L10n.string(
                "You can try again now or later — your logs are safe.",
                defaultValue: "You can try again now or later — your logs are safe.",
                language: language
            )
        case .restoreFailed:
            L10n.string(
                "Check your connection and try again — your logs are safe.",
                defaultValue: "Check your connection and try again — your logs are safe.",
                language: language
            )
        case .activationDelayed:
            L10n.string(
                "Your purchase went through, but Premium hasn't switched on yet. Try Restore purchases in a moment.",
                defaultValue: "Your purchase went through, but Premium hasn't switched on yet. Try Restore purchases in a moment.",
                language: language
            )
        }
    }
}

private struct PaywallBenefit: Identifiable {
    let id: String
    let systemImage: String
    let title: String
}

private enum PaywallCopy {
    static func okButton(for language: AppLanguage) -> String {
        string("OK", defaultValue: "OK", language: language)
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
        string("Restore purchases", defaultValue: "Restore purchases", language: language)
    }

    static func privacyPolicy(for language: AppLanguage) -> String {
        string("Privacy Policy", defaultValue: "Privacy Policy", language: language)
    }

    static func termsOfUse(for language: AppLanguage) -> String {
        string("Terms of Use", defaultValue: "Terms of Use", language: language)
    }

    static func subscriptionsUnavailable(for language: AppLanguage) -> String {
        string("Subscriptions Unavailable", defaultValue: "Subscriptions Unavailable", language: language)
    }

    static func tryAgain(for language: AppLanguage) -> String {
        string("Try Again", defaultValue: "Try Again", language: language)
    }

    static func comparePlans(for language: AppLanguage) -> String {
        string("Compare plans", defaultValue: "Compare plans", language: language)
    }

    static func heroTitle(for language: AppLanguage, reason: PremiumPaywallReason) -> String {
        switch reason {
        case .mealScan:
            string("Unlock photo meal estimates", defaultValue: "Unlock photo meal estimates", language: language)
        case .meal:
            string("See how meals relate to how you feel", defaultValue: "See how meals relate to how you feel", language: language)
        case .glucose:
            string("Keep glucose in context", defaultValue: "Keep glucose in context", language: language)
        case .supplements:
            string("See how supplements fit your routine", defaultValue: "See how supplements fit your routine", language: language)
        case .photo:
            string("Keep a private skin & hair journal", defaultValue: "Keep a private skin & hair journal", language: language)
        case .insights:
            string("Go deeper than the basics", defaultValue: "Go deeper than the basics", language: language)
        case .report:
            string("Bring every visit a clear summary", defaultValue: "Bring every visit a clear summary", language: language)
        case .general, .settings:
            string("Get more from every check-in", defaultValue: "Get more from every check-in", language: language)
        }
    }

    static func heroSubtitle(for language: AppLanguage, reason: PremiumPaywallReason) -> String {
        switch reason {
        case .mealScan:
            string(
                "Turn meal photos into editable calorie, macro, and cycle-aware nutrition drafts.",
                defaultValue: "Turn meal photos into editable calorie, macro, and cycle-aware nutrition drafts.",
                language: language
            )
        default:
            string(
                "Premium adds the tools many people with PCOS use alongside their care. Your data stays on your iPhone.",
                defaultValue: "Premium adds the tools many people with PCOS use alongside their care. Your data stays on your iPhone.",
                language: language
            )
        }
    }

    static func benefits(for language: AppLanguage) -> [PaywallBenefit] {
        [
            PaywallBenefit(
                id: "logs",
                systemImage: "fork.knife",
                title: string("Meal, glucose & supplement logs, linked to symptoms", defaultValue: "Meal, glucose & supplement logs, linked to symptoms", language: language)
            ),
            PaywallBenefit(
                id: "insights",
                systemImage: "chart.bar.xaxis",
                title: string("Deeper insights: sleep, activity, meals", defaultValue: "Deeper insights: sleep, activity, meals", language: language)
            ),
            PaywallBenefit(
                id: "reports",
                systemImage: "doc.text",
                title: string("Unlimited appointment-ready PDF reports", defaultValue: "Unlimited appointment-ready PDF reports", language: language)
            ),
            PaywallBenefit(
                id: "photos",
                systemImage: "photo",
                title: string("Private photo journal for skin & hair", defaultValue: "Private photo journal for skin & hair", language: language)
            ),
        ]
    }

    static func bestValueBadge(savings: String, language: AppLanguage) -> String {
        L10n.format("Best value · %@", defaultValue: "Best value · %@", language: language, savings)
    }

    static func perMonthBilledYearly(price: String, language: AppLanguage) -> String {
        L10n.format("%@/month, billed yearly", defaultValue: "%@/month, billed yearly", language: language, price)
    }

    static func continueButton(price: String, language: AppLanguage) -> String {
        L10n.format("Continue — %@", defaultValue: "Continue — %@", language: language, price)
    }

    static func renewalTerms(price: String, language: AppLanguage) -> String {
        L10n.format(
            "Renews at %@ until you cancel. Cancel anytime in Settings › Apple Account › Subscriptions, at least 24 hours before renewal.",
            defaultValue: "Renews at %@ until you cancel. Cancel anytime in Settings › Apple Account › Subscriptions, at least 24 hours before renewal.",
            language: language,
            price
        )
    }

    static func reassurance(for language: AppLanguage) -> String {
        string(
            "No ads. No selling your data. Not a medical device.",
            defaultValue: "No ads. No selling your data. Not a medical device.",
            language: language
        )
    }

    static func welcomeTitle(for language: AppLanguage) -> String {
        string("Welcome to Premium", defaultValue: "Welcome to Premium", language: language)
    }

    static func welcomeSubtitle(for language: AppLanguage, deferredLogger: LoggerShortcut?) -> String {
        switch deferredLogger {
        case .meal?, .bloodSugar?, .supplements?:
            string("Meal, glucose and supplement logs are on.", defaultValue: "Meal, glucose and supplement logs are on.", language: language)
        default:
            string("Everything in Premium is ready for you.", defaultValue: "Everything in Premium is ready for you.", language: language)
        }
    }

    static func welcomeHighlights(for language: AppLanguage) -> [PaywallBenefit] {
        [
            PaywallBenefit(
                id: "welcome.logs",
                systemImage: "fork.knife",
                title: string("Meal & glucose logging", defaultValue: "Meal & glucose logging", language: language)
            ),
            PaywallBenefit(
                id: "welcome.insights",
                systemImage: "chart.bar.xaxis",
                title: string("Deeper insights", defaultValue: "Deeper insights", language: language)
            ),
            PaywallBenefit(
                id: "welcome.reports",
                systemImage: "doc.text",
                title: string("Unlimited PDF reports", defaultValue: "Unlimited PDF reports", language: language)
            ),
        ]
    }

    static func welcomeButton(for language: AppLanguage, deferredLogger: LoggerShortcut?) -> String {
        switch deferredLogger {
        case .meal?:
            string("Log your first meal", defaultValue: "Log your first meal", language: language)
        case .bloodSugar?:
            string("Log your first glucose reading", defaultValue: "Log your first glucose reading", language: language)
        case .supplements?:
            string("Log your first supplement", defaultValue: "Log your first supplement", language: language)
        case .photo?:
            string("Open your photo journal", defaultValue: "Open your photo journal", language: language)
        default:
            string("Continue", defaultValue: "Continue", language: language)
        }
    }

    static func manageAnytime(for language: AppLanguage) -> String {
        string(
            "Manage your subscription anytime in Settings.",
            defaultValue: "Manage your subscription anytime in Settings.",
            language: language
        )
    }

    static func selected(for language: AppLanguage) -> String {
        string("Selected", defaultValue: "Selected", language: language)
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
                id: "full_cycle_history",
                title: string("Full cycle history", defaultValue: "Full cycle history", language: language),
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
        ]
    }

    private static func string(_ key: String, defaultValue: String, language: AppLanguage) -> String {
        L10n.string(key, defaultValue: defaultValue, language: language)
    }
}

// MARK: - Components

private struct PaywallHeader: View {
    let language: AppLanguage
    let reason: PremiumPaywallReason

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(PaywallCopy.heroTitle(for: language, reason: reason))
                .appHeadingFont(.title, weight: .bold)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.hero.title")

            Text(PaywallCopy.heroSubtitle(for: language, reason: reason))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.hero.subtitle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.hero")
    }
}

private struct PaywallCloseButton: View {
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppTheme.cardBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PaywallCopy.closeButton(for: language))
        .accessibilityIdentifier("paywall.close")
    }
}

private struct PaywallBenefitRow: View {
    let benefit: PaywallBenefit

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: benefit.systemImage)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.coralAccent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                        .fill(AppTheme.coralAccent.opacity(AppTheme.opacityLight))
                )
                .accessibilityHidden(true)

            Text(benefit.title)
                .appFont(.body)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.benefit.\(benefit.id)")
    }
}

private struct PaywallBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .appFont(.caption, weight: .semibold)
            .foregroundStyle(AppTheme.coralAccent)
            .padding(.horizontal, AppTheme.spacing8)
            .padding(.vertical, AppTheme.spacing4)
            .background(
                Capsule()
                    .fill(AppTheme.coralAccent.opacity(AppTheme.opacityLight))
            )
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            // At accessibility sizes each row stacks and names its tiers, so the column header goes.
            if !dynamicTypeSize.isAccessibilitySize {
                header
            }

            ForEach(features) { feature in
                PaywallFeatureRow(language: language, feature: feature)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge)
                .fill(AppTheme.cardBackground)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.feature_table")
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(PaywallCopy.featureHeader(for: language))
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)

            Spacer()

            Text(PaywallCopy.freeHeader(for: language))
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 44)

            Text(PaywallCopy.premiumHeader(for: language))
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.coralAccent)
                .frame(width: 64)
        }
        .padding(.horizontal, AppTheme.spacing12)
        .padding(.top, AppTheme.spacing12)
        .padding(.bottom, AppTheme.spacing8)
    }
}

private struct PaywallFeatureRow: View {
    let language: AppLanguage
    let feature: PaywallFeature

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.leading, AppTheme.spacing12)

            if dynamicTypeSize.isAccessibilitySize {
                stackedRow
            } else {
                columnRow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combinedAccessibilityLabel)
        .accessibilityIdentifier("paywall.feature.\(feature.id)")
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(feature.title)
                .appFont(.body)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(tiersText)
                .appFont(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing12)
        .padding(.vertical, AppTheme.spacing12)
    }

    private var columnRow: some View {
        HStack {
            Text(feature.title)
                .appFont(.body)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

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

    private var tiersText: String {
        let free = PaywallCopy.freeHeader(for: language)
        let premium = PaywallCopy.premiumHeader(for: language)
        return feature.freeIncluded ? "\(free), \(premium)" : premium
    }

    private var combinedAccessibilityLabel: String {
        "\(feature.title): \(tiersText)"
    }
}

private struct PaywallInclusionIcon: View {
    let isIncluded: Bool
    let accentColor: Color

    var body: some View {
        Image(systemName: isIncluded ? "checkmark.circle.fill" : "minus.circle")
            .appFont(.body, weight: .semibold)
            .foregroundStyle(isIncluded ? accentColor : AppTheme.secondaryText.opacity(0.55))
            .accessibilityHidden(true)
    }
}

/// Radio-style plan card. Tapping selects the plan; it never starts a purchase.
private struct PaywallPlanCard: View {
    let language: AppLanguage
    let product: BillingProduct
    let badgeText: String?
    let isSelected: Bool
    let isDisabled: Bool
    let selectAction: () -> Void

    var body: some View {
        Button(action: selectAction) {
            HStack(alignment: .center, spacing: AppTheme.spacing12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(isSelected ? AppTheme.accentColor : AppTheme.secondaryText)
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.spacing8) {
                        titleColumn
                        Spacer(minLength: AppTheme.spacing8)
                        priceColumn(alignment: .trailing)
                    }
                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        titleColumn
                        priceColumn(alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(AppTheme.spacing16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                    .stroke(isSelected ? AppTheme.accentColor : AppTheme.cardBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combinedAccessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("paywall.plan.\(product.id)")
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
            Text(product.planTitle(language: language))
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)

            if let badgeText {
                PaywallBadge(text: badgeText)
            }
        }
    }

    private func priceColumn(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: AppTheme.spacing4) {
            Text(product.displayPricePerPeriod(language: language))
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)

            if product.subscriptionPeriod?.unit == .year, let monthly = product.localizedPricePerMonth {
                Text(PaywallCopy.perMonthBilledYearly(price: monthly, language: language))
                    .appFont(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var combinedAccessibilityLabel: String {
        var parts = [
            product.paywallDisplayName(language: language),
            product.displayPricePerPeriod(language: language),
        ]
        if let badgeText { parts.append(badgeText) }
        if isSelected { parts.append(PaywallCopy.selected(for: language)) }
        return parts.joined(separator: ", ")
    }
}

private struct PaywallPrimaryButton: View {
    let title: String
    let isProcessing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .appFont(.headline)
                    .multilineTextAlignment(.center)
                    .opacity(isProcessing ? 0 : 1)

                if isProcessing {
                    ProgressView()
                        .tint(AppTheme.premiumEditorCTAForeground)
                }
            }
            .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, AppTheme.spacing16)
            .background(Capsule().fill(AppTheme.accentColor))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isProcessing ? 0.6 : 1)
    }
}

private struct PaywallRenewalTerms: View {
    let text: String

    var body: some View {
        Text(text)
            .appFont(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("paywall.renewal_terms")
    }
}

private struct PaywallReassurance: View {
    let language: AppLanguage

    var body: some View {
        Label {
            Text(PaywallCopy.reassurance(for: language))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        } icon: {
            Image(systemName: "lock.fill")
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct PaywallFooterLinks: View {
    let language: AppLanguage
    let isRestoring: Bool
    let isDisabled: Bool
    let restoreAction: () -> Void
    let privacyPolicyURL: URL?
    let termsOfServiceURL: URL?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.spacing8) { links(separated: true) }
            VStack(spacing: 0) { links(separated: false) }
        }
        .appFont(.caption, weight: .medium)
        .tint(AppTheme.accentColor)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func links(separated: Bool) -> some View {
        Button(action: restoreAction) {
            if isRestoring {
                ProgressView()
                    .frame(minHeight: 44)
            } else {
                Text(PaywallCopy.restorePurchases(for: language))
                    .foregroundStyle(AppTheme.accentColor)
                    .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.restore")

        if let url = termsOfServiceURL {
            if separated {
                Text("\u{00B7}")
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityHidden(true)
            }

            Link(destination: url) {
                Text(PaywallCopy.termsOfUse(for: language))
                    .frame(minHeight: 44)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("paywall.terms_of_service")
        }

        if let url = privacyPolicyURL {
            if separated {
                Text("\u{00B7}")
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityHidden(true)
            }

            Link(destination: url) {
                Text(PaywallCopy.privacyPolicy(for: language))
                    .frame(minHeight: 44)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("paywall.privacy_policy")
        }
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
                .frame(minHeight: 44)
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

#Preview {
    PaywallView()
        .environment(AppState())
}
