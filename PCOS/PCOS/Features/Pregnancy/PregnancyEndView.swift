import SwiftUI
import SwiftData

struct PregnancyEndView: View {
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
            .accessibilityIdentifier("screen.pregnancy_end")
            .navigationTitle(AppTheme.usesPremiumEditorStyling ? "" : L10n.string("End Pregnancy Mode", defaultValue: "End Pregnancy Mode"))
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
                L10n.string("End Pregnancy Mode?", defaultValue: "End Pregnancy Mode?"),
                isPresented: $showConfirmation
            ) {
                Button(L10n.string("Confirm", defaultValue: "Confirm")) {
                    endPregnancy()
                }
                Button(L10n.string("Cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                Text(PregnancyCopy.endConfirmationMessage(for: viewModel?.endReason ?? .delivery))
            }
            .onAppear {
                if viewModel == nil {
                    let vm = PregnancyViewModel(modelContext: modelContext)
                    vm.loadData()
                    viewModel = vm
                }
            }
        }
    }

    private var standardContent: some View {
        Form {
            Section(L10n.string("End Reason", defaultValue: "End Reason")) {
                Picker(
                    L10n.string("Reason", defaultValue: "Reason"),
                    selection: endReasonBinding
                ) {
                    ForEach(PregnancyEndReason.allCases) { reason in
                        Text(reason.displayName).tag(reason)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.string("End Date", defaultValue: "End Date")) {
                DatePicker(
                    L10n.string("Date", defaultValue: "Date"),
                    selection: endDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.accentColor)
            }

            Section {
                Button {
                    showConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text(L10n.string("End Pregnancy Mode", defaultValue: "End Pregnancy Mode"))
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
                    lunarReasonCard
                    lunarEndDateCard
                    lunarResumeCard

                    if let errorMessage {
                        Text(errorMessage)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.premiumEditorWarningAccentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppTheme.spacing12)
                            .lunarEndCard()
                    }

                    lunarEndButton
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
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 52, height: 52)
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.22), radius: 16, y: 8)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("End Pregnancy Mode", defaultValue: "End Pregnancy Mode"))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)

                Text(L10n.string(
                    "Resume cycle tracking when you are ready. Your pregnancy history stays preserved.",
                    defaultValue: "Resume cycle tracking when you are ready. Your pregnancy history stays preserved."
                ))
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarEndCard()
        .accessibilityIdentifier("pregnancy_end.lunar.header")
    }

    private var lunarReasonCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("End Reason", defaultValue: "End Reason"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: AppTheme.spacing8) {
                ForEach(PregnancyEndReason.allCases, id: \.self) { reason in
                    let isSelected = endReasonBinding.wrappedValue == reason
                    Button {
                        endReasonBinding.wrappedValue = reason
                    } label: {
                        Text(reason.displayName)
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(isSelected ? AppTheme.premiumEditorCTAForeground : AppTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacing8)
                            .padding(.horizontal, AppTheme.spacing8)
                            .background(
                                Capsule()
                                    .fill(isSelected ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.premiumEditorSurface.opacity(0.82)))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? AppTheme.premiumEditorAccentColor.opacity(0.34) : AppTheme.premiumEditorBorder.opacity(0.54), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.spacing16)
        .lunarEndCard()
        .accessibilityIdentifier("pregnancy_end.lunar.reason_card")
    }

    private var lunarEndDateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("End Date", defaultValue: "End Date"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppTheme.premiumEditorAccentColor.opacity(0.12)))
                    .accessibilityHidden(true)

                DatePicker(
                    L10n.string("Date", defaultValue: "Date"),
                    selection: endDateBinding,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(AppTheme.premiumEditorAccentColor)
            }
        }
        .padding(AppTheme.spacing16)
        .lunarEndCard()
        .accessibilityIdentifier("pregnancy_end.lunar.date_card")
    }

    private var lunarResumeCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Label {
                Text(L10n.string("What happens next", defaultValue: "What happens next"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
            }

            Text(L10n.string(
                "Cycle tracking will resume. Your pregnancy data will be preserved.",
                defaultValue: "Cycle tracking will resume. Your pregnancy data will be preserved."
            ))
            .appFont(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing16)
        .lunarEndCard()
        .accessibilityIdentifier("pregnancy_end.lunar.resume_card")
    }

    private var lunarEndButton: some View {
        Button {
            showConfirmation = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "arrow.counterclockwise")
                    .accessibilityHidden(true)
                Text(L10n.string("End Pregnancy Mode", defaultValue: "End Pregnancy Mode"))
                    .appFont(.headline, weight: .semibold)
                Spacer()
            }
            .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            .padding(.vertical, AppTheme.spacing16)
            .background(Capsule().fill(AppTheme.premiumEditorAccentGradient))
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.24), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pregnancy_end.lunar.submit")
    }

    private var endReasonBinding: Binding<PregnancyEndReason> {
        Binding(
            get: { viewModel?.endReason ?? .delivery },
            set: { viewModel?.endReason = $0 }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { viewModel?.endDate ?? Date() },
            set: { viewModel?.endDate = $0 }
        )
    }

    private func endPregnancy() {
        guard let viewModel else { return }
        do {
            try viewModel.endPregnancyMode(appState: appState)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func lunarEndCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
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
