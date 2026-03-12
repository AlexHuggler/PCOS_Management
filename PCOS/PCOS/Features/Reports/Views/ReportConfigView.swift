import SwiftUI
import SwiftData

struct ReportConfigView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var viewModel: ReportViewModel?
    @State private var reportGenerated = false

    private enum ActiveAlert: Identifiable {
        case error(String)

        var id: String {
            switch self {
            case .error: "error"
            }
        }
    }

    @State private var activeAlert: ActiveAlert?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    reportForm(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Health Report")
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .error(let message):
                    return Alert(
                        title: Text("Report Error"),
                        message: Text(message),
                        dismissButton: .cancel(Text("OK"))
                    )
                }
            }
            .sensoryFeedback(.success, trigger: reportGenerated)
            .onAppear {
                if viewModel == nil {
                    viewModel = ReportViewModel(modelContext: modelContext)
                }
            }
        }
        .premiumGated()
    }

    // MARK: - Report Form

    @ViewBuilder
    private func reportForm(viewModel: ReportViewModel) -> some View {
        List {
            // Date Range
            Section {
                DatePicker(
                    "Start Date",
                    selection: Bindable(viewModel).startDate,
                    in: ...viewModel.endDate,
                    displayedComponents: .date
                )

                DatePicker(
                    "End Date",
                    selection: Bindable(viewModel).endDate,
                    in: viewModel.startDate...,
                    displayedComponents: .date
                )
            } header: {
                Text("Date Range")
            }

            // Section Toggles
            Section {
                Toggle("Cycles", isOn: Bindable(viewModel).includeCycles)
                Toggle("Symptoms", isOn: Bindable(viewModel).includeSymptoms)
                Toggle("Blood Sugar", isOn: Bindable(viewModel).includeBloodSugar)
                Toggle("Supplements", isOn: Bindable(viewModel).includeSupplements)
                Toggle("Meals", isOn: Bindable(viewModel).includeMeals)
                Toggle("Insights", isOn: Bindable(viewModel).includeInsights)
            } header: {
                Text("Include Sections")
            }

            // Generate / Share
            Section {
                if viewModel.isGenerating {
                    HStack(spacing: AppTheme.spacing12) {
                        ProgressView()
                        Text("Generating report...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let pdfURL = viewModel.generatedPDFURL {
                    ShareLink(
                        item: pdfURL,
                        preview: SharePreview(
                            "CycleBalance Health Report",
                            image: Image(systemName: "doc.richtext")
                        )
                    ) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(AppTheme.coralAccent)

                    Button {
                        generateReport(viewModel: viewModel)
                    } label: {
                        Label("Regenerate Report", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(AppTheme.sage)
                } else {
                    Button {
                        generateReport(viewModel: viewModel)
                    } label: {
                        Text("Generate Report")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(AppTheme.coralAccent))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(AppTheme.sage)
    }

    // MARK: - Actions

    private func generateReport(viewModel: ReportViewModel) {
        Task {
            await viewModel.generateReport()
            if let error = viewModel.errorMessage {
                activeAlert = .error(error)
            } else if viewModel.generatedPDFURL != nil {
                reportGenerated.toggle()
            }
        }
    }
}

#Preview {
    ReportConfigView()
        .modelContainer(for: Cycle.self, inMemory: true)
        .environment(AppState())
}
