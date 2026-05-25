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
                        selection: Binding(
                            get: { viewModel?.activationStartDate ?? Date() },
                            set: { viewModel?.activationStartDate = $0 }
                        ),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .tint(AppTheme.accentColor)
                }

                Section(L10n.string("Estimated Due Date", defaultValue: "Estimated Due Date")) {
                    Toggle(
                        L10n.string("I have an estimated due date", defaultValue: "I have an estimated due date"),
                        isOn: Binding(
                            get: { viewModel?.activationDueDate != nil },
                            set: { enabled in
                                if enabled {
                                    viewModel?.activationDueDate = Calendar.current.date(byAdding: .day, value: 280, to: viewModel?.activationStartDate ?? Date())
                                } else {
                                    viewModel?.activationDueDate = nil
                                }
                            }
                        )
                    )

                    if viewModel?.activationDueDate != nil {
                        DatePicker(
                            L10n.string("Due date", defaultValue: "Due date"),
                            selection: Binding(
                                get: { viewModel?.activationDueDate ?? Date() },
                                set: { viewModel?.activationDueDate = $0 }
                            ),
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
            .accessibilityIdentifier("screen.pregnancy_activation")
            .navigationTitle(L10n.string("Pregnancy Mode", defaultValue: "Pregnancy Mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
            }
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
