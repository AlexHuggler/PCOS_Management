import SwiftUI

struct MealDetailView: View {
    let meal: MealEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                    // Photo
                    if let photoData = meal.photoData,
                       let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                    }

                    // Header: type icon + description
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

                    // Glycemic impact
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

                    // Macros
                    if meal.carbsGrams != nil || meal.proteinGrams != nil || meal.fatGrams != nil {
                        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                            Text(L10n.string("Macros", defaultValue: "Macros"))
                                .appFont(.subheadline, weight: .medium)

                            HStack(spacing: AppTheme.spacing16) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }

                    // Notes
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
            .navigationTitle(meal.mealType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func macroItem(label: String, value: String) -> some View {
        VStack(spacing: AppTheme.spacing4) {
            Text(value)
                .appFont(.headline)
                .foregroundStyle(AppTheme.accentColor)
            Text(label)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func giColor(for impact: GlycemicImpact) -> Color {
        switch impact {
        case .low: .green
        case .medium: .orange
        case .high: AppTheme.coralAccent
        }
    }
}
