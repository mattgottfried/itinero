import Foundation

enum SearchLogic {
    /// Every word in the query must appear somewhere in the fields; ignores case and accents ("pokemon" finds "Pokémon").
    static func matches(_ query: String, in fields: [String]) -> Bool {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = fields.joined(separator: " ")
        return tokens.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
