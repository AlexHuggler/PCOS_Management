import SwiftUI

struct PersonalizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var appearance = AppearancePreferences.shared
    @State private var tracking = TrackingPreferences.shared

    var body: some View {
        Form {
            Section(L10n.string("Appearance", defaultValue: "Appearance")) {
                Picker(L10n.string("Theme", defaultValue: "Theme"), selection: $appearance.themeOption) {
                    ForEach([ThemeOption.calm, .lunarCalm, .botanicalJournal]) { theme in Text(theme.displayName).tag(theme) }
                }
                Picker(L10n.string("Color mode", defaultValue: "Color mode"), selection: $appearance.colorMode) {
                    ForEach(AppearanceColorMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Picker(L10n.string("Information detail", defaultValue: "Information detail"), selection: $tracking.informationDetail) {
                    ForEach(InformationDetail.allCases) { detail in Text(detail.title).tag(detail) }
                }
            }
            Section {
                ForEach(tracking.favoriteActions) { action in
                    Label(action.title, systemImage: action.systemImage)
                }
                .onMove { source, destination in
                    var ordered = tracking.favoriteActions
                    ordered.move(fromOffsets: source, toOffset: destination)
                    tracking.favoriteActions = ordered
                }
                DisclosureGroup(L10n.string("Available actions", defaultValue: "Available actions")) {
                ForEach(LoggerShortcut.allCases) { action in
                    Toggle(action.title, isOn: favoriteBinding(action))
                        .disabled(!tracking.favoriteActions.contains(action) && tracking.favoriteActions.count >= 3)
                }
                }
            } header: {
                Text(L10n.string("Favorite actions", defaultValue: "Favorite actions"))
            } footer: {
                Text(L10n.string("Choose up to three. Tap Edit to change their order. Premium actions keep their existing access requirements.", defaultValue: "Choose up to three. Tap Edit to change their order. Premium actions keep their existing access requirements."))
            }
            Section {
                ForEach(tracking.visibleCards) { card in Text(card.title) }
                    .onMove { source, destination in
                        var ordered = tracking.visibleCards
                        ordered.move(fromOffsets: source, toOffset: destination)
                        tracking.visibleCards = ordered
                    }
                DisclosureGroup(L10n.string("Available cards", defaultValue: "Available cards")) {
                ForEach(TodayCard.allCases) { card in
                    Toggle(card.title, isOn: cardBinding(card))
                }
                }
            } header: {
                Text(L10n.string("Today cards", defaultValue: "Today cards"))
            } footer: {
                Text(L10n.string("Choose what appears on Today. Tap Edit to reorder visible cards.", defaultValue: "Choose what appears on Today. Tap Edit to reorder visible cards."))
            }
            Section(L10n.string("Pinned symptoms", defaultValue: "Pinned symptoms")) {
                DisclosureGroup(L10n.string("Choose pinned symptoms", defaultValue: "Choose pinned symptoms")) {
                ForEach(SymptomType.allCases) { symptom in
                    Toggle(symptom.displayName, isOn: Binding(
                        get: { tracking.pinnedSymptomRawValues.contains(symptom.rawValue) },
                        set: { selected in
                            var values = tracking.pinnedSymptomRawValues.filter { $0 != symptom.rawValue }
                            if selected { values.append(symptom.rawValue) }
                            tracking.pinnedSymptomRawValues = values
                        }
                    ))
                }
                }
            }
            Section {
                Picker(L10n.string("Weight & water units", defaultValue: "Weight & water units"), selection: $tracking.bodyMeasurementStyle) {
                    ForEach(BodyMeasurementStyle.allCases) { units in Text(units.title).tag(units) }
                }
                Toggle(L10n.string("Show weight", defaultValue: "Show weight"), isOn: $tracking.showWeight)
                Toggle(L10n.string("Show nutrition numbers", defaultValue: "Show nutrition numbers"), isOn: $tracking.showNutritionNumbers)
                Toggle(L10n.string("Show fertility context", defaultValue: "Show fertility context"), isOn: $tracking.showFertility)
            } header: {
                Text(L10n.string("Optional context", defaultValue: "Optional context"))
            } footer: {
                Text(L10n.string("Hiding a topic does not delete your records.", defaultValue: "Hiding a topic does not delete your records."))
            }
            Section(L10n.string("About you", defaultValue: "About you")) {
                CompanionProfileFields(profile: appState.onboardingProfile)
            }
        }
        .navigationTitle(L10n.string("Make it yours", defaultValue: "Make it yours"))
        .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
            ToolbarItem(placement: .confirmationAction) { Button(L10n.string("Done", defaultValue: "Done")) { dismiss() } }
        }
        .accessibilityIdentifier("settings.personalization")
    }

    private func favoriteBinding(_ action: LoggerShortcut) -> Binding<Bool> {
        Binding(get: { tracking.favoriteActions.contains(action) }, set: { selected in
            var values = tracking.favoriteActions.filter { $0 != action }
            if selected { values.append(action) }
            tracking.favoriteActions = values
        })
    }

    private func cardBinding(_ card: TodayCard) -> Binding<Bool> {
        Binding(get: { tracking.visibleCards.contains(card) }, set: { selected in
            var values = tracking.visibleCards.filter { $0 != card }
            if selected { values.append(card) }
            tracking.visibleCards = values
        })
    }
}

/// Shared optional fields; setters persist directly through OnboardingProfile.
struct CompanionProfileFields: View {
    @Bindable var profile: OnboardingProfile

    var body: some View {
        TextField(L10n.string("Name (optional)", defaultValue: "Name (optional)"), text: $profile.preferredName)
            .textContentType(.givenName)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
        Picker(L10n.string("Main focus (optional)", defaultValue: "Main focus (optional)"), selection: $profile.primaryGoal) {
            Text(L10n.string("No preference", defaultValue: "No preference")).tag(Optional<PrimaryGoal>.none)
            ForEach(PrimaryGoal.allCases) { goal in Text(goal.displayName).tag(Optional(goal)) }
        }
        ForEach(SymptomFocusArea.allCases) { focus in
            Toggle(focus == .digestionWeight ? L10n.string("Digestion", defaultValue: "Digestion") : focus.displayName, isOn: Binding(
                get: { profile.symptomFocusAreas.contains(focus) },
                set: { selected in
                    var values = profile.symptomFocusAreas.filter { $0 != focus }
                    if selected { values.append(focus) }
                    profile.symptomFocusAreas = values
                }
            ))
        }
    }
}
