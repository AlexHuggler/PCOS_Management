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
            .navigationTitle(L10n.string("Log Ovulation Clues", defaultValue: "Log Ovulation Clues"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Save", defaultValue: "Save")) {
                        saveObservation()
                    }
                    .accessibilityIdentifier("ovulationLog.save")
                }
            }
            .task(id: selectedDate) {
                loadExistingObservation()
            }
        }
    }
}

private extension OvulationLogView {
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
