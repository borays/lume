import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: Binding(
                get: { store.sidebarSelection },
                set: { value in
                    store.sidebarSelection = value
                    DispatchQueue.main.async { store.selectFirstInScope() }
                }
            )) {
                Section("知识库") {
                    Label("全部笔记", systemImage: "tray.full")
                        .badge(store.notes.count)
                        .tag(SidebarSelection.all)
                        .simultaneousGesture(TapGesture().onEnded {
                            store.sidebarSelection = .all
                            DispatchQueue.main.async { store.selectFirstInScope() }
                        })
                        .contextMenu {
                            Button("新建笔记…") { store.activeSheet = .newNote(folder: nil) }
                            Button("新建文件夹…") { store.activeSheet = .newFolder(parent: "") }
                            Divider()
                            Button("重新扫描知识库") { store.reload() }
                        }

                    OutlineGroup(store.folderTree.children, children: \.optionalChildren) { node in
                        FolderRow(node: node)
                            .tag(SidebarSelection.folder(node.path))
                            .contextMenu { folderMenu(node) }
                    }
                }

                Section("标签") {
                    ForEach(visibleTags) { tag in
                        TagRow(tag: tag)
                            .tag(SidebarSelection.tag(tag.name))
                            .contextMenu { tagMenu(tag) }
                    }
                    if store.tags.count > visibleTags.count {
                        Button {
                            store.activeSheet = .allTags
                        } label: {
                            Text("全部 \(store.tags.count) 个标签…")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        openSettings()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("设置…", systemImage: "gearshape")
                            Text(store.rootURL.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .contextMenu { backgroundMenu }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("知识库")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(store.notes.count) 篇笔记 · \(store.folderTree.children.count) 个分类")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                store.activeSheet = .quickOpen
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("快速打开（⌘P）")

            Button {
                store.activeSheet = .newNote(folder: store.defaultNewNoteFolder)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("新建笔记（⌘N）")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func folderMenu(_ node: FolderNode) -> some View {
        Button("在此目录新建笔记…") {
            store.activeSheet = .newNote(folder: node.path)
        }
        Button("新建子文件夹…") {
            store.activeSheet = .newFolder(parent: node.path)
        }
        Divider()
        Button("重命名…") {
            store.activeSheet = .renameFolder(path: node.path)
        }
        Button("移到废纸篓…", role: .destructive) {
            store.requestTrashFolder(node)
        }
        Divider()
        Button("在 Finder 中打开") {
            store.revealFolder(node.path)
        }
        Button("复制目录路径") {
            store.copyFolderPath(node.path)
        }
        Divider()
        Button("按此目录筛选") {
            store.sidebarSelection = .folder(node.path)
            store.searchText = ""
        }
    }

    @ViewBuilder
    private func tagMenu(_ tag: TagCount) -> some View {
        Button("筛选此标签") {
            store.sidebarSelection = .tag(tag.name)
            store.searchText = ""
        }
        Button("在全部笔记中搜索") {
            store.sidebarSelection = .all
            store.searchText = tag.name
        }
        Divider()
        Button("复制标签") {
            store.copyToPasteboard("#\(tag.name)", message: "已复制标签 #\(tag.name)")
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
        Button("在 Finder 中显示知识库") {
            store.revealLibrary()
        }
    }

    private var visibleTags: [TagCount] {
        var result = Array(store.tags.prefix(22))
        if case .tag(let name)? = store.sidebarSelection,
           !result.contains(where: { $0.name == name }),
           let extra = store.tags.first(where: { $0.name == name }) {
            result.insert(extra, at: 0)
        }
        return result
    }
}
