import SwiftUI
import UIKit

struct FSAHSAResourcesView: View {
    @Environment(AppState.self) private var appState
    @State private var patientName = ""
    @State private var clinicianName = ""
    @State private var clinicianPractice = ""
    @State private var recommendedItems: String
    @State private var notes = ""
    @State private var copied = false

    private let letterService: MedicalNecessityLetterGenerating = MedicalNecessityLetterService()

    init() {
        _recommendedItems = State(
            initialValue: L10n.string(
                "Low-glycemic nutrition support, blood glucose monitoring supplies, and symptom tracking support for PCOS management.",
                defaultValue: "Low-glycemic nutrition support, blood glucose monitoring supplies, and symptom tracking support for PCOS management.",
                language: AppLanguage.stored()
            )
        )
    }

    private var letterText: String {
        letterService.generateLetter(
            from: MedicalNecessityLetterInput(
                patientName: patientName,
                clinicianName: clinicianName,
                clinicianPractice: clinicianPractice,
                recommendedItems: recommendedItems,
                notes: notes
            ),
            now: Date()
        )
    }

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(localized("E28.2 (Polycystic ovary syndrome)", defaultValue: "E28.2 (Polycystic ovary syndrome)"))
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text(localized("ICD-10", defaultValue: "ICD-10"))
                }
                Text(localized(
                    "Potentially eligible expenses can include condition-related tracking support and clinician-recommended supplies.",
                    defaultValue: "Potentially eligible expenses can include condition-related tracking support and clinician-recommended supplies."
                ))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(localized(
                    "Final reimbursement decisions are made by the plan administrator.",
                    defaultValue: "Final reimbursement decisions are made by the plan administrator."
                ))
                    .appFont(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(localized("FSA/HSA Reference", defaultValue: "FSA/HSA Reference"))
            }

            Section {
                TextField(text: $patientName) {
                    Text(localized("Patient name", defaultValue: "Patient name"))
                }
                TextField(text: $clinicianName) {
                    Text(localized("Clinician name", defaultValue: "Clinician name"))
                }
                TextField(text: $clinicianPractice) {
                    Text(localized("Practice / contact", defaultValue: "Practice / contact"))
                }

                Text(localized("Recommended items", defaultValue: "Recommended items"))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $recommendedItems)
                    .frame(minHeight: 80)

                Text(localized("Additional notes", defaultValue: "Additional notes"))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            } header: {
                Text(localized("Letter Inputs", defaultValue: "Letter Inputs"))
            }

            Section {
                TextEditor(text: .constant(letterText))
                    .frame(minHeight: 280)
                    .font(.footnote.monospaced())
                    .disabled(true)

                Button {
                    UIPasteboard.general.string = letterText
                    copied.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "doc.on.doc")
                        Text(localized("Copy Letter", defaultValue: "Copy Letter"))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }

                ShareLink(item: letterText) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text(localized("Share Letter", defaultValue: "Share Letter"))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            } header: {
                Text(localized("Letter of Medical Necessity (Editable Template)", defaultValue: "Letter of Medical Necessity (Editable Template)"))
            }
        }
        .navigationTitle(localized("FSA/HSA Tools", defaultValue: "FSA/HSA Tools"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copied)
    }

    private var language: AppLanguage {
        appState.selectedAppLanguage
    }

    private func localized(_ key: String, defaultValue: String? = nil) -> String {
        L10n.string(key, defaultValue: defaultValue, language: language)
    }
}

#Preview {
    NavigationStack {
        FSAHSAResourcesView()
    }
}
