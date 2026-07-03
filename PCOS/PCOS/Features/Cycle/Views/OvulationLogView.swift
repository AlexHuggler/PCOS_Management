import SwiftUI
import SwiftData

struct OvulationLogView: View {
    private enum TemperatureUnit: String, CaseIterable, Identifiable {
        case fahrenheit
        case celsius

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .fahrenheit:
                L10n.string("Fahrenheit", defaultValue: "Fahrenheit")
            case .celsius:
                L10n.string("Celsius", defaultValue: "Celsius")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDate: Date
    @State private var temperatureInput = ""
    @State private var temperatureUnit: TemperatureUnit = .fahrenheit
    @State private var cervicalMucus: CervicalMucusType = .notObserved
    @State private var lhTestResult: LHTestResult = .notTested
    @State private var notes = ""
    @State private var errorMessage: String?

    init(initialDate: Date = Date()) {
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Group {
                if AppTheme.usesPremiumEditorStyling {
                    lunarOvulationContent
                } else {
                    standardOvulationForm
                }
            }
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Log Ovulation Clues", defaultValue: "Log Ovulation Clues"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.ovulation_log")
            .background {
                if AppTheme.usesPremiumEditorStyling {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                }
            }
            .toolbar {
                if AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .principal) {
                        Text(L10n.string("Ovulation clues", defaultValue: "Ovulation clues"))
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        if AppTheme.usesPremiumEditorStyling {
                            Image(systemName: "xmark")
                        } else {
                            Text(L10n.string("Cancel", defaultValue: "Cancel"))
                        }
                    }
                    .accessibilityLabel(L10n.string("Cancel", defaultValue: "Cancel"))
                }

                if !AppTheme.usesPremiumEditorStyling {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.string("Save", defaultValue: "Save")) {
                            saveObservation()
                        }
                        .accessibilityIdentifier("ovulationLog.save")
                    }
                }
            }
            .task(id: selectedDate) {
                loadExistingObservation()
            }
        }
    }
}

private extension OvulationLogView {
    var standardOvulationForm: some View {
        Form {
            Section(L10n.string("Timing", defaultValue: "Timing")) {
                DatePicker(
                    L10n.string("Date", defaultValue: "Date"),
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .accessibilityIdentifier("ovulationLog.date")
            }

            Section(L10n.string("Signals", defaultValue: "Signals")) {
                TextField(
                    L10n.string("Basal body temperature", defaultValue: "Basal body temperature"),
                    text: $temperatureInput
                )
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("ovulationLog.temperature")

                Picker(
                    L10n.string("Temperature unit", defaultValue: "Temperature unit"),
                    selection: $temperatureUnit
                ) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.displayName)
                            .tag(unit)
                    }
                }

                Picker(
                    L10n.string("Cervical mucus", defaultValue: "Cervical mucus"),
                    selection: $cervicalMucus
                ) {
                    ForEach(CervicalMucusType.allCases) { type in
                        Text(type.displayName)
                            .tag(type)
                    }
                }

                Picker(
                    L10n.string("LH test", defaultValue: "LH test"),
                    selection: $lhTestResult
                ) {
                    ForEach(LHTestResult.allCases) { result in
                        Text(result.displayName)
                            .tag(result)
                    }
                }
            }

            Section(L10n.string("Notes", defaultValue: "Notes")) {
                TextEditor(text: $notes)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("ovulationLog.notes")
            }

            Section {
                Text(
                    L10n.string(
                        "CycleBalance uses these fertility clues to narrow fertile-window estimates without assuming every cycle ovulates the same way.",
                        defaultValue: "CycleBalance uses these fertility clues to narrow fertile-window estimates without assuming every cycle ovulates the same way."
                    )
                )
                .appFont(.caption)
                .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .appFont(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    var lunarOvulationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                lunarHeader
                lunarDateCard
                lunarClueGrid
                lunarTemperatureCard
                lunarNotesCard
                lunarInsightCard

                if let errorMessage {
                    Text(errorMessage)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                        .padding(AppTheme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lunarOvulationCard()
                }

                lunarSavePanel
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.top, AppTheme.spacing8)
            .padding(.bottom, AppTheme.spacing24)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ovulation_log.lunar.surface")
    }

    var lunarHeader: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Track ovulation clues", defaultValue: "Track ovulation clues"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(L10n.string("Log signals gently. Patterns can matter even when cycles vary.", defaultValue: "Log signals gently. Patterns can matter even when cycles vary."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: "moon.stars.fill")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 52, height: 52)
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.22), radius: 16, y: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ovulation_log.lunar.header")
    }

    var lunarDateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Observation date", defaultValue: "Observation date"), systemImage: "calendar")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            Text(selectedDate.formatted(.dateTime.month(.wide).day().year()))
                .appHeadingFont(.title3, weight: .regular)
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            DatePicker(
                L10n.string("Date", defaultValue: "Date"),
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .tint(AppTheme.premiumEditorAccentColor)
            .foregroundStyle(AppTheme.primaryText)
            .accessibilityIdentifier("ovulationLog.date")
        }
        .padding(AppTheme.spacing12)
        .lunarOvulationCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ovulation_log.lunar.date_card")
    }

    var lunarClueGrid: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Clues", defaultValue: "Clues"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            lunarLHCard
            lunarMucusCard
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ovulation_log.lunar.clue_grid")
    }

    var lunarLHCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Label(L10n.string("LH test", defaultValue: "LH test"), systemImage: "scope")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(lhTestResult.displayName)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
            }

            LazyVGrid(columns: lunarLHOptionColumns, spacing: AppTheme.spacing8) {
                ForEach(LHTestResult.allCases) { result in
                    lunarOptionButton(
                        title: result.displayName,
                        icon: lhIcon(for: result),
                        isSelected: result == lhTestResult,
                        selectedIdentifier: "ovulation_log.lunar.lh.\(result.rawValue)"
                    ) {
                        lhTestResult = result
                    }
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarOvulationCard()
    }

    var lunarMucusCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Label(L10n.string("Cervical mucus", defaultValue: "Cervical mucus"), systemImage: "drop.degreesign")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(cervicalMucus.displayName)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
            }

            LazyVGrid(columns: lunarOptionColumns, spacing: AppTheme.spacing8) {
                ForEach(CervicalMucusType.allCases) { type in
                    lunarOptionButton(
                        title: type.displayName,
                        icon: mucusIcon(for: type),
                        isSelected: type == cervicalMucus,
                        selectedIdentifier: "ovulation_log.lunar.mucus.\(type.rawValue)"
                    ) {
                        cervicalMucus = type
                    }
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarOvulationCard()
    }

    var lunarTemperatureCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack {
                Label(L10n.string("Basal temperature", defaultValue: "Basal temperature"), systemImage: "thermometer.medium")
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text(temperatureUnit.displayName)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            TextField(
                L10n.string("Basal body temperature", defaultValue: "Basal body temperature"),
                text: $temperatureInput
            )
            .appFont(.body)
            .keyboardType(.decimalPad)
            .textInputAutocapitalization(.never)
            .foregroundStyle(AppTheme.primaryText)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )
            .accessibilityIdentifier("ovulationLog.temperature")

            HStack(spacing: AppTheme.spacing8) {
                ForEach(TemperatureUnit.allCases) { unit in
                    Button {
                        temperatureUnit = unit
                    } label: {
                        Text(unit.displayName)
                            .appFont(.subheadline, weight: temperatureUnit == unit ? .semibold : .regular)
                            .foregroundStyle(temperatureUnit == unit ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacing8)
                            .background(
                            Capsule()
                                    .fill(temperatureUnit == unit ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorSurface.opacity(0.88)))
                            )
                            .overlay(
                            Capsule()
                                    .stroke(temperatureUnit == unit ? AppTheme.premiumEditorAccentColor.opacity(0.45) : AppTheme.premiumEditorBorder.opacity(0.52), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(temperatureUnit == unit ? .isSelected : [])
                    .accessibilityIdentifier("ovulation_log.lunar.temperature_unit.\(unit.rawValue)")
                }
            }
        }
        .padding(AppTheme.spacing12)
        .lunarOvulationCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ovulation_log.lunar.temperature")
    }

    var lunarNotesCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label(L10n.string("Notes (optional)", defaultValue: "Notes (optional)"), systemImage: "sparkles")
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            TextField(
                L10n.string("What did you notice?", defaultValue: "What did you notice?"),
                text: $notes,
                axis: .vertical
            )
            .appFont(.body)
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(3...6)
            .submitLabel(.done)
            .textInputAutocapitalization(.sentences)
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
            )
            .accessibilityIdentifier("ovulationLog.notes")
        }
        .padding(AppTheme.spacing12)
        .lunarOvulationCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ovulation_log.lunar.notes")
    }

    var lunarInsightCard: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "waveform.path.ecg")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorAccentGradient)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("No single clue has to be perfect.", defaultValue: "No single clue has to be perfect."))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Text(L10n.string("CycleBalance combines LH, mucus, temperature, and notes to refine estimates over time.", defaultValue: "CycleBalance combines LH, mucus, temperature, and notes to refine estimates over time."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarOvulationCard()
    }

    var lunarSavePanel: some View {
        VStack(spacing: AppTheme.spacing8) {
            Button(action: saveObservation) {
                Text(L10n.string("Save ovulation clues", defaultValue: "Save ovulation clues"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing16)
                    .background(Capsule().fill(AppTheme.premiumEditorAccentGradient))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ovulationLog.save")

            Text(L10n.string("Private by default. Edit these clues anytime.", defaultValue: "Private by default. Edit these clues anytime."))
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ovulation_log.lunar.save_button")
    }

    var lunarOptionColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 96), spacing: AppTheme.spacing8)
        ]
    }

    var lunarLHOptionColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: AppTheme.spacing8),
            GridItem(.flexible(minimum: 0), spacing: AppTheme.spacing8)
        ]
    }

    func lunarOptionButton(
        title: String,
        icon: String,
        isSelected: Bool,
        selectedIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: icon)
                    .appFont(.caption, weight: .semibold)
                    .frame(width: 18)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)

                Text(title)
                    .appFont(.caption, weight: isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppTheme.spacing8)
            .padding(.vertical, AppTheme.spacing8)
            .foregroundStyle(isSelected ? AppTheme.premiumEditorAccentColor : AppTheme.primaryText)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(AppTheme.premiumEditorRaisedSurface.opacity(0.96))
                            : AnyShapeStyle(AppTheme.premiumEditorSurface.opacity(0.88))
                    )
            )
            .overlay(
                Group {
                    if isSelected {
                        Capsule()
                            .strokeBorder(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
                    } else {
                        Capsule()
                            .strokeBorder(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(selectedIdentifier)
    }

    func lhIcon(for result: LHTestResult) -> String {
        switch result {
        case .notTested:
            "minus.circle"
        case .negative:
            "checkmark.circle"
        case .high:
            "arrow.up.circle"
        case .peak:
            "sparkle.magnifyingglass"
        }
    }

    func mucusIcon(for type: CervicalMucusType) -> String {
        switch type {
        case .notObserved:
            "minus.circle"
        case .dry:
            "sun.min"
        case .sticky:
            "circle.hexagongrid"
        case .creamy:
            "cloud"
        case .watery:
            "drop"
        case .eggWhite:
            "sparkles"
        }
    }

    func loadExistingObservation() {
        do {
            let store = OvulationObservationStore(modelContext: modelContext)
            let observation = try store.observation(on: selectedDate)
            if let observation {
                if let basalBodyTemperatureCelsius = observation.basalBodyTemperatureCelsius {
                    let displayTemperature = temperatureUnit == .fahrenheit
                        ? (basalBodyTemperatureCelsius * 9 / 5) + 32
                        : basalBodyTemperatureCelsius
                    temperatureInput = String(format: "%.2f", displayTemperature)
                } else {
                    temperatureInput = ""
                }
                cervicalMucus = observation.cervicalMucus ?? .notObserved
                lhTestResult = observation.lhTestResult ?? .notTested
                notes = observation.notes ?? ""
            } else {
                temperatureInput = ""
                cervicalMucus = .notObserved
                lhTestResult = .notTested
                notes = ""
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveObservation() {
        do {
            let store = OvulationObservationStore(modelContext: modelContext)
            try store.upsertObservation(
                date: selectedDate,
                basalBodyTemperatureCelsius: normalizedTemperatureCelsius(),
                cervicalMucus: cervicalMucus,
                lhTestResult: lhTestResult,
                notes: notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func normalizedTemperatureCelsius() throws -> Double? {
        let trimmed = temperatureInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let rawValue = Double(trimmed) else {
            throw OvulationLogError.invalidTemperature
        }

        switch temperatureUnit {
        case .fahrenheit:
            guard (95...101.5).contains(rawValue) else {
                throw OvulationLogError.temperatureOutOfRange
            }
            return (rawValue - 32) * 5 / 9
        case .celsius:
            guard (35...39).contains(rawValue) else {
                throw OvulationLogError.temperatureOutOfRange
            }
            return rawValue
        }
    }
}

private extension View {
    func lunarOvulationCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.8)
                .opacity(0.72)
        )
        .shadow(color: AppTheme.cardShadowColor.opacity(AppTheme.usesPremiumEditorStyling ? 1.0 : 0.8), radius: 14, y: 8)
    }
}

private enum OvulationLogError: LocalizedError {
    case invalidTemperature
    case temperatureOutOfRange

    var errorDescription: String? {
        switch self {
        case .invalidTemperature:
            L10n.string("Enter your basal temperature as a number.", defaultValue: "Enter your basal temperature as a number.")
        case .temperatureOutOfRange:
            L10n.string("Basal temperature looks out of range. Double-check the unit and try again.", defaultValue: "Basal temperature looks out of range. Double-check the unit and try again.")
        }
    }
}

#Preview {
    OvulationLogView()
        .modelContainer(for: [OvulationObservation.self], inMemory: true)
}
