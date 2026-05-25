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
            Form {
                Section(L10n.string("End Reason", defaultValue: "End Reason")) {
                    Picker(
                        L10n.string("Reason", defaultValue: "Reason"),
                        selection: Binding(
                            get: { viewModel?.endReason ?? .delivery },
                            set: { viewModel?.endReason = $0 }
                        )
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
                        selection: Binding(
                            get: { viewModel?.endDate ?? Date() },
                            set: { viewModel?.endDate = $0 }
                        ),
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
            .navigationTitle(L10n.string("End Pregnancy Mode", defaultValue: "End Pregnancy Mode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .alert(
                L10n.string("End Pregnancy Mode?", defaultValue: "End Pregnancy Mode?"),
                isPresented: $showConfirmation
            ) {
                Button(L10n.string("Confirm", defaultValue: "Confirm")) {
                    endPregnancy()
                }
                Button(L10n.string("Cancel", defaultValue: "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.string(
                    "Cycle tracking will resume. Your pregnancy data will be preserved.",
                    defaultValue: "Cycle tracking will resume. Your pregnancy data will be preserved."
                ))
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
