import Foundation

/// Pulls math spans out of the raw Markdown before swift-markdown parses them,
/// replacing each with a private-use placeholder. This mirrors why MarkText runs
/// math as a marked extension: without it `\(...\)` loses its escapes and
/// emphasis characters inside `$...$` would be parsed as Markdown.
enum MathExtractor {
    struct Item {
        let latex: String
        let display: Bool
    }

    static let openMark: Character = "\u{E000}"
    static let closeMark: Character = "\u{E001}"

    static func placeholder(_ index: Int) -> String {
        "\(openMark)\(index)\(closeMark)"
    }

    /// Returns the item when `text` consists solely of one math placeholder.
    static func item(for text: String, items: [Item]) -> Item? {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard characters.count >= 3,
              characters.first == openMark,
              characters.last == closeMark else { return nil }
        let numberText = String(characters[1..<(characters.count - 1)])
        guard let index = Int(numberText), items.indices.contains(index) else { return nil }
        return items[index]
    }

    static func extract(_ source: String) -> (body: String, items: [Item]) {
        var items: [Item] = []
        let lines = source.components(separatedBy: "\n")
        var output: [String] = []
        var fence: (character: Character, length: Int)?
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let active = fence {
                output.append(line)
                if isFenceMarker(trimmed, character: active.character, minimum: active.length) {
                    fence = nil
                }
                index += 1
                continue
            }

            if let marker = fenceMarker(trimmed) {
                fence = marker
                output.append(line)
                index += 1
                continue
            }

            if trimmed == "$$" || trimmed == "\\[" {
                let closing = trimmed == "$$" ? "$$" : "\\]"
                var content: [String] = []
                var cursor = index + 1
                var closed = false
                while cursor < lines.count {
                    if lines[cursor].trimmingCharacters(in: .whitespaces) == closing {
                        closed = true
                        break
                    }
                    content.append(lines[cursor])
                    cursor += 1
                }
                if closed {
                    let latex = content.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        items.append(Item(latex: latex, display: true))
                        output.append("")
                        output.append(placeholder(items.count - 1))
                        output.append("")
                    }
                    index = cursor + 1
                    continue
                }
            }

            if let displayMath = singleLineDisplayMath(trimmed) {
                items.append(Item(latex: displayMath, display: true))
                output.append("")
                output.append(placeholder(items.count - 1))
                output.append("")
                index += 1
                continue
            }

            output.append(extractInline(from: line, items: &items))
            index += 1
        }

        return (output.joined(separator: "\n"), items)
    }

    // MARK: - Fences

    private static func fenceMarker(_ trimmed: String) -> (character: Character, length: Int)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        return (first, count)
    }

    private static func isFenceMarker(_ trimmed: String, character: Character, minimum: Int) -> Bool {
        guard trimmed.first == character else { return false }
        let count = trimmed.prefix { $0 == character }.count
        guard count >= minimum else { return false }
        return trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Display math

    private static func singleLineDisplayMath(_ trimmed: String) -> String? {
        let characters = Array(trimmed)
        guard characters.count > 4 else { return nil }
        let last = characters.count - 1

        if characters[0] == "$", characters[1] == "$",
           characters[last] == "$", characters[last - 1] == "$" {
            let content = String(characters[2..<(characters.count - 2)])
                .trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : content
        }

        if characters[0] == "\\", characters[1] == "[",
           characters[last] == "]", characters[last - 1] == "\\" {
            let content = String(characters[2..<(characters.count - 2)])
                .trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : content
        }

        return nil
    }

    // MARK: - Inline math

    private static func extractInline(from line: String, items: inout [Item]) -> String {
        let characters = Array(line)
        var output = ""
        var index = 0
        var codeTicks = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\\" {
                if index + 1 < characters.count, characters[index + 1] == "(",
                   let result = inlineParenthesizedMath(characters, from: index, items: &items) {
                    output += result.text
                    index = result.next
                    continue
                }
                output.append(character)
                if index + 1 < characters.count {
                    output.append(characters[index + 1])
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            if character == "`" {
                let count = characters[index...].prefix { $0 == "`" }.count
                if codeTicks == 0 {
                    codeTicks = count
                } else if count == codeTicks {
                    codeTicks = 0
                }
                output += String(repeating: "`", count: count)
                index += count
                continue
            }

            if codeTicks == 0, character == "$",
               index + 1 < characters.count, characters[index + 1] != "$",
               let result = dollarMath(characters, from: index, items: &items) {
                output += result.text
                index = result.next
                continue
            }

            output.append(character)
            index += 1
        }

        return output
    }

    private static func inlineParenthesizedMath(
        _ characters: [Character],
        from start: Int,
        items: inout [Item]
    ) -> (text: String, next: Int)? {
        var cursor = start + 2
        while cursor + 1 < characters.count {
            if characters[cursor] == "\\", characters[cursor + 1] == ")" {
                let latex = String(characters[(start + 2)..<cursor])
                    .trimmingCharacters(in: .whitespaces)
                guard !latex.isEmpty else { return nil }
                items.append(Item(latex: latex, display: false))
                return (placeholder(items.count - 1), cursor + 2)
            }
            cursor += 1
        }
        return nil
    }

    private static func dollarMath(
        _ characters: [Character],
        from start: Int,
        items: inout [Item]
    ) -> (text: String, next: Int)? {
        guard !characters[start + 1].isWhitespace else { return nil }
        var cursor = start + 1
        while cursor < characters.count {
            if characters[cursor] == "\\" {
                cursor += 2
                continue
            }
            if characters[cursor] == "$" {
                let content = String(characters[(start + 1)..<cursor])
                guard !content.isEmpty,
                      !content.hasPrefix(" "), !content.hasSuffix(" "),
                      !(cursor + 1 < characters.count && characters[cursor + 1].isNumber) else {
                    return nil
                }
                items.append(Item(latex: content, display: false))
                return (placeholder(items.count - 1), cursor + 1)
            }
            cursor += 1
        }
        return nil
    }
}
