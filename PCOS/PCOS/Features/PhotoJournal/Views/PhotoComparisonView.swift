import SwiftUI
import SwiftData

struct PhotoComparisonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PhotoJournalViewModel?
    @State private var selectedType: HairPhotoType = .scalpPart

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Type selector
                typeSelector

                // Comparison content
                if let vm = viewModel {
                    comparisonContent(vm: vm)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(L10n.string("Compare Photos", defaultValue: "Compare Photos"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.photo_comparison")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) { dismiss() }
                }
            }
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
        .background(AppTheme.groupedBackground)
    }

    @ViewBuilder
    private func comparisonContent(vm: PhotoJournalViewModel) -> some View {
        let earliest = vm.earliestPhoto(for: selectedType)
        let latest = vm.latestPhoto(for: selectedType)

        if earliest == nil && latest == nil {
            // No photos at all for this type
            AppEmptyStateView(
                title: "No Photos",
                message: "Add photos for \(selectedType.displayName) to start comparing changes over time.",
                systemImage: "photo.on.rectangle.angled"
            )
            .frame(maxHeight: .infinity)
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
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.accentColor.opacity(0.08))
                    )
                }
                .padding()
            }
        } else {
            // Two or more photos -- show side-by-side
            ScrollView {
                HStack(alignment: .top, spacing: AppTheme.spacing12) {
                    if let before = earliest {
                        ComparisonPhotoCard(label: "Before", photo: before, image: vm.image(for: before))
                    }

                    if let after = latest {
                        ComparisonPhotoCard(label: "After", photo: after, image: vm.image(for: after))
                    }
                }
                .padding()
            }
        }
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
                .foregroundStyle(.primary)

            ZStack {
                RoundedRectangle(cornerRadius: presentation.cornerRadius)
                    .fill(Color(uiColor: presentation.slotBackgroundColor))

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
                    .foregroundStyle(.secondary)
                    .padding(presentation.slotPadding)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(presentation.slotAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: presentation.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: presentation.cornerRadius)
                    .stroke(Color(uiColor: presentation.slotBorderColor), lineWidth: presentation.slotBorderWidth)
            )

            Text(formattedDate)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PhotoComparisonView()
        .modelContainer(for: HairPhotoEntry.self, inMemory: true)
}
