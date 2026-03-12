import SwiftUI
import SwiftData

struct MealHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MealViewModel?

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
                        ContentUnavailableView(
                            "No Meals Logged",
                            systemImage: "fork.knife",
                            description: Text("Meals you log will appear here.")
                        )
                    } else {
                        List {
                            ForEach(groups, id: \.date) { group in
                                Section {
                                    ForEach(group.meals) { meal in
                                        MealRow(meal: meal)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    viewModel.deleteMeal(meal)
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
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Meal History")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if viewModel == nil {
                    viewModel = MealViewModel(modelContext: modelContext)
                }
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
                .font(.title3)
                .foregroundStyle(AppTheme.sage)
                .frame(width: 32, height: 32)

            // Description and time
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(meal.mealDescription)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(meal.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // GI colored capsule
            Text(giLabel(for: meal.glycemicImpact))
                .font(.caption2)
                .fontWeight(.semibold)
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
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        }
    }
}

#Preview {
    MealHistoryView()
        .modelContainer(for: MealEntry.self, inMemory: true)
}
