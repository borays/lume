import AppKit
import Markdown

final class TaskIndexCounter {
    var next = 0
}

struct MarkdownRenderOptions {
    var baseURL: URL?
    var maxImageWidth: CGFloat = 560
    var baseFontSize: CGFloat = 13.5
    /// 用户选择的正文/标题字体族，空表示系统字体；代码块始终使用等宽字体。
    var baseFontFamily: String?
    var isPrinting: Bool = false
    /// 预览里图片走后台加载，缺图时先显示占位；导出与自测仍同步读取。
    var asynchronousImages: Bool = false
    var footnotes: FootnoteRegistry?
    var mathItems: [MathExtractor.Item] = []
    var taskCounter: TaskIndexCounter?

    func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        guard let family = baseFontFamily, !family.isEmpty else {
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        let managerWeight: Int
        if weight >= .bold {
            managerWeight = 9
        } else if weight >= .semibold {
            managerWeight = 7
        } else if weight >= .medium {
            managerWeight = 6
        } else {
            managerWeight = 5
        }
        return NSFontManager.shared.font(
            withFamily: family,
            traits: [],
            weight: managerWeight,
            size: size
        ) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}

enum RenderTheme {
    // MarkText: light `rgb(0 0 0 / 3%)` over white, dark `#424344`；边框为 editor-color-10。
    static let codeBackground = NSColor(name: "mynote.code.bg") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x42 / 255, green: 0x43 / 255, blue: 0x44 / 255, alpha: 1)
            : NSColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF7 / 255, alpha: 1)
    }

    static let codeBorder = NSColor(name: "mynote.code.border") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.10)
            : NSColor(srgbRed: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE6 / 255, alpha: 1)
    }

    static let inlineCodeBackground = NSColor(name: "mynote.inline.bg") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.10)
            : NSColor(white: 0.93, alpha: 1.0)
    }

    static let tableHeaderBackground = NSColor(name: "mynote.table.header") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.06)
            : NSColor(white: 0.965, alpha: 1.0)
    }

    static let quoteBar = NSColor.tertiaryLabelColor
    static let rule = NSColor.separatorColor
}

enum MarkdownRenderer {
    private struct Context {
        var listDepth: Int = 0
        var quoteDepth: Int = 0
    }

    private static let urlPattern = try! NSRegularExpression(
        pattern: "https?://[A-Za-z0-9\\-._~:/?#\\[\\]@!$&'()*+,;=%]+"
    )

    
    static func render(_ markdown: String, options: MarkdownRenderOptions = MarkdownRenderOptions()) -> NSAttributedString {
        let document = Frontmatter.split(markdown)
        let footnotes = FootnoteParser.extract(document.body)
        let math = MathExtractor.extract(footnotes.body)
        var options = options
        options.mathItems = math.items
        options.taskCounter = TaskIndexCounter()
        options.footnotes = footnotes.definitions.isEmpty
            ? nil
            : FootnoteRegistry(definitions: footnotes.definitions)

        let tree = Document(parsing: subscriptMarkup(math.body))
        let output = NSMutableAttributedString()
        appendBlocks(Array(tree.children), context: Context(), options: options, to: output)
        if let registry = options.footnotes {
            appendFootnotes(registry, options: options, to: output)
        }
        return output
    }

    /// cmark-gfm 把单波浪线 `~x~` 也当删除线，MarkText 风格的下标就渲染不出来。
    /// 解析前先把围栏与行内代码之外的 `~x~` 换成 `<sub>x</sub>`，`~~删除线~~` 不受影响。
    private static let subscriptPattern = try! NSRegularExpression(pattern: "(?<!~)~([^~\\s]+)~(?!~)")

    static func subscriptMarkup(_ source: String) -> String {
        guard source.contains("~") else { return source }
        var lines = source.components(separatedBy: "\n")
        var fence: (character: Character, length: Int)?
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if closesFence(trimmed, character: open.character, minimum: open.length) {
                    fence = nil
                }
                continue
            }
            if let marker = fenceMarker(trimmed) {
                fence = marker
                continue
            }
            lines[index] = outsideInlineCode(lines[index]) { text in
                subscriptPattern.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: "<sub>$1</sub>"
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func fenceMarker(_ trimmed: String) -> (character: Character, length: Int)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        return (first, count)
    }

    private static func closesFence(_ trimmed: String, character: Character, minimum: Int) -> Bool {
        guard trimmed.first == character else { return false }
        let count = trimmed.prefix { $0 == character }.count
        return count >= minimum && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func outsideInlineCode(_ line: String, transform: (String) -> String) -> String {
        guard line.contains("`") else { return transform(line) }
        var output = ""
        var cursor = line.startIndex
        while cursor < line.endIndex {
            guard line[cursor] == "`" else {
                let next = line[cursor...].firstIndex(of: "`") ?? line.endIndex
                output += transform(String(line[cursor..<next]))
                cursor = next
                continue
            }
            let tickStart = cursor
            while cursor < line.endIndex, line[cursor] == "`" {
                cursor = line.index(after: cursor)
            }
            let ticks = String(line[tickStart..<cursor])
            guard let close = line[cursor...].range(of: ticks) else {
                output += transform(ticks)
                continue
            }
            output += line[tickStart..<close.upperBound]
            cursor = close.upperBound
        }
        return output
    }

    static func plainText(_ markdown: String) -> String {
        let document = Frontmatter.split(markdown)
        return document.body
    }

    static func bodyWithoutTitleHeading(_ markdown: String, title: String?) -> String {
        let document = Frontmatter.split(markdown)
        guard let rawTitle = (title ?? Frontmatter.parse(markdown).title)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty else {
            return document.body
        }
        var lines = document.body.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return document.body
        }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("# ") else { return document.body }
        let heading = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard heading.compare(rawTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else {
            return document.body
        }
        lines.remove(at: index)
        if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    // MARK: - Blocks

    private static func appendBlocks(_ blocks: [Markup], context: Context, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            if let paragraph = block as? Paragraph, isDefinitionListParagraph(paragraph) {
                // 术语与 `: 解释` 之间没有空行时，两者属于同一个段落（软换行分隔）。
                appendInlineDefinitionList(paragraph, options: options, to: output)
                index += 1
                index = appendTrailingDefinitions(blocks, from: index, options: options, to: output)
                continue
            }
            if let term = block as? Paragraph,
               index + 1 < blocks.count,
               let next = blocks[index + 1] as? Paragraph,
               isDefinitionText(plainText(of: Array(next.children))) {
                appendDefinitionTerm(Array(term.children), options: options, to: output)
                index = appendTrailingDefinitions(blocks, from: index + 1, options: options, to: output)
                continue
            }
            appendBlock(block, context: context, options: options, to: output)
            index += 1
        }
    }

    /// 术语之后允许用空行分隔多条定义，一并吃掉并返回下一个待处理块的下标。
    private static func appendTrailingDefinitions(
        _ blocks: [Markup],
        from start: Int,
        options: MarkdownRenderOptions,
        to output: NSMutableAttributedString
    ) -> Int {
        var index = start
        while index < blocks.count,
              let definition = blocks[index] as? Paragraph,
              isDefinitionText(plainText(of: Array(definition.children))) {
            appendDefinition(definition, options: options, to: output)
            index += 1
        }
        return index
    }

    /// Markdown Extra 定义列表：`: 解释` 行紧跟术语段落。
    private static func isDefinitionText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(":") else { return false }
        let rest = trimmed.dropFirst()
        return rest.isEmpty || rest.first!.isWhitespace
    }

    private static func paragraphLines(_ paragraph: Paragraph) -> [[Markup]] {
        var lines: [[Markup]] = []
        var current: [Markup] = []
        for node in paragraph.children {
            if node is SoftBreak || node is LineBreak {
                lines.append(current)
                current = []
            } else {
                current.append(node)
            }
        }
        lines.append(current)
        return lines
    }

    private static func isDefinitionListParagraph(_ paragraph: Paragraph) -> Bool {
        let lines = paragraphLines(paragraph)
        guard lines.count > 1, !isDefinitionText(plainText(of: lines[0])) else { return false }
        return lines.dropFirst().contains { isDefinitionText(plainText(of: $0)) }
    }

    private static func appendInlineDefinitionList(_ paragraph: Paragraph, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        for line in paragraphLines(paragraph) {
            guard !line.isEmpty else { continue }
            if isDefinitionText(plainText(of: line)) {
                appendDefinitionNodes(line, options: options, to: output)
            } else {
                appendDefinitionTerm(line, options: options, to: output)
            }
        }
    }

    private static func appendDefinitionTerm(_ nodes: [Markup], options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let font = options.font(size: options.baseFontSize, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 2
        let attributed = NSMutableAttributedString(attributedString: inline(
            nodes,
            font: font,
            color: .labelColor,
            options: options
        ))
        guard attributed.length > 0 else { return }
        let range = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        output.append(attributed)
        output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraphStyle]))
    }

    private static func appendDefinition(_ paragraph: Paragraph, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        appendDefinitionNodes(Array(paragraph.children), options: options, to: output)
    }

    private static func appendDefinitionNodes(_ nodes: [Markup], options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let font = options.font(size: options.baseFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 6
        paragraphStyle.headIndent = 22
        paragraphStyle.firstLineHeadIndent = 22
        guard !plainText(of: nodes).trimmingCharacters(in: .whitespaces).dropFirst().isEmpty else { return }
        // 去掉行首的 “:” 后按普通行内内容渲染，保留定义里的加粗、代码等格式。
        var inlines = nodes
        if let first = inlines.first as? Text {
            let remainder = String(first.string.drop(while: { $0 == " " || $0 == "\t" }).dropFirst())
                .trimmingCharacters(in: .whitespaces)
            if remainder.isEmpty {
                inlines.removeFirst()
            } else {
                inlines[0] = Text(remainder)
            }
        }
        guard !inlines.isEmpty else { return }
        let attributed = NSMutableAttributedString(attributedString: inline(
            inlines,
            font: font,
            color: .secondaryLabelColor,
            options: options
        ))
        guard attributed.length > 0 else { return }
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))
        output.append(attributed)
        output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraphStyle]))
    }

    private static func appendBlock(_ block: Markup, context: Context, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        switch block {
        case let heading as Heading:
            appendHeading(Array(heading.children), level: heading.level, options: options, to: output)
        case let paragraph as Paragraph:
            appendParagraph(Array(paragraph.children), context: context, options: options, to: output)
        case let code as CodeBlock:
            appendCodeBlock(code.code, language: code.language ?? "", options: options, to: output)
        case is ThematicBreak:
            appendRule(to: output)
        case let quote as BlockQuote:
            appendQuote(quote, context: context, options: options, to: output)
        case let html as HTMLBlock:
            appendHTMLBlock(html.rawHTML, options: options, to: output)
        case let list as OrderedList:
            appendListItems(Array(list.children), ordered: true, start: Int(list.startIndex), context: context, options: options, to: output)
        case let list as UnorderedList:
            appendListItems(Array(list.children), ordered: false, start: 1, context: context, options: options, to: output)
        case let table as Table:
            appendTable(table, options: options, to: output)
        default:
            let children = Array(block.children)
            if children.isEmpty {
                appendParagraph([block], context: context, options: options, to: output)
            } else {
                appendBlocks(children, context: context, options: options, to: output)
            }
        }
    }

    private static func appendHeading(_ nodes: [Markup], level: Int, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        // 字号随阅读字号等比缩放，基准 13.5 对应 26/21/17/15/13.5。
        let scales: [CGFloat] = [1.93, 1.56, 1.26, 1.11, 1.0, 1.0]
        let base = max(10, options.baseFontSize)
        let raw = base * scales[max(0, min(level - 1, scales.count - 1))]
        let size = (raw * 2).rounded() / 2
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = max(10, (base * 1.04).rounded())
        paragraph.paragraphSpacing = max(5, (base * 0.52).rounded())
        paragraph.lineSpacing = 2
        let font = options.font(size: size, weight: level <= 2 ? .bold : .semibold)
        let attributed = inline(nodes, font: font, color: .labelColor, options: options)
        output.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 2), .paragraphStyle: paragraph]))
        output.append(attributed)
        output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
    }

    private static func appendParagraph(_ nodes: [Markup], context: Context, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        if let display = displayMathItem(in: nodes, options: options),
           let rendered = MathRenderer.render(
               display.latex,
               fontSize: max(14, options.baseFontSize + 1.5),
               display: true,
               color: context.quoteDepth > 0 ? .secondaryLabelColor : .labelColor
           ) {
            appendDisplayMath(rendered, options: options, to: output)
            return
        }

        if context.quoteDepth == 0, nodes.count == 1, let image = nodes[0] as? Image {
            appendImageFigure(image, options: options, to: output)
            return
        }

        let font = options.font(size: options.baseFontSize)
        let attributed: NSMutableAttributedString
        let paragraph = NSMutableParagraphStyle()
        if context.quoteDepth > 0 {
            attributed = NSMutableAttributedString(attributedString: inline(nodes, font: font, color: .secondaryLabelColor, options: options))
            if context.quoteDepth == 1, attributed.length > 0 {
                attributed.insert(NSAttributedString(string: "▍ ", attributes: [
                    .font: font,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]), at: 0)
            }
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 9
            paragraph.headIndent = 18
            paragraph.firstLineHeadIndent = 18
        } else {
            attributed = NSMutableAttributedString(attributedString: inline(nodes, font: font, color: .labelColor, options: options))
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 9
        }
        attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))
        output.append(attributed)
        output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
    }

    private static func appendQuote(_ quote: BlockQuote, context: Context, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        if let alert = alertInfo(in: quote) {
            appendAlert(alert.kind, leading: alert.leading, blocks: alert.blocks, context: context, options: options, to: output)
            return
        }
        var quoteContext = context
        quoteContext.quoteDepth += 1
        appendBlocks(Array(quote.children), context: quoteContext, options: options, to: output)
    }

    // MARK: - GitHub alerts

    private enum AlertKind: String {
        case note = "NOTE"
        case tip = "TIP"
        case important = "IMPORTANT"
        case warning = "WARNING"
        case caution = "CAUTION"

        var title: String {
            switch self {
            case .note: return "Note"
            case .tip: return "Tip"
            case .important: return "Important"
            case .warning: return "Warning"
            case .caution: return "Caution"
            }
        }

        var symbol: String {
            switch self {
            case .note: return "info.circle.fill"
            case .tip: return "lightbulb.fill"
            case .important: return "exclamationmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .caution: return "exclamationmark.octagon.fill"
            }
        }

        private var lightColor: NSColor {
            switch self {
            case .note: return NSColor(srgbRed: 0.035, green: 0.412, blue: 0.855, alpha: 1)
            case .tip: return NSColor(srgbRed: 0.102, green: 0.498, blue: 0.216, alpha: 1)
            case .important: return NSColor(srgbRed: 0.510, green: 0.314, blue: 0.875, alpha: 1)
            case .warning: return NSColor(srgbRed: 0.604, green: 0.404, blue: 0.000, alpha: 1)
            case .caution: return NSColor(srgbRed: 0.820, green: 0.141, blue: 0.184, alpha: 1)
            }
        }

        private var darkColor: NSColor {
            switch self {
            case .note: return NSColor(srgbRed: 0.267, green: 0.576, blue: 0.973, alpha: 1)
            case .tip: return NSColor(srgbRed: 0.247, green: 0.725, blue: 0.314, alpha: 1)
            case .important: return NSColor(srgbRed: 0.671, green: 0.490, blue: 0.973, alpha: 1)
            case .warning: return NSColor(srgbRed: 0.824, green: 0.600, blue: 0.133, alpha: 1)
            case .caution: return NSColor(srgbRed: 0.973, green: 0.318, blue: 0.286, alpha: 1)
            }
        }

        var color: NSColor {
            NSColor(name: "lume.alert.\(rawValue)") { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
            }
        }

        var background: NSColor {
            NSColor(name: "lume.alert.bg.\(rawValue)") { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return (dark ? darkColor : lightColor).withAlphaComponent(dark ? 0.13 : 0.08)
            }
        }
    }

    private static let alertMarkerPattern = try! NSRegularExpression(
        pattern: "^\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]$",
        options: [.caseInsensitive]
    )

    private static func alertInfo(in quote: BlockQuote) -> (kind: AlertKind, leading: [Markup], blocks: [Markup])? {
        let children = Array(quote.children)
        guard let first = children.first as? Paragraph else { return nil }
        let nodes = Array(first.children)
        guard let markerText = nodes.first as? Text else { return nil }
        let marker = markerText.string.trimmingCharacters(in: .whitespaces)
        let ns = marker as NSString
        guard let match = alertMarkerPattern.firstMatch(in: marker, range: NSRange(location: 0, length: ns.length)),
              let kind = AlertKind(rawValue: ns.substring(with: match.range(at: 1)).uppercased()) else {
            return nil
        }
        var leading = Array(nodes.dropFirst())
        if let firstNode = leading.first, firstNode is SoftBreak || firstNode is LineBreak {
            leading.removeFirst()
        }
        return (kind, leading, Array(children.dropFirst()))
    }

    private static func appendAlert(_ kind: AlertKind, leading: [Markup], blocks: [Markup], context: Context, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let accent = kind.color
        let block = NSTextBlock()
        block.backgroundColor = kind.background
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(3.5, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(accent, for: .minX)

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.paragraphSpacingBefore = 10
        titleParagraph.paragraphSpacing = 4
        titleParagraph.lineSpacing = 2
        titleParagraph.textBlocks = [block]

        let title = NSMutableAttributedString()
        if let icon = symbolImage(kind.symbol, color: accent, pointSize: 12) {
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = CGRect(x: 0, y: -2.5, width: icon.size.width, height: icon.size.height)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "  "))
        }
        title.append(NSAttributedString(string: kind.title, attributes: [
            .font: options.font(size: max(12, options.baseFontSize - 0.5), weight: .semibold),
            .foregroundColor: accent
        ]))
        if title.length > 0 {
            title.addAttribute(.paragraphStyle, value: titleParagraph, range: NSRange(location: 0, length: title.length))
        }
        output.append(title)
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 3),
            .paragraphStyle: titleParagraph
        ]))

        guard !leading.isEmpty || !blocks.isEmpty else { return }
        let content = NSMutableAttributedString()
        if !leading.isEmpty {
            appendInlineParagraph(leading, options: options, to: content)
        }
        appendBlocks(blocks, context: context, options: options, to: content)
        applyAlertBlock(block, to: content)
        output.append(content)
        output.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)]))
    }

    private static func appendInlineParagraph(_ nodes: [Markup], options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let font = options.font(size: options.baseFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 9
        let attributed = NSMutableAttributedString(attributedString: inline(nodes, font: font, color: .labelColor, options: options))
        guard attributed.length > 0 else { return }
        attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))
        output.append(attributed)
        output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
    }

    private static func applyAlertBlock(_ block: NSTextBlock, to content: NSMutableAttributedString) {
        guard content.length > 0 else { return }
        var updates: [(NSRange, NSParagraphStyle)] = []
        content.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle, style.textBlocks.isEmpty else { return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.setParagraphStyle(style)
            paragraph.textBlocks = [block]
            paragraph.paragraphSpacingBefore = 0
            paragraph.paragraphSpacing = 3
            updates.append((range, paragraph))
        }
        for (range, style) in updates {
            content.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }

    private static func checkboxImage(checked: Bool) -> NSImage? {
        let tint = checked ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor
        return symbolImage(checked ? "checkmark.square.fill" : "square", color: tint, pointSize: 12.5)
    }

    private static func symbolImage(_ name: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let configured = base.withSymbolConfiguration(configuration) else { return base }
        let tinted = NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private static func appendListItems(_ items: [Markup], ordered: Bool, start: Int, context: Context, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let itemContext = Context(listDepth: context.listDepth + 1, quoteDepth: context.quoteDepth)
        for (offset, rawItem) in items.enumerated() {
            guard let item = rawItem as? ListItem else { continue }
            let marker: String
            var taskIndex: Int?
            if let checkbox = item.checkbox {
                marker = checkbox == .checked ? "☑" : "☐"
                if let counter = options.taskCounter {
                    taskIndex = counter.next
                    counter.next += 1
                }
            } else if ordered {
                marker = "\(start + offset)."
            } else {
                marker = "•"
            }
            appendListItem(item, marker: marker, taskIndex: taskIndex, context: itemContext, options: options, to: output)
        }
    }

    private static func appendListItem(_ item: ListItem, marker: String, taskIndex: Int? = nil, context: Context, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let baseIndent = CGFloat(max(0, context.listDepth - 1)) * 18
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        paragraph.headIndent = baseIndent + 20
        paragraph.firstLineHeadIndent = baseIndent
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: baseIndent + 20)]
        let font = options.font(size: options.baseFontSize)

        var children = Array(item.children)
        let firstNodes: [Markup]
        if let first = children.first as? Paragraph {
            children.removeFirst()
            firstNodes = Array(first.children)
        } else {
            firstNodes = []
        }

        let line = NSMutableAttributedString()
        if let taskIndex {
            let checked = marker == "☑"
            if let icon = checkboxImage(checked: checked) {
                let attachment = NSTextAttachment()
                attachment.image = icon
                attachment.bounds = CGRect(x: 0, y: -3, width: icon.size.width, height: icon.size.height)
                let token = NSMutableAttributedString(attachment: attachment)
                token.addAttributes([
                    .paragraphStyle: paragraph,
                    .lumeTaskIndex: taskIndex
                ], range: NSRange(location: 0, length: token.length))
                line.append(token)
                line.append(NSAttributedString(string: "\t", attributes: [
                    .font: font,
                    .paragraphStyle: paragraph
                ]))
            } else {
                line.append(NSAttributedString(string: marker + "\t", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: options.baseFontSize - 0.5, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: paragraph
                ]))
                line.addAttribute(.lumeTaskIndex, value: taskIndex, range: NSRange(location: 0, length: 1))
            }
        } else {
            line.append(NSAttributedString(string: marker + "\t", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: options.baseFontSize - 0.5, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraph
            ]))
        }
        line.append(inline(firstNodes, font: font, color: .labelColor, options: options))
        line.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
        output.append(line)

        appendBlocks(children, context: context, options: options, to: output)
    }

    private static func appendCodeBlock(_ code: String, language: String, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let lang = language.lowercased()
        if lang == "mermaid" || lang == "mmd" || (lang.isEmpty && mermaidKeyword(of: code) != nil) {
            if let diagram = MermaidRenderer.render(code: code, maxWidth: options.maxImageWidth) {
                appendMermaidDiagram(diagram.image, kind: diagram.kind, source: code, options: options, to: output)
                return
            }
        }
        if lang == "math" || lang == "latex" || lang == "tex" || lang == "katex" {
            if let rendered = MathRenderer.render(
                code,
                fontSize: max(14, options.baseFontSize + 1.5),
                display: true,
                color: .labelColor
            ) {
                appendDisplayMath(rendered, options: options, to: output)
                return
            }
        }

        let fontSize = max(11, (options.baseFontSize * 0.9 * 10).rounded() / 10)
        let font = NSFont(name: "Menlo", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let block = CodeBlockTextBlock(fill: RenderTheme.codeBackground, stroke: RenderTheme.codeBorder)
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(12, type: .absoluteValueType, for: .padding)

        let displayCode = (code.isEmpty ? " " : code)
            .replacingOccurrences(of: "\t", with: "    ")
        let highlighted: NSAttributedString
        if let swiftHighlight = CodeHighlightService.highlight(code: displayCode, language: language, fontSize: fontSize) {
            highlighted = swiftHighlight
        } else {
            highlighted = CodeHighlighter.highlight(displayCode, language: language, font: font)
        }

        let lineHeight = ceil(fontSize * 1.6)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        paragraph.textBlocks = [block]

        if output.length > 0 {
            let lead = NSMutableParagraphStyle()
            lead.paragraphSpacing = 8
            output.append(NSAttributedString(string: "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 5),
                .paragraphStyle: lead
            ]))
        }

        let body = NSMutableAttributedString(attributedString: highlighted)
        while body.string.hasSuffix("\n") {
            body.deleteCharacters(in: NSRange(location: body.length - 1, length: 1))
        }
        let badge = language.split(separator: " ").first.map(String.init) ?? ""
        let range = NSRange(location: 0, length: body.length)
        var blockAttributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .lumeCopyCode: code,
            .lumeCodeLanguage: badge
        ]
        if CodeLanguages.canonical(language) != nil || language.isEmpty {
            blockAttributes[.lumeCodeHighlightKey] = CodeHighlightService.cacheKeyString(
                code: displayCode,
                language: language,
                fontSize: fontSize
            )
        }
        body.addAttributes(blockAttributes, range: range)
        output.append(body)
        let terminator = NSMutableParagraphStyle()
        terminator.minimumLineHeight = lineHeight
        terminator.maximumLineHeight = lineHeight
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .paragraphStyle: terminator
        ]))
        let spacer = NSMutableParagraphStyle()
        spacer.paragraphSpacing = 14
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 5),
            .paragraphStyle: spacer
        ]))
    }

    /// 未写语言名的围栏里若首行是图表关键字，也按 Mermaid 渲染。
    private static func mermaidKeyword(of code: String) -> String? {
        let keywords: Set<String> = [
            "flowchart", "graph", "sequencediagram", "statediagram", "statediagram-v2",
            "classdiagram", "erdiagram", "gantt", "gitgraph", "mindmap", "pie", "journey",
            "c4context", "c4container", "c4component", "c4dynamic", "c4deployment"
        ]
        guard let first = code
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }
        let token = first.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        return keywords.contains(token) ? token : nil
    }

    private static func appendMermaidDiagram(_ image: NSImage, kind: String, source: String, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacingBefore = 6
        paragraph.paragraphSpacing = 4

        let attachment = NSTextAttachment()
        attachment.image = image
        let width = max(120, min(options.maxImageWidth, image.size.width))
        let scale = width / max(image.size.width, 1)
        attachment.bounds = CGRect(x: 0, y: 0, width: width, height: image.size.height * scale)

        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 3),
            .paragraphStyle: paragraph
        ]))
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttributes([
            .lumeImagePixelSize: NSValue(size: image.size)
        ], range: NSRange(location: 0, length: attachmentString.length))
        output.append(attachmentString)

        let caption = NSMutableAttributedString()
        caption.append(NSAttributedString(string: "\nMermaid · \(kind)　", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraph
        ]))
        if !options.isPrinting {
            // 占位字符用于定位复制图标，图标由预览层绘制，与代码块复制按钮一致。
            caption.append(NSAttributedString(string: "\u{00A0}\u{00A0}\u{00A0}", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.controlAccentColor,
                .paragraphStyle: paragraph,
                .lumeCopyCode: source,
                .lumeCopyLink: true
            ]))
        }
        caption.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 4),
            .paragraphStyle: paragraph
        ]))
        output.append(caption)
    }

    private static func appendRule(to output: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 12
        paragraph.paragraphSpacingBefore = 6
        output.append(NSAttributedString(string: String(repeating: "─", count: 36), attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: RenderTheme.rule,
            .paragraphStyle: paragraph
        ]))
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 4),
            .paragraphStyle: paragraph
        ]))
    }

    // MARK: - Math

    private static func displayMathItem(in nodes: [Markup], options: MarkdownRenderOptions) -> MathExtractor.Item? {
        guard nodes.count == 1, let text = nodes[0] as? Text else { return nil }
        guard let item = MathExtractor.item(for: text.string, items: options.mathItems) else { return nil }
        return item.display ? item : nil
    }

    private static func appendDisplayMath(_ rendered: MathRenderer.Rendered, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 10

        let limit = max(120, options.maxImageWidth)
        let scale = max(0.2, min(1, limit / max(rendered.size.width, 1)))
        let attachment = NSTextAttachment()
        attachment.image = rendered.image
        attachment.bounds = CGRect(
            x: 0,
            y: -rendered.descent * scale,
            width: rendered.size.width * scale,
            height: rendered.size.height * scale
        )
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attachmentString.length))

        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 3),
            .paragraphStyle: paragraph
        ]))
        output.append(attachmentString)
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 6),
            .paragraphStyle: paragraph
        ]))
    }

    // MARK: - Footnotes

    private static func appendFootnotes(_ registry: FootnoteRegistry, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let entries = registry.orderedDefinitions
        guard !entries.isEmpty else { return }

        let separator = NSMutableParagraphStyle()
        separator.paragraphSpacingBefore = 18
        separator.paragraphSpacing = 7
        output.append(NSAttributedString(string: String(repeating: "─", count: 24), attributes: [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.separatorColor,
            .paragraphStyle: separator
        ]))
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 6),
            .paragraphStyle: separator
        ]))

        let font = options.font(size: max(11, options.baseFontSize - 1.5))
        for entry in entries {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 5
            paragraph.headIndent = 22
            paragraph.firstLineHeadIndent = 0

            let line = NSMutableAttributedString()
            line.append(NSAttributedString(string: "\(entry.number).  ", attributes: [
                .font: options.font(size: max(9, font.pointSize * 0.92), weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
                .paragraphStyle: paragraph
            ]))

            let extracted = MathExtractor.extract(entry.definition.content)
            var definitionOptions = options
            definitionOptions.mathItems = extracted.items
            let tree = Document(parsing: extracted.body)
            var appended = false
            for block in tree.children {
                if appended {
                    line.append(NSAttributedString(string: " ", attributes: [
                        .font: font,
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]))
                }
                if let textBlock = block as? Paragraph {
                    line.append(inline(Array(textBlock.children), font: font, color: .secondaryLabelColor, options: definitionOptions))
                } else if let code = block as? CodeBlock {
                    appendPlain(code.code, style: InlineStyle(
                        font: NSFont.monospacedSystemFont(ofSize: max(10, font.pointSize - 0.5), weight: .regular),
                        color: .secondaryLabelColor,
                        attributes: [.backgroundColor: RenderTheme.inlineCodeBackground]
                    ), options: definitionOptions, to: line)
                } else {
                    let nodes = Array(block.children)
                    if !nodes.isEmpty {
                        line.append(inline(nodes, font: font, color: .secondaryLabelColor, options: definitionOptions))
                    }
                }
                appended = true
            }
            if line.length > 0 {
                line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
            }
            output.append(line)
            output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
        }
    }

    // MARK: - HTML blocks

    private static let htmlBreakPattern = try! NSRegularExpression(pattern: "<br\\s*/?>", options: [.caseInsensitive])
    private static let htmlRulePattern = try! NSRegularExpression(pattern: "<hr\\s*/?>", options: [.caseInsensitive])
    private static let htmlImagePattern = try! NSRegularExpression(pattern: "<img\\b[^>]*>", options: [.caseInsensitive])
    private static let htmlTagPatternForBlocks = try! NSRegularExpression(pattern: "<[^>]*>")

    private static func appendHTMLBlock(_ raw: String, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.range(of: "<details", options: .caseInsensitive) != nil {
            appendDetailsBlock(trimmed, options: options, to: output)
            return
        }

        if let start = trimmed.range(of: "<pre", options: .caseInsensitive)?.lowerBound,
           let end = trimmed.range(of: "</pre>", options: [.caseInsensitive, .backwards])?.lowerBound,
           start < end {
            let inner = String(trimmed[start..<end])
            let code = decodeHTMLEntities(stripHTMLTags(inner))
            appendCodeBlock(code, language: "", options: options, to: output)
            return
        }

        let ns = trimmed as NSString
        let imageMatches = htmlImagePattern.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        for match in imageMatches {
            let tag = ns.substring(with: match.range)
            let source = htmlAttribute("src", in: tag) ?? ""
            let alt = htmlAttribute("alt", in: tag) ?? ""
            appendImage(alt: alt, path: source, font: options.font(size: options.baseFontSize), options: options, to: output)
        }

        var text = htmlImagePattern.stringByReplacingMatches(
            in: trimmed,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
        text = htmlBreakPattern.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: "\n"
        )
        let hasRule = htmlRulePattern.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        ) != nil
        text = htmlRulePattern.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: ""
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if hasRule {
            appendRule(to: output)
        }
        guard !text.isEmpty else { return }
        let font = options.font(size: options.baseFontSize)
        for line in text.components(separatedBy: "\n") {
            let content = line.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            let attributed = NSMutableAttributedString(attributedString: htmlInlineAttributed(content, font: font, options: options))
            guard attributed.length > 0 else { continue }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 9
            attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))
            output.append(attributed)
            output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
        }
    }

    private static let htmlBlockLevelTags: Set<String> = [
        "div", "p", "section", "article", "center", "header", "footer", "main", "aside", "nav",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "table",
        "thead", "tbody", "tfoot", "tr", "td", "th", "figure", "figcaption", "blockquote", "pre", "details", "summary"
    ]

    private static func htmlInlineAttributed(_ html: String, font: NSFont, options: MarkdownRenderOptions) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var style = InlineStyle(font: font, color: .labelColor)
        var stack: [InlineStyle] = []
        let ns = html as NSString
        var cursor = 0
        for match in htmlTagPattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                let raw = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                appendPlain(decodeHTMLEntities(raw), style: style, options: options, to: result)
            }
            handleHTMLTag(ns.substring(with: match.range), style: &style, stack: &stack, options: options, to: result, skipBlockTags: true)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            appendPlain(decodeHTMLEntities(ns.substring(from: cursor)), style: style, options: options, to: result)
        }
        return result
    }

    private static func appendDetailsBlock(_ raw: String, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        var summary = "Details"
        var body = raw
        if let summaryStart = raw.range(of: "<summary", options: .caseInsensitive),
           let summaryEnd = raw.range(of: "</summary>", options: [.caseInsensitive, .backwards]) {
            let afterOpen = raw.range(of: ">", range: summaryStart.upperBound..<summaryEnd.lowerBound)
            if let afterOpen {
                let inner = String(raw[afterOpen.upperBound..<summaryEnd.lowerBound])
                let decoded = decodeHTMLEntities(stripHTMLTags(inner))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty { summary = decoded }
            }
            body = String(raw[summaryEnd.upperBound...])
        }
        body = body.replacingOccurrences(of: "</details>", with: "", options: [.caseInsensitive])
        body = body.replacingOccurrences(of: "<details>", with: "", options: [.caseInsensitive])

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 6
        let title = NSMutableAttributedString(string: "▸ \(summary)", attributes: [
            .font: options.font(size: max(12, options.baseFontSize - 0.5), weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ])
        output.append(title)
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 4),
            .paragraphStyle: paragraph
        ]))

        let inner = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty else { return }
        let tree = Document(parsing: inner)
        appendBlocks(Array(tree.children), context: Context(), options: options, to: output)
    }

    private static func stripHTMLTags(_ text: String) -> String {
        let ns = text as NSString
        return htmlTagPatternForBlocks.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&nbsp;": " ", "&mdash;": "—",
            "&ndash;": "–", "&hellip;": "…", "&copy;": "©", "&reg;": "®"
        ]
        for (key, value) in named {
            result = result.replacingOccurrences(of: key, with: value, options: [.caseInsensitive])
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let raw = ns.substring(with: match.range(at: 1))
                let value: UInt32?
                if raw.lowercased().hasPrefix("x") {
                    value = UInt32(raw.dropFirst(), radix: 16)
                } else {
                    value = UInt32(raw, radix: 10)
                }
                guard let value, let scalar = Unicode.Scalar(value) else { continue }
                result = (result as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
            }
        }
        return result
    }

    // MARK: - Tables

    private static func appendTable(_ table: Table, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let headerCells = Array(table.head.cells)
        let columnCount = headerCells.count
        guard columnCount > 0 else { return }

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let font = options.font(size: max(11.5, options.baseFontSize - 1))
        let headerFont = options.font(size: max(11.5, options.baseFontSize - 1), weight: .semibold)
        let alignments = table.columnAlignments
        let result = NSMutableAttributedString()

        func columnAlignment(_ column: Int) -> NSTextAlignment {
            guard column < alignments.count, let alignment = alignments[column] else { return .left }
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            }
        }

        func appendRow(_ cells: [Markup], isHeader: Bool, rowIndex: Int) {
            for column in 0..<columnCount {
                let cellNodes = column < cells.count ? Array(cells[column].children) : []
                let cellFont = isHeader ? headerFont : font
                let block = NSTextTableBlock(
                    table: textTable,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: column,
                    columnSpan: 1
                )
                block.setBorderColor(NSColor.separatorColor)
                block.setWidth(0.6, type: .absoluteValueType, for: .border)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                if isHeader {
                    block.backgroundColor = RenderTheme.tableHeaderBackground
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]
                paragraph.lineSpacing = 2
                paragraph.alignment = columnAlignment(column)
                let cellText = NSMutableAttributedString(attributedString: inline(
                    cellNodes,
                    font: cellFont,
                    color: .labelColor,
                    options: options
                ))
                if cellText.length > 0 {
                    cellText.mutableString.replaceOccurrences(
                        of: "\n",
                        with: " ",
                        options: [],
                        range: NSRange(location: 0, length: cellText.length)
                    )
                    cellText.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: cellText.length))
                }
                result.append(cellText)
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: cellFont,
                    .paragraphStyle: paragraph
                ]))
            }
        }

        appendRow(headerCells, isHeader: true, rowIndex: 0)
        var rowIndex = 1
        for row in table.body.rows {
            appendRow(Array(row.cells), isHeader: false, rowIndex: rowIndex)
            rowIndex += 1
        }

        let trailing = NSMutableParagraphStyle()
        trailing.paragraphSpacing = 10
        trailing.lineSpacing = 0
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 4),
            .paragraphStyle: trailing
        ]))
        output.append(result)
    }

    // MARK: - Inline

    private struct InlineStyle {
        var font: NSFont
        var color: NSColor
        var attributes: [NSAttributedString.Key: Any] = [:]
    }

    private static let htmlTagPattern = try! NSRegularExpression(pattern: "<[^>]*>")

    private static func inline(_ nodes: [Markup], font: NSFont, color: NSColor, options: MarkdownRenderOptions) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var style = InlineStyle(font: font, color: color)
        var stack: [InlineStyle] = []
        renderInlineNodes(nodes, style: &style, stack: &stack, options: options, to: result)
        return result
    }

    private static func renderInlineNodes(_ nodes: [Markup], style: inout InlineStyle, stack: inout [InlineStyle], options: MarkdownRenderOptions, to result: NSMutableAttributedString) {
        for node in nodes {
            if let html = node as? InlineHTML {
                handleInlineHTML(html.rawHTML, style: &style, stack: &stack, options: options, to: result)
                continue
            }
            renderInlineNode(node, style: &style, stack: &stack, options: options, to: result)
        }
    }

    private static func renderInlineNode(_ node: Markup, style: inout InlineStyle, stack: inout [InlineStyle], options: MarkdownRenderOptions, to result: NSMutableAttributedString) {
        switch node {
        case let text as Text:
            appendPlain(text.string, style: style, options: options, to: result)
        case let code as InlineCode:
            var attributes = style.attributes
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: max(11, style.font.pointSize - 1), weight: .regular)
            attributes[.foregroundColor] = style.color
            attributes[.backgroundColor] = RenderTheme.inlineCodeBackground
            result.append(NSAttributedString(string: code.code, attributes: attributes))
        case let strong as Strong:
            var derived = style
            derived.font = boldFont(style.font)
            renderInlineNodes(Array(strong.children), style: &derived, stack: &stack, options: options, to: result)
        case let emphasis as Emphasis:
            var derived = style
            derived.font = italicFont(style.font)
            renderInlineNodes(Array(emphasis.children), style: &derived, stack: &stack, options: options, to: result)
        case let strike as Strikethrough:
            var derived = style
            derived.attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            renderInlineNodes(Array(strike.children), style: &derived, stack: &stack, options: options, to: result)
        case let link as Link:
            var derived = style
            if let destination = link.destination, let url = resolveURL(destination, baseURL: options.baseURL) {
                derived.attributes[.link] = url
                derived.attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                derived.color = NSColor.linkColor
            }
            renderInlineNodes(Array(link.children), style: &derived, stack: &stack, options: options, to: result)
        case let image as Image:
            appendImage(alt: plainText(of: Array(image.children)), path: image.source ?? "", font: style.font, options: options, to: result)
        case is SoftBreak, is LineBreak:
            result.append(NSAttributedString(string: "\n", attributes: [.font: style.font, .foregroundColor: style.color]))
        default:
            let children = Array(node.children)
            if children.isEmpty {
                let text = plainText(of: [node])
                if !text.isEmpty {
                    appendPlain(text, style: style, options: options, to: result)
                }
            } else {
                renderInlineNodes(children, style: &style, stack: &stack, options: options, to: result)
            }
        }
    }

    private static func handleInlineHTML(_ raw: String, style: inout InlineStyle, stack: inout [InlineStyle], options: MarkdownRenderOptions, to result: NSMutableAttributedString) {
        let ns = raw as NSString
        let matches = htmlTagPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            handleHTMLTag(ns.substring(with: match.range), style: &style, stack: &stack, options: options, to: result)
        }
    }

    private static func handleHTMLTag(_ tagText: String, style: inout InlineStyle, stack: inout [InlineStyle], options: MarkdownRenderOptions, to result: NSMutableAttributedString, skipBlockTags: Bool = false) {
        var body = tagText
        guard body.hasPrefix("<"), body.hasSuffix(">") else { return }
        body = String(body.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("!--") || body.hasPrefix("!") || body.hasPrefix("?") { return }

        let closing = body.hasPrefix("/")
        if closing { body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if body.hasSuffix("/") { body = String(body.dropLast()).trimmingCharacters(in: .whitespaces) }

        var name = body
        if let space = name.firstIndex(where: { $0.isWhitespace }) {
            name = String(name[..<space])
        }
        name = name.lowercased()
        guard !name.isEmpty else { return }
        if skipBlockTags, htmlBlockLevelTags.contains(name) { return }

        if closing {
            if !stack.isEmpty { style = stack.removeLast() }
            return
        }

        switch name {
        case "br":
            result.append(NSAttributedString(string: "\n", attributes: [.font: style.font, .foregroundColor: style.color]))
        case "b", "strong":
            stack.append(style)
            style.font = boldFont(style.font)
        case "i", "em", "cite":
            stack.append(style)
            style.font = italicFont(style.font)
        case "u", "ins":
            stack.append(style)
            style.attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        case "s", "del", "strike":
            stack.append(style)
            style.attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        case "mark":
            stack.append(style)
            style.attributes[.backgroundColor] = InlineExtensions.markBackground
        case "code", "kbd", "samp", "tt":
            stack.append(style)
            style.font = NSFont.monospacedSystemFont(ofSize: max(11, style.font.pointSize - 1), weight: .regular)
            if name != "tt" {
                style.attributes[.backgroundColor] = RenderTheme.inlineCodeBackground
            }
        case "sup":
            stack.append(style)
            style.attributes[.baselineOffset] = max(3, style.font.pointSize * 0.36)
            style.font = NSFontManager.shared.convert(style.font, toSize: max(8, style.font.pointSize * 0.7))
        case "sub":
            stack.append(style)
            style.attributes[.baselineOffset] = -max(1.5, style.font.pointSize * 0.14)
            style.font = NSFontManager.shared.convert(style.font, toSize: max(8, style.font.pointSize * 0.7))
        case "a":
            stack.append(style)
            if let href = htmlAttribute("href", in: body),
               let url = resolveURL(href, baseURL: options.baseURL) {
                style.attributes[.link] = url
                style.attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                style.color = NSColor.linkColor
            }
        case "img":
            let source = htmlAttribute("src", in: body) ?? ""
            let alt = htmlAttribute("alt", in: body) ?? ""
            appendImage(alt: alt, path: source, font: style.font, options: options, to: result)
        case "span", "font", "small", "big", "abbr", "q", "wbr", "bdi", "bdo",
             "ruby", "rt", "var", "dfn", "time", "label", "output":
            stack.append(style)
        default:
            break
        }
    }

    private static func htmlAttribute(_ name: String, in body: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: name + "\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))",
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = body as NSString
        guard let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 2...4 where match.range(at: group).location != NSNotFound {
            return ns.substring(with: match.range(at: group))
        }
        return nil
    }

    private static func plainText(of nodes: [Markup]) -> String {
        var text = ""
        for node in nodes {
            if let literal = node as? Text {
                text += literal.string
            } else {
                text += plainText(of: Array(node.children))
            }
        }
        return text
    }

    private static func appendPlain(_ text: String, style: InlineStyle, options: MarkdownRenderOptions, to result: NSMutableAttributedString) {
        guard !text.isEmpty else { return }
        let inlineStyle = InlineTextStyle(
            font: style.font,
            color: style.color,
            attributes: style.attributes,
            mathFontSize: max(12.5, style.font.pointSize),
            footnotes: options.footnotes,
            isPrinting: options.isPrinting,
            mathItems: options.mathItems
        )
        let fullRange = NSRange(text.startIndex..., in: text)
        let matches = urlPattern.matches(in: text, range: fullRange)
        if matches.isEmpty {
            let display = style.attributes[.link] != nil ? softBreakable(text) : text
            InlineExtensions.append(display, style: inlineStyle, to: result)
            return
        }
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                InlineExtensions.append(substring(text, plainRange), style: inlineStyle, to: result)
            }
            let urlText = substring(text, match.range)
            var attributes = inlineStyle.attributes
            attributes[.font] = style.font
            attributes[.foregroundColor] = NSColor.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if let url = URL(string: urlText) {
                attributes[.link] = url
            }
            result.append(NSAttributedString(string: softBreakable(urlText), attributes: attributes))
            cursor = match.range.location + match.range.length
        }
        if cursor < fullRange.length {
            let tailRange = NSRange(location: cursor, length: fullRange.length - cursor)
            InlineExtensions.append(substring(text, tailRange), style: inlineStyle, to: result)
        }
    }

    /// 超长 URL 在预览里没有断行机会会溢出色块，这里按分隔符插入零宽空格。
    /// 只处理纯 ASCII 的长链接，避免影响中文正文；链接目标仍保留原 URL。
    private static func softBreakable(_ text: String) -> String {
        guard text.count > 56,
              !text.contains(where: { $0.isWhitespace }),
              text.unicodeScalars.allSatisfy({ $0.isASCII }),
              text.contains("/") || text.contains("?") || text.contains("&")
        else { return text }
        let separators: Set<Character> = [":", "/", "?", "&", "=", "#", ".", "_", "-"]
        var result = String()
        result.reserveCapacity(text.count + text.count / 8)
        var run = 0
        for character in text {
            result.append(character)
            run += 1
            if separators.contains(character) {
                result.append("\u{200B}")
                run = 0
            } else if run >= 32 {
                result.append("\u{200B}")
                run = 0
            }
        }
        return result
    }

    private static func resolveURL(_ raw: String, baseURL: URL?) -> URL? {
        if raw.hasPrefix("#") { return nil }
        if let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        let decoded = raw.removingPercentEncoding ?? raw
        guard let baseURL else { return URL(string: raw) }
        return URL(fileURLWithPath: decoded, relativeTo: baseURL).standardizedFileURL
    }

    private static func appendImage(alt: String, path: String, font: NSFont, options: MarkdownRenderOptions, to result: NSMutableAttributedString) {
        guard !path.hasPrefix("http://"), !path.hasPrefix("https://") else {
            if !alt.isEmpty {
                result.append(NSAttributedString(string: alt, attributes: [
                    .font: italicFont(font),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            return
        }
        let decoded = path.removingPercentEncoding ?? path
        let fileURL: URL?
        if decoded.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: decoded)
        } else if let baseURL = options.baseURL {
            fileURL = URL(fileURLWithPath: decoded, relativeTo: baseURL).standardizedFileURL
        } else {
            fileURL = nil
        }
        guard let fileURL else {
            appendMissingImage(alt: alt, font: font, to: result)
            return
        }
        let maxWidth = max(120, options.maxImageWidth)
        if options.asynchronousImages {
            if let image = MarkdownImageStore.cachedImage(for: fileURL) {
                result.append(attachmentString(for: image, url: fileURL, maxWidth: maxWidth))
            } else {
                MarkdownImageStore.requestImage(for: fileURL)
                result.append(imagePlaceholder(alt: alt, url: fileURL, font: font, maxWidth: maxWidth))
            }
            return
        }
        guard let image = MarkdownImageStore.image(for: fileURL) else {
            appendMissingImage(alt: alt, font: font, to: result)
            return
        }
        result.append(attachmentString(for: image, url: fileURL, maxWidth: maxWidth))
    }

    private static func appendMissingImage(alt: String, font: NSFont, to result: NSMutableAttributedString) {
        guard !alt.isEmpty else { return }
        result.append(NSAttributedString(string: "[图片：\(alt)]", attributes: [
            .font: italicFont(font),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
    }

    private static func imagePlaceholder(alt: String, url: URL, font: NSFont, maxWidth: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacingBefore = 6
        paragraph.paragraphSpacing = 12
        return NSAttributedString(string: "正在加载图片…", attributes: [
            .font: italicFont(font),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraph,
            .lumeImagePendingURL: url,
            .lumeImagePendingAlt: alt,
            .lumeImagePendingMaxWidth: maxWidth
        ])
    }

    static func attachmentString(for image: NSImage, url: URL, maxWidth: CGFloat) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = imageBounds(for: image.size, maxWidth: maxWidth)
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttributes([
            .lumeImageURL: url,
            .lumeImagePixelSize: NSValue(size: image.size)
        ], range: NSRange(location: 0, length: attachmentString.length))
        return attachmentString
    }

    static func imageBounds(for original: CGSize, maxWidth: CGFloat) -> CGRect {
        let limit = max(120, maxWidth)
        var scale = limit / max(original.width, 1)
        scale = min(scale, 2.2)
        scale = min(scale, 1600 / max(original.height, 1))
        scale = max(scale, 0.02)
        return CGRect(x: 0, y: 0, width: original.width * scale, height: original.height * scale)
    }

    /// 独占一段的图片居中显示，alt 文字作为题注放在图下。
    private static func appendImageFigure(_ image: Image, options: MarkdownRenderOptions, to output: NSMutableAttributedString) {
        let alt = plainText(of: Array(image.children)).trimmingCharacters(in: .whitespacesAndNewlines)
        let font = options.font(size: options.baseFontSize)
        let picture = NSMutableAttributedString()
        appendImage(alt: alt, path: image.source ?? "", font: font, options: options, to: picture)
        guard picture.length > 0 else { return }
        let rendered = picture.attribute(.attachment, at: 0, effectiveRange: nil) != nil
            || picture.attribute(.lumeImagePendingURL, at: 0, effectiveRange: nil) != nil
        guard rendered else {
            // 远程图或文件缺失时 appendImage 已给出文字占位，不再重复题注。
            output.append(picture)
            output.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacingBefore = 6
        paragraph.paragraphSpacing = alt.isEmpty ? 12 : 2
        picture.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: picture.length))
        output.append(picture)
        output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
        guard !alt.isEmpty else { return }
        let captionFont = options.font(size: max(11, options.baseFontSize - 2.5))
        let captionParagraph = NSMutableParagraphStyle()
        captionParagraph.alignment = .center
        captionParagraph.paragraphSpacing = 12
        let caption = NSAttributedString(string: alt, attributes: [
            .font: captionFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: captionParagraph
        ])
        output.append(caption)
        output.append(NSAttributedString(string: "\n", attributes: [.font: captionFont, .paragraphStyle: captionParagraph]))
    }

    static func resizeImages(in storage: NSTextStorage?, maxWidth: CGFloat) {
        guard let storage, storage.length > 0 else { return }
        let limit = max(120, maxWidth)
        var changed = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let stored = storage.attribute(.lumeImagePixelSize, at: range.location, effectiveRange: nil) as? NSValue
            guard let original = stored?.sizeValue ?? attachment.image?.size,
                  original.width > 0, original.height > 0 else { return }
            var scale = limit / original.width
            scale = min(scale, 2.2)
            scale = min(scale, 1600 / original.height)
            scale = max(scale, 0.02)
            let size = CGSize(width: original.width * scale, height: original.height * scale)
            if abs(attachment.bounds.width - size.width) > 0.5 || abs(attachment.bounds.height - size.height) > 0.5 {
                attachment.bounds = CGRect(origin: .zero, size: size)
                changed = true
            }
        }
        if changed {
            storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
        }
    }

    private static func boldFont(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private static func italicFont(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    // MARK: - Helpers

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }
}
