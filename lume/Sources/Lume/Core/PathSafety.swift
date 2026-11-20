import Foundation

enum PathSafetyError: LocalizedError {
    case invalidPath(String)
    case outsideRoot(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "路径不合法：\(path)"
        case .outsideRoot(let path):
            return "路径超出知识库范围：\(path)"
        }
    }
}

struct LibraryPaths {
    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    var rootReal: URL {
        root.resolvingSymlinksInPath().standardizedFileURL
    }

    func resolve(relative: String, mustExist: Bool = false) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"),
              !relative.hasPrefix("~") else {
            throw PathSafetyError.invalidPath(relative)
        }
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let base = rootReal
        let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        guard isInside(parent, base) else {
            throw PathSafetyError.outsideRoot(relative)
        }
        if mustExist || FileManager.default.fileExists(atPath: candidate.path) {
            let real = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isInside(real, base) else {
                throw PathSafetyError.outsideRoot(relative)
            }
            return real
        }
        return candidate
    }

    func contains(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        let base = rootReal
        return isInside(target, base) || isInside(target.resolvingSymlinksInPath(), base)
    }

    func isInside(_ url: URL, _ base: URL) -> Bool {
        url.path == base.path || url.path.hasPrefix(base.path + "/")
    }

    func relativePath(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        if path == base { return "" }
        if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
        return url.lastPathComponent
    }
}
