import SwiftUI

/// Toast banner with undo action and countdown timer.
struct UndoToast: View {
    let message: String
    let duration: TimeInterval
    let onUndo: () -> Void
    let onExpire: () -> Void

    @State private var remaining: TimeInterval
    @State private var timerTask: Task<Void, Never>?

    init(message: String, duration: TimeInterval = 6, onUndo: @escaping () -> Void, onExpire: @escaping () -> Void) {
        self.message = message
        self.duration = duration
        self.onUndo = onUndo
        self.onExpire = onExpire
        self._remaining = State(initialValue: duration)
    }

    var body: some View {
        HStack(spacing: AppTheme.spacing8) {
            Text(message)
                .appFont(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            Text("\(Int(remaining.rounded(.up)))s")
                .appFont(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Button {
                timerTask?.cancel()
                onUndo()
            } label: {
                Text("Undo")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.coralAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.vertical, AppTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.secondary.opacity(AppTheme.opacityLight), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sensoryFeedback(.warning, trigger: remaining < 1)
        .onAppear { startTimer() }
        .onDisappear { timerTask?.cancel() }
    }

    private func startTimer() {
        timerTask?.cancel()
        remaining = duration
        timerTask = Task {
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.2)) {
                    remaining -= 1
                }
            }
            guard !Task.isCancelled else { return }
            onExpire()
        }
    }
}

#Preview {
    VStack {
        Spacer()
        UndoToast(message: "Meal entry deleted", onUndo: {}, onExpire: {})
            .padding()
    }
}
