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
            .navigationTitle("Compare Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
            ContentUnavailableView {
                Label("No Photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Add photos for \(selectedType.displayName) to start comparing changes over time.")
            }
            .frame(maxHeight: .infinity)
        } else if earliest?.id == latest?.id {
            // Only one photo
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    if let photo = earliest {
                        ComparisonPhotoCard(label: "Current", photo: photo)
                    }

                    HStack(spacing: AppTheme.spacing8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Add more \(selectedType.displayName) photos to compare changes over time.")
                            .font(.subheadline)
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
                        ComparisonPhotoCard(label: "Before", photo: before)
                    }

                    if let after = latest {
                        ComparisonPhotoCard(label: "After", photo: after)
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

    private var formattedDate: String {
        photo.date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(.primary)

            if let uiImage = UIImage(data: photo.photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            Text(formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PhotoComparisonView()
        .modelContainer(for: HairPhotoEntry.self, inMemory: true)
}
