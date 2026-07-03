import SwiftUI
import SwiftData

struct PhotoComparisonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PhotoJournalViewModel?
    @State private var selectedType: HairPhotoType = .scalpPart

    var body: some View {
        NavigationStack {
            ZStack {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    typeSelector

                    if let vm = viewModel {
                        comparisonContent(vm: vm)
                    } else {
                        ProgressView()
                            .tint(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.accentColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Compare Photos", defaultValue: "Compare Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.photo_comparison")
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Compare photos", defaultValue: "Compare photos"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) { dismiss() }
                }
            }
            .lunarPhotoComparisonNavigationBackground()
            .onAppear {
                viewModel = PhotoJournalViewModel(modelContext: modelContext)
            }
        }
        .premiumGated()
    }

    // MARK: - Subviews

    private var typeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing8) {
                ForEach(HairPhotoType.allCases) { type in
                    CategoryChip(
                        title: type.displayName,
                        isSelected: selectedType == type
                    ) {
                        selectedType = type
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, AppTheme.spacing8)
        }
        .background(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : AppTheme.groupedBackground)
    }

    @ViewBuilder
    private func comparisonContent(vm: PhotoJournalViewModel) -> some View {
        let earliest = vm.earliestPhoto(for: selectedType)
        let latest = vm.latestPhoto(for: selectedType)

        if earliest == nil && latest == nil {
            // No photos at all for this type
            if AppTheme.usesPremiumEditorStyling {
                lunarComparisonEmptyState
            } else {
                AppEmptyStateView(
                    title: "No Photos",
                    message: "Add photos for \(selectedType.displayName) to start comparing changes over time.",
                    systemImage: "photo.on.rectangle.angled"
                )
                .frame(maxHeight: .infinity)
            }
        } else if earliest?.id == latest?.id {
            // Only one photo
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    if let photo = earliest {
                        ComparisonPhotoCard(label: "Current", photo: photo, image: vm.image(for: photo))
                    }

                    HStack(spacing: AppTheme.spacing8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Add more \(selectedType.displayName) photos to compare changes over time.")
                            .appFont(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lunarPhotoComparisonCard(cornerRadius: AppTheme.cornerRadiusMedium)
                }
                .padding()
            }
        } else {
            // Two or more photos -- show side-by-side
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    if AppTheme.usesPremiumEditorStyling {
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            Text(L10n.string("Then and now", defaultValue: "Then and now"))
                                .appFont(.title3, weight: .semibold)
                                .foregroundStyle(AppTheme.primaryText)
                            Text(L10n.string(
                                "Compare photos taken under similar conditions so changes stay easier to interpret.",
                                defaultValue: "Compare photos taken under similar conditions so changes stay easier to interpret."
                            ))
                            .appFont(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    HStack(alignment: .top, spacing: AppTheme.spacing12) {
                        if let before = earliest {
                            ComparisonPhotoCard(label: "Before", photo: before, image: vm.image(for: before))
                        }

                        if let after = latest {
                            ComparisonPhotoCard(label: "After", photo: after, image: vm.image(for: after))
                        }
                    }
                }
                .padding()
                .accessibilityIdentifier("photo_comparison.lunar.content")
            }
        }
    }

    private var lunarComparisonEmptyState: some View {
        VStack(spacing: AppTheme.spacing16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
            Text(L10n.string("No photos yet", defaultValue: "No photos yet"))
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(
                String(
                    format: L10n.string(
                        "Add photos for %@ to start comparing changes over time.",
                        defaultValue: "Add photos for %@ to start comparing changes over time."
                    ),
                    selectedType.displayName
                )
            )
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
        }
        .padding(AppTheme.spacing24)
        .frame(maxWidth: .infinity)
        .lunarPhotoComparisonCard()
        .padding(AppTheme.spacing16)
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("photo_comparison.lunar.empty")
    }
}

// MARK: - Comparison Photo Card

private struct ComparisonPhotoCard: View {
    let label: String
    let photo: HairPhotoEntry
    let image: UIImage?
    private let presentation = ComparisonPhotoPresentation(style: .clinical)

    private var formattedDate: String {
        photo.date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(label)
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)

            ZStack {
                RoundedRectangle(cornerRadius: presentation.cornerRadius)
                    .fill(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground.opacity(0.72) : Color(uiColor: presentation.slotBackgroundColor))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(presentation.slotPadding)
                } else {
                    VStack(spacing: AppTheme.spacing8) {
                        Image(systemName: "photo")
                            .appFont(.largeTitle)
                        Text("No Photo")
                            .appFont(.caption, weight: .medium)
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(presentation.slotPadding)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(presentation.slotAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: presentation.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: presentation.cornerRadius)
                    .stroke(
                        AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBorder.opacity(0.62) : Color(uiColor: presentation.slotBorderColor),
                        lineWidth: presentation.slotBorderWidth
                    )
            )

            Text(formattedDate)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if AppTheme.usesPremiumEditorStyling {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                                AppTheme.premiumEditorSurface.opacity(0.78),
                                AppTheme.premiumEditorBackground.opacity(0.9),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay {
            if AppTheme.usesPremiumEditorStyling {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
            }
        }
        .shadow(color: AppTheme.usesPremiumEditorStyling ? AppTheme.cardShadowColor : .clear, radius: 18, y: 12)
        .accessibilityIdentifier(AppTheme.usesPremiumEditorStyling ? "photo_comparison.lunar.card.\(label.lowercased())" : "")
    }
}

private extension View {
    @ViewBuilder
    func lunarPhotoComparisonNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func lunarPhotoComparisonCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
        if AppTheme.usesPremiumEditorStyling {
            background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                                AppTheme.premiumEditorSurface.opacity(0.78),
                                AppTheme.premiumEditorBackground.opacity(0.9),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
            )
            .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
        } else {
            background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.accentColor.opacity(0.08))
            )
        }
    }
}

#Preview {
    PhotoComparisonView()
        .modelContainer(for: HairPhotoEntry.self, inMemory: true)
}
