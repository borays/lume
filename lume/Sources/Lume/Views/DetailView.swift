import SwiftUI

struct DetailView: View {
    @EnvironmentObject var store: LibraryStore
    @ObservedObject private var bridge = EditorBridge.shared

    var body: some View {
        Group {
            if let note = store.selectedNote {
                editorLayout(note: note)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func editorLayout(note: Note) -> some View {
        VStack(spacing: 0) {
            if store.conflict != nil {
                conflictBanner
            }
            header(note: note)
            Divider()
            if store.editorMode != .preview {
                EditorFormatBar()
                Divider()
            }
            content(note: note)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
    }

    private func header(note: Note) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            breadcrumb(note)

            TextField("标题", text: $store.titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .bold))
                .onSubmit { store.commitTitle() }
                .help("修改标题会同步 frontmatter 与一级标题，按回车保存")

            HStack(spacing: 12) {
                if let date = note.date {
                    Label(DateDisplay.full(date), systemImage: "calendar")
                }
                Label(DateDisplay.compact(note.modified), systemImage: "clock")
                    .help("最近修改")
                Text("\(store.draft.count) 字符")
                    .monospacedDigit()
                Spacer(minLength: 4)
                Button {
                    store.activeSheet = .tags(noteID: note.id)
                } label: {
                    Label("标签", systemImage: "tag")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("编辑标签（⇧⌘T）")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if !note.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(note.tags.prefix(8)), id: \.self) { tag in
                            TagChip(tag: tag) {
                                store.sidebarSelection = .tag(tag)
                                store.searchText = ""
                            }
                        }
                        if note.tags.count > 8 {
                            Text("+\(note.tags.count - 8)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func breadcrumb(_ note: Note) -> some View {
        let segments = breadcrumbSegments(for: note)
        HStack(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { entry in
                Button {
                    store.sidebarSelection = entry.element.path.isEmpty ? .all : .folder(entry.element.path)
                    store.searchText = ""
                } label: {
                    Text(entry.element.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("筛选此目录")

                if entry.offset < segments.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
            }
        }
    }

    private func breadcrumbSegments(for note: Note) -> [(title: String, path: String)] {
        guard !note.folderPath.isEmpty else { return [("知识库", "")] }
        var result: [(title: String, path: String)] = []
        var accumulated: [String] = []
        for part in note.folderPath.split(separator: "/") {
            accumulated.append(String(part))
            result.append((title: String(part), path: accumulated.joined(separator: "/")))
        }
        return result
    }

    @ViewBuilder
    private func content(note: Note) -> some View {
        switch store.editorMode {
        case .editor:
            editor
        case .preview:
            preview
        case .split:
            HSplitView {
                editor
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                preview
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: Binding(
                get: { store.draft },
                set: { store.draft = $0 }
            ),
            onChange: { store.updateDraft($0) }
        )
    }

    private var preview: some View {
        ZStack {
            MarkdownPreview(
                markdown: store.previewMarkdown,
                baseURL: store.currentFolderURL,
                title: store.titleDraft,
                fontFamily: bridge.fontFamily
            )
            if previewIsEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("这篇笔记还没有内容")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("开始编辑") {
                        store.editorMode = .editor
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var previewIsEmpty: Bool {
        MarkdownRenderer.bodyWithoutTitleHeading(store.previewMarkdown, title: store.titleDraft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var conflictBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("文件已在外部修改")
                    .font(.system(size: 12, weight: .semibold))
                Text("磁盘内容与你的未保存修改不一致，请选择处理方式。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("重新加载磁盘版本") { store.resolveConflictUsingDisk() }
                .controlSize(.small)
            Button("保留我的修改") { store.resolveConflictKeepingMine() }
                .controlSize(.small)
            Button("另存为副本") { store.resolveConflictSavingCopy() }
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            SaveStatusView(state: store.saveState)
            Text("·").foregroundStyle(.tertiary)
            Text("\(store.draft.count) 字符")
                .monospacedDigit()
            Text("·").foregroundStyle(.tertiary)
            Text("\(lineCount) 行")
                .monospacedDigit()
            Spacer()
            if store.isScanning {
                ProgressView()
                    .controlSize(.mini)
                Text("索引中…")
            }
            Text("Markdown · UTF-8")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private var lineCount: Int {
        store.draft.isEmpty ? 0 : store.draft.components(separatedBy: "\n").count
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("没有打开笔记", systemImage: "note.text")
        } description: {
            Text("从左侧选择一篇笔记，或新建一篇开始记录。")
        } actions: {
            HStack(spacing: 10) {
                Button("新建笔记") {
                    store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
                }
                .buttonStyle(.borderedProminent)
                Button("快速打开…") {
                    store.activeSheet = .quickOpen
                }
            }
        }
    }
}
