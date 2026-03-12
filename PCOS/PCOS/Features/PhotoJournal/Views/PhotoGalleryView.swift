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

                // Photo grid or empty state
                if photos.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Yet", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Start tracking changes by adding your first photo.")
                    } actions: {
                        Button("Add Photo") {
                            showCapture = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.coralAccent)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.spacing12) {
                            if photos.count == 1 {
                                HStack(spacing: AppTheme.spacing8) {
                                    Image(systemName: "rectangle.split.2x1")
                                        .foregroundStyle(.secondary)
                                    Text("Add one more photo to compare progress.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.spacing4)
                            }

                            LazyVGrid(columns: columns, spacing: AppTheme.spacing4) {
                                ForEach(photos) { photo in
                                    PhotoThumbnail(photo: photo)
                                        .onTapGesture {
                                            selectedPhoto = photo
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deletePhoto(photo)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        .padding(AppTheme.spacing4)
                    }
                }
            }
            .navigationTitle("Photo Journal")
            .navigationBarTitleDisplayMode(.inline)
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
                    }
                }
            }
            .sheet(isPresented: $showCapture) {
                PhotoCaptureView()
                    .onDisappear { refreshPhotos() }
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailSheet(photo: photo, onDelete: {
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
        .premiumGated()
    }

    // MARK: - Subviews

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing8) {
                CategoryChip(
                    title: "All",
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
        viewModel?.deletePhoto(photo)
        refreshPhotos()
    }
}

// MARK: - Photo Thumbnail

private struct PhotoThumbnail: View {
    let photo: HairPhotoEntry

    var body: some View {
        Group {
            if let uiImage = UIImage(data: photo.photoData) {
                Image(uiImage: uiImage)
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
                    if let uiImage = UIImage(data: photo.photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                        HStack {
                            Label(photo.photoType.displayName, systemImage: "tag")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(formattedDate)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let notes = photo.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(notes)
                                    .font(.body)
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
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            }
            .navigationTitle("Photo Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PhotoGalleryView()
        .modelContainer(for: HairPhotoEntry.self, inMemory: true)
}
