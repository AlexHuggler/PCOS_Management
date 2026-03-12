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
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    photoTypeSelector
                    photoSection

                    if let vm = viewModel {
                        guideText(for: vm.selectedPhotoType)
                    }

                    notesSection
                    dateSection
                    saveButton
                }
                .padding()
            }
            .navigationTitle("Add Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            activeAlert = .cancel
                        } else {
                            dismiss()
                        }
                    }
                }
            }
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
            .sensoryFeedback(.warning, trigger: activeAlert?.id)
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraImagePicker(
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
                            saveCoordinator.showErrorHaptic()
                            activeAlert = .error("Could not import photo: \(error.localizedDescription)")
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
        }
    }

    private var photoTypeSelector: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Photo Type")
                .font(.headline)

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
    }

    private var photoSection: some View {
        let capturedPhotoData = viewModel?.capturedPhotoData
        let hasPhoto = capturedPhotoData != nil
        let primarySource: PhotoCaptureSource = hasPhoto ? .library : .camera

        return VStack(spacing: AppTheme.spacing12) {
            if let photoData = capturedPhotoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            VStack(spacing: AppTheme.spacing8) {
                sourceButton(for: primarySource)
                sourceButton(for: primarySource == .camera ? .library : .camera)
            }
        }
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
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            case .camera:
                Button {
                    presentCameraIfAvailable()
                } label: {
                    Label(title, systemImage: "camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemFill))
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
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.accentColor.opacity(0.08))
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Notes")
                .font(.headline)

            TextField("Add any observations...", text: Binding(
                get: { viewModel?.notes ?? "" },
                set: { viewModel?.notes = $0 }
            ), axis: .vertical)
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text("Date")
                .font(.headline)

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        let hasPhoto = viewModel?.hasPhoto == true

        return Button {
            savePhoto()
        } label: {
            Text("Save Photo")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(hasPhoto
                              ? AppTheme.coralAccent
                              : Color.gray.opacity(0.3))
                )
                .foregroundStyle(.white)
        }
        .disabled(!hasPhoto)
        .buttonStyle(.plain)
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
        } catch {
            saveCoordinator.showErrorHaptic()
            activeAlert = .error("Could not save photo: \(error.localizedDescription)")
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

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (Data?) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

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
