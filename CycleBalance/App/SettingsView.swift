import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var showDeletedFeedback = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    HStack {
                        Label("Subscription", systemImage: "star.circle")
                        Spacer()
                        Text(appState.isPremium ? "Premium" : "Free")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data") {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Export", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            generateExport()
                        } label: {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

                Section("Health") {
                    Label("HealthKit Access", systemImage: "heart.text.square")
                    Label("CloudKit Sync", systemImage: "icloud")
                }

                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Label("Privacy Policy", systemImage: "hand.raised")
                    Label("Terms of Service", systemImage: "doc.text")

                    Button {
                        appState.onboardingProfile.resetOnboarding()
                        appState.hasCompletedOnboarding = false
                    } label: {
                        Label("Replay Welcome Tour", systemImage: "arrow.counterclockwise")
                    }
                }

                Section {
                    VStack(alignment: .center, spacing: 4) {
                        Text("CycleBalance")
                            .font(.footnote)
                            .fontWeight(.medium)
                        Text("Not a medical device. Always consult your healthcare provider.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .sensoryFeedback(.warning, trigger: showDeleteConfirmation)
            .sensoryFeedback(.success, trigger: showDeletedFeedback)
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "An unknown error occurred.")
            }
            .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all your cycle data, symptoms, and insights. This action cannot be undone.")
            }
        }
    }

    private func generateExport() {
        var csv = "Type,Date,Detail,Value,Notes\n"

        // Export cycles
        let cycleDescriptor = FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.startDate)])
        if let cycles = try? modelContext.fetch(cycleDescriptor) {
            for cycle in cycles {
                let dateStr = ISO8601DateFormatter().string(from: cycle.startDate)
                let length = cycle.lengthDays.map(String.init) ?? "ongoing"
                csv += "Cycle,\(dateStr),Length,\(length),\n"
            }
        }

        // Export cycle entries
        let entryDescriptor = FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)])
        if let entries = try? modelContext.fetch(entryDescriptor) {
            for entry in entries {
                let dateStr = ISO8601DateFormatter().string(from: entry.date)
                let flow = entry.flowIntensity?.displayName ?? "none"
                let notes = entry.notes?.replacingOccurrences(of: ",", with: ";") ?? ""
                csv += "Period,\(dateStr),\(flow),\(entry.isPeriodDay ? "yes" : "no"),\(notes)\n"
            }
        }

        // Export symptoms
        let symptomDescriptor = FetchDescriptor<SymptomEntry>(sortBy: [SortDescriptor(\.date)])
        if let symptoms = try? modelContext.fetch(symptomDescriptor) {
            for symptom in symptoms {
                let dateStr = ISO8601DateFormatter().string(from: symptom.date)
                let notes = symptom.notes?.replacingOccurrences(of: ",", with: ";") ?? ""
                csv += "Symptom,\(dateStr),\(symptom.symptomType.displayName),\(symptom.severity),\(notes)\n"
            }
        }

        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("CycleBalance_Export.csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            exportURL = tempURL
        } catch {
            exportError = "Could not create export file: \(error.localizedDescription)"
        }
    }

    private func deleteAllData() {
        do {
            try modelContext.delete(model: CycleEntry.self)
            try modelContext.delete(model: Cycle.self)
            try modelContext.delete(model: SymptomEntry.self)
            try modelContext.delete(model: Insight.self)
            try modelContext.save()
            showDeletedFeedback.toggle()
        } catch {
            // Deletion is best-effort; SwiftData will log errors
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
