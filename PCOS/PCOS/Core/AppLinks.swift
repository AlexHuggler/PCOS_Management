import Foundation

enum AppLinks {
    static var privacyPolicy: URL? {
        URL(string: "https://cyclebalance.app/privacy")
    }

    static var termsOfService: URL? {
        URL(string: "https://cyclebalance.app/terms")
    }

    /// Apple's standard licensed application end user license agreement.
    static var appleStandardEULA: URL? {
        URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }

    static var feedbackMail: URL? {
        URL(string: "mailto:feedback@cyclebalance.app")
    }
}
