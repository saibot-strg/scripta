import SwiftUI

/// The block structure of a model's Markdown answer: headings, list items
/// and paragraphs. SwiftUI's `Text` only renders inline Markdown.
enum SummaryBlock: Equatable {
    case heading(String)
    /// `marker`: "•" or "1." for numbered lists; `level` 0 is the outermost list.
    case listItem(marker: String, text: String, level: Int)
    case paragraph(String)

    static func blocks(from markdown: String) -> [SummaryBlock] {
        var blocks: [SummaryBlock] = []
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line != "---" else { continue }
            if line.hasPrefix("#") {
                let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(.heading(text.trimmingCharacters(in: CharacterSet(charactersIn: "*")))) }
            } else if let bullet = ["- ", "* ", "• "].first(where: line.hasPrefix) {
                let text = line.dropFirst(bullet.count).trimmingCharacters(in: .whitespaces)
                blocks.append(.listItem(marker: "•", text: text, level: level(of: rawLine)))
            } else if let match = line.firstMatch(of: /^(\d{1,2})[.)]\s+(.+)$/) {
                blocks.append(.listItem(marker: "\(match.1).", text: String(match.2), level: level(of: rawLine)))
            } else if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4, !line.dropFirst(2).dropLast(2).contains("**") {
                // "**Kernpunkte**" on its own line is a heading too.
                blocks.append(.heading(String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: CharacterSet(charactersIn: ":"))))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }

    /// Nesting from the indentation: models indent sub-items by 2 or 4 spaces.
    private static func level(of line: String) -> Int {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return min((indent + 2) / 4, 2)
    }
}

/// Renders a summary: headings, bullet lists and paragraphs with inline
/// Markdown (bold, italics).
struct SummaryMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(SummaryBlock.blocks(from: markdown).enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let text):
                    Text(inline(text))
                        .font(.title3.weight(.semibold))
                        .padding(.top, index == 0 ? 0 : 12)
                        .accessibilityAddTraits(.isHeader)
                case .listItem(let marker, let text, let level):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: level == 0 ? marker : "◦")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(inline(text))
                    }
                    .padding(.leading, CGFloat(level) * 20)
                case .paragraph(let text):
                    Text(inline(text))
                }
            }
        }
        .font(.body)
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
