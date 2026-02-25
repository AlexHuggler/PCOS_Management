import SwiftUI

/// Contextual tooltip with message text and a "Got it" dismiss button.
/// Appears with a scale+opacity transition matching the app's overlay patterns.
struct TooltipOverlay: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Got it") {
                onDismiss()
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(AppTheme.accentColor)
        }
        .padding(AppTheme.spacing16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        TooltipOverlay(message: "Check the Calendar to see your cycle at a glance") {}
            .padding()
    }
}
