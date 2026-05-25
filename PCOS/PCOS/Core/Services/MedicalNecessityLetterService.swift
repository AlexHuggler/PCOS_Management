import Foundation

struct MedicalNecessityLetterInput {
    var patientName: String
    var clinicianName: String
    var clinicianPractice: String
    var recommendedItems: String
    var notes: String
}

protocol MedicalNecessityLetterGenerating {
    func generateLetter(from input: MedicalNecessityLetterInput, now: Date) -> String
}

struct MedicalNecessityLetterService: MedicalNecessityLetterGenerating {
    func generateLetter(from input: MedicalNecessityLetterInput, now: Date = Date()) -> String {
        let locale = L10n.locale(for: AppLanguage.stored())
        let dateText = now.formatted(.dateTime.locale(locale).month(.abbreviated).day().year())
        let clinicianLine = input.clinicianName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localized("Clinician Name", defaultValue: "Clinician Name")
            : input.clinicianName
        let practiceLine = input.clinicianPractice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localized("Practice / Contact", defaultValue: "Practice / Contact")
            : input.clinicianPractice
        let patientLine = input.patientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localized("Patient Name", defaultValue: "Patient Name")
            : input.patientName
        let itemsLine = input.recommendedItems.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localized(
                "Evidence-based nutrition and symptom management support related to PCOS.",
                defaultValue: "Evidence-based nutrition and symptom management support related to PCOS."
            )
            : input.recommendedItems
        let notesLine = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let optionalNotes = notesLine.isEmpty
            ? ""
            : "\n\(localized("Additional clinical notes:", defaultValue: "Additional clinical notes:"))\n\(notesLine)\n"

        return """
        \(localized("Date", defaultValue: "Date")): \(dateText)

        \(localized("Re: Letter of Medical Necessity", defaultValue: "Re: Letter of Medical Necessity"))
        \(localized("Patient", defaultValue: "Patient")): \(patientLine)

        \(localized("To Whom It May Concern,", defaultValue: "To Whom It May Concern,"))

        \(localized("I am writing to document medical necessity for support services and related care for the above patient, who is being managed for Polycystic Ovary Syndrome (PCOS), ICD-10 code E28.2.", defaultValue: "I am writing to document medical necessity for support services and related care for the above patient, who is being managed for Polycystic Ovary Syndrome (PCOS), ICD-10 code E28.2."))

        \(localized("Recommended medically necessary support includes:", defaultValue: "Recommended medically necessary support includes:"))
        \(itemsLine)\(optionalNotes)
        \(localized("This support is intended to assist management of metabolic, endocrine, and symptom burden associated with PCOS. Please consider this letter as supporting documentation for applicable FSA/HSA reimbursement review.", defaultValue: "This support is intended to assist management of metabolic, endocrine, and symptom burden associated with PCOS. Please consider this letter as supporting documentation for applicable FSA/HSA reimbursement review."))

        \(localized("Sincerely,", defaultValue: "Sincerely,"))
        \(clinicianLine)
        \(practiceLine)

        \(localized("Disclaimer: Template only. Final clinical wording should be reviewed and edited by a licensed clinician.", defaultValue: "Disclaimer: Template only. Final clinical wording should be reviewed and edited by a licensed clinician."))
        """
    }

    private func localized(_ key: String, defaultValue: String? = nil) -> String {
        L10n.string(key, defaultValue: defaultValue)
    }
}
