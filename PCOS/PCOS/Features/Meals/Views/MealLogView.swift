import SwiftUI
import SwiftData
import PhotosUI

struct MealLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MealViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var dirtyTracker: FormDirtyTracker<FormSnapshot>?
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case description
        case carbs
        case protein
        case fat
        case notes
    }

    private struct FormSnapshot: Equatable {
        var mealType: MealType
        var mealDescription: String
        var glycemicImpact: GlycemicImpact
        var carbsText: String
        var proteinText: String
        var fatText: String
        var photoData: Data?
        var notes: String
        var mealDate: Date
    }

    private enum ActiveAlert: Identifiable {
        case cancel
        case error(String)

        var id: String {
            switch self {
            case .cancel: "cancel"
            case .error: "error"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let viewModel {
                    Section {
                        Picker("Meal Type", selection: Binding(
                            get: { viewModel.mealType },
                            set: { viewModel.mealType = $0 }
                        )) {
                            ForEach(MealType.allCases) { type in
                                Label(type.displayName, systemImage: type.systemImage)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        TextField("What did you eat?", text: Binding(
                            get: { viewModel.mealDescription },
                            set: { viewModel.mealDescription = $0 }
                        ))
                        .focused($focusedField, equals: .description)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .carbs
                        }

                        if !viewModel.mealDescriptionSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppTheme.spacing8) {
                                    ForEach(viewModel.mealDescriptionSuggestions, id: \.self) { suggestion in
                                        Button {
                                            viewModel.applyMealDescriptionSuggestion(suggestion)
                                        } label: {
                                            Text(suggestion)
                                                .font(.caption)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .fill(AppTheme.sage.opacity(0.18))
                                                )
                                                .foregroundStyle(AppTheme.sage)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("Description")
                    }

                    Section {
                        HStack(spacing: AppTheme.spacing8) {
                            GIButton(
                                impact: .low,
                                label: "Low",
                                examples: "Vegetables, legumes, nuts",
                                color: .green,
                                isSelected: viewModel.glycemicImpact == .low
                            ) {
                                viewModel.glycemicImpact = .low
                            }

                            GIButton(
                                impact: .medium,
                                label: "Med",
                                examples: "Rice, whole wheat, fruits",
                                color: .orange,
                                isSelected: viewModel.glycemicImpact == .medium
                            ) {
                                viewModel.glycemicImpact = .medium
                            }

                            GIButton(
                                impact: .high,
                                label: "High",
                                examples: "White bread, sugary foods",
                                color: AppTheme.coralAccent,
                                isSelected: viewModel.glycemicImpact == .high
                            ) {
                                viewModel.glycemicImpact = .high
                            }
                        }
                        .listRowInsets(EdgeInsets(
                            top: AppTheme.spacing8,
                            leading: AppTheme.spacing16,
                            bottom: AppTheme.spacing8,
                            trailing: AppTheme.spacing16
                        ))
                    } header: {
                        Text("Glycemic Impact")
                    }

                    Section {
                        VStack(spacing: AppTheme.spacing12) {
                            macroInputRow(
                                title: "Carbs",
                                value: Binding(
                                    get: { viewModel.carbsText },
                                    set: { viewModel.carbsText = $0 }
                                ),
                                options: ["15", "30", "45", "60"],
                                focused: .carbs
                            )

                            macroInputRow(
                                title: "Protein",
                                value: Binding(
                                    get: { viewModel.proteinText },
                                    set: { viewModel.proteinText = $0 }
                                ),
                                options: ["10", "20", "30", "40"],
                                focused: .protein
                            )

                            macroInputRow(
                                title: "Fat",
                                value: Binding(
                                    get: { viewModel.fatText },
                                    set: { viewModel.fatText = $0 }
                                ),
                                options: ["10", "20", "30", "40"],
                                focused: .fat
                            )
                        }
                    } header: {
                        Text("Macros (Optional)")
                    }

                    Section {
                        let selectedPhotoData = viewModel.photoData
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images
                        ) {
                            HStack {
                                if let photoData = selectedPhotoData,
                                   let uiImage = UIImage(data: photoData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Spacer()

                                    Button("Remove") {
                                        viewModel.photoData = nil
                                        selectedPhotoItem = nil
                                    }
                                    .foregroundStyle(.red)
                                } else {
                                    Label("Add Photo", systemImage: "camera")
                                        .foregroundStyle(AppTheme.sage)
                                }
                            }
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            guard let newItem else { return }
                            Task { @MainActor in
                                do {
                                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                                        return
                                    }
                                    viewModel.photoData = data
                                } catch {
                                    saveCoordinator.showErrorHaptic()
                                    activeAlert = .error("Could not import photo: \(error.localizedDescription)")
                                }
                            }
                        }
                    } header: {
                        Text("Photo (Optional)")
                    }

                    Section {
                        TextField("Any additional notes...", text: Binding(
                            get: { viewModel.notes },
                            set: { viewModel.notes = $0 }
                        ), axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)

                        if !viewModel.mealNoteSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppTheme.spacing8) {
                                    ForEach(viewModel.mealNoteSuggestions, id: \.self) { suggestion in
                                        let isSelected = viewModel.isMealNoteSelected(suggestion)
                                        Button {
                                            viewModel.toggleMealNoteSuggestion(suggestion)
                                        } label: {
                                            HStack(spacing: 4) {
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .font(.caption2)
                                                }
                                                Text(suggestion)
                                                    .font(.caption)
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
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("Notes")
                    }

                    Section {
                        DatePicker(
                            "Meal Date",
                            selection: Binding(
                                get: { viewModel.mealDate },
                                set: { viewModel.mealDate = $0 }
                            ),
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    Section {
                        Button {
                            saveMeal()
                        } label: {
                            Text("Save Meal")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(viewModel.isValid
                                              ? AppTheme.sage
                                              : Color.gray.opacity(0.3))
                                )
                                .foregroundStyle(.white)
                        }
                        .disabled(!viewModel.isValid)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Log Meal")
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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MealHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .description {
                        Button("Next") { focusedField = .carbs }
                    } else if focusedField == .carbs {
                        Button("Next") { focusedField = .protein }
                    } else if focusedField == .protein {
                        Button("Next") { focusedField = .fat }
                    } else if focusedField == .fat {
                        Button("Next") { focusedField = .notes }
                    }
                    Spacer()
                    Button("Done") { focusedField = nil }
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
                }
            }
            .sensoryFeedback(.warning, trigger: activeAlert?.id)
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .onAppear {
                let vm = MealViewModel(modelContext: modelContext)
                viewModel = vm
                dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
        .premiumGated()
    }

    private var hasUnsavedChanges: Bool {
        guard let viewModel, let dirtyTracker else { return false }
        return dirtyTracker.isDirty(current: snapshot(for: viewModel))
    }

    private func macroInputRow(
        title: String,
        value: Binding<String>,
        options: [String],
        focused: FocusedField
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack {
                Text("\(title) (g)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                TextField("0", text: value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($focusedField, equals: focused)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacing8) {
                    ForEach(options, id: \.self) { option in
                        Button {
                            value.wrappedValue = option
                        } label: {
                            Text("\(option)g")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(AppTheme.sage.opacity(0.16))
                                )
                                .foregroundStyle(AppTheme.sage)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func saveMeal() {
        do {
            try viewModel?.saveMeal()
            saveCoordinator.showSuccessAndDismiss {
                dismiss()
            }
        } catch {
            saveCoordinator.showErrorHaptic()
            activeAlert = .error("Could not save meal: \(error.localizedDescription)")
        }
    }

    private func snapshot(for viewModel: MealViewModel) -> FormSnapshot {
        FormSnapshot(
            mealType: viewModel.mealType,
            mealDescription: viewModel.mealDescription,
            glycemicImpact: viewModel.glycemicImpact,
            carbsText: viewModel.carbsText,
            proteinText: viewModel.proteinText,
            fatText: viewModel.fatText,
            photoData: viewModel.photoData,
            notes: viewModel.notes,
            mealDate: viewModel.mealDate
        )
    }
}

private struct GIButton: View {
    let impact: GlycemicImpact
    let label: String
    let examples: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.spacing4) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(examples)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing8)
            .padding(.horizontal, AppTheme.spacing4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.2) : Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    MealLogView()
        .modelContainer(for: MealEntry.self, inMemory: true)
}
