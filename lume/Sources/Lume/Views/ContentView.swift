import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @ObservedObject private var theme = ThemeManager.shared

    @State private var saveAnimating = false
    @State private var saveAnimationID = 0

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } content: {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 336, max: 460)
        } detail: {
            DetailView()
                .navigationSplitViewColumnWidth(min: 420, ideal: 700)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1040, minHeight: 660)
        .toolbar { toolbar }
        .sheet(item: $store.activeSheet) { sheet in
            sheetContent(sheet)
                .environmentObject(store)
        }
        .confirmationDialog(
            "移到废纸篓？",
            isPresented: Binding(
                get: { store.pendingTrashNote != nil },
                set: { if !$0 { store.pendingTrashNote = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) { store.confirmTrash() }
            Button("取消", role: .cancel) { store.pendingTrashNote = nil }
        } message: {
            Text("“\(store.pendingTrashNote?.title ?? "")” 将移到系统废纸篓，可从废纸篓恢复。")
        }
        .confirmationDialog(
            "移到废纸篓？",
            isPresented: Binding(
                get: { store.pendingTrashFolder != nil },
                set: { if !$0 { store.pendingTrashFolder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) { store.confirmTrashFolder() }
            Button("取消", role: .cancel) { store.pendingTrashFolder = nil }
        } message: {
            Text("“\(store.pendingTrashFolder?.name ?? "")” 及其中的 \(pendingFolderNoteCount) 篇笔记将移到系统废纸篓，可从废纸篓恢复。")
        }
        .alert(
            "出错了",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) { toast }
        .animation(.easeInOut(duration: 0.18), value: store.infoMessage)
        .onReceive(NotificationCenter.default.publisher(for: .mynoteOpenLink)) { notification in
            if let url = notification.object as? URL {
                store.openLink(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumeCodeCopied)) { _ in
            store.infoMessage = "代码已复制到剪贴板"
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumeToggleTask)) { notification in
            if let index = notification.object as? Int {
                store.toggleTask(at: index)
            }
        }
        .onChange(of: store.savePulse) { _, _ in
            startSaveAnimation()
        }
        .onAppear {
            EditorBridge.shared.store = store
        }
        .task {
            store.bootstrap()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
            } label: {
                toolbarIcon("plus")
            }
            .buttonStyle(.plain)
            .help("新建笔记（⌘N）")

            Button {
                store.activeSheet = .importWeb
            } label: {
                toolbarIcon("square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .help("导入网页…（⇧⌘I）")

            HStack(spacing: 2) {
                ForEach(EditorMode.allCases) { mode in
                    Button {
                        store.editorMode = mode
                    } label: {
                        toolbarIcon(mode.symbol, active: store.editorMode == mode)
                    }
                    .buttonStyle(.plain)
                    .help("\(mode.title)（\(mode.shortcutHint)）")
                }
            }

            Button {
                ThemeManager.shared.toggle()
            } label: {
                toolbarIcon(theme.toggleIcon)
            }
            .buttonStyle(.plain)
            .help("切换深浅色外观（⌘⇧A）")

            if store.selectedNote != nil {
                Button {
                    store.saveIfNeeded(force: true, manual: true)
                } label: {
                    if saveAnimating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 26, height: 22)
                    } else {
                        toolbarIcon("internaldrive")
                            .overlay(alignment: .topTrailing) {
                                if store.saveState == .dirty {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 5, height: 5)
                                        .offset(x: -3, y: 4)
                                }
                            }
                    }
                }
                .buttonStyle(.plain)
                .help(store.saveState == .dirty ? "有未保存的修改，点击立即保存（⌘S）" : "保存到磁盘（⌘S）")
                .accessibilityLabel(saveAnimating ? "正在保存" : "保存")
            }

            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26, height: 22)
            }

            if let note = store.selectedNote {
                NoteActionMenu(note: note)
            }
        }
    }

    private func toolbarIcon(_ name: String, active: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 13.5, weight: .medium))
            .frame(width: 26, height: 22)
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func startSaveAnimation() {
        saveAnimationID += 1
        let id = saveAnimationID
        saveAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard id == saveAnimationID else { return }
            saveAnimating = false
        }
    }

    private var pendingFolderNoteCount: Int {
        guard let path = store.pendingTrashFolder?.path else { return 0 }
        return store.notes.filter { $0.folderPath == path || $0.folderPath.hasPrefix(path + "/") }.count
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .newNote(let folder):
            NewNoteSheet(initialFolder: folder ?? store.defaultNewNoteFolder)
        case .importWeb:
            WebImportSheet()
        case .newFolder(let parent):
            NewFolderSheet(parent: parent)
        case .renameFolder(let path):
            RenameFolderSheet(path: path)
        case .quickOpen:
            QuickOpenSheet()
        case .rename(let id):
            RenameSheet(noteID: id)
        case .move(let id):
            MoveSheet(noteID: id)
        case .tags(let id):
            TagsSheet(noteID: id)
        case .allTags:
            AllTagsSheet()
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let info = store.infoMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(info)
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: info) {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                if store.infoMessage == info {
                    store.infoMessage = nil
                }
            }
        }
    }
}
