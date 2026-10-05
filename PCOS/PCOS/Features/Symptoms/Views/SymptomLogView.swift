import SwiftUI
import SwiftData

struct SymptomLogView: View {
    var initialCategory: SymptomCategory? = nil
    var initialDate: Date? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = TrackingPreferences.shared
    @State private var draft = DailyCheckInDraft(date: Date())
    @State private var original: DailyCheckInDraft?
    @State private var suggested: [SymptomType] = []
    @State private var showAllSymptoms = false
    @State private var errorMessage: String?
    @State private var showDiscard = false
    @State private var pendingDate: Date?
    @State private var feedback = SaveInteractionCoordinator()

    private var isDirty: Bool { original.map { $0 != draft } ?? false }
    private var pinned: Set<String> { Set(preferences.pinnedSymptomRawValues) }
    private var quickSymptoms: [SymptomType] {
        let pins = SymptomType.allCases.filter { pinned.contains($0.rawValue) }
        let source = pins + suggested + [.fatigue, .bloating, .cramps, .acne]
        var seen = Set<SymptomType>()
        return source.filter { seen.insert($0).inserted }.prefix(8).map { $0 }
    }
    private var allSymptoms: [SymptomType] {
        let types = initialCategory?.symptomTypes ?? SymptomType.allCases
        return types.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.string("A moment for you", defaultValue: "A moment for you"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.string("Log what feels useful. Anything you skip stays unrecorded.", defaultValue: "Log what feels useful. Anything you skip stays unrecorded."))
                        .foregroundStyle(.secondary)
                    DatePicker(L10n.string("Date", defaultValue: "Date"), selection: Binding(get: { draft.date }, set: { changeDate($0) }), in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("symptom_log.date")
                }
                Section(L10n.string("How are you feeling?", defaultValue: "How are you feeling?")) {
                    Picker(L10n.string("Mood", defaultValue: "Mood"), selection: Binding<DailyMood?>(get: { draft.mood.value }, set: { draft.mood = $0.map(CheckInChange.set) ?? .clear })) {
                        Text(L10n.string("Not recorded", defaultValue: "Not recorded")).tag(DailyMood?.none)
                        ForEach(DailyMood.allCases) { mood in Text(mood.title).tag(Optional(mood)) }
                    }
                    .accessibilityIdentifier("symptom_log.mood")
                    metricPicker("Energy", value: $draft.energy, range: 1...5)
                }
                Section {
                    ForEach(quickSymptoms, id: \.self) { type in symptomRow(type) }
                    DisclosureGroup(L10n.string("All symptoms", defaultValue: "All symptoms"), isExpanded: $showAllSymptoms) {
                        ForEach(allSymptoms, id: \.self) { type in symptomRow(type) }
                    }
                    Toggle(L10n.string("I reviewed my symptoms", defaultValue: "I reviewed my symptoms"), isOn: Binding(get: { draft.symptomsReviewed }, set: { reviewed in
                        draft.symptomsReviewed = reviewed
                        if reviewed && draft.symptoms == .untouched { draft.symptoms = .set([:]) }
                    }))
                    .accessibilityIdentifier("symptom_log.reviewed")
                    Button(L10n.string("No symptoms today", defaultValue: "No symptoms today")) {
                        draft.recordNoSymptoms()
                    }
                    .accessibilityIdentifier("symptom_log.no_symptoms")
                } header: {
                    Text(L10n.string("Symptoms", defaultValue: "Symptoms"))
                } footer: {
                    Text(L10n.string("Pin the symptoms you use often. Mood does not add a clinical symptom. Bleeding can be recorded in your period log.", defaultValue: "Pin the symptoms you use often. Mood does not add a clinical symptom. Bleeding can be recorded in your period log."))
                }
                Section(L10n.string("More about your day", defaultValue: "More about your day")) {
                    metricPicker("Pain", value: $draft.pain, range: 0...10)
                    metricPicker("Stress", value: $draft.stress, range: 1...5)
                    HStack {
                        Text(preferences.bodyMeasurementStyle == .metric ? L10n.string("Water (mL)", defaultValue: "Water (mL)") : L10n.string("Water (oz)", defaultValue: "Water (oz)"))
                        Spacer()
                        TextField(L10n.string("Not recorded", defaultValue: "Not recorded"), value: Binding<Int?>(get: { draft.water.value.map { preferences.bodyMeasurementStyle.water(fromOunces: $0) } }, set: { draft.water = $0.map { .set(preferences.bodyMeasurementStyle.ounces(fromWater: $0)) } ?? .clear }), format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("symptom_log.water")
                    }
                    TextField(L10n.string("Private note (optional)", defaultValue: "Private note (optional)"), text: Binding(get: { draft.note.value ?? "" }, set: { draft.note = $0.isEmpty ? .clear : .set($0) }), axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("symptom_log.note")
                }
                if feedback.isShowingSavedFeedback {
                    Label(L10n.string("Check-in saved", defaultValue: "Check-in saved"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accentColor)
                        .accessibilityIdentifier("symptom_log.saved")
                }
            }
            .tint(AppTheme.accentColor)
            .navigationTitle(L10n.string("Daily check-in", defaultValue: "Daily check-in"))
            .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        if isDirty { pendingDate = nil; showDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Save", defaultValue: "Save"), action: save)
                        .fontWeight(.semibold)
                        .disabled(original == nil || !isDirty || feedback.isShowingSavedFeedback)
                        .accessibilityIdentifier("symptom_log.save_button")
                }
            }
            .interactiveDismissDisabled(isDirty)
            .task { if original == nil { load(date: initialDate ?? draft.date) } }
            .onDisappear { feedback.cancelPending() }
            .alert(L10n.string("Unable to save check-in", defaultValue: "Unable to save check-in"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(L10n.string("OK", defaultValue: "OK"), role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog(L10n.string("Discard unsaved changes?", defaultValue: "Discard unsaved changes?"), isPresented: $showDiscard, titleVisibility: .visible) {
                Button(L10n.string("Discard changes", defaultValue: "Discard changes"), role: .destructive) {
                    if let date = pendingDate { load(date: date); pendingDate = nil } else { dismiss() }
                }
                Button(L10n.string("Keep editing", defaultValue: "Keep editing"), role: .cancel) { pendingDate = nil }
            }
        }
    }

    private func metricPicker(_ title: String, value: Binding<CheckInChange<Int>>, range: ClosedRange<Int>) -> some View {
        Picker(L10n.string(title, defaultValue: title), selection: Binding<Int?>(get: { value.wrappedValue.value }, set: { value.wrappedValue = $0.map(CheckInChange.set) ?? .clear })) {
            Text(L10n.string("Not recorded", defaultValue: "Not recorded")).tag(Int?.none)
            ForEach(Array(range), id: \.self) { number in Text("\(number)").tag(Optional(number)) }
        }
        .accessibilityIdentifier("symptom_log.\(title.lowercased())")
    }

    private func symptomRow(_ type: SymptomType) -> some View {
        HStack {
            Button {
                var values = pinned
                if values.contains(type.rawValue) { values.remove(type.rawValue) } else { values.insert(type.rawValue) }
                preferences.pinnedSymptomRawValues = values.sorted()
            } label: {
                Image(systemName: pinned.contains(type.rawValue) ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.format("Pin %@", defaultValue: "Pin %@", type.displayName))
            .accessibilityAddTraits(pinned.contains(type.rawValue) ? .isSelected : [])
            Picker(type.displayName, selection: Binding<Int>(get: { draft.symptoms.value?[type] ?? 0 }, set: { severity in
                var values = draft.symptoms.value ?? [:]
                if severity == 0 { values.removeValue(forKey: type) } else { values[type] = severity }
                draft.symptoms = .set(values)
                draft.symptomsReviewed = true
            })) {
                Text(L10n.string("Not selected", defaultValue: "Not selected")).tag(0)
                ForEach(1...5, id: \.self) { severity in Text("\(severity)").tag(severity) }
            }
        }
    }

    private func changeDate(_ date: Date) {
        guard !Calendar.current.isDate(date, inSameDayAs: draft.date) else { return }
        if isDirty { pendingDate = date; showDiscard = true } else { load(date: date) }
    }

    private func load(date: Date) {
        do {
            draft = try DailyCheckInService(modelContext: modelContext).load(on: date)
            original = draft
            suggested = SymptomViewModel(modelContext: modelContext).frequentSymptoms()
        } catch { errorMessage = L10n.string("Your check-in could not be loaded. Please try again.", defaultValue: "Your check-in could not be loaded. Please try again.") }
    }

    private func save() {
        do {
            let changes = original.map { draft.changes(since: $0) } ?? draft
            try DailyCheckInService(modelContext: modelContext).save(changes)
            original = draft
            CheckInAnalytics.recordSave(source: .sheet)
            feedback.showSuccessAndDismiss { dismiss() }
        } catch {
            feedback.showErrorFeedback()
            errorMessage = L10n.string("Your check-in was not saved. Please check your entries and try again.", defaultValue: "Your check-in was not saved. Please check your entries and try again.")
        }
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(chipFill)
                )
                .overlay(chipBorder)
                .foregroundStyle(chipForeground)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var chipFill: Color {
        if isSelected, AppTheme.usesPremiumEditorStyling {
            AppTheme.premiumEditorRaisedSurface.opacity(0.96)
        } else if isSelected {
            AppTheme.accentColor
        } else if AppTheme.usesPremiumEditorStyling {
            AppTheme.premiumEditorSurface.opacity(0.9)
        } else {
            Color(.tertiarySystemFill)
        }
    }

    private var chipForeground: Color {
        if isSelected, AppTheme.usesPremiumEditorStyling {
            AppTheme.premiumEditorAccentColor
        } else if isSelected {
            .white
        } else {
            AppTheme.primaryText
        }
    }

    @ViewBuilder
    private var chipBorder: some View {
        if isSelected, AppTheme.usesPremiumEditorStyling {
            Capsule().strokeBorder(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
        } else {
            Capsule().strokeBorder(Color.clear, lineWidth: 0)
        }
    }
}

// MARK: - Skeleton Card
