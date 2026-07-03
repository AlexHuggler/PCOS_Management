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

    private var supplementAccent: Color {
        AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.sage
    }

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
            ZStack {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    if let viewModel {
                        ScrollView {
                            VStack(spacing: AppTheme.spacing16) {
                                if AppTheme.usesPremiumEditorStyling {
                                    lunarSupplementHeader
                                }
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
                                    if AppTheme.usesPremiumEditorStyling {
                                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                                            .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.76))
                                            .frame(height: 108)
                                            .redacted(reason: .placeholder)
                                    } else {
                                        SkeletonListRow()
                                            .cardStyle()
                                    }
                                }
                                if !AppTheme.usesPremiumEditorStyling {
                                    SkeletonRing()
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .accessibilityIdentifier("screen.supplement_log")
            .background(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : Color.clear)
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Log Supplements", defaultValue: "Log Supplements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Supplement rhythm", defaultValue: "Supplement rhythm"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
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
            .lunarSupplementNavigationBackground()
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

    private var lunarSupplementHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Support your routine", defaultValue: "Support your routine"))
                        .appFont(.largeTitle, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.string(
                        "Track doses, timing, and consistency without turning your supplement routine into a scorecard.",
                        defaultValue: "Track doses, timing, and consistency without turning your supplement routine into a scorecard."
                    ))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                Image(systemName: "pills.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                    .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.24), radius: 16, y: 8)
            }

            HStack(spacing: AppTheme.spacing8) {
                lunarSummaryPill(
                    title: L10n.string("Today", defaultValue: "Today"),
                    value: "\(todaysLogs.count)",
                    systemImage: "calendar.badge.clock"
                )
                lunarSummaryPill(
                    title: L10n.string("Taken", defaultValue: "Taken"),
                    value: "\(todaysLogs.filter(\.taken).count)",
                    systemImage: "checkmark.seal.fill"
                )
                lunarSummaryPill(
                    title: L10n.string("Remaining", defaultValue: "Remaining"),
                    value: "\(todaysLogs.filter { !$0.taken }.count)",
                    systemImage: "moon.zzz.fill"
                )
            }
        }
        .padding(AppTheme.spacing16)
        .lunarSupplementCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("supplement_log.lunar.header")
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
        Group {
            if AppTheme.usesPremiumEditorStyling {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(tint.opacity(0.14)))

                        Spacer()

                        if showsDisclosure {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(title)
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        Text(subtitle)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            } else {
                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: systemImage)
                        .appFont(.title3)
                        .foregroundStyle(tint)

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(title)
                            .appFont(.headline)
                            .foregroundStyle(Color.primary)

                        Text(subtitle)
                            .appFont(.caption)
                            .foregroundStyle(Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if showsDisclosure {
                        Image(systemName: "chevron.right")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing12 : 0)
        .lunarSupplementCard()
    }

    @ViewBuilder
    private func todaysSupplementsSection(viewModel: SupplementViewModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            if AppTheme.usesPremiumEditorStyling {
                lunarSectionHeader(
                    title: L10n.string("Today's supplements", defaultValue: "Today's supplements"),
                    subtitle: L10n.string("Tap a dose to mark it taken", defaultValue: "Tap a dose to mark it taken"),
                    systemImage: "list.bullet.clipboard.fill"
                )
            } else {
                AppTheme.sectionHeader("Today's Supplements")
            }

            if todaysLogs.isEmpty {
                VStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "pill")
                        .appFont(.largeTitle)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : Color(.tertiaryLabel))
                    Text(L10n.string("No supplements logged today", defaultValue: "No supplements logged today"))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.primaryText : Color.secondary)
                    Text(L10n.string("Tap the button below to add your first supplement.", defaultValue: "Tap the button below to add your first supplement."))
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.secondaryText : Color(.tertiaryLabel))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacing24)
                .lunarSupplementCard()
                .accessibilityIdentifier("supplement_log.lunar.empty")
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
                    .foregroundStyle(log.taken ? supplementAccent : AppTheme.secondaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(log.supplementName)
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(AppTheme.primaryText)
                    .strikethrough(!log.taken, color: AppTheme.secondaryText)

                HStack(spacing: AppTheme.spacing8) {
                    if let dosage = log.dosageMg, dosage > 0 {
                        Text("\(Int(dosage)) mg")
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    if let brand = log.brand, !brand.isEmpty {
                        Text(brand)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.72))
                    }
                }
            }

            Spacer()

            Text(log.timeTaken, style: .time)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            Button {
                viewModel.deleteLog(log)
                refreshSupplementState()
                initialLogCount = todaysLogs.count
            } label: {
                Image(systemName: "trash")
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorWarningAccentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, AppTheme.spacing8)
        .padding(.horizontal, AppTheme.spacing12)
        .lunarSupplementCard()
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
                Text(L10n.string("Add Supplement", defaultValue: "Add Supplement"))
                    .appFont(.subheadline, weight: .semibold)
            }
            .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorCTAForeground : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(AppTheme.usesPremiumEditorStyling ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.accentColor))
            )
            .overlay {
                if AppTheme.usesPremiumEditorStyling {
                    Capsule()
                        .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.8)
                }
            }
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
            .scrollContentBackground(AppTheme.usesPremiumEditorStyling ? .hidden : .automatic)
            .background(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : Color.clear)
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Add Supplement", defaultValue: "Add Supplement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Add supplement", defaultValue: "Add supplement"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
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
            .lunarSupplementNavigationBackground()
            .accessibilityIdentifier("supplement_log.add_sheet")
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

    private func lunarSummaryPill(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.spacing8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(supplementAccent)
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

    private func lunarSectionHeader(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(supplementAccent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(supplementAccent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Supplement Search Result

private extension View {
    @ViewBuilder
    func lunarSupplementNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func lunarSupplementCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
        if AppTheme.usesPremiumEditorStyling {
            background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                                AppTheme.premiumEditorSurface.opacity(0.78),
                                AppTheme.premiumEditorBackground.opacity(0.9)
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
