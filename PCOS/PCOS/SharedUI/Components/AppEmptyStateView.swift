import SwiftUI

struct AppEmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let animateSymbol: Bool
    @ViewBuilder let actions: () -> Actions

    init(
        title: String,
        message: String,
        systemImage: String,
        animateSymbol: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.animateSymbol = animateSymbol
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing16) {
            Group {
                if animateSymbol {
                    Image(systemName: systemImage)
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: systemImage)
                }
            }
            .appFont(.largeTitle, weight: .semibold)
            .foregroundStyle(.secondary)

            VStack(spacing: AppTheme.spacing8) {
                Text(title)
                    .appFont(.title3, weight: .bold)
                    .multilineTextAlignment(.center)

                Text(message)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.spacing24)
        .padding(.vertical, AppTheme.spacing32)
        .accessibilityElement(children: .contain)
    }
}

extension AppEmptyStateView where Actions == EmptyView {
    init(
        title: String,
        message: String,
        systemImage: String,
        animateSymbol: Bool = false
    ) {
        self.init(
            title: title,
            message: message,
            systemImage: systemImage,
            animateSymbol: animateSymbol
        ) {
            EmptyView()
        }
    }
}
