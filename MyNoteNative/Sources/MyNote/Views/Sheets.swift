import AppKit
import SwiftUI

struct NewNoteSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let initialFolder: String

    @State private var title = ""
    @State private var folder = ""
    @State private var tagsText = ""
    @FocusState private var titleFocused: Bool

    init(initialFolder: String) {
        self.initialFolder = initialFolder
        _folder = State(initialValue: initialFolder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("新建笔记")
                    .font(.system(size: 20, weight: .semibold))
                Text("保存为 Markdown 文件，自动写入 frontmatter 与一级标题。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 13) {
                field("标题") {
                    TextField("例如：Ceph OSD 故障处理", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))
                        .controlSize(.large)
                        .focused($titleFocused)
                }
                field("保存目录") {
                    Picker("", selection: $folder) {
                        ForEach(store.folderOptions) { option in
                            Text(option.indent + option.name).tag(option.path)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                field("标签（可选）") {
                    TextField("用逗号分隔，例如：Ceph, 故障处理", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                }
                if !parsedTags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(parsedTags, id: \.self) { tag in
                            TagChip(tag: tag)
                        }
                    }
                }
            }

            HStack {
                Text(folder == "00-收件箱" ? "00-收件箱不存在时会自动创建" : folder)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { titleFocused = true }
    }

    private var parsedTags: [String] {
        tagsText.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func create() {
        if store.createNote(title: title, folder: folder, tags: parsedTags) {
            dismiss()
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

struct NewFolderSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let parent: String

    @State private var folderName = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("新建文件夹")
                    .font(.system(size: 20, weight: .semibold))
                Text(parent.isEmpty ? "位于知识库根目录" : "位于 \(parent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            TextField("文件夹名称", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .controlSize(.large)
                .focused($focused)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { focused = true }
    }

    private func create() {
        if store.createFolder(parent: parent, name: folderName) {
            dismiss()
        }
    }
}

struct RenameFolderSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let path: String

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("重命名文件夹")
                    .font(.system(size: 18, weight: .semibold))
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TextField("文件夹名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            Text("会同步重命名知识库中的真实目录，目录内笔记的路径随之更新。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("重命名") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            name = path.components(separatedBy: "/").last ?? path
            focused = true
        }
    }

    private func commit() {
        if store.renameFolder(path: path, to: name) {
            dismiss()
        }
    }
}

struct RenameSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let noteID: String

    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名笔记")
                .font(.system(size: 18, weight: .semibold))
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            Text("会同步更新文件名、frontmatter 标题与正文一级标题。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            title = store.note(id: noteID)?.title ?? ""
            focused = true
        }
    }

    private func commit() {
        if store.renameNote(id: noteID, to: title) {
            dismiss()
        }
    }
}

struct MoveSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let noteID: String

    @State private var folder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("移动笔记")
                .font(.system(size: 18, weight: .semibold))
            Text(store.note(id: noteID)?.title ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Picker("目标目录", selection: $folder) {
                ForEach(store.folderOptions) { option in
                    Text(option.indent + option.name).tag(option.path)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("移动") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(folder.isEmpty || folder == store.note(id: noteID)?.folderPath)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            folder = store.note(id: noteID)?.folderPath ?? store.defaultNewNoteFolder
        }
    }

    private func commit() {
        if store.moveNote(id: noteID, to: folder) {
            dismiss()
        }
    }
}

struct TagsSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let noteID: String

    @State private var tagsText = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑标签")
                .font(.system(size: 18, weight: .semibold))
            Text(store.note(id: noteID)?.title ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            TextField("标签之间用逗号分隔", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            if !parsedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(parsedTags, id: \.self) { tag in
                            TagChip(tag: tag)
                        }
                    }
                }
            }
            Text("标签保存在 notes 的 frontmatter 中，可用于侧边栏筛选。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            tagsText = (store.note(id: noteID)?.tags ?? []).joined(separator: ", ")
            focused = true
        }
    }

    private var parsedTags: [String] {
        tagsText.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func commit() {
        if store.setTags(id: noteID, tags: parsedTags) {
            dismiss()
        }
    }
}

struct AllTagsSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("筛选标签", text: $query)
                    .textFieldStyle(.plain)
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTags) { tag in
                        Button {
                            store.sidebarSelection = .tag(tag.name)
                            store.searchText = ""
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "number")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(tag.name)
                                Spacer()
                                Text("\(tag.count)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .frame(width: 420, height: 520)
    }

    private var filteredTags: [TagCount] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.tags }
        return store.tags.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

struct QuickOpenSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索并打开笔记…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { openFirst() }
                Text("↩ 打开")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            Divider()
            if results.isEmpty {
                VStack(spacing: 6) {
                    Text("没有匹配的笔记")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { note in
                            Button {
                                store.select(note.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(note.title)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .lineLimit(1)
                                        Text(note.folderPath)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(DateDisplay.compact(note.modified))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .frame(width: 580, height: 440)
        .onAppear { focused = true }
    }

    private var results: [Note] {
        store.quickOpenResults(query)
    }

    private func openFirst() {
        if let first = results.first {
            store.select(first.id)
            dismiss()
        }
    }
}
