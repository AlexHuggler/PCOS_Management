import SwiftUI
import SwiftData

struct MealHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MealViewModel?
    @State private var pendingDeleteMeal: MealEntry?
    @State private var showUndoToast = false
    @State private var selectedMeal: MealEntry?

    /// Meals grouped by day, sorted most recent first.
    private var groupedMeals: [(date: Date, meals: [MealEntry])] {
        guard let viewModel else { return [] }
        let meals = viewModel.fetchRecentMeals(days: 90)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: meals) { meal in
            calendar.startOfDay(for: meal.timestamp)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, meals: $0.value.sorted { $0.timestamp < $1.timestamp }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    let groups = groupedMeals
                    if groups.isEmpty {
                        AppEmptyStateView(
                            title: L10n.string("No Meals Logged", defaultValue: "No Meals Logged"),
                            message: L10n.string("Meals you log will appear here.", defaultValue: "Meals you log will appear here."),
                            systemImage: "fork.knife"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(groups, id: \.date) { group in
                                Section {
                                    ForEach(group.meals) { meal in
                                        MealRow(meal: meal)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedMeal = meal }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    pendingDeleteMeal = meal
                                                    withAnimation {
                                                        showUndoToast = true
                                                    }
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                } header: {
                                    Text(group.date, format: .dateTime.weekday(.wide).month(.wide).day())
                                }
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if showUndoToast, pendingDeleteMeal != nil {
                                UndoToast(
                                    message: L10n.string("Meal entry deleted", defaultValue: "Meal entry deleted"),
                                    onUndo: {
                                        withAnimation {
                                            pendingDeleteMeal = nil
                                            showUndoToast = false
                                        }
                                    },
                                    onExpire: {
                                        if let meal = pendingDeleteMeal {
                                            viewModel.deleteMeal(meal)
                                        }
                                        withAnimation {
                                            pendingDeleteMeal = nil
                                            showUndoToast = false
                                        }
                                    }
                                )
                                .padding()
                            }
                        }
                    }
                } else {
                    List {
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonListRow()
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("Meal History", defaultValue: "Meal History"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if viewModel == nil {
                    viewModel = MealViewModel(modelContext: modelContext)
                }
            }
            .sheet(item: $selectedMeal) { meal in
                MealDetailView(meal: meal)
            }
        }
    }
}

// MARK: - Meal Row

private struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: AppTheme.spacing12) {
            // Meal type icon
            Image(systemName: meal.mealType.systemImage)
                .appFont(.title3)
                .foregroundStyle(AppTheme.sage)
                .frame(width: 32, height: 32)

            // Description and time
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(meal.mealDescription)
                    .appFont(.subheadline, weight: .medium)
                    .lineLimit(2)

                Text(meal.timestamp, format: .dateTime.hour().minute())
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // GI colored capsule
            Text(giLabel(for: meal.glycemicImpact))
                .appFont(.caption2, weight: .semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(giColor(for: meal.glycemicImpact).opacity(0.2))
                )
                .foregroundStyle(giColor(for: meal.glycemicImpact))

            // Photo thumbnail
            if let photoData = meal.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, AppTheme.spacing4)
    }

    private func giColor(for impact: GlycemicImpact) -> Color {
        switch impact {
        case .low: .green
        case .medium: .orange
        case .high: AppTheme.coralAccent
        }
    }

    private func giLabel(for impact: GlycemicImpact) -> String {
        switch impact {
        case .low: L10n.string("Low", defaultValue: "Low")
        case .medium: L10n.string("Med", defaultValue: "Med")
        case .high: L10n.string("High", defaultValue: "High")
        }
    }
}

#Preview {
    MealHistoryView()
        .modelContainer(for: MealEntry.self, inMemory: true)
}
