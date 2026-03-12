import SwiftUI
import SwiftData

struct SupplementLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SupplementViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var showAddSheet = false
    @State private var todaysLogs: [SupplementLog] = []
    @State private var initialLogCount = 0

    @State private var selectedCatalogSupplement: PCOSSupplement?
    @State private var customName = ""
    @State private var dosageText = ""
    @State private var brandText = ""
    @State private var scheduledTime = Date()
    @State private var useCustomName = false
    @State private var addFormDirtyTracker: FormDirtyTracker<AddFormSnapshot>?
    @State private var addFormAlert: AddFormAlert?
    @FocusState private var addSheetFocusedField: AddSheetFocusedField?

    private enum AddSheetFocusedField: Hashable {
        case customName
        case dosage
        case brand
    }

    private struct AddFormSnapshot: Equatable {
        var selectedSupplementName: String?
        var customName: String
        var dosageText: String
        var brandText: String
        var scheduledTime: Date
        var useCustomName: Bool
    }

    private enum AddFormAlert: Identifiable {
        case discard

        var id: String { "discard" }
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
            VStack(spacing: 0) {
                if let viewModel {
                    ScrollView {
                        VStack(spacing: AppTheme.spacing16) {
                            todaysSupplementsSection(viewModel: viewModel)
                            addSupplementButton
                        }
                        .padding()
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Log Supplements")
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
                        SupplementHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
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
                }
            }
            .sensoryFeedback(.warning, trigger: activeAlert?.id)
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .sheet(isPresented: $showAddSheet) {
                addSupplementSheet
            }
            .onAppear {
                let vm = SupplementViewModel(modelContext: modelContext)
                viewModel = vm
                refreshTodaysLogs()
                initialLogCount = todaysLogs.count
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
        .premiumGated()
    }

    @ViewBuilder
    private func todaysSupplementsSection(viewModel: SupplementViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            AppTheme.sectionHeader("Today's Supplements")

            if todaysLogs.isEmpty {
                VStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "pill")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No supplements logged today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap the button below to add your first supplement.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing24)
                .cardStyle()
            } else {
                ForEach(todaysLogs) { log in
                    supplementRow(log: log, viewModel: viewModel)
                }
            }
        }
    }

    private func supplementRow(log: SupplementLog, viewModel: SupplementViewModel) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Button {
                viewModel.toggleTaken(log)
                refreshTodaysLogs()
            } label: {
                Image(systemName: log.taken ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(log.taken ? AppTheme.sage : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(log.supplementName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(!log.taken, color: .secondary)

                HStack(spacing: AppTheme.spacing8) {
                    if let dosage = log.dosageMg, dosage > 0 {
                        Text("\(Int(dosage)) mg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let brand = log.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Text(log.timeTaken, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                viewModel.deleteLog(log)
                refreshTodaysLogs()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, AppTheme.spacing8)
        .padding(.horizontal, AppTheme.spacing12)
        .cardStyle()
        .sensoryFeedback(.selection, trigger: log.taken)
    }

    private var addSupplementButton: some View {
        Button {
            resetAddForm()
            showAddSheet = true
        } label: {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("Add Supplement")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(AppTheme.accentColor))
        }
        .buttonStyle(.plain)
    }

    private var addSupplementSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Custom supplement name", isOn: $useCustomName)

                    if useCustomName {
                        TextField("Supplement name", text: $customName)
                            .focused($addSheetFocusedField, equals: .customName)
                            .submitLabel(.next)
                            .onSubmit {
                                addSheetFocusedField = .dosage
                            }
                    } else {
                        Picker("Supplement", selection: $selectedCatalogSupplement) {
                            Text("Select...").tag(nil as PCOSSupplement?)
                            ForEach(PCOSSupplements.catalog) { supplement in
                                Text(supplement.name)
                                    .tag(supplement as PCOSSupplement?)
                            }
                        }
                    }

                    if let viewModel, useCustomName, !viewModel.supplementNameSuggestions.isEmpty {
                        Text("Recent supplements")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.spacing8) {
                                ForEach(viewModel.supplementNameSuggestions, id: \.self) { suggestion in
                                    Button {
                                        customName = suggestion
                                    } label: {
                                        Text(suggestion)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(AppTheme.accentColor.opacity(0.12))
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
                    Text("Supplement")
                } footer: {
                    if let selected = selectedCatalogSupplement, !useCustomName {
                        Text(selected.description)
                    }
                }

                Section("Details") {
                    if let viewModel, !useCustomName {
                        Text(viewModel.recommendedDosageLabel(for: selectedCatalogSupplement))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let recommendedValue = viewModel.recommendedDosageValue(for: selectedCatalogSupplement) {
                            Button {
                                dosageText = recommendedValue
                            } label: {
                                Text("Use recommended dose")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(AppTheme.accentColor.opacity(0.12))
                                    )
                                    .foregroundStyle(AppTheme.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: AppTheme.spacing8) {
                        TextField("Dosage", text: $dosageText)
                            .keyboardType(.decimalPad)
                            .focused($addSheetFocusedField, equals: .dosage)
                        Text("mg")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.spacing8) {
                            ForEach(["30", "200", "400", "500", "600", "1000", "2000", "4000"], id: \.self) { amount in
                                Button {
                                    dosageText = amount
                                } label: {
                                    Text("\(amount) mg")
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

                    TextField("Brand (optional)", text: $brandText)
                        .focused($addSheetFocusedField, equals: .brand)
                        .submitLabel(.done)

                    if let viewModel, !viewModel.supplementBrandSuggestions.isEmpty {
                        Text("Recent brands")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.spacing8) {
                                ForEach(viewModel.supplementBrandSuggestions, id: \.self) { suggestion in
                                    Button {
                                        brandText = suggestion
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
                }

                Section("Time Taken") {
                    DatePicker("Time", selection: $scheduledTime, displayedComponents: [.hourAndMinute, .date])

                    if let viewModel, viewModel.hasPreferredSupplementTime {
                        Button {
                            scheduledTime = viewModel.preferredSupplementTime
                        } label: {
                            Label("Same as yesterday", systemImage: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(AppTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Supplement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedAddFormChanges {
                            addFormAlert = .discard
                        } else {
                            showAddSheet = false
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSupplement()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if addSheetFocusedField == .customName {
                        Button("Next") { addSheetFocusedField = .dosage }
                    } else if addSheetFocusedField == .dosage {
                        Button("Next") { addSheetFocusedField = .brand }
                    }
                    Spacer()
                    Button("Done") { addSheetFocusedField = nil }
                }
            }
            .interactiveDismissDisabled(hasUnsavedAddFormChanges)
            .alert(item: $addFormAlert) { _ in
                Alert(
                    title: Text("Discard changes?"),
                    message: Text("You have unsaved supplement details that will be lost."),
                    primaryButton: .destructive(Text("Discard")) {
                        showAddSheet = false
                    },
                    secondaryButton: .cancel(Text("Keep Editing"))
                )
            }
            .onChange(of: selectedCatalogSupplement) { _, newValue in
                guard !useCustomName else { return }
                dosageText = viewModel?.recommendedDosageValue(for: newValue) ?? ""
            }
        }
    }

    private var resolvedName: String {
        if useCustomName {
            return customName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedCatalogSupplement?.name ?? ""
    }

    private var canSave: Bool {
        !resolvedName.isEmpty
    }

    private var hasUnsavedChanges: Bool {
        todaysLogs.count != initialLogCount
    }

    private var hasUnsavedAddFormChanges: Bool {
        guard let addFormDirtyTracker else { return false }
        return addFormDirtyTracker.isDirty(current: addFormSnapshot)
    }

    private var addFormSnapshot: AddFormSnapshot {
        AddFormSnapshot(
            selectedSupplementName: selectedCatalogSupplement?.name,
            customName: customName,
            dosageText: dosageText,
            brandText: brandText,
            scheduledTime: scheduledTime,
            useCustomName: useCustomName
        )
    }

    private func resetAddForm() {
        guard let viewModel else {
            selectedCatalogSupplement = nil
            customName = ""
            dosageText = ""
            brandText = ""
            scheduledTime = Date()
            useCustomName = false
            addFormDirtyTracker = FormDirtyTracker(initial: addFormSnapshot)
            return
        }

        let preferredName = viewModel.preferredSupplementName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let catalogMatch = PCOSSupplements.catalog.first(where: {
            $0.name.caseInsensitiveCompare(preferredName) == .orderedSame
        }) {
            selectedCatalogSupplement = catalogMatch
            useCustomName = false
            customName = ""
            dosageText = catalogMatch.defaultDosageMg > 0 ? "\(Int(catalogMatch.defaultDosageMg))" : ""
        } else if !preferredName.isEmpty {
            selectedCatalogSupplement = nil
            customName = preferredName
            useCustomName = true
            dosageText = ""
        } else {
            selectedCatalogSupplement = nil
            customName = ""
            dosageText = ""
            useCustomName = false
        }

        brandText = viewModel.preferredSupplementBrand
        scheduledTime = viewModel.preferredSupplementTime
        addFormDirtyTracker = FormDirtyTracker(initial: addFormSnapshot)
    }

    private func refreshTodaysLogs() {
        todaysLogs = viewModel?.fetchTodaysLogs() ?? []
    }

    private func saveSupplement() {
        let name = resolvedName
        guard !name.isEmpty else { return }

        let dosage = Double(dosageText)
        let brand = brandText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try viewModel?.logSupplement(
                name: name,
                dosageMg: dosage,
                brand: brand.isEmpty ? nil : brand,
                time: scheduledTime
            )
            showAddSheet = false
            refreshTodaysLogs()
            initialLogCount = todaysLogs.count
            saveCoordinator.showSuccessTransient()
        } catch {
            saveCoordinator.showErrorHaptic()
            activeAlert = .error("Could not save supplement: \(error.localizedDescription)")
        }
    }
}

extension PCOSSupplement: Equatable {
    static func == (lhs: PCOSSupplement, rhs: PCOSSupplement) -> Bool {
        lhs.name == rhs.name && lhs.defaultDosageMg == rhs.defaultDosageMg
    }
}

extension PCOSSupplement: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(defaultDosageMg)
    }
}

#Preview {
    SupplementLogView()
        .modelContainer(for: SupplementLog.self, inMemory: true)
}
