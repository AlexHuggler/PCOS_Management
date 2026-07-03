import StoreKit
import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UIKit

private enum PhotoCaptureSource {
    case library
    case camera
}

struct PhotoCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var viewModel: PhotoJournalViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var selectedItem: PhotosPickerItem?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
    @State private var isShowingCamera = false

    private struct FormSnapshot: Equatable {
        var selectedPhotoType: HairPhotoType
        var capturedPhotoData: Data?
        var notes: String
        var photoDate: Date
    }

    private enum ActiveAlert: Identifiable {
        case cancel
        case error(String)
        case cameraPermissionDenied
        case cameraUnavailable

        var id: String {
            switch self {
            case .cancel: return "cancel"
            case .error: return "error"
            case .cameraPermissionDenied: return "cameraPermissionDenied"
            case .cameraUnavailable: return "cameraUnavailable"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                }

                ScrollView {
                    VStack(spacing: AppTheme.spacing16) {
                        if AppTheme.usesPremiumEditorStyling {
                            lunarCaptureHeader
                        }

                        photoTypeSelector
                        photoSection

                        if let vm = viewModel {
                            guideText(for: vm.selectedPhotoType)
                        }

                        notesSection
                        dateSection
                        saveButton
                    }
                    .padding(AppTheme.spacing16)
                    .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
                }
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Add Photo", defaultValue: "Add Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        if hasUnsavedChanges {
                            activeAlert = .cancel
                        } else {
                            dismiss()
                        }
                    }
                }
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Add Photo", defaultValue: "Add Photo"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
            }
            .lunarPhotoCaptureNavigationBackground()
            .interactiveDismissDisabled(hasUnsavedChanges)
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .cancel:
                    return Alert(
                        title: Text("Discard changes?"),
                        message: Text("You have unsaved changes that will be lost."),
                        primaryButton: .destructive(Text("Discard")) { dismiss() },
                        secondaryButton: .cancel(Text("Keep Editing"))
                    )
                case .error(let message):
                    return Alert(
                        title: Text("Could not Save"),
                        message: Text(message),
                        dismissButton: .cancel(Text("OK"))
                    )
                case .cameraPermissionDenied:
                    return Alert(
                        title: Text("Camera Access Needed"),
                        message: Text("Enable camera access in Settings to capture photos directly."),
                        primaryButton: .default(Text("Open Settings")) {
                            openAppSettings()
                        },
                        secondaryButton: .cancel(Text("Not Now"))
                    )
                case .cameraUnavailable:
                    return Alert(
                        title: Text("Camera Unavailable"),
                        message: Text("This device does not have a camera available right now."),
                        dismissButton: .cancel(Text("OK"))
                    )
                }
            }
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(
                    photoType: viewModel?.selectedPhotoType ?? .scalpPart,
                    onImagePicked: { data in
                        if let data {
                            viewModel?.capturedPhotoData = data
                        }
                        isShowingCamera = false
                    },
                    onCancel: {
                        isShowingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self) else {
                            return
                        }
                        await MainActor.run {
                            viewModel?.capturedPhotoData = data
                        }
                    } catch {
                        await MainActor.run {
                            saveCoordinator.showErrorFeedback()
                            activeAlert = .error(
                                String(
                                    localized: "Could not import photo: \(error.localizedDescription)",
                                    comment: "Error shown when importing a progress photo fails."
                                )
                            )
                        }
                    }
                }
            }
            .onAppear {
                let vm = PhotoJournalViewModel(modelContext: modelContext)
                viewModel = vm
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
            .accessibilityIdentifier("screen.photo_capture")
        }
    }

    private var lunarCaptureHeader: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Add a progress photo", defaultValue: "Add a progress photo"))
                    .appFont(.largeTitle, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo_capture.lunar.header")

                Text(L10n.string(
                    "Use the same angle and lighting when you can. These photos stay private on your device.",
                    defaultValue: "Use the same angle and lighting when you can. These photos stay private on your device."
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
        .padding(AppTheme.spacing16)
        .lunarPhotoCaptureCard()
    }

    private var photoTypeSelector: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Photo Type")
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacing8) {
                    ForEach(HairPhotoType.allCases) { type in
                        CategoryChip(
                            title: type.displayName,
                            isSelected: viewModel?.selectedPhotoType == type
                        ) {
                            viewModel?.selectedPhotoType = type
                        }
                    }
                }
            }
        }
        .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing16 : 0)
        .lunarPhotoCaptureCard(cornerRadius: AppTheme.cornerRadiusMedium)
        .accessibilityIdentifier("photo_capture.lunar.type")
    }

    private var photoSection: some View {
        let capturedPhotoData = viewModel?.capturedPhotoData
        let hasPhoto = capturedPhotoData != nil
        let primarySource: PhotoCaptureSource = hasPhoto ? .library : .camera
        let selectedPhotoType = viewModel?.selectedPhotoType ?? .scalpPart

        return VStack(spacing: AppTheme.spacing12) {
            if let photoData = capturedPhotoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            PhotoPositioningOverlay(photoType: selectedPhotoType)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground.opacity(0.72) : Color(.tertiarySystemFill))
                        .frame(height: 220)
                    PhotoPositioningOverlay(photoType: selectedPhotoType)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            VStack(spacing: AppTheme.spacing8) {
                sourceButton(for: primarySource)
                sourceButton(for: primarySource == .camera ? .library : .camera)
            }
        }
        .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing16 : 0)
        .lunarPhotoCaptureCard()
        .accessibilityIdentifier("photo_capture.lunar.photo_section")
    }

    private func sourceButton(for source: PhotoCaptureSource) -> some View {
        let hasCapturedPhoto = viewModel?.capturedPhotoData != nil
        let title: String
        switch source {
        case .library:
            title = hasCapturedPhoto ? "Replace from Library" : "Choose from Library"
        case .camera:
            title = hasCapturedPhoto ? "Retake with Camera" : "Use Camera"
        }

        return Group {
            switch source {
            case .library:
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(title, systemImage: "photo.on.rectangle.angled")
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.primaryText : AppTheme.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorSurface.opacity(0.76) : Color(.tertiarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBorder.opacity(0.58) : Color.clear, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            case .camera:
                Button {
                    presentCameraIfAvailable()
                } label: {
                    Label(title, systemImage: "camera")
                        .appFont(.headline)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : AppTheme.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.usesPremiumEditorStyling ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(Color(.tertiarySystemFill)))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func guideText(for type: HairPhotoType) -> some View {
        let text: String = switch type {
        case .scalpPart: "Center your part line in the frame"
        case .hairline: "Position your forehead hairline in the frame"
        case .faceChin: "Center your chin area in the frame"
        case .faceUpperLip: "Center your upper lip area in the frame"
        case .body: "Position the area you want to track"
        }

        return HStack(spacing: AppTheme.spacing8) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : .secondary)
            Text(text)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .lunarPhotoCaptureCard(cornerRadius: AppTheme.cornerRadiusMedium)
        .accessibilityIdentifier("photo_capture.lunar.guide")
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(L10n.string("Notes", defaultValue: "Notes"))
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)

            if AppTheme.usesPremiumEditorStyling {
                TextField("Add any observations...", text: Binding(
                    get: { viewModel?.notes ?? "" },
                    set: { viewModel?.notes = $0 }
                ), axis: .vertical)
                .appFont(.body)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(3...6)
                .padding(AppTheme.spacing12)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                        .fill(AppTheme.premiumEditorSurface.opacity(0.76))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                        .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
                )
            } else {
                TextField("Add any observations...", text: Binding(
                    get: { viewModel?.notes ?? "" },
                    set: { viewModel?.notes = $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            }

            if let viewModel, !viewModel.photoNoteSuggestions.isEmpty {
                Text("Quick notes")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                FlowLayout(spacing: AppTheme.spacing8) {
                    ForEach(viewModel.photoNoteSuggestions, id: \.self) { suggestion in
                        let isSelected = viewModel.isPhotoNoteSelected(suggestion)
                        Button {
                            viewModel.togglePhotoNoteSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .appFont(.caption2)
                                }
                                Text(suggestion)
                                    .appFont(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? AppTheme.accentColor.opacity(0.22) : AppTheme.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(AppTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing16 : 0)
        .lunarPhotoCaptureCard(cornerRadius: AppTheme.cornerRadiusMedium)
        .accessibilityIdentifier("photo_capture.lunar.notes")
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Date")
                .appFont(.headline)
                .foregroundStyle(AppTheme.primaryText)

            DatePicker(
                "Photo Date",
                selection: Binding(
                    get: { viewModel?.photoDate ?? Date() },
                    set: { viewModel?.photoDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .tint(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing16 : 0)
        .lunarPhotoCaptureCard(cornerRadius: AppTheme.cornerRadiusMedium)
        .accessibilityIdentifier("photo_capture.lunar.date")
    }

    private var saveButton: some View {
        let hasPhoto = viewModel?.hasPhoto == true

        return Button {
            savePhoto()
        } label: {
            Text("Save Photo")
                .appFont(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(hasPhoto
                              ? (AppTheme.usesPremiumEditorStyling ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.coralAccent))
                              : AnyShapeStyle(Color.gray.opacity(0.3)))
                )
                .foregroundStyle(AppTheme.usesPremiumEditorStyling && hasPhoto ? AppTheme.premiumEditorCTAForeground : .white)
        }
        .disabled(!hasPhoto)
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo_capture.lunar.save_button")
    }

    private var hasUnsavedChanges: Bool {
        guard let viewModel, let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot(for: viewModel))
    }

    private func presentCameraIfAvailable() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            activeAlert = .cameraUnavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
            selectedItem = nil
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        isShowingCamera = true
                        selectedItem = nil
                    } else {
                        activeAlert = .cameraPermissionDenied
                    }
                }
            }
        case .denied, .restricted:
            activeAlert = .cameraPermissionDenied
        @unknown default:
            activeAlert = .cameraUnavailable
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    private func savePhoto() {
        do {
            try viewModel?.savePhoto()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
            ReviewPromptService.requestReviewIfEligible(modelContext: modelContext, moment: .photoProgressSaved, requestReview: requestReview)
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                String(
                    localized: "Could not save photo: \(error.localizedDescription)",
                    comment: "Error shown when a progress photo cannot be saved."
                )
            )
        }
    }

    private func snapshot(for viewModel: PhotoJournalViewModel) -> FormSnapshot {
        FormSnapshot(
            selectedPhotoType: viewModel.selectedPhotoType,
            capturedPhotoData: viewModel.capturedPhotoData,
            notes: viewModel.notes,
            photoDate: viewModel.photoDate
        )
    }
}

private extension View {
    @ViewBuilder
    func lunarPhotoCaptureNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func lunarPhotoCaptureCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
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
            self
        }
    }
}

private struct PhotoPositioningOverlay: View {
    let photoType: HairPhotoType

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                switch photoType {
                case .scalpPart:
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: width * 0.62, height: height * 0.78)

                    Rectangle()
                        .fill(.white.opacity(0.7))
                        .frame(width: 2, height: height * 0.68)
                case .hairline:
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: width * 0.74, height: height * 0.42)
                        .offset(y: -height * 0.18)
                case .faceChin:
                    Ellipse()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: width * 0.56, height: height * 0.34)
                        .offset(y: height * 0.18)
                case .faceUpperLip:
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: width * 0.42, height: height * 0.16)
                        .offset(y: height * 0.03)
                case .body:
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 7]))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: width * 0.84, height: height * 0.82)
                }

                VStack {
                    Spacer()
                    Text(photoType.overlayInstruction)
                        .appFont(.caption, weight: .semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.black.opacity(0.45))
                        )
                        .foregroundStyle(.white)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: width, height: height)
        }
    }
}

private extension HairPhotoType {
    var overlayInstruction: String {
        switch self {
        case .scalpPart:
            "Align your part line with the center guide."
        case .hairline:
            "Frame your hairline inside the top guide."
        case .faceChin:
            "Center the chin area in the oval."
        case .faceUpperLip:
            "Place the upper lip inside the guide box."
        case .body:
            "Keep the target area inside the full-frame guide."
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let photoType: HairPhotoType
    let onImagePicked: (Data?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.cameraOverlayView = makeOverlayView()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    private func makeOverlayView() -> UIView {
        let host = UIHostingController(rootView: PhotoPositioningOverlay(photoType: photoType))
        host.view.backgroundColor = .clear
        host.view.frame = UIScreen.main.bounds
        host.view.isUserInteractionEnabled = false
        return host.view
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let data = image?.jpegData(compressionQuality: 0.9)
            parent.onImagePicked(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

#Preview {
    PhotoCaptureView()
        .modelContainer(for: HairPhotoEntry.self, inMemory: true)
}
