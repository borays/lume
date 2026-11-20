import AppKit
import SwiftUI

struct Shortcut: Codable, Hashable {
    var key: String
    var command = false
    var shift = false
    var option = false
    var control = false

    init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// 修饰键之外必须有 ⌘/⌥/⌃ 之一，避免把普通输入录成快捷键。
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else { return nil }

        let key: String
        switch event.keyCode {
        case 51, 117: key = "delete"
        case 36, 76: key = "return"
        case 48: key = "tab"
        case 53: key = "escape"
        case 49: key = "space"
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        default:
            guard let raw = event.charactersIgnoringModifiers?.lowercased(),
                  raw.count == 1,
                  let scalar = raw.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar) else { return nil }
            key = raw
        }

        self.key = key
        command = flags.contains(.command)
        shift = flags.contains(.shift)
        option = flags.contains(.option)
        control = flags.contains(.control)
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "delete": return .delete
        case "return": return .return
        case "tab": return .tab
        case "escape": return .escape
        case "space": return .space
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        default:
            guard key.count == 1, let character = key.first else { return nil }
            return KeyEquivalent(character)
        }
    }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        return modifiers
    }

    var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + keyLabel
    }

    private var keyLabel: String {
        switch key {
        case "delete": return "⌫"
        case "return": return "↩"
        case "tab": return "⇥"
        case "escape": return "⎋"
        case "space": return "␣"
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        default: return key.uppercased()
        }
    }
}

enum ShortcutCategory: String, CaseIterable, Identifiable {
    case file = "文件"
    case edit = "编辑"
    case note = "笔记"
    case format = "格式"
    case view = "视图"

    var id: String { rawValue }
}

enum AppCommandID: String, CaseIterable, Identifiable {
    case newNote, newNoteInFolder, newFolder, importWeb
    case save, exportPDF, quickOpen, find
    case renameNote, moveNote, editTags, duplicateNote, revealInFinder, moveToTrash
    case bold, italic, strikethrough, highlight, inlineCode, codeBlock
    case inlineMath, blockMath, footnote, link
    case heading1, heading2, heading3, heading4, heading5, heading6, bodyText
    case bulletList, numberedList, taskList, quote
    case table, divider, image, attachment, date
    case modeEditor, modeSplit, modePreview, toggleAppearance, rescanLibrary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newNote: return "新建笔记"
        case .newNoteInFolder: return "新建到当前目录"
        case .newFolder: return "新建文件夹"
        case .importWeb: return "导入网页"
        case .save: return "保存"
        case .exportPDF: return "导出 PDF"
        case .quickOpen: return "快速打开"
        case .find: return "查找"
        case .renameNote: return "重命名笔记"
        case .moveNote: return "移动笔记"
        case .editTags: return "编辑标签"
        case .duplicateNote: return "创建副本"
        case .revealInFinder: return "在 Finder 中显示"
        case .moveToTrash: return "移到废纸篓"
        case .bold: return "加粗"
        case .italic: return "斜体"
        case .strikethrough: return "删除线"
        case .highlight: return "高亮"
        case .inlineCode: return "行内代码"
        case .codeBlock: return "代码块"
        case .inlineMath: return "行内公式"
        case .blockMath: return "块级公式"
        case .footnote: return "脚注"
        case .link: return "链接"
        case .heading1: return "一级标题"
        case .heading2: return "二级标题"
        case .heading3: return "三级标题"
        case .heading4: return "四级标题"
        case .heading5: return "五级标题"
        case .heading6: return "六级标题"
        case .bodyText: return "正文"
        case .bulletList: return "无序列表"
        case .numberedList: return "有序列表"
        case .taskList: return "任务列表"
        case .quote: return "引用"
        case .table: return "插入表格"
        case .divider: return "插入分隔线"
        case .image: return "插入图片"
        case .attachment: return "插入附件"
        case .date: return "插入当前日期"
        case .modeEditor: return "仅编辑"
        case .modeSplit: return "分栏"
        case .modePreview: return "仅预览"
        case .toggleAppearance: return "切换深浅色外观"
        case .rescanLibrary: return "重新扫描知识库"
        }
    }

    var category: ShortcutCategory {
        switch self {
        case .newNote, .newNoteInFolder, .newFolder, .importWeb, .save, .exportPDF, .quickOpen, .find:
            return .file
        case .renameNote, .moveNote, .editTags, .duplicateNote, .revealInFinder, .moveToTrash:
            return .note
        case .bold, .italic, .strikethrough, .highlight, .inlineCode, .codeBlock,
             .inlineMath, .blockMath, .footnote, .link,
             .heading1, .heading2, .heading3, .heading4, .heading5, .heading6, .bodyText,
             .bulletList, .numberedList, .taskList, .quote,
             .table, .divider, .image, .attachment, .date:
            return .format
        case .modeEditor, .modeSplit, .modePreview, .toggleAppearance, .rescanLibrary:
            return .view
        }
    }

    var defaultShortcut: Shortcut? {
        switch self {
        case .newNote: return Shortcut(key: "n", command: true)
        case .newNoteInFolder: return Shortcut(key: "n", command: true, shift: true)
        case .newFolder: return Shortcut(key: "n", command: true, option: true)
        case .importWeb: return Shortcut(key: "i", command: true, shift: true)
        case .save: return Shortcut(key: "s", command: true)
        case .exportPDF: return Shortcut(key: "e", command: true, shift: true)
        case .quickOpen: return Shortcut(key: "p", command: true)
        case .find: return Shortcut(key: "f", command: true)
        case .renameNote: return Shortcut(key: "r", command: true)
        case .moveNote: return Shortcut(key: "m", command: true, shift: true)
        case .editTags: return Shortcut(key: "t", command: true, shift: true)
        case .duplicateNote: return Shortcut(key: "d", command: true)
        case .revealInFinder: return Shortcut(key: "r", command: true, option: true)
        case .moveToTrash: return Shortcut(key: "delete", command: true)
        case .bold: return Shortcut(key: "b", command: true)
        case .italic: return Shortcut(key: "i", command: true)
        case .strikethrough: return Shortcut(key: "x", command: true, shift: true)
        case .highlight: return Shortcut(key: "h", command: true, shift: true)
        case .inlineCode: return Shortcut(key: "c", command: true, shift: true)
        case .codeBlock: return Shortcut(key: "c", command: true, control: true)
        case .inlineMath: return Shortcut(key: "m", command: true, control: true)
        case .blockMath: return Shortcut(key: "m", command: true, shift: true, control: true)
        case .footnote: return Shortcut(key: "u", command: true, shift: true)
        case .link: return Shortcut(key: "k", command: true)
        case .heading1: return Shortcut(key: "1", command: true, option: true)
        case .heading2: return Shortcut(key: "2", command: true, option: true)
        case .heading3: return Shortcut(key: "3", command: true, option: true)
        case .heading4: return Shortcut(key: "4", command: true, option: true)
        case .heading5: return Shortcut(key: "5", command: true, option: true)
        case .heading6: return Shortcut(key: "6", command: true, option: true)
        case .bodyText: return Shortcut(key: "0", command: true, control: true)
        case .bulletList: return Shortcut(key: "l", command: true, shift: true)
        case .numberedList: return Shortcut(key: "o", command: true, shift: true)
        case .taskList: return Shortcut(key: "k", command: true, shift: true)
        case .quote: return Shortcut(key: "q", command: true, option: true)
        case .table: return Shortcut(key: "t", command: true, control: true)
        case .divider: return Shortcut(key: "-", command: true, shift: true, control: true)
        case .image: return Shortcut(key: "i", command: true, control: true)
        case .attachment: return Shortcut(key: "a", command: true, shift: true, control: true)
        case .date: return Shortcut(key: "d", command: true, option: true)
        case .modeEditor: return Shortcut(key: "1", command: true, control: true)
        case .modeSplit: return Shortcut(key: "2", command: true, control: true)
        case .modePreview: return Shortcut(key: "3", command: true, control: true)
        case .toggleAppearance: return Shortcut(key: "a", command: true, shift: true)
        case .rescanLibrary: return Shortcut(key: "r", command: true, shift: true)
        }
    }
}

final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    private struct Payload: Codable {
        var overrides: [String: Shortcut] = [:]
        var disabled: [String] = []
    }

    private let defaults: UserDefaults
    private let storageKey: String
    @Published private(set) var overrides: [String: Shortcut] = [:]
    @Published private(set) var disabled: Set<String> = []

    init(defaults: UserDefaults = .standard, storageKey: String = "Lume.shortcuts.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func shortcut(for id: AppCommandID) -> Shortcut? {
        if let custom = overrides[id.rawValue] { return custom }
        if disabled.contains(id.rawValue) { return nil }
        return id.defaultShortcut
    }

    func display(for id: AppCommandID) -> String? {
        shortcut(for: id)?.display
    }

    func conflict(for id: AppCommandID) -> AppCommandID? {
        guard let current = shortcut(for: id) else { return nil }
        return AppCommandID.allCases.first {
            $0 != id && shortcut(for: $0) == current
        }
    }

    /// 组合键在应用内唯一：分配给新命令时会从其他命令移除。
    func set(_ shortcut: Shortcut?, for id: AppCommandID) {
        if let shortcut {
            disabled.remove(id.rawValue)
            if shortcut == id.defaultShortcut {
                overrides.removeValue(forKey: id.rawValue)
            } else {
                overrides[id.rawValue] = shortcut
            }
            for other in AppCommandID.allCases where other != id && self.shortcut(for: other) == shortcut {
                overrides.removeValue(forKey: other.rawValue)
                disabled.insert(other.rawValue)
            }
        } else {
            overrides.removeValue(forKey: id.rawValue)
            disabled.insert(id.rawValue)
        }
        save()
    }

    func reset(_ id: AppCommandID) {
        overrides.removeValue(forKey: id.rawValue)
        disabled.remove(id.rawValue)
        save()
    }

    func resetAll() {
        overrides.removeAll()
        disabled.removeAll()
        save()
    }

    var usesDefaults: Bool {
        overrides.isEmpty && disabled.isEmpty
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        overrides = payload.overrides
        disabled = Set(payload.disabled)
    }

    private func save() {
        let payload = Payload(overrides: overrides, disabled: Array(disabled))
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

enum ReadingPreferences {
    static let fontSizeKey = "Lume.previewFontSize"
    static let contentWidthKey = "Lume.previewContentWidth"
    static let defaultFontSize: Double = 14
    static let defaultContentWidth: Double = 740
}
