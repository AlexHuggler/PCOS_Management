import Testing
@testable import PCOS

@Suite("QuickNoteComposer")
struct QuickNoteComposerTests {
    @Test("Toggle appends and removes notes with comma separator")
    func toggleAddRemove() {
        var notes = ""

        notes = QuickNoteComposer.toggled("Felt fine", in: notes)
        #expect(notes == "Felt fine")

        notes = QuickNoteComposer.toggled("Missed meal", in: notes)
        #expect(notes == "Felt fine, Missed meal")

        notes = QuickNoteComposer.toggled("Felt fine", in: notes)
        #expect(notes == "Missed meal")
    }

    @Test("Selection matching is case-insensitive")
    func caseInsensitiveSelection() {
        let notes = "High stress, Poor sleep"
        #expect(QuickNoteComposer.isSelected("high stress", in: notes))
        #expect(QuickNoteComposer.isSelected("POOR SLEEP", in: notes))
    }

    @Test("Token parsing drops empty values and trims whitespace")
    func tokenParsing() {
        let tokens = QuickNoteComposer.tokens(from: "  Dizzy , ,  Shaky ,")
        #expect(tokens == ["Dizzy", "Shaky"])
    }

    @Test("Exact-match token clears follow-up suggestion query")
    func exactMatchTokenClearsSuggestionQuery() {
        let suggestions = ["High stress", "Late meal", "Ate out"]
        let query = QuickNoteComposer.suggestionQuery(
            in: "High stress, Late meal",
            availableSuggestions: suggestions
        )

        #expect(query.isEmpty)
    }

    @Test("Visible suggestions keep selected tokens when filtering")
    func visibleSuggestionsKeepSelectedTokens() {
        let visible = QuickNoteComposer.visibleSuggestions(
            from: ["Late meal"],
            selectedIn: "High stress, Late meal",
            availableSuggestions: ["High stress", "Late meal", "Ate out"]
        )

        #expect(visible == ["High stress", "Late meal"])
    }
}
