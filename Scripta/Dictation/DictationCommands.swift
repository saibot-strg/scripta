import Foundation

/// Spoken punctuation and line breaks in dictations, in German and English:
/// "Komma", "neue Zeile", "Rufzeichen", "question mark" …
///
/// Parakeet writes a spoken command as a word and usually sets it off with
/// punctuation of its own ("gut, Punkt, neue Zeile, bis morgen"; "well.
/// Period. New line. See"), sometimes it already wrote the character as well
/// ("dir? Fragezeichen,"). That punctuation is dropped and the command's
/// character put where it belongs.
enum DictationCommands {
    enum Placement {
        /// Sticks to the word before, space after: . , ? ! : ; …
        case trailing
        /// Starts a new line, without spaces around it.
        case lineBreak
        /// Space before, sticks to the word after: ( „ “
        case opening
        /// Sticks to the word before, space after: ) “ ”
        case closing
        /// Sticks to the words on both sides: - /
        case joining
        /// Spaces on both sides: –
        case spaced
    }

    struct Command {
        let phrases: [String]
        let symbol: String
        let placement: Placement
        /// Also an ordinary word ("der Punkt ist …", "a period of time"): a
        /// command only when it stands alone, i.e. between punctuation, next
        /// to another command, at the start or end, or between digits.
        var isAmbiguous = false
    }

    static let all: [Command] = [
        Command(phrases: ["Punkt"], symbol: ".", placement: .trailing, isAmbiguous: true),
        Command(phrases: ["period"], symbol: ".", placement: .trailing, isAmbiguous: true),
        Command(phrases: ["full stop"], symbol: ".", placement: .trailing),
        Command(phrases: ["Komma", "comma"], symbol: ",", placement: .trailing),
        Command(phrases: ["Fragezeichen", "question mark"], symbol: "?", placement: .trailing),
        Command(phrases: ["Ausrufezeichen", "Ausrufzeichen", "Rufzeichen", "exclamation mark", "exclamation point"],
                symbol: "!", placement: .trailing),
        Command(phrases: ["Doppelpunkt"], symbol: ":", placement: .trailing),
        Command(phrases: ["colon"], symbol: ":", placement: .trailing, isAmbiguous: true),
        Command(phrases: ["Semikolon", "Strichpunkt", "semicolon"], symbol: ";", placement: .trailing),
        Command(phrases: ["Auslassungspunkte", "ellipsis"], symbol: "…", placement: .trailing),
        Command(phrases: ["neue Zeile", "Zeilenumbruch", "new line", "newline", "line break"], symbol: "\n", placement: .lineBreak),
        Command(phrases: ["neuer Absatz", "new paragraph"], symbol: "\n\n", placement: .lineBreak),
        Command(phrases: ["Absatz"], symbol: "\n\n", placement: .lineBreak, isAmbiguous: true),
        Command(phrases: ["Bindestrich", "hyphen"], symbol: "-", placement: .joining),
        Command(phrases: ["Gedankenstrich"], symbol: "–", placement: .spaced),
        Command(phrases: ["dash"], symbol: "–", placement: .spaced, isAmbiguous: true),
        Command(phrases: ["Schrägstrich"], symbol: "/", placement: .joining),
        Command(phrases: ["slash"], symbol: "/", placement: .joining, isAmbiguous: true),
        Command(phrases: ["Klammer auf", "open parenthesis", "open paren", "open bracket"], symbol: "(", placement: .opening),
        Command(phrases: ["Klammer zu", "close parenthesis", "close paren", "close bracket"], symbol: ")", placement: .closing),
        Command(phrases: ["Anführungszeichen auf"], symbol: "„", placement: .opening),
        Command(phrases: ["Anführungszeichen zu"], symbol: "“", placement: .closing),
        Command(phrases: ["open quote"], symbol: "“", placement: .opening),
        Command(phrases: ["close quote", "end quote"], symbol: "”", placement: .closing),
    ]

    /// Replaces the spoken commands in recognized text.
    static func apply(to text: String) -> String {
        let source = text as NSString
        var output = Output(isEnglish: TranscriptBuilder.detectLanguage(of: text) == "en")
        var cursor = 0

        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard match.range.location >= cursor,
                  let command = commandsByPhrase[normalized(source.substring(with: match.range))] else { continue }

            // Spaces and punctuation Parakeet put around the command.
            var left = match.range.location
            while left > cursor, isSeparator(source.character(at: left - 1)) { left -= 1 }
            var right = NSMaxRange(match.range)
            while right < source.length, isSeparator(source.character(at: right)) { right += 1 }
            let leftPunctuation = source.substring(with: NSRange(location: left, length: match.range.location - left))
            let rightPunctuation = source.substring(with: NSRange(location: NSMaxRange(match.range), length: right - NSMaxRange(match.range)))

            let nextIsDigit = right < source.length && isDigit(source.character(at: right))
            if command.isAmbiguous {
                let aloneOnTheLeft = left == cursor || leftPunctuation.contains(where: isPunctuation)
                let aloneOnTheRight = right == source.length || rightPunctuation.contains(where: isPunctuation)
                // "Version 2 Punkt 1"
                let betweenDigits = left > 0 && isDigit(source.character(at: left - 1)) && nextIsDigit
                    && !leftPunctuation.contains(where: isPunctuation) && !rightPunctuation.contains(where: isPunctuation)
                guard (aloneOnTheLeft && aloneOnTheRight) || betweenDigits else { continue }
            }

            output.appendText(source.substring(with: NSRange(location: cursor, length: left - cursor)))
            output.append(command, leftPunctuation: leftPunctuation, rightPunctuation: rightPunctuation, nextIsDigit: nextIsDigit)
            cursor = right
        }
        output.appendText(source.substring(from: cursor))
        return output.result
    }

    // MARK: - Matching

    private static let commandsByPhrase: [String: Command] = Dictionary(
        all.flatMap { command in command.phrases.map { (normalized($0), command) } },
        uniquingKeysWith: { first, _ in first }
    )

    /// All phrases, longest first ("neuer Absatz" before "Absatz"), as whole words.
    private static let pattern: NSRegularExpression = {
        let phrases = all.flatMap(\.phrases).sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
        let alternatives = phrases.joined(separator: "|")
        // Lookarounds instead of \b, so "Zeitpunkt" and "Punkte" don't match.
        return try! NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        )
    }()

    private static func normalized(_ phrase: String) -> String {
        phrase.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let punctuation: Set<Character> = [",", ".", ";", ":", "!", "?", "…"]
    private static let sentenceEnds: Set<Character> = [".", "?", "!"]

    private static func isPunctuation(_ character: Character) -> Bool {
        punctuation.contains(character)
    }

    private static func isSeparator(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        let character = Character(scalar)
        return character == " " || character == "\t" || isPunctuation(character)
    }

    private static func isDigit(_ unit: unichar) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    // MARK: - Output

    private struct Output {
        let isEnglish: Bool
        private(set) var text = ""
        /// What goes between the last command and the next words.
        private var separator = ""
        private var capitalizesNext = false
        /// English only: Parakeet capitalized the next word after a full stop
        /// of its own, which a spoken comma or colon replaced.
        private var lowercasesNext = false

        init(isEnglish: Bool) {
            self.isEnglish = isEnglish
        }

        var result: String {
            text.trimmingCharacters(in: .whitespaces)
        }

        /// Words between commands; the commands decide the spacing around them.
        mutating func appendText(_ chunk: String) {
            let words = chunk.drop(while: \.isWhitespace)
            guard !words.isEmpty else { return }
            if !text.isEmpty, !text.hasSuffix("\n") { text += separator }
            if capitalizesNext {
                text += words.prefix(1).uppercased() + words.dropFirst()
            } else if lowercasesNext, Self.mayLowercase(words) {
                text += words.prefix(1).lowercased() + words.dropFirst()
            } else {
                text += words
            }
            separator = ""
            capitalizesNext = false
            lowercasesNext = false
        }

        mutating func append(_ command: Command, leftPunctuation: String, rightPunctuation: String, nextIsDigit: Bool) {
            let parakeetEndedSentence = rightPunctuation.contains(where: DictationCommands.sentenceEnds.contains)
            separator = ""
            capitalizesNext = false
            lowercasesNext = false

            switch command.placement {
            case .trailing:
                let joinsDigits = [",", "."].contains(command.symbol) && text.last?.isNumber == true && nextIsDigit
                text += command.symbol
                separator = joinsDigits ? "" : " "
                capitalizesNext = DictationCommands.sentenceEnds.contains(Character(command.symbol))
                lowercasesNext = isEnglish && !capitalizesNext && parakeetEndedSentence
            case .lineBreak:
                // A sentence end before the break stays; Parakeet's commas don't.
                if let end = leftPunctuation.last(where: { ".?!:;…".contains($0) }), !text.isEmpty,
                   !text.hasSuffix("\n"), !(text.last.map(DictationCommands.punctuation.contains) ?? false) {
                    text.append(end)
                }
                text += command.symbol
                capitalizesNext = true
            case .opening:
                if !text.isEmpty, !text.hasSuffix("\n") { text += " " }
                text += command.symbol
            case .closing:
                text += command.symbol
                separator = " "
                lowercasesNext = isEnglish && parakeetEndedSentence
            case .joining:
                text += command.symbol
            case .spaced:
                if !text.isEmpty, !text.hasSuffix("\n") { text += " " }
                text += command.symbol
                separator = " "
                lowercasesNext = isEnglish && parakeetEndedSentence
            }
        }

        /// Not "I", "I'm" or acronyms.
        private static func mayLowercase(_ words: Substring) -> Bool {
            let word = words.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
            if word == "I" || word.hasPrefix("I'") || word.hasPrefix("I’") { return false }
            return !(word.count > 1 && word.allSatisfy(\.isUppercase))
        }
    }
}
