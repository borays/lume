import AppKit

struct InlineTextStyle {
    var font: NSFont
    var color: NSColor
    var attributes: [NSAttributedString.Key: Any] = [:]
    var mathFontSize: CGFloat = 14
    var footnotes: FootnoteRegistry?
    var isPrinting: Bool = false
    var mathItems: [MathExtractor.Item] = []
}

/// Renders the inline syntaxes MarkText adds on top of CommonMark/GFM:
/// `==mark==`, `^sup^`, `~sub~`, `:emoji:`, `[^footnote]`, `$math$` and `\(math\)`.
enum InlineExtensions {
    static func append(_ text: String, style: InlineTextStyle, to result: NSMutableAttributedString) {
        let characters = Array(text)
        var index = 0
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(NSAttributedString(string: buffer, attributes: baseAttributes(style)))
            buffer = ""
        }

        while index < characters.count {
            let character = characters[index]

            if character == MathExtractor.openMark {
                if let close = characters[(index + 1)...].firstIndex(of: MathExtractor.closeMark),
                   let number = Int(String(characters[(index + 1)..<close])),
                   style.mathItems.indices.contains(number) {
                    let item = style.mathItems[number]
                    if let attachment = mathAttachment(
                        item.latex,
                        fontSize: style.mathFontSize,
                        display: item.display,
                        style: style
                    ) {
                        flush()
                        result.append(attachment)
                        index = close + 1
                        continue
                    }
                }
            }

            if character == "\\" {
                if index + 1 < characters.count, characters[index + 1] == "(" {
                    if let rendered = inlineMath(characters, from: index + 2, closing: ")", style: style) {
                        flush()
                        result.append(rendered.attributed)
                        index = rendered.endIndex
                        continue
                    }
                }
                if index + 1 < characters.count {
                    flush()
                    result.append(NSAttributedString(string: String(characters[index + 1]), attributes: baseAttributes(style)))
                    index += 2
                    continue
                }
                buffer.append(character)
                index += 1
                continue
            }

            if character == "[", index + 1 < characters.count, characters[index + 1] == "^" {
                if let footnote = footnoteReference(characters, from: index, style: style) {
                    flush()
                    result.append(footnote.attributed)
                    index = footnote.endIndex
                    continue
                }
            }

            if character == "$", index + 1 < characters.count, characters[index + 1] != "$",
               !characters[index + 1].isWhitespace {
                if let rendered = inlineDollarMath(characters, from: index, style: style) {
                    flush()
                    result.append(rendered.attributed)
                    index = rendered.endIndex
                    continue
                }
            }

            if character == "=", index + 1 < characters.count, characters[index + 1] == "=",
               let closing = findMarkClose(characters, from: index + 2),
               closing > index + 2 {
                let content = String(characters[(index + 2)..<closing])
                if !content.isEmpty, !content.hasPrefix(" "), !content.hasSuffix(" ") {
                    flush()
                    var marked = style
                    var attributes = baseAttributes(style)
                    attributes[.backgroundColor] = InlineExtensions.markBackground
                    marked.attributes = attributes
                    append(content, style: marked, to: result)
                    index = closing + 2
                    continue
                }
            }

            if character == "^", !previousIsWhitespace(characters, index),
               let closing = findScriptClose(characters, from: index + 1, marker: "^") {
                let content = String(characters[(index + 1)..<closing])
                flush()
                result.append(script(content, style: style, superscript: true))
                index = closing + 1
                continue
            }

            // MarkText 规则：下标的 ~ 要紧跟前一个字符（H~2~O），且不能是删除线的 ~~。
            if character == "~", index + 1 < characters.count, characters[index + 1] != "~",
               !previousIsWhitespace(characters, index),
               let closing = findScriptClose(characters, from: index + 1, marker: "~") {
                let content = String(characters[(index + 1)..<closing])
                flush()
                result.append(script(content, style: style, superscript: false))
                index = closing + 1
                continue
            }

            if character == ":", index + 1 < characters.count,
               let closing = emojiClose(characters, from: index + 1) {
                let alias = String(characters[(index + 1)..<closing]).lowercased()
                if let emoji = EmojiMap.aliases[alias] {
                    flush()
                    result.append(NSAttributedString(string: emoji, attributes: baseAttributes(style)))
                    index = closing + 1
                    continue
                }
            }

            buffer.append(character)
            index += 1
        }
        flush()
    }

    static var markBackground: NSColor {
        NSColor(name: "lume.mark.bg") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.systemYellow.withAlphaComponent(0.24)
                : NSColor.systemYellow.withAlphaComponent(0.35)
        }
    }

    private static func baseAttributes(_ style: InlineTextStyle) -> [NSAttributedString.Key: Any] {
        var attributes = style.attributes
        attributes[.font] = style.font
        attributes[.foregroundColor] = style.color
        return attributes
    }

    private static func previousIsWhitespace(_ characters: [Character], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        return characters[index - 1].isWhitespace
    }

    private static func find(_ characters: [Character], from start: Int, marker: Character) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if characters[index] == marker { return index }
            index += 1
        }
        return nil
    }

    private static func find(_ characters: [Character], from start: Int, marker: String) -> Int? {
        guard let markerCharacter = marker.first else { return nil }
        return find(characters, from: start, marker: markerCharacter)
    }

    private static func findMarkClose(_ characters: [Character], from start: Int) -> Int? {
        var index = start
        while index + 1 < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if characters[index] == "=", characters[index + 1] == "=" { return index }
            index += 1
        }
        return nil
    }

    /// Superscript/subscript content cannot contain whitespace, mirroring MarkText's rules.
    private static func findScriptClose(_ characters: [Character], from start: Int, marker: Character) -> Int? {
        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if character.isWhitespace || character == "\n" { return nil }
            if character == marker { return index }
            index += 1
        }
        return nil
    }

    private static func emojiClose(_ characters: [Character], from start: Int) -> Int? {
        var index = start
        guard index < characters.count else { return nil }
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" || character == "+" || character == "-" {
                index += 1
                continue
            }
            return character == ":" ? index : nil
        }
        return nil
    }

    private static func footnoteReference(
        _ characters: [Character],
        from start: Int,
        style: InlineTextStyle
    ) -> (attributed: NSAttributedString, endIndex: Int)? {
        guard let registry = style.footnotes,
              let closing = find(characters, from: start + 2, marker: "]") else { return nil }
        let id = String(characters[(start + 2)..<closing])
        guard !id.isEmpty, let number = registry.number(for: id) else { return nil }
        let font = NSFont.systemFont(ofSize: max(9, style.mathFontSize * 0.64), weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.controlAccentColor,
            .baselineOffset: max(2.5, style.mathFontSize * 0.32)
        ]
        return (NSAttributedString(string: "\(number)", attributes: attributes), closing + 1)
    }

    private static func inlineDollarMath(
        _ characters: [Character],
        from start: Int,
        style: InlineTextStyle
    ) -> (attributed: NSAttributedString, endIndex: Int)? {
        var index = start + 1
        while index < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if characters[index] == "\n" { return nil }
            if characters[index] == "$" {
                let content = String(characters[(start + 1)..<index])
                guard !content.isEmpty,
                      !content.hasPrefix(" "), !content.hasSuffix(" "),
                      index + 1 >= characters.count || !characters[index + 1].isNumber else { return nil }
                guard let attachment = mathAttachment(content, fontSize: style.mathFontSize, display: false, style: style) else {
                    return nil
                }
                return (attachment, index + 1)
            }
            index += 1
        }
        return nil
    }

    private static func inlineMath(
        _ characters: [Character],
        from start: Int,
        closing: Character,
        style: InlineTextStyle
    ) -> (attributed: NSAttributedString, endIndex: Int)? {
        var index = start
        while index < characters.count {
            if characters[index] == "\\", index + 1 < characters.count, characters[index + 1] == closing {
                let content = String(characters[start..<index])
                guard let attachment = mathAttachment(content, fontSize: style.mathFontSize, display: false, style: style) else {
                    return nil
                }
                return (attachment, index + 2)
            }
            if characters[index] == "\n" { return nil }
            index += 1
        }
        return nil
    }

    static func mathAttachment(
        _ latex: String,
        fontSize: CGFloat,
        display: Bool,
        style: InlineTextStyle
    ) -> NSAttributedString? {
        guard let rendered = MathRenderer.render(
            latex,
            fontSize: fontSize,
            display: display,
            color: style.color
        ) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = rendered.image
        attachment.bounds = CGRect(
            x: 0,
            y: -rendered.descent,
            width: rendered.size.width,
            height: rendered.size.height
        )
        return NSAttributedString(attachment: attachment)
    }

    private static func script(_ content: String, style: InlineTextStyle, superscript: Bool) -> NSAttributedString {
        let scale: CGFloat = 0.68
        let font = NSFontManager.shared.convert(
            style.font,
            toSize: max(8, style.font.pointSize * scale)
        )
        let offset = superscript
            ? max(3, style.font.pointSize * 0.36)
            : -max(1.5, style.font.pointSize * 0.14)
        var scriptStyle = style
        scriptStyle.font = font
        var attributes = baseAttributes(style)
        attributes[.font] = font
        attributes[.baselineOffset] = offset
        scriptStyle.attributes = attributes
        let result = NSMutableAttributedString()
        append(content, style: scriptStyle, to: result)
        return result
    }
}
