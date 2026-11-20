import Foundation
import UniformTypeIdentifiers

enum ImageInsertError: LocalizedError {
    case unsupported(String)
    case missingNote

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext):
            return "不支持的图片格式：\(ext)"
        case .missingNote:
            return "请先打开一篇笔记"
        }
    }
}

enum ImageInserter {
    static let allowedTypes: [UTType] = {
        var types: [UTType] = [.png, .jpeg, .gif, .tiff, .heic, .svg]
        if let webp = UTType(filenameExtension: "webp") { types.append(webp) }
        return types
    }()

    static func importImage(from source: URL, noteFolder: String, root: URL) throws -> String {
        let ext = source.pathExtension.lowercased()
        let allowed = Set(["png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "heif", "svg", "webp"])
        guard allowed.contains(ext) else {
            throw ImageInsertError.unsupported(ext)
        }
        let paths = LibraryPaths(root: root)
        let assetsURL = try paths.resolve(relative: "assets")
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let rawBase = source.deletingPathExtension().lastPathComponent
        var base = rawBase
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if base.isEmpty { base = "image" }
        if base.count > 40 { base = String(base.prefix(40)) }

        var name = "\(stamp)-\(base).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: assetsURL.appendingPathComponent(name).path) {
            name = "\(stamp)-\(base)-\(counter).\(ext)"
            counter += 1
        }
        let destination = assetsURL.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)

        let depth = noteFolder.split(separator: "/").count
        let prefix = String(repeating: "../", count: depth)
        let alt = base.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        return "![\(alt)](\(prefix)assets/\(name))"
    }
}

enum AttachmentInserter {
    /// 把任意文件复制到知识库 assets 目录，返回可直接插入的 Markdown 链接。
    static func copy(from source: URL, noteFolder: String, root: URL) throws -> String {
        let paths = LibraryPaths(root: root)
        let assetsURL = try paths.resolve(relative: "assets")
        try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let ext = source.pathExtension
        let rawBase = source.deletingPathExtension().lastPathComponent
        var base = rawBase
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if base.isEmpty { base = "attachment" }
        if base.count > 40 { base = String(base.prefix(40)) }

        var name = ext.isEmpty ? "\(stamp)-\(base)" : "\(stamp)-\(base).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: assetsURL.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(stamp)-\(base)-\(counter)" : "\(stamp)-\(base)-\(counter).\(ext)"
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: assetsURL.appendingPathComponent(name))

        let depth = noteFolder.split(separator: "/").count
        let prefix = String(repeating: "../", count: depth)
        let label = (rawBase.isEmpty ? name : rawBase)
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        return "[\(label)](\(prefix)assets/\(name))"
    }
}
