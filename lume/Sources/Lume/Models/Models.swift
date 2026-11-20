import Foundation

struct Note: Identifiable, Hashable {
    let id: String
    let url: URL
    var relPath: String
    var folderPath: String
    var title: String
    var date: Date?
    var tags: [String]
    var modified: Date
    var size: Int
    var excerpt: String
    var body: String

    var displayFolder: String {
        folderPath.isEmpty ? "根目录" : folderPath
    }

    var fileURL: URL { url }

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct FolderNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    var children: [FolderNode]
    var directCount: Int
    var totalCount: Int

    var optionalChildren: [FolderNode]? {
        children.isEmpty ? nil : children
    }

    static let root = FolderNode(id: "", name: "知识库", path: "", children: [], directCount: 0, totalCount: 0)
}

struct TagCount: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let count: Int
}

struct ScanResult {
    let root: URL
    let notes: [Note]
    let folderTree: FolderNode
    let tags: [TagCount]
    let scannedAt: Date
}

enum SidebarSelection: Hashable {
    case all
    case folder(String)
    case tag(String)
}

enum EditorMode: String, CaseIterable, Identifiable {
    case editor
    case split
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor: return "编辑"
        case .split: return "分栏"
        case .preview: return "预览"
        }
    }

    var symbol: String {
        switch self {
        case .editor: return "square.and.pencil"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }

    var shortcutHint: String {
        switch self {
        case .editor: return "⌃⌘1"
        case .split: return "⌃⌘2"
        case .preview: return "⌃⌘3"
        }
    }
}

enum NoteSortOrder: String, CaseIterable, Identifiable {
    case title
    case modified
    case modifiedAscending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "按标题"
        case .modified: return "最近修改"
        case .modifiedAscending: return "最早修改"
        }
    }
}

enum SaveState: Equatable {
    case idle
    case dirty
    case saving
    case saved(Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "已保存"
        case .dirty: return "未保存"
        case .saving: return "保存中…"
        case .saved: return "已自动保存"
        case .failed(let message): return message
        }
    }

    var symbol: String {
        switch self {
        case .idle, .saved: return "checkmark.circle"
        case .dirty: return "circle.fill"
        case .saving: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

struct ConflictState: Identifiable {
    let id = UUID()
    let noteID: String
    let diskContent: String
}

enum ActiveSheet: Identifiable {
    case newNote(folder: String?)
    case importWeb
    case newFolder(parent: String)
    case renameFolder(path: String)
    case quickOpen
    case rename(noteID: String)
    case move(noteID: String)
    case tags(noteID: String)
    case allTags

    var id: String {
        switch self {
        case .newNote: return "new"
        case .importWeb: return "importWeb"
        case .newFolder(let parent): return "newFolder-\(parent)"
        case .renameFolder(let path): return "renameFolder-\(path)"
        case .quickOpen: return "quick"
        case .rename(let id): return "rename-\(id)"
        case .move(let id): return "move-\(id)"
        case .tags(let id): return "tags-\(id)"
        case .allTags: return "allTags"
        }
    }
}

struct FolderOption: Identifiable, Hashable {
    let path: String
    let name: String
    let depth: Int

    var id: String { path }
    var indent: String { String(repeating: "　", count: max(0, depth - 1)) }
}
