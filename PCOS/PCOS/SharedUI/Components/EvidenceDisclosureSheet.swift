import SwiftUI

struct EvidenceDisclosureSheet: View {
    @Environment(\.dismiss) private var dismiss

    let content: InsightDisclosureContent
    let language: AppLanguage

    @State private var showingReferences = false

    var body: some View {
        NavigationStack {
            List {
                DisclosureHeaderSection(content: content, language: language)
                DisclosureBodySection(
                    title: whySectionTitle,
                    text: content.specificExplanation,
                    accessibilityID: "evidence_disclosure.specific_explanation"
                )

                if let evidenceSummary = content.evidenceSummary {
                    DisclosureBodySection(
                        title: evidenceSectionTitle,
                        text: evidenceSummary,
                        accessibilityID: "evidence_disclosure.evidence_summary"
                    )
                }

                if !content.referenceDocket.isEmpty {
                    DisclosureReferencesSection(
                        references: content.referenceDocket,
                        language: language,
                        showingReferences: $showingReferences
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(content.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Done", defaultValue: "Done", language: language)) {
                        dismiss()
                    }
                    .accessibilityIdentifier("evidence_disclosure.done_button")
                }
            }
        }
        .accessibilityIdentifier("evidence_disclosure.sheet")
    }

    private var whySectionTitle: String {
        L10n.string(
            "Why you're seeing this",
            defaultValue: "Why you're seeing this",
            language: language
        )
    }

    private var evidenceSectionTitle: String {
        L10n.string(
            "Evidence overview",
            defaultValue: "Evidence overview",
            language: language
        )
    }
}

private struct DisclosureHeaderSection: View {
    let content: InsightDisclosureContent
    let language: AppLanguage

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(content.headerTitle)
                    .appFont(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("evidence_disclosure.header_title")

                if let evidenceStrength = content.evidenceStrength {
                    DisclosureEvidenceStrengthRow(
                        evidenceStrength: evidenceStrength,
                        language: language
                    )
                }
            }
            .padding(.vertical, AppTheme.spacing4)
        }
    }
}

private struct DisclosureEvidenceStrengthRow: View {
    let evidenceStrength: EvidenceStrength
    let language: AppLanguage

    var body: some View {
        HStack(spacing: AppTheme.spacing8) {
            Text(
                L10n.string(
                    "Evidence strength",
                    defaultValue: "Evidence strength",
                    language: language
                )
            )
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Text(evidenceStrength.displayName)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.accentColor)
        }
        .accessibilityIdentifier("evidence_disclosure.evidence_strength")
    }
}

private struct DisclosureBodySection: View {
    let title: String
    let text: String
    let accessibilityID: String

    var body: some View {
        Section {
            Text(text)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(accessibilityID)
        } header: {
            Text(title)
                .accessibilityIdentifier("\(accessibilityID).title")
        }
    }
}

private struct DisclosureReferencesSection: View {
    let references: [EvidenceReference]
    let language: AppLanguage
    @Binding var showingReferences: Bool

    var body: some View {
        Section {
            Button(action: toggleReferences) {
                HStack(spacing: AppTheme.spacing8) {
                    Text(
                        L10n.string(
                            "References",
                            defaultValue: "References",
                            language: language
                        )
                    )
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showingReferences ? "chevron.up" : "chevron.down")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier("evidence_disclosure.references_toggle")
            .accessibilityValue(
                showingReferences
                    ? L10n.string(
                        "References expanded",
                        defaultValue: "References expanded",
                        language: language
                    )
                    : ""
            )

            if showingReferences {
                DisclosureExpandedReferencesMarker(language: language)
                ForEach(Array(references.enumerated()), id: \.element.id) { index, reference in
                    DisclosureSourceRow(
                        index: index,
                        reference: reference,
                        language: language
                    )
                }
            }
        }
    }

    private func toggleReferences() {
        showingReferences.toggle()
    }
}

private struct DisclosureExpandedReferencesMarker: View {
    let language: AppLanguage

    var body: some View {
        Text(
            L10n.string(
                "References expanded",
                defaultValue: "References expanded",
                language: language
            )
        )
            .appFont(.caption2)
            .foregroundStyle(.clear)
            .opacity(0.01)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("evidence_disclosure.references_content")
    }
}

private struct DisclosureSourceRow: View {
    let index: Int
    let reference: EvidenceReference
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            Text(reference.title)
                .appFont(.subheadline, weight: .medium)
                .foregroundStyle(.primary)

            Text(reference.sourceLabel)
                .appFont(.caption)
                .foregroundStyle(.secondary)

            Text(reference.relevanceNote)
                .appFont(.caption)
                .foregroundStyle(.secondary)

            Link(
                L10n.string("View Source", defaultValue: "View Source", language: language),
                destination: reference.url
            )
                .appFont(.caption, weight: .semibold)
                .accessibilityIdentifier("evidence_disclosure.source_link.\(index)")
        }
        .padding(.vertical, AppTheme.spacing4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evidence_disclosure.source.\(index)")
    }
}
