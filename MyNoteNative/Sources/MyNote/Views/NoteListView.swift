import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var store: LibraryStore
    @FocusState private var searchFocused: Bool
    @State private var scopeScrollToken = 0
    @State private var lastScopeChange = Date.distantPast

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.searchScopeTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                Menu {
                    Picker("排序方式", selection: $store.sortOrder) {
                        ForEach(NoteSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("排序方式")

                Button {
                    store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(Color.accentColor.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("在当前目录新建笔记（⌘N）")
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索标题、正文、标签", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        if !store.searchText.isEmpty {
            return "在「\(store.searchScopeTitle)」中找到 \(store.filteredNotes.count) 条"
        }
        return "共 \(store.filteredNotes.count) 篇笔记"
    }

    @ViewBuilder
    private var content: some View {
        if store.filteredNotes.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: store.notes.isEmpty ? "tray" : "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(store.notes.isEmpty ? "知识库为空" : "没有匹配的笔记")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if store.searchText.isEmpty {
                    Button("新建笔记") {
                        store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("清除搜索") {
                        store.searchText = ""
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu { backgroundMenu }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.filteredNotes) { note in
                            NoteListRow(note: note)
                                .id(note.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .background(NoteListKeyCatcher(onKey: handleKey))
                .contextMenu { backgroundMenu }
                .onAppear {
                    scrollToSelection(proxy)
                }
                .onChange(of: store.selectedNoteID) { _, _ in
                    scrollToSelection(proxy)
                }
                .onChange(of: store.sidebarSelection) { _, _ in
                    lastScopeChange = Date()
                    scopeScrollToken += 1
                    let token = scopeScrollToken
                    DispatchQueue.main.async {
                        let previous = store.selectedNoteID
                        store.selectFirstInScope()
                        guard store.selectedNoteID == previous else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            guard token == scopeScrollToken, let id = store.selectedNoteID else { return }
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
                .onChange(of: store.filteredNotes.count) { _, _ in
                    guard Date().timeIntervalSince(lastScopeChange) > 0.4 else { return }
                    scrollToSelection(proxy)
                }
                .onChange(of: store.editorMode) { _, _ in
                    scrollToSelection(proxy)
                }
            }
        }
    }

    @ViewBuilder
    private var backgroundMenu: some View {
        Button("新建笔记…") {
            store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
        }
        Button("新建文件夹…") {
            store.activeSheet = .newFolder(parent: "")
        }
        Divider()
        Button("重新扫描知识库") {
            store.reload()
        }
        if !store.searchText.isEmpty {
            Divider()
            Button("清除搜索") {
                store.searchText = ""
            }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        let token = scopeScrollToken
        guard let id = store.selectedNoteID else { return }
        let anchor: UnitPoint = store.filteredNotes.first?.id == id ? .top : .center
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard token == scopeScrollToken else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    private func handleKey(_ key: NoteListKey) {
        let notes = store.filteredNotes
        guard !notes.isEmpty else { return }
        guard let current = store.selectedNoteID,
              let index = notes.firstIndex(where: { $0.id == current }) else {
            store.select(notes.first?.id)
            return
        }
        let pageSize = 10
        let target: Int
        switch key {
        case .up: target = index - 1
        case .down: target = index + 1
        case .pageUp: target = index - pageSize
        case .pageDown: target = index + pageSize
        case .home: target = 0
        case .end: target = notes.count - 1
        }
        store.select(notes[min(max(0, target), notes.count - 1)].id)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(store.filteredNotes.count) 篇")
                .monospacedDigit()
            if store.isScanning {
                ProgressView()
                    .controlSize(.mini)
            }
            Spacer()
            Text("⌘N 新建")
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
