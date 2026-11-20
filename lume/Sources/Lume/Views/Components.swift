import SwiftUI

enum DateDisplay {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func compact(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return dayFormatter.string(from: date)
        }
        return fullFormatter.string(from: date)
    }

    static func full(_ date: Date) -> String {
        fullFormatter.string(from: date)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(DateDisplay.compact(note.modified))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            if !note.excerpt.isEmpty {
                Text(note.excerpt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .lineLimit(2)
            }
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                Text(shortFolder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !note.tags.isEmpty {
                    Text("·").font(.system(size: 9))
                    Text(Array(note.tags.prefix(2)).map { "#\($0)" }.joined(separator: " "))
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var shortFolder: String {
        if note.folderPath.isEmpty { return "根目录" }
        let parts = note.folderPath.split(separator: "/")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: " / ")
        }
        return note.folderPath
    }
}

struct NoteListRow: View {
    @EnvironmentObject private var store: LibraryStore
    let note: Note
    @State private var hovering = false

    private var isSelected: Bool { store.selectedNoteID == note.id }

    var body: some View {
        NoteRow(note: note)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.14)
                          : (hovering ? Color.primary.opacity(0.045) : Color.clear))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                store.select(note.id)
                DispatchQueue.main.async { NoteListKeyFocus.shared.focus() }
            }
            .contextMenu { NoteContextMenu(note: note) }
    }
}

struct FolderRow: View {
    let node: FolderNode

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: node.children.isEmpty ? "folder" : "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(node.totalCount)")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

struct TagRow: View {
    let tag: TagCount

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "number")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(tag.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(tag.count)")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

struct TagChip: View {
    let tag: String
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .help("筛选标签 \(tag)")
        } else {
            label
        }
    }

    private var label: some View {
        Text("#\(tag)")
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.accentColor.opacity(0.11)))
            .foregroundStyle(Color.accentColor)
    }
}

struct NoteContextMenu: View {
    @EnvironmentObject var store: LibraryStore
    let note: Note

    var body: some View {
        Button("打开") { store.select(note.id) }
        Divider()
        Button("重命名…") { store.activeSheet = .rename(noteID: note.id) }
        Button("移动到…") { store.activeSheet = .move(noteID: note.id) }
        Button("编辑标签…") { store.activeSheet = .tags(noteID: note.id) }
        Button("创建副本") { _ = store.duplicateNote(id: note.id) }
        Divider()
        Button("复制文件路径") { store.copyNotePath(note) }
        Button("复制 Markdown 链接") { store.copyNoteLink(note) }
        Divider()
        Button("导出 PDF…") {
            if store.selectedNoteID != note.id {
                store.select(note.id)
            }
            store.exportCurrentPDF()
        }
        Button("在 Finder 中显示") { store.revealInFinder(note) }
        Divider()
        Button("移到废纸篓…", role: .destructive) { store.requestTrash(note) }
    }
}

struct NoteActionMenu: View {
    @EnvironmentObject var store: LibraryStore
    let note: Note

    var body: some View {
        Menu {
            Button("重命名…") { store.activeSheet = .rename(noteID: note.id) }
            Button("移动到…") { store.activeSheet = .move(noteID: note.id) }
            Button("编辑标签…") { store.activeSheet = .tags(noteID: note.id) }
            Divider()
            Button("创建副本") { _ = store.duplicateNote(id: note.id) }
            Button("导出 PDF…") { store.exportCurrentPDF() }
            Button("在 Finder 中显示") { store.revealInFinder(note) }
            Divider()
            Button("移到废纸篓…", role: .destructive) { store.requestTrash(note) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13.5, weight: .medium))
                .frame(width: 26, height: 22)
                .foregroundStyle(Color.primary)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("笔记操作")
    }
}

struct SaveStatusView: View {
    let state: SaveState

    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.system(size: 11))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .failed:
            return .red
        case .dirty:
            return .orange
        case .saving:
            return .secondary
        case .idle, .saved:
            return .secondary
        }
    }
}

enum NoteListKey {
    case up, down, pageUp, pageDown, home, end
}

final class NoteListKeyView: NSView {
    var onKey: ((NoteListKey) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let handled: NoteListKey?
        switch event.specialKey {
        case .upArrow: handled = .up
        case .downArrow: handled = .down
        case .pageUp: handled = .pageUp
        case .pageDown: handled = .pageDown
        case .home: handled = .home
        case .end: handled = .end
        default: handled = nil
        }
        if let handled {
            onKey?(handled)
        } else {
            super.keyDown(with: event)
        }
    }
}

final class NoteListKeyFocus {
    static let shared = NoteListKeyFocus()
    weak var view: NoteListKeyView?

    func focus() {
        guard let view, let window = view.window else { return }
        window.makeFirstResponder(view)
    }
}

struct NoteListKeyCatcher: NSViewRepresentable {
    let onKey: (NoteListKey) -> Void

    func makeNSView(context: Context) -> NoteListKeyView {
        let view = NoteListKeyView()
        view.onKey = onKey
        NoteListKeyFocus.shared.view = view
        return view
    }

    func updateNSView(_ nsView: NoteListKeyView, context: Context) {
        nsView.onKey = onKey
        NoteListKeyFocus.shared.view = nsView
    }
}
