import AppKit

@MainActor
final class EditorBridge: ObservableObject {
    static let shared = EditorBridge()

    weak var textView: NSTextView?
    weak var store: LibraryStore?

    @Published var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: Self.fontSizeKey)
        }
    }

    /// 空字符串表示跟随系统：编辑区用系统等宽，预览用系统正文字体。
    @Published var fontFamily: String {
        didSet {
            UserDefaults.standard.set(fontFamily, forKey: Self.fontFamilyKey)
        }
    }

    static let fontSizeKey = "Lume.editorFontSize"
    static let fontFamilyKey = "Lume.editorFontFamily"

    static let diagramTemplates: [(title: String, code: String)] = [
        ("流程图", """
        flowchart TD
            A[开始] --> B{条件判断}
            B -->|是| C[处理]
            B -->|否| D[结束]
            C --> D
        """),
        ("时序图", """
        sequenceDiagram
            participant U as 用户
            participant S as 服务
            U->>S: 发起请求
            S-->>U: 返回结果
        """),
        ("状态图", """
        stateDiagram-v2
            [*] --> 待处理
            待处理 --> 处理中: 开始
            处理中 --> 已完成: 完成
            处理中 --> 待处理: 退回
            已完成 --> [*]
        """),
        ("ER 图", """
        erDiagram
            USER ||--o{ ORDER : places
            ORDER ||--|{ ITEM : contains
            USER {
                string name
                string email
            }
        """),
        ("甘特图", """
        gantt
            title 项目计划
            dateFormat YYYY-MM-DD
            section 阶段一
            需求梳理 :a1, 2026-01-05, 5d
            方案设计 :a2, after a1, 4d
            section 阶段二
            开发实现 :b1, after a2, 10d
        """),
        ("Git 图", """
        gitGraph
            commit id: "init"
            branch feature
            checkout feature
            commit id: "feat-1"
            checkout main
            merge feature
        """),
        ("脑图", """
        mindmap
          root((知识库))
            规划
              目标
              里程碑
            执行
              任务
              复盘
        """),
        ("C4 架构图", """
        C4Context
            title 系统上下文
            Person(user, "用户", "使用系统")
            System(app, "应用系统", "提供核心功能")
            System_Ext(ext, "外部服务", "第三方接口")
            Rel(user, app, "使用")
            Rel(app, ext, "调用")
        """)
    ]

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = saved > 0 ? CGFloat(saved) : 13.5
        fontFamily = UserDefaults.standard.string(forKey: Self.fontFamilyKey) ?? ""
    }

    static var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var fontFamilyLabel: String {
        fontFamily.isEmpty ? "系统默认" : fontFamily
    }

    /// 编辑区主体字体：默认系统等宽；用户选择字体后，缺字或字体被卸载时回落到系统等宽。
    func editorFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        familyFont(weight: weight, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// 预览正文与标题字体：默认系统字体，选择后使用所选字体族。
    func previewFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        familyFont(weight: weight, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    func codeFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private func familyFont(weight: NSFont.Weight, size: CGFloat) -> NSFont? {
        guard !fontFamily.isEmpty else { return nil }
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
            withFamily: fontFamily,
            traits: [],
            weight: managerWeight,
            size: size
        )
    }

    var hasEditor: Bool { textView != nil }

    /// 输入法正在拼写（marked text）时不要落盘，否则会保存半截拼音。
    var isComposing: Bool { textView?.hasMarkedText() ?? false }

    func attach(_ view: NSTextView?) {
        textView = view
    }

    func detach(_ view: NSTextView) {
        if textView === view { textView = nil }
    }

    func adjustFontSize(by delta: CGFloat) {
        setFontSize(fontSize + delta)
    }

    func setFontSize(_ value: CGFloat) {
        fontSize = min(20, max(11, value.rounded()))
    }

    func resetFontSize() {
        setFontSize(13.5)
    }

    func focus() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        // 工具栏插入完成后把插入点滚入可见区域，等布局更新后再滚
        let range = textView.selectedRange()
        DispatchQueue.main.async {
            textView.scrollRangeToVisible(range)
        }
    }

    func focusAtEnd() {
        guard let textView, let window = textView.window else { return }
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: length, length: 0))
        window.makeFirstResponder(textView)
    }

    func toggleWrap(_ marker: String) {
        guard let textView else { return }
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        if range.length == 0 {
            textView.insertText(marker + marker, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + marker.utf16.count, length: 0))
            focus()
            return
        }
        let selected = ns.substring(with: range)
        if selected.hasPrefix(marker), selected.hasSuffix(marker),
           selected.utf16.count >= marker.utf16.count * 2 {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            textView.insertText(inner, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location, length: inner.utf16.count))
            focus()
            return
        }
        let before = range.location - marker.utf16.count
        let after = range.location + range.length
        if before >= 0, after + marker.utf16.count <= ns.length,
           ns.substring(with: NSRange(location: before, length: marker.utf16.count)) == marker,
           ns.substring(with: NSRange(location: after, length: marker.utf16.count)) == marker {
            let outer = NSRange(location: before, length: range.length + marker.utf16.count * 2)
            textView.insertText(selected, replacementRange: outer)
            textView.setSelectedRange(NSRange(location: before, length: selected.utf16.count))
            focus()
            return
        }
        textView.insertText(marker + selected + marker, replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + marker.utf16.count, length: selected.utf16.count))
        focus()
    }

    func setHeading(level: Int) {
        transformLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            var body = line
            if let regex = try? NSRegularExpression(pattern: "^\\s*#{1,6}\\s+") {
                let range = NSRange(line.startIndex..., in: line)
                body = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            }
            if level <= 0 { return body }
            return String(repeating: "#", count: level) + " " + body
        }
    }

    func applyList(ordered: Bool) {
        guard let textView else { return }
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        let lineRange = ns.lineRange(for: range)
        let block = ns.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        let markerRegex = try? NSRegularExpression(pattern: "^\\s*(?:[-*+]|\\d+[.)])\\s+")
        let allPrefixed = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.allSatisfy { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.range(of: "^([-*+]|\\d+[.)])\\s+", options: .regularExpression) != nil
        }

        var counter = 1
        let converted = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            var content = line
            if let regex = markerRegex {
                let range = NSRange(line.startIndex..., in: line)
                content = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            }
            if allPrefixed { return content }
            if ordered {
                defer { counter += 1 }
                return "\(counter). " + content
            }
            return "- " + content
        }
        let replacement = converted.joined(separator: "\n")
        textView.insertText(replacement, replacementRange: lineRange)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: replacement.utf16.count))
        focus()
    }

    func applyQuote() {
        guard let textView else { return }
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: textView.selectedRange())
        let block = ns.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let contentLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allQuoted = !contentLines.isEmpty && contentLines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
        let converted = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return line }
            if allQuoted {
                if let range = line.range(of: "^\\s*>\\s?", options: .regularExpression) {
                    return String(line[range.upperBound...])
                }
                return line
            }
            return "> " + line
        }
        let replacement = converted.joined(separator: "\n")
        textView.insertText(replacement, replacementRange: lineRange)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: replacement.utf16.count))
        focus()
    }

    func toggleCodeBlock() {
        guard let textView else { return }
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        if range.length == 0 {
            let snippet = "\n```\n\n```\n"
            textView.insertText(snippet, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + 5, length: 0))
            focus()
            return
        }
        let selected = ns.substring(with: range)
        if selected.hasPrefix("```"), selected.hasSuffix("```"), selected.utf16.count >= 8 {
            var inner = String(selected.dropFirst(3).dropLast(3))
            if inner.hasPrefix("\n") { inner.removeFirst() }
            if inner.hasSuffix("\n") { inner.removeLast() }
            textView.insertText(inner, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location, length: inner.utf16.count))
            focus()
            return
        }
        let snippet = "\n```\n" + selected + "\n```\n"
        textView.insertText(snippet, replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + 5, length: selected.utf16.count))
        focus()
    }

    func insertDiagram(_ code: String) {
        guard textView != nil else { return }
        insertBlock("```mermaid\n" + code + "\n```")
    }

    func insertCodeBlock(language: String) {
        guard let textView else { return }
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        let selected = ns.substring(with: range)
        let fence = "```" + language
        let snippet = fence + "\n" + selected + "\n```"
        guard let inserted = insertBlock(snippet) else { return }
        let codeStart = inserted.location + fence.utf16.count + 1
        if selected.isEmpty {
            textView.setSelectedRange(NSRange(location: codeStart, length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: codeStart, length: selected.utf16.count))
        }
        focus()
    }

    func toggleStrike() {
        toggleWrap("~~")
    }

    func toggleHighlight() {
        toggleWrap("==")
    }

    func toggleInlineMath() {
        guard let textView else { return }
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        if range.length == 0 {
            textView.insertText("$$", replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            focus()
            return
        }
        let selected = ns.substring(with: range)
        if selected.hasPrefix("$"), selected.hasSuffix("$"), selected.utf16.count >= 2 {
            let inner = String(selected.dropFirst().dropLast())
            textView.insertText(inner, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location, length: inner.utf16.count))
        } else {
            textView.insertText("$" + selected + "$", replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + 1, length: selected.utf16.count))
        }
        focus()
    }

    func insertBlockMath() {
        guard let textView else { return }
        guard let inserted = insertBlock("$$\n\n$$") else { return }
        textView.setSelectedRange(NSRange(location: inserted.location + 3, length: 0))
        focus()
    }

    func insertAlert(kind: String) {
        guard let textView else { return }
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        let selected = ns.substring(with: range)
        if selected.isEmpty {
            let marker = "> [!" + kind + "]\n> "
            guard let inserted = insertBlock(marker) else { return }
            textView.setSelectedRange(NSRange(location: inserted.location + marker.utf16.count, length: 0))
        } else {
            let quoted = selected.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
            let block = "> [!" + kind + "]\n" + quoted
            textView.insertText(block, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location, length: block.utf16.count))
        }
        focus()
    }

    func insertFootnote() {
        guard let textView else { return }
        let ns = textView.string as NSString
        var maxNumber = 0
        if let regex = try? NSRegularExpression(pattern: "\\[\\^(\\d+)\\]") {
            regex.enumerateMatches(in: textView.string, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match else { return }
                maxNumber = max(maxNumber, Int(ns.substring(with: match.range(at: 1))) ?? 0)
            }
        }
        let label = String(maxNumber + 1)
        let range = textView.selectedRange()
        textView.insertText("[^\(label)]", replacementRange: range)

        let updated = textView.string as NSString
        let separator: String
        if updated.length == 0 {
            separator = ""
        } else if updated.hasSuffix("\n\n") {
            separator = ""
        } else if updated.hasSuffix("\n") {
            separator = "\n"
        } else {
            separator = "\n\n"
        }
        let definition = separator + "[^\(label)]: "
        let end = NSRange(location: updated.length, length: 0)
        textView.insertText(definition, replacementRange: end)
        textView.setSelectedRange(NSRange(location: updated.length + definition.utf16.count, length: 0))
        focus()
    }

    func applyTaskList() {
        guard let textView else { return }
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: textView.selectedRange())
        let block = ns.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let taskPattern = "^\\s*[-*+]\\s+\\[[ xX]\\]\\s+"
        let contentLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allTasks = !contentLines.isEmpty && contentLines.allSatisfy {
            $0.range(of: taskPattern, options: .regularExpression) != nil
        }
        let converted = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            var content = line
            if let regex = try? NSRegularExpression(pattern: taskPattern) {
                let range = NSRange(line.startIndex..., in: line)
                content = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            }
            if allTasks { return content }
            return "- [ ] " + content.trimmingCharacters(in: .whitespaces)
        }
        let replacement = converted.joined(separator: "\n")
        textView.insertText(replacement, replacementRange: lineRange)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: replacement.utf16.count))
        focus()
    }

    func insertTable() {
        guard let textView else { return }
        let table = """
        | 列 1 | 列 2 | 列 3 |
        | --- | --- | --- |
        |  |  |  |
        |  |  |  |
        """
        guard let inserted = insertBlock(table) else { return }
        let header = (textView.string as NSString).range(of: "列 1", options: [], range: inserted)
        if header.location != NSNotFound {
            textView.setSelectedRange(header)
        }
        focus()
    }

    func insertDivider() {
        insertBlock("---")
    }

    func insertAttachment() {
        guard let store, let markdown = store.insertAttachmentFromPanel() else { return }
        insertBlock(markdown)
    }

    func insertLink() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let selected = (textView.string as NSString).substring(with: range)
        if selected.isEmpty {
            let template = "[]()"
            textView.insertText(template, replacementRange: range)
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
        } else {
            let template = "[\(selected)](https://)"
            textView.insertText(template, replacementRange: range)
            let urlStart = range.location + selected.utf16.count + 3
            textView.setSelectedRange(NSRange(location: urlStart, length: 8))
        }
        focus()
    }

    func insertImage() {
        guard let store, let markdown = store.insertImageFromPanel() else { return }
        insertBlock(markdown)
    }

    func insertDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        insertText(formatter.string(from: Date()))
    }

    func insertText(_ text: String) {
        guard let textView else { return }
        textView.insertText(text, replacementRange: textView.selectedRange())
        focus()
    }

    @discardableResult
    func insertBlock(_ block: String) -> NSRange? {
        guard let textView else { return nil }
        let ns = textView.string as NSString
        let range = textView.selectedRange()
        var prefix = ""
        var suffix = ""
        if range.location > 0 {
            let before = ns.substring(with: NSRange(location: range.location - 1, length: 1))
            if before != "\n" { prefix = "\n\n" }
        }
        let end = range.location + range.length
        if end < ns.length {
            let after = ns.substring(with: NSRange(location: end, length: 1))
            if after != "\n" { suffix = "\n" }
        }
        let start = range.location
        textView.insertText(prefix + block + suffix, replacementRange: range)
        focus()
        return NSRange(location: start + prefix.utf16.count, length: block.utf16.count)
    }

    func searchSelection() {
        guard let textView, let store else { return }
        let selected = (textView.string as NSString).substring(with: textView.selectedRange())
        let query = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        store.sidebarSelection = .all
        store.searchText = query
    }

    func showFind() {
        guard let textView else { return }
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performFindPanelAction(item)
    }

    private func transformLines(_ transform: (String, Int) -> String) {
        guard let textView else { return }
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: textView.selectedRange())
        let block = ns.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        let trailingNewline = lines.last == ""
        if trailingNewline { lines.removeLast() }
        let converted = lines.enumerated().map { index, line in transform(line, index) }
        var replacement = converted.joined(separator: "\n")
        if trailingNewline { replacement += "\n" }
        textView.insertText(replacement, replacementRange: lineRange)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: replacement.utf16.count))
        focus()
    }
}

@MainActor
final class EditorActions: NSObject {
    static let shared = EditorActions()

    @objc func bold() { EditorBridge.shared.toggleWrap("**") }
    @objc func italic() { EditorBridge.shared.toggleWrap("*") }
    @objc func strike() { EditorBridge.shared.toggleStrike() }
    @objc func inlineCode() { EditorBridge.shared.toggleWrap("`") }
    @objc func codeBlock() { EditorBridge.shared.toggleCodeBlock() }
    @objc func link() { EditorBridge.shared.insertLink() }
    @objc func heading1() { EditorBridge.shared.setHeading(level: 1) }
    @objc func heading2() { EditorBridge.shared.setHeading(level: 2) }
    @objc func heading3() { EditorBridge.shared.setHeading(level: 3) }
    @objc func bulletList() { EditorBridge.shared.applyList(ordered: false) }
    @objc func numberedList() { EditorBridge.shared.applyList(ordered: true) }
    @objc func taskList() { EditorBridge.shared.applyTaskList() }
    @objc func quote() { EditorBridge.shared.applyQuote() }
    @objc func table() { EditorBridge.shared.insertTable() }
    @objc func divider() { EditorBridge.shared.insertDivider() }
    @objc func insertImage() { EditorBridge.shared.insertImage() }
    @objc func insertAttachment() { EditorBridge.shared.insertAttachment() }
    @objc func insertDate() { EditorBridge.shared.insertDate() }
    @objc func highlight() { EditorBridge.shared.toggleHighlight() }
    @objc func inlineMath() { EditorBridge.shared.toggleInlineMath() }
    @objc func blockMath() { EditorBridge.shared.insertBlockMath() }
    @objc func footnote() { EditorBridge.shared.insertFootnote() }
    @objc func alertNote() { EditorBridge.shared.insertAlert(kind: "NOTE") }
    @objc func alertTip() { EditorBridge.shared.insertAlert(kind: "TIP") }
    @objc func alertImportant() { EditorBridge.shared.insertAlert(kind: "IMPORTANT") }
    @objc func alertWarning() { EditorBridge.shared.insertAlert(kind: "WARNING") }
    @objc func alertCaution() { EditorBridge.shared.insertAlert(kind: "CAUTION") }
    @objc func searchSelection() { EditorBridge.shared.searchSelection() }
}

final class MarkdownTextView: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        menu.addItem(formatMenuItem())
        menu.addItem(insertMenuItem())
        menu.addItem(.separator())
        let search = NSMenuItem(title: "在知识库中搜索所选内容", action: #selector(EditorActions.searchSelection), keyEquivalent: "")
        search.target = EditorActions.shared
        menu.addItem(search)
        return menu
    }

    private func formatMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "格式", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "格式")
        submenu.addItem(actionItem("加粗", #selector(EditorActions.bold)))
        submenu.addItem(actionItem("斜体", #selector(EditorActions.italic)))
        submenu.addItem(actionItem("删除线", #selector(EditorActions.strike)))
        submenu.addItem(actionItem("高亮", #selector(EditorActions.highlight)))
        submenu.addItem(actionItem("行内代码", #selector(EditorActions.inlineCode)))
        submenu.addItem(actionItem("代码块", #selector(EditorActions.codeBlock)))
        submenu.addItem(actionItem("行内公式", #selector(EditorActions.inlineMath)))
        submenu.addItem(actionItem("块级公式", #selector(EditorActions.blockMath)))
        submenu.addItem(actionItem("脚注", #selector(EditorActions.footnote)))
        submenu.addItem(actionItem("链接", #selector(EditorActions.link)))
        submenu.addItem(.separator())
        submenu.addItem(actionItem("一级标题", #selector(EditorActions.heading1)))
        submenu.addItem(actionItem("二级标题", #selector(EditorActions.heading2)))
        submenu.addItem(actionItem("三级标题", #selector(EditorActions.heading3)))
        submenu.addItem(.separator())
        submenu.addItem(actionItem("无序列表", #selector(EditorActions.bulletList)))
        submenu.addItem(actionItem("有序列表", #selector(EditorActions.numberedList)))
        submenu.addItem(actionItem("任务列表", #selector(EditorActions.taskList)))
        submenu.addItem(actionItem("引用", #selector(EditorActions.quote)))
        parent.submenu = submenu
        return parent
    }

    private func insertMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "插入", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "插入")
        submenu.addItem(actionItem("表格", #selector(EditorActions.table)))
        submenu.addItem(actionItem("分隔线", #selector(EditorActions.divider)))
        let alerts = NSMenuItem(title: "GitHub 告警", action: nil, keyEquivalent: "")
        let alertMenu = NSMenu(title: "GitHub 告警")
        alertMenu.addItem(actionItem("Note 提示", #selector(EditorActions.alertNote)))
        alertMenu.addItem(actionItem("Tip 技巧", #selector(EditorActions.alertTip)))
        alertMenu.addItem(actionItem("Important 重点", #selector(EditorActions.alertImportant)))
        alertMenu.addItem(actionItem("Warning 警告", #selector(EditorActions.alertWarning)))
        alertMenu.addItem(actionItem("Caution 注意", #selector(EditorActions.alertCaution)))
        alerts.submenu = alertMenu
        submenu.addItem(alerts)
        submenu.addItem(.separator())
        submenu.addItem(actionItem("图片…", #selector(EditorActions.insertImage)))
        submenu.addItem(actionItem("附件…", #selector(EditorActions.insertAttachment)))
        submenu.addItem(actionItem("当前日期", #selector(EditorActions.insertDate)))
        parent.submenu = submenu
        return parent
    }

    private func actionItem(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = EditorActions.shared
        return item
    }
}
