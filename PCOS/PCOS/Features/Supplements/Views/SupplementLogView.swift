import SwiftUI
import SwiftData

struct SupplementLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var viewModel: SupplementViewModel?
    @State private var saveCoordinator = SaveInteractionCoordinator()
    @State private var activeAlert: ActiveAlert?
    @State private var showAddSheet = false
    @State private var todaysLogs: [SupplementLog] = []
    @State private var initialLogCount = 0
    @State private var canRepeatYesterday = false
    @State private var activeDisclosure: InsightDisclosureContent?

    @State private var selectedCatalogSupplement: PCOSSupplement?
    @State private var supplementNameText = ""
    @State private var dosageText = ""
    @State private var brandText = ""
    @State private var scheduledTime = Date()
    @State private var addFormDirtyTracker: FormDirtyTracker<AddFormSnapshot>?
    @State private var addFormAlert: AddFormAlert?
    @FocusState private var addSheetFocusedField: AddSheetFocusedField?

    private enum AddSheetFocusedField: Hashable {
        case supplementName
        case dosage
        case brand
    }

    private struct AddFormSnapshot: Equatable {
        var supplementNameText: String
        var dosageText: String
        var brandText: String
        var scheduledTime: Date
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
                            utilityActionsSection(viewModel: viewModel)
                            todaysSupplementsSection(viewModel: viewModel)
                            addSupplementButton
                        }
                        .padding()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.spacing16) {
                            ForEach(0..<4, id: \.self) { _ in
                                SkeletonListRow()
                                    .cardStyle()
                            }
                            SkeletonRing()
                                .frame(maxWidth: .infinity)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(L10n.string("Log Supplements", defaultValue: "Log Supplements"))
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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SupplementHistoryView()
                    } label: {
                        Label(L10n.string("History", defaultValue: "History"), systemImage: "clock.arrow.circlepath")
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
            .overlay {
                if saveCoordinator.isShowingSavedFeedback {
                    SavedFeedbackOverlay()
                }
            }
            .sensoryFeedback(.success, trigger: saveCoordinator.isShowingSavedFeedback)
            .sheet(isPresented: $showAddSheet) {
                addSupplementSheet
            }
            .onAppear {
                let vm = SupplementViewModel(modelContext: modelContext)
                viewModel = vm
                refreshSupplementState()
                initialLogCount = todaysLogs.count
            }
            .onDisappear {
                saveCoordinator.cancelPending()
            }
        }
        .premiumGated()
    }

    @ViewBuilder
    private func utilityActionsSection(viewModel: SupplementViewModel) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            if canRepeatYesterday {
                Button {
                    repeatYesterdaySupplements(using: viewModel)
                } label: {
                    utilityActionCard(
                        title: L10n.string("Repeat Yesterday", defaultValue: "Repeat Yesterday"),
                        subtitle: L10n.string(
                            "Quickly reuse yesterday's list",
                            defaultValue: "Quickly reuse yesterday's list"
                        ),
                        systemImage: "arrow.triangle.2.circlepath.circle.fill",
                        tint: AppTheme.sage
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("supplement_log.repeat_yesterday_button")
            }

            NavigationLink {
                SupplementHistoryView()
            } label: {
                utilityActionCard(
                    title: L10n.string("View History", defaultValue: "View History"),
                    subtitle: L10n.string(
                        "Review adherence and past entries",
                        defaultValue: "Review adherence and past entries"
                    ),
                    systemImage: "clock.arrow.circlepath",
                    tint: AppTheme.accentColor,
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("supplement_log.inline_history_button")
        }
    }

    private func utilityActionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: systemImage)
                .appFont(.title3)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .appFont(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .cardStyle()
    }

    @ViewBuilder
    private func todaysSupplementsSection(viewModel: SupplementViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            AppTheme.sectionHeader("Today's Supplements")

            if todaysLogs.isEmpty {
                VStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "pill")
                        .appFont(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No supplements logged today")
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap the button below to add your first supplement.")
                        .appFont(.caption)
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
                refreshSupplementState()
            } label: {
                Image(systemName: log.taken ? "checkmark.circle.fill" : "circle")
                    .appFont(.title2)
                    .foregroundStyle(log.taken ? AppTheme.sage : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(log.supplementName)
                    .appFont(.subheadline, weight: .medium)
                    .strikethrough(!log.taken, color: .secondary)

                HStack(spacing: AppTheme.spacing8) {
                    if let dosage = log.dosageMg, dosage > 0 {
                        Text("\(Int(dosage)) mg")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let brand = log.brand, !brand.isEmpty {
                        Text(brand)
                            .appFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Text(log.timeTaken, style: .time)
                .appFont(.caption)
                .foregroundStyle(.secondary)

            Button {
                viewModel.deleteLog(log)
                refreshSupplementState()
                initialLogCount = todaysLogs.count
            } label: {
                Image(systemName: "trash")
                    .appFont(.caption)
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
                    .appFont(.title3)
                Text("Add Supplement")
                    .appFont(.subheadline, weight: .semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(AppTheme.accentColor))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("supplement_log.add_button")
    }

    /// Catalog + recent supplements filtered by the current search text.
    private var filteredSupplements: [SupplementSearchResult] {
        let query = supplementNameText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results: [SupplementSearchResult] = []

        // Catalog items
        let catalogMatches = query.isEmpty
            ? PCOSSupplements.catalog
            : PCOSSupplements.catalog.filter { $0.name.lowercased().contains(query) }
        for item in catalogMatches {
            results.append(.catalog(item))
        }

        // Recent custom supplements not already in catalog
        let catalogNames = Set(PCOSSupplements.catalog.map { $0.name.lowercased() })
        let recentNames = viewModel?.supplementNameSuggestions ?? []
        let customMatches = recentNames
            .filter { !catalogNames.contains($0.lowercased()) }
            .filter { query.isEmpty || $0.lowercased().contains(query) }
        for name in customMatches {
            results.append(.recent(name))
        }

        return results
    }

    private var addSupplementSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Search or type a supplement name", text: $supplementNameText)
                        .accessibilityIdentifier("supplement_log.add_sheet.search_field")
                        .focused($addSheetFocusedField, equals: .supplementName)
                        .submitLabel(.next)
                        .onSubmit { addSheetFocusedField = .dosage }
                        .autocorrectionDisabled()

                    if !filteredSupplements.isEmpty {
                        ForEach(filteredSupplements) { result in
                            Button {
                                selectSupplement(result)
                            } label: {
                                HStack(spacing: AppTheme.spacing12) {
                                    Image(systemName: result.isCatalog ? "pill.fill" : "clock.arrow.circlepath")
                                        .appFont(.caption)
                                        .foregroundStyle(result.isCatalog ? AppTheme.accentColor : .secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .appFont(.subheadline)
                                            .foregroundStyle(.primary)
                                        if let description = result.catalogDescription {
                                            Text(description)
                                                .appFont(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if let dosage = result.defaultDosage, dosage > 0 {
                                        Text("\(Int(dosage)) mg")
                                            .appFont(.caption)
                                            .foregroundStyle(.tertiary)
                                    }

                                    if result.name.lowercased() == supplementNameText.lowercased() {
                                        Image(systemName: "checkmark")
                                            .appFont(.caption)
                                            .foregroundStyle(AppTheme.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Supplement")
                } footer: {
                    if let selected = selectedCatalogSupplement {
                        supplementSelectionFooter(for: selected)
                    }
                }

                Section {
                    if let selected = selectedCatalogSupplement, selected.defaultDosageMg > 0 {
                        HStack {
                            Text(viewModel?.recommendedDosageLabel(for: selected) ?? "")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if dosageText != viewModel?.recommendedDosageValue(for: selected) {
                                Button(L10n.string("Use recommended", defaultValue: "Use recommended")) {
                                    dosageText = viewModel?.recommendedDosageValue(for: selected) ?? ""
                                }
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.accentColor)
                            }
                        }
                    }

                    HStack(spacing: AppTheme.spacing8) {
                        TextField("Dosage", text: $dosageText)
                            .keyboardType(.decimalPad)
                            .focused($addSheetFocusedField, equals: .dosage)
                        Text("mg")
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.spacing8) {
                            ForEach(["30", "200", "400", "500", "600", "1000", "2000", "4000"], id: \.self) { amount in
                                ChipButton(title: "\(amount) mg", color: AppTheme.sage) {
                                    dosageText = amount
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    TextField("Brand (optional)", text: $brandText)
                        .focused($addSheetFocusedField, equals: .brand)
                        .submitLabel(.done)

                    if let viewModel, !viewModel.supplementBrandSuggestions.isEmpty {
                        Text("Recent brands")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.spacing8) {
                                ForEach(viewModel.supplementBrandSuggestions, id: \.self) { suggestion in
                                    ChipButton(title: suggestion, color: AppTheme.sage) {
                                        brandText = suggestion
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Details")
                }

                Section("Time Taken") {
                    DatePicker("Time", selection: $scheduledTime, displayedComponents: [.hourAndMinute, .date])

                    if let viewModel, viewModel.hasPreferredSupplementTime {
                        Button {
                            scheduledTime = viewModel.preferredSupplementTime
                        } label: {
                            Label("Same as yesterday", systemImage: "clock.arrow.circlepath")
                                .appFont(.caption)
                                .foregroundStyle(AppTheme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(L10n.string("Add Supplement", defaultValue: "Add Supplement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        if hasUnsavedAddFormChanges {
                            addFormAlert = .discard
                        } else {
                            showAddSheet = false
                        }
                    }
                    .accessibilityIdentifier("supplement_log.add_sheet.cancel_button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Save", defaultValue: "Save")) {
                        saveSupplement()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if addSheetFocusedField == .supplementName {
                        Button(L10n.string("Next", defaultValue: "Next")) { addSheetFocusedField = .dosage }
                    } else if addSheetFocusedField == .dosage {
                        Button(L10n.string("Next", defaultValue: "Next")) { addSheetFocusedField = .brand }
                    }
                    Spacer()
                    Button(L10n.string("Done", defaultValue: "Done")) { addSheetFocusedField = nil }
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
            .sensoryFeedback(.selection, trigger: selectedCatalogSupplement)
            .sheet(item: $activeDisclosure) { disclosure in
                EvidenceDisclosureSheet(content: disclosure, language: appState.selectedAppLanguage)
            }
        }
    }

    private func supplementSelectionFooter(for supplement: PCOSSupplement) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(supplement.description)

            HStack(spacing: AppTheme.spacing8) {
                Text(
                    L10n.string(
                        "Evidence strength",
                        defaultValue: "Evidence strength",
                        language: appState.selectedAppLanguage
                    )
                )
                    .appFont(.caption)
                    .foregroundStyle(.secondary)

                Text(supplement.evidenceStrength.displayName)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.accentColor)
            }

            Button(
                L10n.string(
                    "Sources",
                    defaultValue: "Sources",
                    language: appState.selectedAppLanguage
                )
            ) {
                activeDisclosure = InsightEvidenceCatalog.disclosure(
                    for: supplement,
                    language: appState.selectedAppLanguage
                )
            }
            .buttonStyle(.plain)
            .appFont(.caption, weight: .semibold)
            .foregroundStyle(AppTheme.accentColor)
            .accessibilityIdentifier("supplement_log.catalog.\(supplement.key).sources_button")
        }
        .padding(.top, AppTheme.spacing4)
    }

    private func selectSupplement(_ result: SupplementSearchResult) {
        supplementNameText = result.name
        if case .catalog(let supplement) = result {
            selectedCatalogSupplement = supplement
            if supplement.defaultDosageMg > 0 {
                dosageText = viewModel?.recommendedDosageValue(for: supplement) ?? ""
            }
        } else {
            selectedCatalogSupplement = nil
        }
        addSheetFocusedField = .dosage
    }

    private var resolvedName: String {
        supplementNameText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            supplementNameText: supplementNameText,
            dosageText: dosageText,
            brandText: brandText,
            scheduledTime: scheduledTime
        )
    }

    private func resetAddForm() {
        guard let viewModel else {
            selectedCatalogSupplement = nil
            supplementNameText = ""
            dosageText = ""
            brandText = ""
            scheduledTime = Date()
            addFormDirtyTracker = FormDirtyTracker(initial: addFormSnapshot)
            return
        }

        viewModel.reset()
        selectedCatalogSupplement = nil
        supplementNameText = viewModel.supplementName
        dosageText = viewModel.dosageText
        brandText = viewModel.brand
        scheduledTime = viewModel.scheduledTime
        addFormDirtyTracker = FormDirtyTracker(initial: addFormSnapshot)
    }

    private func refreshSupplementState() {
        todaysLogs = viewModel?.fetchTodaysLogs() ?? []
        canRepeatYesterday = viewModel?.hasYesterdayLogs() ?? false
    }

    private func repeatYesterdaySupplements(using viewModel: SupplementViewModel) {
        do {
            let insertedCount = try viewModel.repeatYesterdaySupplements()
            refreshSupplementState()
            initialLogCount = todaysLogs.count
            if insertedCount > 0 {
                saveCoordinator.showSuccessTransient()
            }
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                String(
                    localized: "Could not repeat supplements: \(error.localizedDescription)",
                    comment: "Error shown when yesterday's supplements could not be repeated."
                )
            )
        }
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
            refreshSupplementState()
            initialLogCount = todaysLogs.count
            saveCoordinator.showSuccessTransient()
        } catch {
            saveCoordinator.showErrorFeedback()
            activeAlert = .error(
                String(
                    localized: "Could not save supplement: \(error.localizedDescription)",
                    comment: "Error shown when a supplement log cannot be saved."
                )
            )
        }
    }
}

// MARK: - Supplement Search Result

private enum SupplementSearchResult: Identifiable {
    case catalog(PCOSSupplement)
    case recent(String)

    var id: String {
        switch self {
        case .catalog(let s): "catalog.\(s.name)"
        case .recent(let n): "recent.\(n)"
        }
    }

    var name: String {
        switch self {
        case .catalog(let s): s.name
        case .recent(let n): n
        }
    }

    var isCatalog: Bool {
        if case .catalog = self { return true }
        return false
    }

    var catalogDescription: String? {
        if case .catalog(let s) = self { return s.description }
        return nil
    }

    var defaultDosage: Double? {
        if case .catalog(let s) = self { return s.defaultDosageMg }
        return nil
    }
}

extension PCOSSupplement: Equatable {
    static func == (lhs: PCOSSupplement, rhs: PCOSSupplement) -> Bool {
        lhs.key == rhs.key
    }
}

extension PCOSSupplement: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

#Preview {
    SupplementLogView()
        .modelContainer(for: SupplementLog.self, inMemory: true)
}
