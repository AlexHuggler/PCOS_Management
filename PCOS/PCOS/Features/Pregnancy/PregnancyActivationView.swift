import SwiftUI
import SwiftData

struct PregnancyActivationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var viewModel: PregnancyViewModel?
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if AppTheme.usesPremiumEditorStyling {
                    lunarContent
                } else {
                    standardContent
                }
            }
            .accessibilityIdentifier("screen.pregnancy_activation")
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("Pregnancy Mode", defaultValue: "Pregnancy Mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if AppTheme.usesPremiumEditorStyling {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .appFont(.headline, weight: .semibold)
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.86)))
                                .overlay(Circle().stroke(AppTheme.premiumEditorBorder.opacity(0.66), lineWidth: 0.8))
                        }
                        .accessibilityLabel(L10n.string("Cancel", defaultValue: "Cancel"))
                    } else {
                        Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                            dismiss()
                        }
                    }
                }
            }
            .toolbarBackground(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorBackground : Color.clear, for: .navigationBar)
            .alert(
                L10n.string("Enter Pregnancy Mode?", defaultValue: "Enter Pregnancy Mode?"),
                isPresented: $showConfirmation
            ) {
                Button(L10n.string("Confirm", defaultValue: "Confirm")) {
                    activate()
                }
                Button(L10n.string("Cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.string(
                    "Cycle tracking will be paused and your current cycle will be closed. You can return to cycle tracking from Settings.",
                    defaultValue: "Cycle tracking will be paused and your current cycle will be closed. You can return to cycle tracking from Settings."
                ))
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = PregnancyViewModel(modelContext: modelContext)
                }
            }
        }
    }

    private var standardContent: some View {
        Form {
            Section {
                Text(L10n.string(
                    "This will pause cycle tracking. You can return to cycle tracking anytime from Settings.",
                    defaultValue: "This will pause cycle tracking. You can return to cycle tracking anytime from Settings."
                ))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section(L10n.string("Pregnancy Start Date", defaultValue: "Pregnancy Start Date")) {
                DatePicker(
                    L10n.string("Start date", defaultValue: "Start date"),
                    selection: activationStartDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.accentColor)
            }

            Section(L10n.string("Estimated Due Date", defaultValue: "Estimated Due Date")) {
                Toggle(
                    L10n.string("I have an estimated due date", defaultValue: "I have an estimated due date"),
                    isOn: activationHasDueDateBinding
                )

                if viewModel?.activationDueDate != nil {
                    DatePicker(
                        L10n.string("Due date", defaultValue: "Due date"),
                        selection: activationDueDateBinding,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(AppTheme.accentColor)
                }
            }

            Section {
                Button {
                    showConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            L10n.string("Enter Pregnancy Mode", defaultValue: "Enter Pregnancy Mode"),
                            systemImage: "heart.fill"
                        )
                        .appFont(.headline)
                        Spacer()
                    }
                }
                .tint(AppTheme.accentColor)
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

    private var lunarContent: some View {
        ZStack {
            BotanicalScreenBackground(style: .dense)

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    lunarHero
                    lunarModeCard
                    lunarStartDateCard
                    lunarDueDateCard

                    if let errorMessage {
                        Text(errorMessage)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.spacing12)
                            .lunarActivationCard()
                    }

                    lunarActivationButton
                }
                .padding(.horizontal, AppTheme.spacing16)
                .padding(.top, AppTheme.spacing8)
                .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
    }

    private var lunarHero: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: "heart.fill")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 52, height: 52)
            .shadow(color: AppTheme.premiumEditorSecondaryAccentColor.opacity(0.22), radius: 16, y: 8)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Pregnancy Mode", defaultValue: "Pregnancy Mode"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                Text(L10n.string(
                    "Pause cycle predictions while preserving your history.",
                    defaultValue: "Pause cycle predictions while preserving your history."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarActivationCard()
        .accessibilityIdentifier("pregnancy_activation.lunar.header")
    }

    private var lunarModeCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label {
                Text(L10n.string("What changes", defaultValue: "What changes"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
            } icon: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
            }

            Text(L10n.string(
                "This will pause cycle tracking. You can return to cycle tracking anytime from Settings.",
                defaultValue: "This will pause cycle tracking. You can return to cycle tracking anytime from Settings."
            ))
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing16)
        .lunarActivationCard()
        .accessibilityIdentifier("pregnancy_activation.lunar.mode_card")
    }

    private var lunarStartDateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Pregnancy Start Date", defaultValue: "Pregnancy Start Date"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppTheme.premiumEditorAccentColor.opacity(0.12)))
                    .accessibilityHidden(true)

                DatePicker(
                    L10n.string("Start date", defaultValue: "Start date"),
                    selection: activationStartDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.premiumEditorAccentColor)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarActivationCard()
        .accessibilityIdentifier("pregnancy_activation.lunar.start_card")
    }

    private var lunarDueDateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Toggle(
                L10n.string("I have an estimated due date", defaultValue: "I have an estimated due date"),
                isOn: activationHasDueDateBinding
            )
            .appFont(.subheadline, weight: .semibold)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.premiumEditorAccentColor)

            Text(L10n.string(
                "Optional estimates help keep reminders gentle while predictions are paused.",
                defaultValue: "Optional estimates help keep reminders gentle while predictions are paused."
            ))
            .appFont(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            if viewModel?.activationDueDate != nil {
                Divider()
                    .overlay(AppTheme.premiumEditorBorder.opacity(0.46))

                DatePicker(
                    L10n.string("Due date", defaultValue: "Due date"),
                    selection: activationDueDateBinding,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.premiumEditorAccentColor)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarActivationCard()
        .accessibilityIdentifier("pregnancy_activation.lunar.due_date_card")
    }

    private var lunarActivationButton: some View {
        Button {
            showConfirmation = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "heart.fill")
                    .accessibilityHidden(true)
                Text(L10n.string("Enter Pregnancy Mode", defaultValue: "Enter Pregnancy Mode"))
                    .appFont(.headline, weight: .semibold)
                Spacer()
            }
            .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            .padding(.vertical, AppTheme.spacing16)
            .background(Capsule().fill(AppTheme.premiumEditorAccentGradient))
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.24), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pregnancy_activation.lunar.submit")
    }

    private var activationStartDateBinding: Binding<Date> {
        Binding(
            get: { viewModel?.activationStartDate ?? Date() },
            set: { viewModel?.activationStartDate = $0 }
        )
    }

    private var activationDueDateBinding: Binding<Date> {
        Binding(
            get: { viewModel?.activationDueDate ?? Date() },
            set: { viewModel?.activationDueDate = $0 }
        )
    }

    private var activationHasDueDateBinding: Binding<Bool> {
        Binding(
            get: { viewModel?.activationDueDate != nil },
            set: { enabled in
                if enabled {
                    viewModel?.activationDueDate = Calendar.current.date(
                        byAdding: .day,
                        value: 280,
                        to: viewModel?.activationStartDate ?? Date()
                    )
                } else {
                    viewModel?.activationDueDate = nil
                }
            }
        )
    }

    private func activate() {
        guard let viewModel else { return }
        do {
            try viewModel.activatePregnancyMode(appState: appState)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func lunarActivationCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
                )
        )
        .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
    }
}
