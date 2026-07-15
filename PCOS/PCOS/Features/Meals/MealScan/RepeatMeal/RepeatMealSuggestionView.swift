import SwiftUI

struct RepeatMealSuggestionView: View {
    let suggestion: RepeatMealSuggestion
    let onUsePrevious: () -> Void
    let onScanAsNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing20) {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                header
                suggestionCard
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityIdentifier("meal_scan.repeat_suggestion.summary")

            VStack(spacing: AppTheme.spacing12) {
                Button(action: onUsePrevious) {
                    Text(L10n.string("Use Previous Meal", defaultValue: "Use Previous Meal"))
                        .appFont(.headline, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryActionColor)
                .accessibilityIdentifier("meal_scan.repeat_suggestion.use_previous")

                Button(action: onScanAsNew) {
                    Text(L10n.string("Scan as New", defaultValue: "Scan as New"))
                        .appFont(.headline, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
                .tint(secondaryActionColor)
                .accessibilityIdentifier("meal_scan.repeat_suggestion.scan_as_new")
            }
            .controlSize(.large)
        }
        .accessibilityIdentifier("meal_scan.repeat_suggestion")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("Looks familiar", defaultValue: "Looks familiar"))
                    .appFont(.title2, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.string("You can adjust anything before saving.", defaultValue: "You can adjust anything before saving."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(primaryActionColor)
                .frame(width: 48, height: 48)
                .background(Circle().fill(primaryActionColor.opacity(0.12)))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var suggestionCard: some View {
        let content = VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            Text(suggestion.snapshot.mealName)
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing8) {
                Text(MealNutritionCalculator.displayCalories(suggestion.snapshot.nutrition.caloriesKcal))
                    .appFont(.title2, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("kcal", defaultValue: "kcal"))
                    .appFont(.subheadline, weight: .medium)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.spacing16) {
                    macroValue(title: L10n.string("Protein", defaultValue: "Protein"), value: suggestion.snapshot.nutrition.proteinGrams)
                    macroValue(title: L10n.string("Carbs", defaultValue: "Carbs"), value: suggestion.snapshot.nutrition.carbsGrams)
                    macroValue(title: L10n.string("Fat", defaultValue: "Fat"), value: suggestion.snapshot.nutrition.fatGrams)
                }

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    macroValue(title: L10n.string("Protein", defaultValue: "Protein"), value: suggestion.snapshot.nutrition.proteinGrams)
                    macroValue(title: L10n.string("Carbs", defaultValue: "Carbs"), value: suggestion.snapshot.nutrition.carbsGrams)
                    macroValue(title: L10n.string("Fat", defaultValue: "Fat"), value: suggestion.snapshot.nutrition.fatGrams)
                }
            }

            Label(lastLoggedText, systemImage: "calendar")
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing16)

        if AppTheme.usesPremiumEditorStyling {
            content
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                        .fill(AppTheme.premiumEditorSurface.opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall, style: .continuous)
                        .stroke(AppTheme.premiumEditorBorder, lineWidth: 1)
                )
        } else {
            content.cardStyle(cornerRadius: AppTheme.cornerRadiusSmall)
        }
    }

    private func macroValue(title: String, value: Double) -> some View {
        HStack(spacing: AppTheme.spacing4) {
            Text(MealNutritionCalculator.displayMacro(value) + " g")
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(title)
                .appFont(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var lastLoggedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeDate = formatter.localizedString(for: suggestion.sourceMealLoggedAt, relativeTo: Date())
        return L10n.format("last logged %@", defaultValue: "last logged %@", relativeDate)
    }

    private var accessibilitySummary: String {
        [
            L10n.string("Looks familiar", defaultValue: "Looks familiar"),
            L10n.string("You can adjust anything before saving.", defaultValue: "You can adjust anything before saving."),
            suggestion.snapshot.mealName,
            "\(MealNutritionCalculator.displayCalories(suggestion.snapshot.nutrition.caloriesKcal)) kcal",
            "\(MealNutritionCalculator.displayMacro(suggestion.snapshot.nutrition.proteinGrams)) g \(L10n.string("Protein", defaultValue: "Protein"))",
            "\(MealNutritionCalculator.displayMacro(suggestion.snapshot.nutrition.carbsGrams)) g \(L10n.string("Carbs", defaultValue: "Carbs"))",
            "\(MealNutritionCalculator.displayMacro(suggestion.snapshot.nutrition.fatGrams)) g \(L10n.string("Fat", defaultValue: "Fat"))",
            lastLoggedText,
        ].joined(separator: ", ")
    }

    private var primaryActionColor: Color {
        AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.sage
    }

    private var secondaryActionColor: Color {
        AppTheme.isLunarCalm ? AppTheme.premiumEditorSecondaryAccentColor : AppTheme.primaryText
    }
}
