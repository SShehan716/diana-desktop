import Foundation

public enum CompanionText {
    public static let generationInstruction =
        "Use plain, conversational text with natural contractions. Never use emojis, emoticons, Markdown, roleplay actions, or stage directions. Do not start with a stock greeting or repeat the question."

    public static func generated(_ text: String) -> String {
        let emojiFree = text.map { character -> String in
            let scalars = character.unicodeScalars
            let pictograph = scalars.contains {
                $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000)
            }
            let keycap = scalars.contains { $0.value == 0x20E3 }
            if keycap {
                return scalars.first(where: {
                    (0x30...0x39).contains($0.value) || $0.value == 0x23 || $0.value == 0x2A
                }).map(String.init) ?? " "
            }
            return pictograph ? " " : String(character)
        }.joined()
        var result = emojiFree
        // Remove only recognizable stage directions; keep emphasized content.
        result = replacing(
            #"(?i)[*\[]\s*(?:smiles?|laughs?|chuckles?|grins?|giggles?|winks?|sighs?|nods?|waves?|clears throat)(?:\s+(?:warmly|softly|gently|at you))?\s*[*\]]"#,
            in: result, with: " ")
        result = replacing(#"\[([^\]]+)\]\([^\)]+\)"#, in: result, with: "$1")
        result = replacing(#"(\*\*|__)(.+?)\1"#, in: result, with: "$2")
        result = replacing(#"(?<!\w)\*([^*\n]+)\*(?!\w)"#, in: result, with: "$1")
        result = replacing(#"`([^`]+)`"#, in: result, with: "$1")
        result = replacing(#"(?m)^\s*(?:#{1,6}\s+|[-*•]\s+|\d+[.)]\s+)"#, in: result, with: "")
        result = replacing(#"(?<!\S)(?:[:;=8][-^]?[)(DPp/]|<3)(?=\s|$)"#, in: result, with: " ")
        result = replacing(#"[ \t]+"#, in: result, with: " ")
        result = replacing(#" +([,.;:!?])"#, in: result, with: "$1")
        result = replacing(#" *\n *"#, in: result, with: "\n")
        result = replacing(#"\n{3,}"#, in: result, with: "\n\n")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func spoken(_ text: String) -> String {
        var result = generated(text)
        // A standalone emoticon should never be pronounced as punctuation.
        result = replacing(#"(?<!\S)[:;=8][-^]?[)(DPp/](?=\s|$)"#, in: result, with: " ")
        result = replacing(#"[!?]{2,}"#, in: result, with: ".")
        result = replacing(#"[ \t]+"#, in: result, with: " ")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.count > 1500 else { return result }
        let limit = String(result.prefix(1500))
        if let end = limit.lastIndex(where: { ".!?".contains($0) }),
            limit.distance(from: limit.startIndex, to: end) > 750
        {
            return String(limit[...end])
        }
        if let end = limit.lastIndex(of: " ") { return String(limit[..<end]) + "." }
        return limit
    }
    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
