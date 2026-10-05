import Foundation

/// A loaded exit offer and the regular plan it is compared against.
struct ExitOfferCandidate: Equatable, Sendable {
    let offer: BillingProduct
    let regular: BillingProduct
    let discountPercent: Int
}

/// Rules for the one-time discount shown after the paywall is closed without a purchase.
///
/// Honesty rules (App Store 3.1.2 / 5.6): the discount is computed from live StoreKit prices of two
/// plans with the same billing period, rounded down so it is never overstated; the offer is shown
/// at most once per install; there is no countdown or invented deadline.
enum ExitOfferPolicy {
    static let shownDefaultsKey = "paywall.exitOffer.hasBeenShown"
    static let minimumDiscountPercent = 10
    static let maximumDiscountPercent = 90

    /// Whole-percent saving of `offer` versus `regular`, or nil when the comparison is not honest
    /// (different billing periods, missing prices) or the saving is outside the sane range.
    static func discountPercent(regular: BillingProduct, offer: BillingProduct) -> Int? {
        guard
            let regularPeriod = regular.subscriptionPeriod,
            regularPeriod == offer.subscriptionPeriod,
            regular.price > 0,
            offer.price > 0,
            offer.price < regular.price
        else {
            return nil
        }

        let saving = NSDecimalNumber(decimal: (regular.price - offer.price) / regular.price).doubleValue
        let percent = Int((saving * 100).rounded(.down))
        guard (minimumDiscountPercent...maximumDiscountPercent).contains(percent) else { return nil }
        return percent
    }

    static func makeCandidate(regular: BillingProduct?, offer: BillingProduct?) -> ExitOfferCandidate? {
        guard let regular, let offer, let percent = discountPercent(regular: regular, offer: offer) else {
            return nil
        }
        return ExitOfferCandidate(offer: offer, regular: regular, discountPercent: percent)
    }

    static func shouldPresent(
        candidate: ExitOfferCandidate?,
        hasBeenShown: Bool,
        hasPremiumAccess: Bool,
        showsSubscriptionUI: Bool,
        purchaseWasPending: Bool
    ) -> Bool {
        candidate != nil
            && !hasBeenShown
            && !hasPremiumAccess
            && showsSubscriptionUI
            && !purchaseWasPending
    }
}
