import SwiftUI
import SwiftData

struct PhotoGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: PhotoJournalViewModel?
    @State private var selectedFilter: HairPhotoType?
    @State private var selectedPhoto: HairPhotoEntry?
    @State private var showCapture = false
    @State private var showComparison = false
    @State private var photos: [HairPhotoEntry] = []
    @State private var pendingDeletePhoto: HairPhotoEntry?
    @State private var showUndoToast = false

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.spacing4),
        GridItem(.flexible(), spacing: AppTheme.spacing4),
        GridItem(.flexible(), spacing: AppTheme.spacing4),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                filterBar
                photoJournalGuidanceCard

                // Photo grid or empty state
                if photos.isEmpty {
                    AppEmptyStateView(
                        title: L10n.string("No Photos Yet", defaultValue: "No Photos Yet"),
                        message: L10n.string(
                            "Start a private progress journal with a consistent angle and lighting.",
                            defaultValue: "Start a private progress journal with a consistent angle and lighting."
                        ),
                        systemImage: "photo.on.rectangle.angled"
                    ) {
                        Button(L10n.string("Add Photo", defaultValue: "Add Photo")) {
                            showCapture = true
                        }
                        .appFont(.subheadline, weight: .semibold)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.coralAccent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.spacing12) {
                            if photos.count == 1 {
                                HStack(spacing: AppTheme.spacing8) {
                                    Image(systemName: "rectangle.split.2x1")
                                        .foregroundStyle(.secondary)
                                    Text(
                                        L10n.string(
                                            "Add one more photo to compare progress.",
                                            defaultValue: "Add one more photo to compare progress."
                                        )
                                    )
                                        .appFont(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.spacing4)
                            }

                            LazyVGrid(columns: columns, spacing: AppTheme.spacing4) {
                                ForEach(photos) { photo in
                                    PhotoThumbnail(image: viewModel?.image(for: photo))
                                        .onTapGesture {
                                            selectedPhoto = photo
                                        }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deletePhoto(photo)
                                        } label: {
                                            Label(L10n.string("Delete", defaultValue: "Delete"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(AppTheme.spacing4)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showUndoToast, pendingDeletePhoto != nil {
                    UndoToast(
                        message: L10n.string("Photo deleted", defaultValue: "Photo deleted"),
                        onUndo: {
                            withAnimation {
                                pendingDeletePhoto = nil
                                showUndoToast = false
                            }
                        },
                        onExpire: {
                            if let photo = pendingDeletePhoto {
                                viewModel?.deletePhoto(photo)
                                refreshPhotos()
                            }
                            withAnimation {
                                pendingDeletePhoto = nil
                                showUndoToast = false
                            }
                        }
                    )
                    .padding()
                }
            }
            .navigationTitle(L10n.string("Photo Journal", defaultValue: "Photo Journal"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.photo_journal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCapture = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                if photos.count >= 2 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showComparison = true
                        } label: {
                            Image(systemName: "rectangle.split.2x1")
                        }
                        .accessibilityIdentifier("photo_journal.compare_button")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedFilter)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: showCapture)
            .sheet(isPresented: $showCapture) {
                PhotoCaptureView()
                    .onDisappear { refreshPhotos() }
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailSheet(photo: photo, image: viewModel?.image(for: photo), onDelete: {
                    deletePhoto(photo)
                    selectedPhoto = nil
                })
            }
            .sheet(isPresented: $showComparison) {
                PhotoComparisonView()
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = PhotoJournalViewModel(modelContext: modelContext)
                }
                refreshPhotos()
            }
        }
        .accessibilityIdentifier("screen.photo_journal")
        .premiumGated()
    }

    // MARK: - Subviews

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing8) {
                CategoryChip(
                    title: L10n.string("All", defaultValue: "All"),
                    isSelected: selectedFilter == nil
                ) {
                    selectedFilter = nil
                    refreshPhotos()
                }

                ForEach(HairPhotoType.allCases) { type in
                    CategoryChip(
                        title: type.displayName,
                        isSelected: selectedFilter == type
                    ) {
                        selectedFilter = type
                        refreshPhotos()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, AppTheme.spacing8)
        }
        .background(AppTheme.groupedBackground)
    }

    private var photoJournalGuidanceCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Label(L10n.string("Private progress photos", defaultValue: "Private progress photos"), systemImage: "lock.shield")
                .appFont(.headline)
                .foregroundStyle(AppTheme.accentColor)

            Text(
                L10n.string(
                    "Your photo journal stays on device. Keep lighting, distance, and angle as consistent as possible.",
                    defaultValue: "Your photo journal stays on device. Keep lighting, distance, and angle as consistent as possible."
                )
            )
                .appFont(.subheadline)
                .foregroundStyle(.secondary)

            Text(
                L10n.string(
                    "Hair and body changes often need months of comparison, while acne and skin shifts may be easier to compare sooner.",
                    defaultValue: "Hair and body changes often need months of comparison, while acne and skin shifts may be easier to compare sooner."
                )
            )
                .appFont(.subheadline)
                .foregroundStyle(.secondary)

            Text(
                L10n.string(
                    "Try to capture photos at a similar time or routine point each week.",
                    defaultValue: "Try to capture photos at a similar time or routine point each week."
                )
            )
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .fill(AppTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top, AppTheme.spacing12)
        .padding(.bottom, AppTheme.spacing8)
        .accessibilityIdentifier("photo_journal.guidance_card")
    }

    // MARK: - Actions

    private func refreshPhotos() {
        guard let vm = viewModel else { return }
        if let filter = selectedFilter {
            photos = vm.fetchPhotos(for: filter)
        } else {
            photos = vm.fetchAllPhotos()
        }
    }

    private func deletePhoto(_ photo: HairPhotoEntry) {
        pendingDeletePhoto = photo
        withAnimation {
            showUndoToast = true
        }
    }
}

// MARK: - Photo Thumbnail

private struct PhotoThumbnail: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(minHeight: 120)
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Photo Detail Sheet

private struct PhotoDetailSheet: View {
    let photo: HairPhotoEntry
    let image: UIImage?
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var formattedDate: String {
        photo.date.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    // Full-size image
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                        HStack {
                            Label(photo.photoType.displayName, systemImage: "tag")
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(formattedDate)
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let notes = photo.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text(L10n.string("Notes", defaultValue: "Notes"))
                                    .appFont(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(notes)
                                    .appFont(.body)
                            }
                        }

                        if let analysis = photo.analysisResult, !analysis.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text("Density Analysis")
                                    .appFont(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(analysis)
                                    .appFont(.body)
                            }
                        }
                    }
                    .cardStyle()

                    // Delete button
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                            .appFont(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            }
            .navigationTitle(L10n.string("Photo Detail", defaultValue: "Photo Detail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PhotoGalleryView()
        .modelContainer(for: HairPhotoEntry.self, inMemory: true)
}
