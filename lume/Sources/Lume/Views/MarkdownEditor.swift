import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 600), textContainer: container)
        context.coordinator.textContentStorage = contentStorage
        context.coordinator.textLayoutManager = layoutManager
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 22, height: 18)
        if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .complete
        }
        textView.delegate = context.coordinator
        textView.string = text
        applyBaseAttributes(textView)
        context.coordinator.isUpdating = false
        context.coordinator.lastText = text
        context.coordinator.lastAppearance = NSApp.effectiveAppearance.name.rawValue
        context.coordinator.lastFontSize = EditorBridge.shared.fontSize
        context.coordinator.lastFontFamily = EditorBridge.shared.fontFamily

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        EditorBridge.shared.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.parent = self
        EditorBridge.shared.attach(textView)
        let appearance = NSApp.effectiveAppearance.name.rawValue
        if context.coordinator.lastAppearance != appearance {
            context.coordinator.lastAppearance = appearance
            applyBaseAttributes(textView)
        }
        if context.coordinator.lastFontSize != EditorBridge.shared.fontSize
            || context.coordinator.lastFontFamily != EditorBridge.shared.fontFamily {
            context.coordinator.lastFontSize = EditorBridge.shared.fontSize
            context.coordinator.lastFontFamily = EditorBridge.shared.fontFamily
            applyBaseAttributes(textView)
        }
        guard textView.string != text else { return }
        // 输入法拼写中替换文本会打断候选并让光标错位，提交后再同步
        guard !textView.hasMarkedText() else { return }
        context.coordinator.isUpdating = true
        let oldSelection = textView.selectedRange()
        textView.string = text
        applyBaseAttributes(textView)
        let length = (text as NSString).length
        let location = min(oldSelection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        context.coordinator.isUpdating = false
        context.coordinator.lastText = text
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
        if let textView = nsView.documentView as? NSTextView {
            EditorBridge.shared.detach(textView)
        }
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 0
        paragraph.defaultTabInterval = 28
        let size = EditorBridge.shared.fontSize
        let font = EditorBridge.shared.editorFont(size: size)
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private func applyBaseAttributes(_ textView: NSTextView) {
        textView.typingAttributes = Self.baseAttributes()
        Self.restyle(textView)
    }

    static func restyle(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let length = (textView.string as NSString).length
        guard length > 0 else { return }
        // 全文 setAttributes 会让 TextKit 2 整篇排版失效，文档高度塌缩导致视口跳动；
        // 因此先离屏构建目标属性，只回写与现状不一致的片段。
        let desired = desiredAttributes(for: textView)
        let full = NSRange(location: 0, length: length)
        var location = 0
        while location < length {
            var desiredRange = NSRange()
            let attrs = desired.attributes(at: location, longestEffectiveRange: &desiredRange, in: full)
            var existingRange = NSRange()
            let existing = storage.attributes(at: location, longestEffectiveRange: &existingRange, in: full)
            if existingRange.location <= desiredRange.location,
               NSMaxRange(existingRange) >= NSMaxRange(desiredRange),
               attributesMatch(attrs, existing) {
                location = NSMaxRange(desiredRange)
            } else {
                storage.setAttributes(attrs, range: desiredRange)
            }
            location = max(location, NSMaxRange(desiredRange), location + 1)
        }
    }

    private static func attributesMatch(
        _ desired: [NSAttributedString.Key: Any],
        _ existing: [NSAttributedString.Key: Any]
    ) -> Bool {
        guard desired.count == existing.count else { return false }
        for (key, value) in desired {
            guard let val = value as? NSObject,
                  let other = existing[key] as? NSObject,
                  val.isEqual(other) else { return false }
        }
        return true
    }

    private static func desiredAttributes(for textView: NSTextView) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: textView.string, attributes: baseAttributes())
        applyFrontmatter(to: result)
        applySyntaxHighlighting(to: result)
        return result
    }

    private static func applySyntaxHighlighting(to result: NSMutableAttributedString) {
        let string = result.string
        guard !string.isEmpty else { return }
        let baseParagraph = baseAttributes()[.paragraphStyle] as? NSParagraphStyle
            ?? NSMutableParagraphStyle()
        let size = EditorBridge.shared.fontSize
        let mono = EditorBridge.shared.codeFont(size: size)
        let lines = string.components(separatedBy: "\n")

        var offset = 0
        var fenceOpen = false
        var fenceLanguage = ""
        var codeStartOffset = 0
        var codeLines: [String] = []

        func flushCode(until lineOffset: Int) {
            guard codeStartOffset >= 0, codeStartOffset <= lineOffset else { return }
            let code = codeLines.joined(separator: "\n")
            let attributed = CodeHighlighter.highlight(code, language: fenceLanguage, font: mono)
            let full = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttributes(in: full) { attrs, range, _ in
                var merge = attrs
                merge[.paragraphStyle] = baseParagraph
                let target = NSRange(
                    location: codeStartOffset + range.location,
                    length: range.length
                )
                if target.location + target.length <= result.length {
                    result.addAttributes(merge, range: target)
                }
            }
            codeLines = []
        }

        for line in lines {
            let lineLength = (line as NSString).length
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            if fenceOpen {
                if isFence {
                    flushCode(until: offset)
                    result.addAttributes(
                        [.foregroundColor: NSColor.secondaryLabelColor],
                        range: NSRange(location: offset, length: lineLength)
                    )
                    fenceOpen = false
                } else {
                    codeLines.append(line)
                }
            } else if isFence {
                fenceOpen = true
                fenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeStartOffset = offset + lineLength + 1
                result.addAttributes(
                    [.foregroundColor: NSColor.secondaryLabelColor],
                    range: NSRange(location: offset, length: lineLength)
                )
                markLanguage(in: line, at: offset, language: fenceLanguage, in: result)
            } else if isHeading(trimmed) {
                result.addAttributes(
                    [
                        .font: EditorBridge.shared.editorFont(size: size, weight: .semibold),
                        .foregroundColor: NSColor.labelColor
                    ],
                    range: NSRange(location: offset, length: lineLength)
                )
            }
            offset += lineLength + 1
        }

        if fenceOpen, codeStartOffset <= result.length {
            flushCode(until: result.length)
        }
    }

    /// 编辑区没有渲染层，围栏后的语言名单独着色，让代码块语言始终可见。
    private static func markLanguage(
        in line: String, at offset: Int, language: String, in result: NSMutableAttributedString
    ) {
        let token = language.split(separator: " ").first.map(String.init) ?? ""
        guard !token.isEmpty else { return }
        let ns = line as NSString
        let range = ns.range(of: token)
        guard range.location != NSNotFound else { return }
        result.addAttributes([
            .foregroundColor: NSColor.controlAccentColor,
            .font: EditorBridge.shared.codeFont(size: EditorBridge.shared.fontSize, weight: .medium)
        ], range: NSRange(location: offset + range.location, length: range.length))
    }

    private static func applyFrontmatter(to result: NSMutableAttributedString) {
        let lines = result.string.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return }
        var offset = 0
        var closeOffset: Int?
        for (index, line) in lines.enumerated() {
            if index > 0, line.trimmingCharacters(in: .whitespaces) == "---" {
                closeOffset = offset + (line as NSString).length
                break
            }
            offset += (line as NSString).length + 1
        }
        guard let closeOffset, closeOffset > 0 else { return }
        let range = NSRange(location: 0, length: min(closeOffset, result.length))
        result.addAttributes([
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: EditorBridge.shared.editorFont(size: max(11, EditorBridge.shared.fontSize - 1.5))
        ], range: range)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var isUpdating = true
        var lastText = ""
        var lastAppearance = ""
        var lastFontSize: CGFloat = 13.5
        var lastFontFamily = ""
        var textContentStorage: NSTextContentStorage?
        var textLayoutManager: NSTextLayoutManager?
        private var restyleWork: DispatchWorkItem?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        /// 输入时不再整篇重设属性，停顿后再统一着色，避免逐键重绘造成闪烁。
        func scheduleRestyle(for textView: NSTextView, delay: TimeInterval = 0.12) {
            restyleWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                guard !textView.hasMarkedText() else {
                    self.scheduleRestyle(for: textView, delay: 0.2)
                    return
                }
                MarkdownEditor.restyle(textView)
            }
            restyleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        func stopObserving() {
            restyleWork?.cancel()
            restyleWork = nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !isUpdating else { return }
            let value = textView.string
            lastText = value
            parent.text = value
            // 拼写中的文本不进入保存流程，提交后 textDidChange 会再次触发
            if !textView.hasMarkedText() {
                parent.onChange(value)
            }
            scheduleRestyle(for: textView)
        }
    }

    private static func isHeading(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("#") else { return false }
        var hashes = 0
        for char in trimmed {
            if char == "#" { hashes += 1 } else { break }
        }
        guard hashes <= 6, trimmed.count > hashes else { return false }
        return trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)].isWhitespace
    }
}
