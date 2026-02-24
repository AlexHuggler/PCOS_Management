import SwiftUI

/// Brief checkmark overlay shown after a successful save action.
struct SavedFeedbackOverlay: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: appeared)

            Text("Saved")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
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
