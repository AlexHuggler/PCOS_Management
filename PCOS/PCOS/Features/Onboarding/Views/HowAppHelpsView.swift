import SwiftUI

/// Feature preview screen shown after the personalized results.
/// Displays 1-2 feature previews matched to the user's quiz answers.
struct HowAppHelpsView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var currentIndex = 0

    private var previews: [FeaturePreview] {
        profile.featurePreviews
    }

    private var currentPreview: FeaturePreview {
        previews[currentIndex]
    }

    private var isLastPreview: Bool {
        currentIndex >= previews.count - 1
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            previewContent
                .id(currentIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .simultaneousGesture(boundedFeaturePreviewSwipeGesture)

            // Continue + Skip
            VStack(spacing: AppTheme.spacing12) {
                Button {
                    advancePreviewOrContinue()
                } label: {
                    Text(
                        isLastPreview
                            ? String(localized: "Continue", comment: "Primary button label on the feature preview screen.")
                            : String(localized: "Next", comment: "Button label to advance to the next feature preview.")
                    )
                    .appFont(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.accentColor)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.how_app_helps.primary")

                Button {
                    onSkip()
                } label: {
                    Text(L10n.string("Skip for now", defaultValue: "Skip for now"))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.how_app_helps.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityIdentifier("screen.onboarding.how_app_helps")
    }

    private var boundedFeaturePreviewSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 42, coordinateSpace: .local)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = abs(value.translation.height)
                guard abs(horizontalDistance) > max(72, verticalDistance * 1.6) else {
                    return
                }

                if horizontalDistance < 0 {
                    advancePreviewOnly()
                } else {
                    retreatPreview()
                }
            }
    }

    private func advancePreviewOrContinue() {
        if !isLastPreview {
            advancePreviewOnly()
        } else {
            onContinue()
        }
    }

    private func advancePreviewOnly() {
        guard !isLastPreview else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex += 1
        }
    }

    private func retreatPreview() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex -= 1
        }
    }

    // MARK: - Preview Content

    private var previewContent: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            // Feature mockup area
            VStack(spacing: AppTheme.spacing16) {
                Image(systemName: currentPreview.systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.accentColor)
                    .accessibilityHidden(true)

                // Wireframe placeholder bars
                VStack(spacing: 8) {
                    GeometryReader { geometry in
                        let availableWidth = LayoutDimensionSanitizer.frameDimension(from: geometry.size.width)
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: availableWidth * 0.7, height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: availableWidth * 0.5, height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: availableWidth * 0.6, height: 8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 40)
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusXL)
                    .fill(AppTheme.accentColor.opacity(AppTheme.opacitySubtle))
            )
            .padding(.horizontal, AppTheme.spacing24)

            // Title
            Text(currentPreview.title)
                .appHeadingFont(.title3, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            // Caption
            Text(currentPreview.caption)
                .appFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            // Personalized subtitle based on user's symptom focus areas
            if let subtitle = currentPreview.personalizedSubtitle {
                Text(subtitle)
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(AppTheme.accentColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacing24)
            }

            // Page dots (only when there are 2 previews)
            if previews.count > 1 {
                HStack(spacing: AppTheme.spacing8) {
                    ForEach(0..<previews.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? AppTheme.accentColor : Color(.tertiarySystemFill))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentIndex)
                    }
                }
            }

            Spacer()
        }
    }
}

#Preview {
    HowAppHelpsView(
        profile: OnboardingProfile(),
        onContinue: {},
        onSkip: {}
    )
}
