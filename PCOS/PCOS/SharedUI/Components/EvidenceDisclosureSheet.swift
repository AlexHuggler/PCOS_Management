import SwiftUI

struct EvidenceDisclosureSheet: View {
    @Environment(\.dismiss) private var dismiss

    let content: InsightDisclosureContent
    let language: AppLanguage

    @State private var showingReferences = false

    var body: some View {
        if AppTheme.usesPremiumEditorStyling {
            lunarBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
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

    private var lunarBody: some View {
        NavigationStack {
            ZStack {
                BotanicalScreenBackground(style: .dense)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                        LunarDisclosureHero(
                            title: content.headerTitle,
                            subtitle: content.navigationTitle,
                            evidenceStrength: content.evidenceStrength,
                            language: language
                        )
                        .accessibilityIdentifier("evidence_disclosure.lunar.header")

                        LunarDisclosureBodyCard(
                            title: whySectionTitle,
                            text: content.specificExplanation,
                            iconName: "sparkles",
                            tint: AppTheme.premiumEditorAccentColor,
                            accessibilityID: "evidence_disclosure.specific_explanation"
                        )
                        .accessibilityIdentifier("evidence_disclosure.lunar.specific_explanation")
                        .background(alignment: .topLeading) {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .accessibilityIdentifier("evidence_disclosure.specific_explanation")
                        }

                        if let evidenceSummary = content.evidenceSummary {
                            LunarDisclosureBodyCard(
                                title: evidenceSectionTitle,
                                text: evidenceSummary,
                                iconName: "chart.line.uptrend.xyaxis",
                                tint: AppTheme.lavenderAccent,
                                accessibilityID: "evidence_disclosure.evidence_summary"
                            )
                            .accessibilityIdentifier("evidence_disclosure.lunar.evidence_summary")
                            .background(alignment: .topLeading) {
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .accessibilityIdentifier("evidence_disclosure.evidence_summary")
                            }
                        }

                        if !content.referenceDocket.isEmpty {
                            LunarDisclosureReferencesCard(
                                references: content.referenceDocket,
                                language: language,
                                showingReferences: $showingReferences
                            )
                            .accessibilityIdentifier("evidence_disclosure.lunar.references")
                            .background(alignment: .topLeading) {
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .accessibilityIdentifier("evidence_disclosure.references_toggle")
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacing20)
                    .padding(.top, AppTheme.spacing20)
                    .padding(.bottom, AppTheme.spacing32)
                }
                .accessibilityIdentifier("screen.evidence_disclosure")
            }
            .navigationTitle(content.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.82)))
                            .overlay(Circle().stroke(AppTheme.premiumEditorBorder.opacity(0.7), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("Done", defaultValue: "Done", language: language))
                    .accessibilityIdentifier("evidence_disclosure.done_button")
                }
            }
            .toolbarBackground(AppTheme.premiumEditorBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
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

private struct LunarDisclosureHero: View {
    let title: String
    let subtitle: String
    let evidenceStrength: EvidenceStrength?
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.premiumEditorAccentGradient)

                    Image(systemName: "moon.stars.fill")
                        .appFont(.title3)
                        .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                }
                .frame(width: 54, height: 54)
                .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.24), radius: 18, y: 8)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(subtitle)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)
                        .textCase(.uppercase)

                    Text(title)
                        .appHeadingFont(.title, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("evidence_disclosure.header_title")
                }
            }

            if let evidenceStrength {
                HStack(spacing: AppTheme.spacing8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                        .accessibilityHidden(true)

                    Text(
                        L10n.string(
                            "Evidence strength",
                            defaultValue: "Evidence strength",
                            language: language
                        )
                    )
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(evidenceStrength.displayName)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                }
                .padding(.horizontal, AppTheme.spacing12)
                .padding(.vertical, AppTheme.spacing8)
                .background(Capsule().fill(AppTheme.premiumEditorSurface.opacity(0.72)))
                .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8))
                .accessibilityIdentifier("evidence_disclosure.evidence_strength")
            }
        }
        .padding(AppTheme.spacing16)
        .lunarDisclosureCard()
    }
}

private struct LunarDisclosureBodyCard: View {
    let title: String
    let text: String
    let iconName: String
    let tint: Color
    let accessibilityID: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: iconName)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.13)))
                    .accessibilityHidden(true)

                Text(title)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityIdentifier("\(accessibilityID).title")
            }

            Text(text)
                .appFont(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accessibilityID)
        }
        .padding(AppTheme.spacing16)
        .lunarDisclosureCard()
    }
}

private struct LunarDisclosureReferencesCard: View {
    let references: [EvidenceReference]
    let language: AppLanguage
    @Binding var showingReferences: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            Button(action: toggleReferences) {
                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "books.vertical.fill")
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(AppTheme.premiumEditorSecondaryAccentColor.opacity(0.13)))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                        Text(
                            L10n.string(
                                "References",
                                defaultValue: "References",
                                language: language
                            )
                        )
                            .appFont(.headline, weight: .semibold)
                            .foregroundStyle(AppTheme.primaryText)

                        Text(referenceCountText)
                            .appFont(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Spacer()

                    Image(systemName: showingReferences ? "chevron.up" : "chevron.down")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(AppTheme.secondaryText)
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

                VStack(spacing: AppTheme.spacing12) {
                    ForEach(Array(references.enumerated()), id: \.element.id) { index, reference in
                        LunarDisclosureSourceRow(
                            index: index,
                            reference: reference,
                            language: language
                        )
                    }
                }
            }
        }
        .padding(AppTheme.spacing16)
        .lunarDisclosureCard()
    }

    private var referenceCountText: String {
        L10n.format(
            "%lld curated sources",
            defaultValue: "%lld curated sources",
            language: language,
            Int64(references.count)
        )
    }

    private func toggleReferences() {
        showingReferences.toggle()
    }
}

private struct LunarDisclosureSourceRow: View {
    let index: Int
    let reference: EvidenceReference
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                Text("\(index + 1)")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(AppTheme.premiumEditorAccentGradient))

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(reference.title)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(reference.sourceLabel)
                        .appFont(.caption, weight: .medium)
                        .foregroundStyle(AppTheme.premiumEditorAccentColor)

                    Text(reference.relevanceNote)
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: reference.url) {
                        Label(
                            L10n.string("View Source", defaultValue: "View Source", language: language),
                            systemImage: "arrow.up.right"
                        )
                        .appFont(.caption, weight: .semibold)
                    }
                    .foregroundStyle(AppTheme.premiumEditorSecondaryAccentColor)
                    .accessibilityIdentifier("evidence_disclosure.source_link.\(index)")
                }
            }
        }
        .padding(AppTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .fill(AppTheme.premiumEditorSurface.opacity(0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("evidence_disclosure.source.\(index)")
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

private extension View {
    func lunarDisclosureCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                            AppTheme.premiumEditorSurface.opacity(0.78),
                            AppTheme.premiumEditorBackground.opacity(0.9),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLarge, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.85)
        )
        .shadow(color: AppTheme.cardShadowColor, radius: 18, y: 12)
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
