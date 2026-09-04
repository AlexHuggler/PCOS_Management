import FirebaseAppCheck
import FirebaseCore

enum FirebaseMealScanAppCheckTokenProviderError: Error, Equatable {
    /// Firebase is configured only for builds that can run the Gemini scanner. Asking for a token
    /// without a configured default app would otherwise trap inside the Firebase SDK.
    case firebaseNotConfigured
}

@MainActor
final class FirebaseMealScanAppCheckTokenProvider: MealScanLimitedUseAppCheckTokenProviding {
    func limitedUseToken() async throws -> String {
        guard FirebaseApp.app() != nil else {
            throw FirebaseMealScanAppCheckTokenProviderError.firebaseNotConfigured
        }
        return try await AppCheck.appCheck().limitedUseToken().token
    }
}
