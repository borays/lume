import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var store: LibraryStore
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建笔记…") {
                store.activeSheet = .newNote(folder: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("新建到当前目录…") {
                store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("新建文件夹…") {
                store.activeSheet = .newFolder(parent: store.defaultNewNoteFolder)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("导入网页…") {
                store.activeSheet = .importWeb
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                store.saveIfNeeded(force: true, manual: true)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(store.selectedNoteID == nil)

            Divider()

            Button("导出 PDF…") {
                store.exportCurrentPDF()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(store.selectedNoteID == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("快速打开…") {
                store.activeSheet = .quickOpen
            }
            .keyboardShortcut("p", modifiers: .command)
        }

        CommandGroup(after: .textEditing) {
            Button("查找…") {
                EditorBridge.shared.showFind()
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("笔记") {
            Button("重命名…") {
                if let id = store.selectedNoteID {
                    store.activeSheet = .rename(noteID: id)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.selectedNoteID == nil)

            Button("移动到…") {
                if let id = store.selectedNoteID {
                    store.activeSheet = .move(noteID: id)
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(store.selectedNoteID == nil)

            Button("编辑标签…") {
                if let id = store.selectedNoteID {
                    store.activeSheet = .tags(noteID: id)
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(store.selectedNoteID == nil)

            Button("创建副本") {
                if let id = store.selectedNoteID {
                    _ = store.duplicateNote(id: id)
                }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(store.selectedNoteID == nil)

            Divider()

            Button("在 Finder 中显示") {
                if let note = store.selectedNote {
                    store.revealInFinder(note)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(store.selectedNoteID == nil)

            Button("移到废纸篓…") {
                if let note = store.selectedNote {
                    store.requestTrash(note)
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(store.selectedNoteID == nil)
        }

        CommandMenu("格式") {
            Button("加粗") { EditorBridge.shared.toggleWrap("**") }
                .keyboardShortcut("b", modifiers: .command)
            Button("斜体") { EditorBridge.shared.toggleWrap("*") }
                .keyboardShortcut("i", modifiers: .command)
            Button("删除线") { EditorBridge.shared.toggleStrike() }
            Button("高亮") { EditorBridge.shared.toggleHighlight() }
            Button("行内代码") { EditorBridge.shared.toggleWrap("`") }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("代码块") { EditorBridge.shared.toggleCodeBlock() }
            Button("行内公式") { EditorBridge.shared.toggleInlineMath() }
            Button("块级公式") { EditorBridge.shared.insertBlockMath() }
            Button("脚注") { EditorBridge.shared.insertFootnote() }
            Menu("GitHub 告警") {
                Button("Note 提示") { EditorBridge.shared.insertAlert(kind: "NOTE") }
                Button("Tip 技巧") { EditorBridge.shared.insertAlert(kind: "TIP") }
                Button("Important 重点") { EditorBridge.shared.insertAlert(kind: "IMPORTANT") }
                Button("Warning 警告") { EditorBridge.shared.insertAlert(kind: "WARNING") }
                Button("Caution 注意") { EditorBridge.shared.insertAlert(kind: "CAUTION") }
            }
            Menu("插入图表") {
                ForEach(EditorBridge.diagramTemplates, id: \.title) { item in
                    Button(item.title) { EditorBridge.shared.insertDiagram(item.code) }
                }
            }
            Button("链接…") { EditorBridge.shared.insertLink() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("一级标题") { EditorBridge.shared.setHeading(level: 1) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("二级标题") { EditorBridge.shared.setHeading(level: 2) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("三级标题") { EditorBridge.shared.setHeading(level: 3) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("正文") { EditorBridge.shared.setHeading(level: 0) }
            Divider()
            Button("无序列表") { EditorBridge.shared.applyList(ordered: false) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("有序列表") { EditorBridge.shared.applyList(ordered: true) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("任务列表") { EditorBridge.shared.applyTaskList() }
            Button("引用") { EditorBridge.shared.applyQuote() }
            Divider()
            Button("插入表格") { EditorBridge.shared.insertTable() }
            Button("插入分隔线") { EditorBridge.shared.insertDivider() }
            Divider()
            Button("插入图片…") { EditorBridge.shared.insertImage() }
                .keyboardShortcut("i", modifiers: [.control, .command])
            Button("插入附件…") { EditorBridge.shared.insertAttachment() }
            Button("插入当前日期") { EditorBridge.shared.insertDate() }
                .keyboardShortcut("d", modifiers: [.option, .command])
        }

        CommandMenu("视图") {
            Button("仅编辑") { store.editorMode = .editor }
                .keyboardShortcut("1", modifiers: [.control, .command])
            Button("分栏") { store.editorMode = .split }
                .keyboardShortcut("2", modifiers: [.control, .command])
            Button("仅预览") { store.editorMode = .preview }
                .keyboardShortcut("3", modifiers: [.control, .command])
            Divider()
            Button("切换深浅色外观") { ThemeManager.shared.toggle() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Picker("外观", selection: Binding(
                get: { ThemeManager.shared.mode },
                set: { ThemeManager.shared.mode = $0 }
            )) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Divider()
            Button("重新扫描知识库") { store.reload() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("知识库设置…") { openSettings() }
        }
    }
}
