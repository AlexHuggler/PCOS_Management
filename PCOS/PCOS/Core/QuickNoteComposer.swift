import Foundation

enum QuickNoteComposer {
    private static let separator = ", "

    static func isSelected(_ suggestion: String, in notes: String) -> Bool {
        let normalizedSuggestion = normalizeToken(suggestion)
        guard !normalizedSuggestion.isEmpty else { return false }

        return tokens(from: notes).contains { normalizeToken($0) == normalizedSuggestion }
    }

    static func toggled(_ suggestion: String, in notes: String) -> String {
        let normalizedSuggestion = normalizeToken(suggestion)
        guard !normalizedSuggestion.isEmpty else { return notes }

        var currentTokens = deduplicated(tokens(from: notes))
        if let index = currentTokens.firstIndex(where: { normalizeToken($0) == normalizedSuggestion }) {
            currentTokens.remove(at: index)
        } else {
            currentTokens.append(suggestion.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return currentTokens.joined(separator: separator)
    }

    static func tokens(from notes: String) -> [String] {
        notes
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let normalized = normalizeToken(value)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            output.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private static func normalizeToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
