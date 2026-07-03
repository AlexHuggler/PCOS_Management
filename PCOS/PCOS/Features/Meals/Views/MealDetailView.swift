import SwiftUI

struct MealDetailView: View {
    let meal: MealEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if AppTheme.usesPremiumEditorStyling {
                    lunarDetailContent
                } else {
                    standardDetailContent
                }
            }
            .navigationTitle(meal.mealType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
            .lunarMealDetailNavigationBackground()
        }
    }

    private var standardDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                if let photoImage {
                    Image(uiImage: photoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                }

                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: meal.mealType.systemImage)
                        .appFont(.title2)
                        .foregroundStyle(AppTheme.sage)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(meal.mealDescription)
                            .appFont(.title3, weight: .semibold)

                        Text(meal.timestamp, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(L10n.string("Glycemic Impact", defaultValue: "Glycemic Impact"))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(meal.glycemicImpact.displayName)
                        .appFont(.subheadline, weight: .semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(giColor(for: meal.glycemicImpact).opacity(0.2))
                        )
                        .foregroundStyle(giColor(for: meal.glycemicImpact))
                }

                if hasMacros {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(L10n.string("Macros", defaultValue: "Macros"))
                            .appFont(.subheadline, weight: .medium)

                        HStack(spacing: AppTheme.spacing16) {
                            macroItems
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                if let notes = meal.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(L10n.string("Notes", defaultValue: "Notes"))
                            .appFont(.subheadline, weight: .medium)

                        Text(notes)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding()
        }
        .background(AppTheme.warmNeutral)
        .accessibilityIdentifier("screen.meal_detail")
    }

    private var lunarDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                if let photoImage {
                    Image(uiImage: photoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
                        )
                        .accessibilityIdentifier("meal_detail.lunar.photo")
                }

                lunarHeaderCard
                lunarGlycemicCard

                if hasMacros {
                    lunarMacroCard
                }

                if let notes = meal.notes, !notes.isEmpty {
                    lunarNotesCard(notes)
                }
            }
            .padding(AppTheme.spacing16)
            .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
        }
        .background(AppTheme.premiumEditorBackground.ignoresSafeArea())
        .tint(AppTheme.premiumEditorAccentColor)
        .accessibilityIdentifier("screen.meal_detail")
    }

    private var lunarHeaderCard: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: meal.mealType.systemImage)
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                .frame(width: 46, height: 46)
                .background(Circle().fill(AppTheme.premiumEditorAccentGradient))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(meal.mealType.displayName)
                    .appFont(.caption, weight: .semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.premiumEditorAccentColor)

                Text(meal.mealDescription)
                    .appHeadingFont(.title3, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(meal.timestamp, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(AppTheme.spacing12)
        .lunarMealDetailCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_detail.lunar.header")
    }

    private var lunarGlycemicCard: some View {
        HStack(spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Glycemic Impact", defaultValue: "Glycemic Impact"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("How this meal may affect energy and symptoms.", defaultValue: "How this meal may affect energy and symptoms."))
                    .appFont(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            Text(meal.glycemicImpact.displayName)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(giColor(for: meal.glycemicImpact))
                .padding(.horizontal, AppTheme.spacing12)
                .padding(.vertical, AppTheme.spacing8)
                .background(Capsule().fill(giColor(for: meal.glycemicImpact).opacity(0.16)))
        }
        .padding(AppTheme.spacing12)
        .lunarMealDetailCard()
        .accessibilityIdentifier("meal_detail.lunar.glycemic")
    }

    private var lunarMacroCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Text(L10n.string("Macros", defaultValue: "Macros"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: AppTheme.spacing8) {
                macroItems
            }
        }
        .padding(AppTheme.spacing12)
        .lunarMealDetailCard()
        .accessibilityIdentifier("meal_detail.lunar.macros")
    }

    private func lunarNotesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(L10n.string("Notes", defaultValue: "Notes"))
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(notes)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing12)
        .lunarMealDetailCard()
        .accessibilityIdentifier("meal_detail.lunar.notes")
    }

    @ViewBuilder
    private var macroItems: some View {
        if let carbs = meal.carbsGrams {
            macroItem(
                label: L10n.string("Carbs", defaultValue: "Carbs"),
                value: String(format: "%.0fg", carbs)
            )
        }
        if let protein = meal.proteinGrams {
            macroItem(
                label: L10n.string("Protein", defaultValue: "Protein"),
                value: String(format: "%.0fg", protein)
            )
        }
        if let fat = meal.fatGrams {
            macroItem(
                label: L10n.string("Fat", defaultValue: "Fat"),
                value: String(format: "%.0fg", fat)
            )
        }
    }

    private var photoImage: UIImage? {
        guard let photoData = meal.photoData else { return nil }
        return UIImage(data: photoData)
    }

    private var hasMacros: Bool {
        meal.carbsGrams != nil || meal.proteinGrams != nil || meal.fatGrams != nil
    }

    private func macroItem(label: String, value: String) -> some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.accentColor)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(AppTheme.usesPremiumEditorStyling ? AppTheme.spacing8 : 0)
        .background {
            if AppTheme.usesPremiumEditorStyling {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.premiumEditorSurface.opacity(0.72))
            }
        }
    }

    private func giColor(for impact: GlycemicImpact) -> Color {
        switch impact {
        case .low: AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : .green
        case .medium: AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorSecondaryAccentColor : .orange
        case .high: AppTheme.coralAccent
        }
    }
}

private extension View {
    @ViewBuilder
    func lunarMealDetailNavigationBackground() -> some View {
        if AppTheme.usesPremiumEditorStyling {
            toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    func lunarMealDetailCard(cornerRadius: CGFloat = AppTheme.cornerRadiusLarge) -> some View {
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
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
        )
        .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
    }
}
