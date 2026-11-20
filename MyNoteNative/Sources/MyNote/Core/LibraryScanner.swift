import Foundation

struct LibraryScanner {
    let root: URL
    private let paths: LibraryPaths

    init(root: URL) {
        let standardized = root.standardizedFileURL
        self.root = standardized
        self.paths = LibraryPaths(root: standardized)
    }

    func scan() throws -> ScanResult {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "MyNote", code: 1, userInfo: [NSLocalizedDescriptionKey: "知识库目录不存在：\(root.path)"])
        }

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                         .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw NSError(domain: "MyNote", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法读取知识库目录"])
        }

        var notes: [Note] = []
        var folderPaths: Set<String> = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isDirectory == true {
                if url.lastPathComponent == "assets" {
                    enumerator.skipDescendants()
                    continue
                }
                let rel = paths.relativePath(of: url)
                if !rel.isEmpty {
                    folderPaths.insert(rel)
                }
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            let rel = paths.relativePath(of: url)
            if rel.isEmpty || rel.hasPrefix("assets/") { continue }
            if let note = makeNote(url: url, relPath: rel, values: values) {
                notes.append(note)
            }
        }

        notes.sort { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        let tree = buildFolderTree(notes: notes, folderPaths: folderPaths)
        let tags = buildTagCounts(notes: notes)
        return ScanResult(root: root, notes: notes, folderTree: tree, tags: tags, scannedAt: Date())
    }

    private func makeNote(url: URL, relPath: String, values: URLResourceValues?) -> Note? {
        guard let raw = readText(url) else { return nil }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let parsed = Frontmatter.parse(text)
        let fileName = url.deletingPathExtension().lastPathComponent
        let title = parsed.title ?? Frontmatter.firstHeading(in: parsed.body) ?? fileName
        let folder = (relPath as NSString).deletingLastPathComponent
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return Note(
            id: relPath,
            url: url,
            relPath: relPath,
            folderPath: folder,
            title: title,
            date: parsed.date,
            tags: parsed.tags,
            modified: modified,
            size: text.utf8.count,
            excerpt: Self.excerpt(from: parsed.body),
            body: text
        )
    }

    private func readText(_ url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return nil
    }

    private func buildFolderTree(notes: [Note], folderPaths: Set<String>) -> FolderNode {
        final class Builder {
            let name: String
            let path: String
            var children: [String: Builder] = [:]
            var directCount = 0

            init(name: String, path: String) {
                self.name = name
                self.path = path
            }
        }

        let rootBuilder = Builder(name: "知识库", path: "")
        @discardableResult
        func insert(_ relPath: String) -> Builder {
            var current = rootBuilder
            guard !relPath.isEmpty else { return current }
            var accumulated: [String] = []
            for component in relPath.components(separatedBy: "/") {
                accumulated.append(component)
                let path = accumulated.joined(separator: "/")
                if let child = current.children[component] {
                    current = child
                } else {
                    let child = Builder(name: component, path: path)
                    current.children[component] = child
                    current = child
                }
            }
            return current
        }
        for folder in folderPaths {
            insert(folder)
        }
        for note in notes {
            rootBuilder.directCount += note.folderPath.isEmpty ? 1 : 0
            insert(note.folderPath).directCount += 1
        }

        func convert(_ builder: Builder) -> FolderNode {
            let children = builder.children.values
                .map(convert)
                .sorted { sortKey($0.name) < sortKey($1.name) }
            let total = builder.directCount + children.reduce(0) { $0 + $1.totalCount }
            return FolderNode(
                id: builder.path,
                name: builder.name,
                path: builder.path,
                children: children,
                directCount: builder.directCount,
                totalCount: total
            )
        }

        return convert(rootBuilder)
    }

    private func buildTagCounts(notes: [Note]) -> [TagCount] {
        var counts: [String: Int] = [:]
        for note in notes {
            for tag in note.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { TagCount(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func sortKey(_ name: String) -> String {
        var digits = ""
        for char in name {
            if char.isNumber { digits.append(char) } else { break }
        }
        let number = Int(digits) ?? 9999
        return String(format: "%04d-%@", number, name.lowercased())
    }

    static func excerpt(from body: String) -> String {
        var collected: [String] = []
        var inFence = false
        for rawLine in body.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("![") { continue }
            if trimmed.hasPrefix("|") { continue }
            if trimmed.allSatisfy({ "|-: ".contains($0) }) { continue }
            var text = trimmed
            text = text.replacingOccurrences(of: "**", with: "")
            text = text.replacingOccurrences(of: "`", with: "")
            text = text.replacingOccurrences(of: "~~", with: "")
            text = text.replacingOccurrences(of: "> ", with: "")
            text = text.replacingOccurrences(of: "- ", with: "")
            if let regex = try? NSRegularExpression(pattern: "!?\\[([^\\]]*)\\]\\([^)]*\\)") {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
            }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            collected.append(text)
            if collected.joined(separator: " ").count > 140 { break }
        }
        var excerpt = collected.joined(separator: " ")
        excerpt = excerpt.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if excerpt.count > 160 {
            excerpt = String(excerpt.prefix(160)) + "…"
        }
        return excerpt
    }
}
