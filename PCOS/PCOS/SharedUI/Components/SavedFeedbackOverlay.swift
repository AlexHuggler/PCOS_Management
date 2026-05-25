import SwiftUI

/// Brief checkmark overlay shown after a successful save action.
struct SavedFeedbackOverlay: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppTheme.spacing12) {
            Image(systemName: "checkmark.circle.fill")
                .appFont(.largeTitle)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: appeared)

            Text("Saved")
                .appFont(.headline)
                .foregroundStyle(.white)
        }
        .padding(AppTheme.spacing32)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL)
                .fill(.ultraThinMaterial)
        )
        .transition(.scale.combined(with: .opacity))
        .onAppear { appeared = true }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        SavedFeedbackOverlay()
    }
}
