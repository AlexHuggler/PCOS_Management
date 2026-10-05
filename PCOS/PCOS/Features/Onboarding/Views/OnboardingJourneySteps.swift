import SwiftUI

// Step views for the v1 onboarding (A2–A7). State lives in OnboardingContainerView; these views
// only render it. Copy follows the persona rules: calm, expectation-only, privacy stated up front.

// MARK: - Shared pieces

struct OnboardingProgressSegments: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index <= current ? AppTheme.accentColor : AppTheme.accentColor.opacity(AppTheme.opacityLight))
                    .frame(width: 28, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Step %lld of %lld", defaultValue: "Step %lld of %lld", Int64(current), Int64(total)))
    }
}

private struct OnboardingTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(title)
                .appHeadingFont(.title, weight: .bold)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .appFont(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IconTile: View {
    let systemImage: String
    var tint: Color = AppTheme.accentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                    .fill(tint.opacity(AppTheme.opacityLight))
            )
            .accessibilityHidden(true)
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
    }
}

// MARK: - A2 Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing24) {
            Image(systemName: "leaf")
                .appFont(.largeTitle)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 112, height: 112)
                .background(Circle().fill(AppTheme.accentColor.opacity(AppTheme.opacityLight)))
                .accessibilityHidden(true)

            OnboardingTitle(
                title: L10n.string("Understand your PCOS patterns, privately.", defaultValue: "Understand your PCOS patterns, privately."),
                subtitle: L10n.string(
                    "A check-in takes about 20 seconds. Over time, you'll see what seems connected: cycles, symptoms, sleep and more.",
                    defaultValue: "A check-in takes about 20 seconds. Over time, you'll see what seems connected: cycles, symptoms, sleep and more."
                )
            )

            OnboardingCard {
                VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                    trustRow("lock", L10n.string("Stays on your iPhone", defaultValue: "Stays on your iPhone"))
                    trustRow("heart", L10n.string("Apple Health is optional", defaultValue: "Apple Health is optional"))
                    trustRow("shield", L10n.string("Not a medical device", defaultValue: "Not a medical device"))
                }
                .padding(AppTheme.spacing16)
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("onboarding.welcome")
    }

    private func trustRow(_ systemImage: String, _ title: String) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            IconTile(systemImage: systemImage)
            Text(title)
                .appFont(.body)
                .foregroundStyle(AppTheme.primaryText)
        }
    }
}

// MARK: - A3 Where you are

extension PCOSExperience {
    /// v1 onboarding copy (A3). Sets Simple vs Detailed explanations.
    var journeyTitle: String {
        switch self {
        case .newlyDiagnosed: L10n.string("Recently diagnosed", defaultValue: "Recently diagnosed")
        case .experienced: L10n.string("Managing for a while", defaultValue: "Managing for a while")
        case .exploring: L10n.string("Not sure yet", defaultValue: "Not sure yet")
        }
    }

    var journeySubtitle: String {
        switch self {
        case .newlyDiagnosed: L10n.string("Learning what helps", defaultValue: "Learning what helps")
        case .experienced: L10n.string("I know the basics and want detail", defaultValue: "I know the basics and want detail")
        case .exploring: L10n.string("Noticing symptoms", defaultValue: "Noticing symptoms")
        }
    }
}

struct OnboardingStageStep: View {
    @Binding var selection: PCOSExperience?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            OnboardingTitle(
                title: L10n.string("Where are you in your PCOS journey?", defaultValue: "Where are you in your PCOS journey?"),
                subtitle: L10n.string("This sets how much we explain. Change it anytime.", defaultValue: "This sets how much we explain. Change it anytime.")
            )

            ForEach([PCOSExperience.newlyDiagnosed, .experienced, .exploring]) { option in
                let isSelected = selection == option
                Button {
                    selection = isSelected ? nil : option
                } label: {
                    HStack(spacing: AppTheme.spacing12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.journeyTitle)
                                .appFont(.headline)
                                .foregroundStyle(AppTheme.primaryText)
                            Text(option.journeySubtitle)
                                .appFont(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: AppTheme.spacing8)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .appFont(.title3)
                            .foregroundStyle(isSelected ? AppTheme.accentColor : AppTheme.secondaryText.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                    .padding(AppTheme.spacing16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                            .fill(AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                            .stroke(isSelected ? AppTheme.accentColor : AppTheme.cardBorder.opacity(0.35), lineWidth: isSelected ? 1.5 : 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier("onboarding.stage.\(option.rawValue)")
            }
        }
    }
}

// MARK: - A4 What to watch

struct OnboardingFocusStep: View {
    @Binding var topics: [OnboardingFocusTopic]
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            OnboardingTitle(
                title: L10n.string("What would you like to understand?", defaultValue: "What would you like to understand?"),
                subtitle: L10n.string("Pick any. We pin these to your daily check-in.", defaultValue: "Pick any. We pin these to your daily check-in.")
            )

            FlowLayout(spacing: AppTheme.spacing8) {
                ForEach(OnboardingFocusTopic.allCases) { topic in
                    let isSelected = topics.contains(topic)
                    Button {
                        if isSelected { topics.removeAll { $0 == topic } } else { topics.append(topic) }
                    } label: {
                        Label {
                            Text(topic.title).appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                        } icon: {
                            if isSelected { Image(systemName: "checkmark") }
                        }
                        .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                        .padding(.horizontal, AppTheme.spacing16)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(isSelected ? AppTheme.accentColor : AppTheme.cardBackground))
                        .overlay(Capsule().stroke(isSelected ? AppTheme.accentColor : AppTheme.cardBorder.opacity(0.45), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("onboarding.focus.\(topic.rawValue)")
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("What should we call you? (optional)", defaultValue: "What should we call you? (optional)"))
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(AppTheme.secondaryText)
                TextField(L10n.string("Name", defaultValue: "Name"), text: $name)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .appFont(.body)
                    .padding(.horizontal, AppTheme.spacing16)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .fill(AppTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                            .stroke(AppTheme.cardBorder.opacity(0.35), lineWidth: 1)
                    )
                    .accessibilityIdentifier("onboarding.name.field")
            }
            .padding(.top, AppTheme.spacing8)
        }
    }
}

// MARK: - A5 First check-in

struct OnboardingFirstCheckInStep: View {
    @Binding var input: QuickCheckInInput
    let symptoms: [SymptomType]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            OnboardingTitle(title: L10n.string("How are you feeling today?", defaultValue: "How are you feeling today?"))

            MoodTileRow(selected: input.mood) { mood in
                input.mood = input.mood == mood ? nil : mood
            }

            Text(L10n.string("YOUR SYMPTOMS", defaultValue: "YOUR SYMPTOMS"))
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityAddTraits(.isHeader)

            OnboardingCard {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    ForEach(symptoms, id: \.self) { symptom in
                        SymptomSeverityRow(symptom: symptom, selected: input.severities[symptom]) { severity in
                            input.toggle(severity, for: symptom)
                        }
                    }
                }
                .padding(AppTheme.spacing16)
            }

            NothingToReportChip(isOn: input.nothingToReport) {
                input.toggleNothingToReport()
            }
        }
    }
}

// MARK: - A6 What unlocks next + reminder

struct OnboardingUnlocksStep: View {
    let savedFirstCheckIn: Bool
    let checkInDays: Int
    @Binding var reminderTime: Date

    private var progress: Int { CheckInProgress.displayed(checkInDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            if savedFirstCheckIn {
                Label(L10n.string("Day 1 saved", defaultValue: "Day 1 saved"), systemImage: "checkmark")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(AppTheme.sage)
                    .padding(.horizontal, AppTheme.spacing12)
                    .padding(.vertical, AppTheme.spacing8)
                    .background(Capsule().fill(AppTheme.sage.opacity(AppTheme.opacityLight)))
                    .accessibilityIdentifier("onboarding.day1_saved")
            }

            OnboardingTitle(title: L10n.string("Here's what unlocks as you log", defaultValue: "Here's what unlocks as you log"))

            OnboardingCard {
                VStack(alignment: .leading, spacing: 0) {
                    unlockRow(
                        systemImage: "chart.bar.xaxis",
                        title: L10n.string("After 7 check-ins", defaultValue: "After 7 check-ins"),
                        detail: L10n.string("Your first symptom pattern", defaultValue: "Your first symptom pattern")
                    ) {
                        VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                            ProgressView(value: CheckInProgress.fraction(checkInDays))
                                .tint(AppTheme.accentColor)
                            Text(L10n.format("%lld of %lld", defaultValue: "%lld of %lld", Int64(progress), Int64(CheckInProgress.firstPatternTarget)))
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(AppTheme.accentColor)
                        }
                    }
                    Divider().padding(.leading, 60)
                    unlockRow(
                        systemImage: "calendar",
                        title: L10n.string("After 2 periods", defaultValue: "After 2 periods"),
                        detail: L10n.string("Your cycle-length range", defaultValue: "Your cycle-length range")
                    ) { EmptyView() }
                    Divider().padding(.leading, 60)
                    unlockRow(
                        systemImage: "heart",
                        title: L10n.string("With Apple Health", defaultValue: "With Apple Health"),
                        detail: L10n.string("Sleep and activity context", defaultValue: "Sleep and activity context")
                    ) { EmptyView() }
                }
            }

            OnboardingCard {
                HStack(alignment: .center, spacing: AppTheme.spacing12) {
                    IconTile(systemImage: "bell")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("Get a gentle nudge?", defaultValue: "Get a gentle nudge?"))
                            .appFont(.headline)
                            .foregroundStyle(AppTheme.primaryText)
                        Text(L10n.string(
                            "One quiet reminder a day. It never shows your symptoms on the lock screen.",
                            defaultValue: "One quiet reminder a day. It never shows your symptoms on the lock screen."
                        ))
                        .appFont(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    DatePicker(
                        L10n.string("Reminder time", defaultValue: "Reminder time"),
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(AppTheme.accentColor)
                    .accessibilityIdentifier("onboarding.reminder.time")
                }
                .padding(AppTheme.spacing16)
            }
        }
    }

    private func unlockRow<Extra: View>(
        systemImage: String,
        title: String,
        detail: String,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            IconTile(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(detail)
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                extra()
                    .padding(.top, AppTheme.spacing4)
            }
        }
        .padding(AppTheme.spacing16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A7 Apple Health (optional)

/// The four read-only groups offered in onboarding, mapped onto the app's Health categories.
enum OnboardingHealthChoice: String, CaseIterable, Identifiable, Sendable {
    case sleep, movement, cycle, glucose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: L10n.string("Sleep", defaultValue: "Sleep")
        case .movement: L10n.string("Movement", defaultValue: "Movement")
        case .cycle: L10n.string("Cycle tracking", defaultValue: "Cycle tracking")
        case .glucose: L10n.string("Blood glucose", defaultValue: "Blood glucose")
        }
    }

    var systemImage: String {
        switch self {
        case .sleep: "moon"
        case .movement: "chart.bar.xaxis"
        case .cycle: "leaf"
        case .glucose: "drop"
        }
    }

    var categories: [HealthKitDataTypeDescriptor.Category] {
        switch self {
        case .sleep: [.sleep]
        case .movement: [.activity]
        case .cycle: [.cycle, .symptoms]
        case .glucose: [.glucose]
        }
    }

    /// Sleep, Movement and Cycle are pre-checked; Glucose only when Blood sugar was chosen in A4.
    static func defaultSelection(for topics: [OnboardingFocusTopic]) -> Set<Self> {
        var selection: Set<Self> = [.sleep, .movement, .cycle]
        if topics.contains(.bloodSugar) { selection.insert(.glucose) }
        return selection
    }

    static func categories(for choices: Set<Self>) -> Set<HealthKitDataTypeDescriptor.Category> {
        Set(choices.flatMap(\.categories))
    }
}

struct OnboardingHealthStep: View {
    @Binding var choices: Set<OnboardingHealthChoice>
    let isHealthAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            IconTile(systemImage: "heart", tint: AppTheme.coralAccent, size: 56)

            OnboardingTitle(
                title: L10n.string("Bring in what your Watch already knows", defaultValue: "Bring in what your Watch already knows"),
                subtitle: L10n.string(
                    "Read-only. CycleBalance never writes to Apple Health, and nothing leaves your iPhone.",
                    defaultValue: "Read-only. CycleBalance never writes to Apple Health, and nothing leaves your iPhone."
                )
            )

            if isHealthAvailable {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(OnboardingHealthChoice.allCases.enumerated()), id: \.element) { index, choice in
                            if index > 0 { Divider().padding(.leading, 60) }
                            Toggle(isOn: Binding(
                                get: { choices.contains(choice) },
                                set: { isOn in
                                    if isOn { choices.insert(choice) } else { choices.remove(choice) }
                                }
                            )) {
                                HStack(spacing: AppTheme.spacing12) {
                                    IconTile(systemImage: choice.systemImage)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(choice.title)
                                            .appFont(.headline)
                                            .foregroundStyle(AppTheme.primaryText)
                                        Text(L10n.string("Read-only", defaultValue: "Read-only"))
                                            .appFont(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                            }
                            .tint(AppTheme.accentColor)
                            .frame(minHeight: 44)
                            .padding(.horizontal, AppTheme.spacing16)
                            .padding(.vertical, AppTheme.spacing8)
                            .accessibilityIdentifier("onboarding.health.\(choice.rawValue)")
                        }
                    }
                }
            } else {
                Text(L10n.string("Apple Health isn't available on this device.", defaultValue: "Apple Health isn't available on this device."))
                    .appFont(.body)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Text(L10n.string("Change this anytime in Settings › Health.", defaultValue: "Change this anytime in Settings › Health."))
                .appFont(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }
}
