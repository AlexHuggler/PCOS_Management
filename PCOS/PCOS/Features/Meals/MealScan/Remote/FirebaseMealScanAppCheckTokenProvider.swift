import FirebaseAppCheck

@MainActor
final class FirebaseMealScanAppCheckTokenProvider: MealScanLimitedUseAppCheckTokenProviding {
    func limitedUseToken() async throws -> String {
        try await AppCheck.appCheck().limitedUseToken().token
    }
}
