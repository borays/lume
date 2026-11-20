import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var store: LibraryStore
    @ObservedObject var shortcuts: ShortcutStore
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            keyed(.newNote) {
                Button("新建笔记…") {
                    store.activeSheet = .newNote(folder: nil)
                }
            }

            keyed(.newNoteInFolder) {
                Button("新建到当前目录…") {
                    store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
                }
            }

            keyed(.newFolder) {
                Button("新建文件夹…") {
                    store.activeSheet = .newFolder(parent: store.defaultNewNoteFolder)
                }
            }

            keyed(.importWeb) {
                Button("导入网页…") {
                    store.activeSheet = .importWeb
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            keyed(.save) {
                Button("保存") {
                    store.saveIfNeeded(force: true, manual: true)
                }
                .disabled(store.selectedNoteID == nil)
            }

            Divider()

            keyed(.exportPDF) {
                Button("导出 PDF…") {
                    store.exportCurrentPDF()
                }
                .disabled(store.selectedNoteID == nil)
            }
        }

        CommandGroup(replacing: .printItem) {
            keyed(.quickOpen) {
                Button("快速打开…") {
                    store.activeSheet = .quickOpen
                }
            }
        }

        CommandGroup(after: .textEditing) {
            keyed(.find) {
                Button("查找…") {
                    EditorBridge.shared.showFind()
                }
            }
        }

        CommandMenu("笔记") {
            keyed(.renameNote) {
                Button("重命名…") {
                    if let id = store.selectedNoteID {
                        store.activeSheet = .rename(noteID: id)
                    }
                }
                .disabled(store.selectedNoteID == nil)
            }

            keyed(.moveNote) {
                Button("移动到…") {
                    if let id = store.selectedNoteID {
                        store.activeSheet = .move(noteID: id)
                    }
                }
                .disabled(store.selectedNoteID == nil)
            }

            keyed(.editTags) {
                Button("编辑标签…") {
                    if let id = store.selectedNoteID {
                        store.activeSheet = .tags(noteID: id)
                    }
                }
                .disabled(store.selectedNoteID == nil)
            }

            keyed(.duplicateNote) {
                Button("创建副本") {
                    if let id = store.selectedNoteID {
                        _ = store.duplicateNote(id: id)
                    }
                }
                .disabled(store.selectedNoteID == nil)
            }

            Divider()

            keyed(.revealInFinder) {
                Button("在 Finder 中显示") {
                    if let note = store.selectedNote {
                        store.revealInFinder(note)
                    }
                }
                .disabled(store.selectedNoteID == nil)
            }

            keyed(.moveToTrash) {
                Button("移到废纸篓…") {
                    if let note = store.selectedNote {
                        store.requestTrash(note)
                    }
                }
                .disabled(store.selectedNoteID == nil)
            }
        }

        CommandMenu("格式") {
            keyed(.bold) { Button("加粗") { EditorBridge.shared.toggleWrap("**") } }
            keyed(.italic) { Button("斜体") { EditorBridge.shared.toggleWrap("*") } }
            keyed(.strikethrough) { Button("删除线") { EditorBridge.shared.toggleStrike() } }
            keyed(.highlight) { Button("高亮") { EditorBridge.shared.toggleHighlight() } }
            keyed(.inlineCode) { Button("行内代码") { EditorBridge.shared.toggleWrap("`") } }
            keyed(.codeBlock) { Button("代码块") { EditorBridge.shared.toggleCodeBlock() } }
            keyed(.inlineMath) { Button("行内公式") { EditorBridge.shared.toggleInlineMath() } }
            keyed(.blockMath) { Button("块级公式") { EditorBridge.shared.insertBlockMath() } }
            keyed(.footnote) { Button("脚注") { EditorBridge.shared.insertFootnote() } }
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
            keyed(.link) { Button("链接…") { EditorBridge.shared.insertLink() } }
            Divider()
            keyed(.heading1) { Button("一级标题") { EditorBridge.shared.setHeading(level: 1) } }
            keyed(.heading2) { Button("二级标题") { EditorBridge.shared.setHeading(level: 2) } }
            keyed(.heading3) { Button("三级标题") { EditorBridge.shared.setHeading(level: 3) } }
            keyed(.heading4) { Button("四级标题") { EditorBridge.shared.setHeading(level: 4) } }
            keyed(.heading5) { Button("五级标题") { EditorBridge.shared.setHeading(level: 5) } }
            keyed(.heading6) { Button("六级标题") { EditorBridge.shared.setHeading(level: 6) } }
            keyed(.bodyText) { Button("正文") { EditorBridge.shared.setHeading(level: 0) } }
            Divider()
            keyed(.bulletList) { Button("无序列表") { EditorBridge.shared.applyList(ordered: false) } }
            keyed(.numberedList) { Button("有序列表") { EditorBridge.shared.applyList(ordered: true) } }
            keyed(.taskList) { Button("任务列表") { EditorBridge.shared.applyTaskList() } }
            keyed(.quote) { Button("引用") { EditorBridge.shared.applyQuote() } }
            Divider()
            keyed(.table) { Button("插入表格") { EditorBridge.shared.insertTable() } }
            keyed(.divider) { Button("插入分隔线") { EditorBridge.shared.insertDivider() } }
            Divider()
            keyed(.image) { Button("插入图片…") { EditorBridge.shared.insertImage() } }
            keyed(.attachment) { Button("插入附件…") { EditorBridge.shared.insertAttachment() } }
            keyed(.date) { Button("插入当前日期") { EditorBridge.shared.insertDate() } }
        }

        CommandMenu("视图") {
            keyed(.modeEditor) { Button("仅编辑") { store.editorMode = .editor } }
            keyed(.modeSplit) { Button("分栏") { store.editorMode = .split } }
            keyed(.modePreview) { Button("仅预览") { store.editorMode = .preview } }
            Divider()
            keyed(.toggleAppearance) { Button("切换深浅色外观") { ThemeManager.shared.toggle() } }
            Picker("外观", selection: Binding(
                get: { ThemeManager.shared.mode },
                set: { ThemeManager.shared.mode = $0 }
            )) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Divider()
            keyed(.rescanLibrary) { Button("重新扫描知识库") { store.reload() } }
            Divider()
            Button("知识库设置…") { openSettings() }
        }
    }

    /// 菜单项的组合键来自用户可配置注册表，未分配时保持无快捷键。
    @ViewBuilder
    private func keyed<Content: View>(
        _ id: AppCommandID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let item = content()
        if let shortcut = shortcuts.shortcut(for: id), let key = shortcut.keyEquivalent {
            item.keyboardShortcut(key, modifiers: shortcut.eventModifiers)
        } else {
            item
        }
    }
}
