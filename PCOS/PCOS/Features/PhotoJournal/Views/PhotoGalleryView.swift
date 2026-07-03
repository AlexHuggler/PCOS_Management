import SwiftUI
import SwiftData

struct PhotoGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
            ZStack {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    if AppTheme.usesPremiumEditorStyling {
                        lunarGalleryHeader
                    }

                    // Filter bar
                    filterBar
                    photoJournalGuidanceCard

                    // Photo grid or empty state
                    if photos.isEmpty {
                        if AppTheme.usesPremiumEditorStyling {
                            lunarEmptyState
                        } else {
                            AppEmptyStateView(
                                title: L10n.string("No Photos Yet", defaultValue: "No Photos Yet"),
                                message: L10n.string(
                                    "Start a private journal for visible PCOS changes with a consistent angle and lighting.",
                                    defaultValue: "Start a private journal for visible PCOS changes with a consistent angle and lighting."
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
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: AppTheme.spacing12) {
                                if photos.count == 1 {
                                    HStack(spacing: AppTheme.spacing8) {
                                        Image(systemName: "rectangle.split.2x1")
                                            .foregroundStyle(AppTheme.secondaryText)
                                        Text(
                                            L10n.string(
                                                "Add one more photo to compare progress.",
                                                defaultValue: "Add one more photo to compare progress."
                                            )
                                        )
                                            .appFont(.subheadline)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, AppTheme.spacing4)
                                }

                                LazyVGrid(columns: columns, spacing: AppTheme.usesPremiumEditorStyling ? AppTheme.spacing8 : AppTheme.spacing4) {
                                    ForEach(photos) { photo in
                                        PhotoThumbnail(image: viewModel?.image(for: photo))
                                            .accessibilityIdentifier("photo_journal.lunar.photo.\(photo.id.uuidString)")
                                            .accessibilityAddTraits(.isButton)
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
                                .accessibilityIdentifier("photo_journal.lunar.grid")
                            }
                            .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing12 : AppTheme.spacing4)
                        }
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
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Photo Journal", defaultValue: "Photo Journal"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.photo_journal")
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(L10n.string("Close", defaultValue: "Close"))
                    }
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Photo journal", defaultValue: "Photo journal"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCapture = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("photo_journal.add_button")
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
            .lunarPhotoNavigationBackground()
            .sensoryFeedback(.selection, trigger: selectedFilter)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: showCapture)
            .lunarPhotoPresentation(isPresented: $showCapture) {
                PhotoCaptureView()
                    .onDisappear { refreshPhotos() }
            }
            .lunarPhotoItemPresentation(item: $selectedPhoto) { photo in
                PhotoDetailSheet(photo: photo, image: viewModel?.image(for: photo), onDelete: {
                    deletePhoto(photo)
                    selectedPhoto = nil
                })
            }
            .lunarPhotoPresentation(isPresented: $showComparison) {
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

    private var lunarGalleryHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Track visible changes", defaultValue: "Track visible changes"))
                        .appFont(.largeTitle, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("photo_journal.lunar.header")
                    Text(L10n.string(
                        "A private, low-pressure space for photos when visual context helps you notice patterns.",
                        defaultValue: "A private, low-pressure space for photos when visual context helps you notice patterns."
                    ))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                    .shadow(color: AppTheme.roseAccent.opacity(0.24), radius: 16, y: 8)
            }

            HStack(spacing: AppTheme.spacing8) {
                lunarSummaryPill(title: L10n.string("Photos", defaultValue: "Photos"), value: "\(photos.count)", systemImage: "photo.stack.fill")
                lunarSummaryPill(title: L10n.string("Types", defaultValue: "Types"), value: "\(Set(photos.map(\.photoType)).count)", systemImage: "tag.fill")
                lunarSummaryPill(title: L10n.string("Compare", defaultValue: "Compare"), value: photos.count >= 2 ? L10n.string("Ready", defaultValue: "Ready") : L10n.string("Soon", defaultValue: "Soon"), systemImage: "rectangle.split.2x1.fill")
            }
        }
        .padding(AppTheme.spacing16)
        .lunarPhotoCard()
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.top, AppTheme.spacing12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo_journal.lunar.header")
    }

    private var lunarEmptyState: some View {
        VStack(spacing: AppTheme.spacing16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
            Text(L10n.string("No photos yet", defaultValue: "No photos yet"))
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(L10n.string(
                "Start a private journal for visible PCOS changes with a consistent angle and lighting.",
                defaultValue: "Start a private journal for visible PCOS changes with a consistent angle and lighting."
            ))
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .multilineTextAlignment(.center)

            Button(L10n.string("Add Photo", defaultValue: "Add Photo")) {
                showCapture = true
            }
            .appFont(.subheadline, weight: .semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.premiumEditorAccentColor)
        }
        .padding(AppTheme.spacing24)
        .frame(maxWidth: .infinity)
        .lunarPhotoCard()
        .padding(AppTheme.spacing16)
        .accessibilityIdentifier("photo_journal.lunar.empty")
    }

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
        .background(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : AppTheme.groupedBackground)
    }

    private var photoJournalGuidanceCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Label(L10n.string("Private progress photos", defaultValue: "Private progress photos"), systemImage: "lock.shield")
                .appFont(.headline)
                .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.accentColor)
                .accessibilityIdentifier("photo_journal.guidance_card")

            Text(
                L10n.string(
                    "Your photo journal stays on device and is meant for personal documentation, not diagnosis.",
                    defaultValue: "Your photo journal stays on device and is meant for personal documentation, not diagnosis."
                )
            )
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            Text(
                L10n.string(
                    "Use it for visible PCOS changes like hair, skin, bloating, or body composition when photos feel helpful.",
                    defaultValue: "Use it for visible PCOS changes like hair, skin, bloating, or body composition when photos feel helpful."
                )
            )
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)

            Text(
                L10n.string(
                    "Try to capture photos at a similar time or routine point each week.",
                    defaultValue: "Try to capture photos at a similar time or routine point each week."
                )
            )
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .lunarPhotoCard(cornerRadius: AppTheme.cornerRadiusMedium)
        .padding(.horizontal)
        .padding(.top, AppTheme.spacing12)
        .padding(.bottom, AppTheme.spacing8)
        .accessibilityIdentifier("photo_journal.guidance_card")
    }

    private func lunarSummaryPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.spacing8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.premiumEditorAccentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.spacing8)
        .padding(.vertical, AppTheme.spacing8)
        .background(Capsule().fill(AppTheme.premiumEditorSurface.opacity(0.76)))
        .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.56), lineWidth: 0.8))
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
                    .fill(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorSurface.opacity(0.9) : Color(.tertiarySystemFill))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.secondaryText : .secondary)
                    }
            }
        }
        .frame(minHeight: 120)
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.usesPremiumEditorStyling ? AppTheme.cornerRadiusMedium : 4, style: .continuous))
        .overlay {
            if AppTheme.usesPremiumEditorStyling {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func lunarPhotoNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func lunarPhotoPresentation<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(isPresented: isPresented, content: destination)
        } else {
            sheet(isPresented: isPresented, content: destination)
        }
    }

    @ViewBuilder
    func lunarPhotoItemPresentation<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(item: item, content: destination)
        } else {
            sheet(item: item, content: destination)
        }
    }

    @ViewBuilder
    func lunarPhotoCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
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
            cardStyle(cornerRadius: cornerRadius)
        }
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
            Group {
                if AppTheme.usesPremiumEditorStyling {
                    lunarPhotoDetailContent
                } else {
                    standardPhotoDetailContent
                }
            }
            .navigationTitle(L10n.string("Photo Detail", defaultValue: "Photo Detail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) { dismiss() }
                }
            }
            .lunarPhotoDetailNavigationBackground()
        }
    }

    private var standardPhotoDetailContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing16) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                }

                metadataCard
                    .cardStyle()

                deleteButton
            }
            .padding()
        }
        .accessibilityIdentifier("screen.photo_detail")
    }

    private var lunarPhotoDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
                        )
                        .accessibilityIdentifier("photo_detail.lunar.image")
                }

                lunarHeaderCard
                lunarMetadataCard
                deleteButton
            }
            .padding(AppTheme.spacing16)
            .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
        }
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
        .accessibilityIdentifier("screen.photo_detail")
    }

    private var lunarHeaderCard: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "photo.fill")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                .frame(width: 46, height: 46)
                .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(photo.photoType.displayName)
                    .appFont(.caption, weight: .semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                Text(formattedDate)
                    .appHeadingFont(.title3, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("Private progress note", defaultValue: "Private progress note"))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(AppTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lunarPhotoCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo_detail.lunar.header")
    }

    private var lunarMetadataCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            metadataCard
        }
        .padding(AppTheme.spacing12)
        .lunarPhotoCard()
        .accessibilityIdentifier("photo_detail.lunar.metadata")
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Label(photo.photoType.displayName, systemImage: "tag")
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : .secondary)

                Spacer()

                Text(formattedDate)
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let notes = photo.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(L10n.string("Notes", defaultValue: "Notes"))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.primaryText : Color.secondary)
                    Text(notes)
                        .appFont(.body)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.secondaryText : AppTheme.primaryText)
                }
            }

            if let analysis = photo.analysisResult, !analysis.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text("Density Analysis")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.primaryText : Color.secondary)
                    Text(analysis)
                        .appFont(.body)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.secondaryText : AppTheme.primaryText)
                }
            }
        }
    }

    private var deleteButton: some View {
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
        .tint(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorWarningAccentColor : .red)
        .accessibilityIdentifier("photo_detail.delete_button")
    }
}

private extension View {
    @ViewBuilder
    func lunarPhotoDetailNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }
}

#Preview {
    PhotoGalleryView()
        .modelContainer(for: HairPhotoEntry.self, inMemory: true)
}
