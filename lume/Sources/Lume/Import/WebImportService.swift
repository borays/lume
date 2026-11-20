import Foundation

enum WebImportService {
    static func normalizeURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let range = text.range(of: #"https?://[^\s<>"']+"#, options: .regularExpression) {
            text = String(text[range])
        } else if let schemeRange = text.range(
            of: #"^[A-Za-z][A-Za-z0-9+.\-]*://"#,
            options: .regularExpression
        ) {
            let scheme = text[schemeRange].lowercased()
            guard scheme.hasPrefix("http://") || scheme.hasPrefix("https://") else { return nil }
            text = String(text[schemeRange.lowerBound...])
        } else if text.hasPrefix("//") {
            text = "https:" + text
        } else if !text.contains(" "), text.contains("."), !text.lowercased().hasPrefix("http") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else {
            return nil
        }
        components.fragment = nil
        return components.url
    }

    static func parse(_ raw: String, allowWebKitFallback: Bool = true) async throws -> WebArticle {
        guard let url = normalizeURL(raw) else { throw WebImportError.invalidURL }

        var failure: Error?
        if let page = try? await WebPageFetcher.fetchWithSession(url) {
            do {
                return try await extract(page: page)
            } catch {
                failure = error
            }
        }

        if allowWebKitFallback, let page = try? await WebPageFetcher.fetchWithWebKit(url) {
            do {
                return try await extract(page: page)
            } catch {
                failure = error
            }
        }

        if let failure { throw failure }
        throw WebImportError.fetchFailed("无法获取网页内容，请检查链接或网络后重试")
    }

    private static func extract(page: WebPageFetcher.Page) async throws -> WebArticle {
        let output = try await Task.detached(priority: .userInitiated) {
            try ArticleExtractor.extract(html: page.html, pageURL: page.finalURL)
        }.value

        return WebArticle(
            sourceURL: page.finalURL,
            finalURL: page.finalURL,
            title: output.title,
            author: output.author,
            publishedAt: output.publishedAt,
            suggestedTags: output.suggestedTags,
            markdown: output.markdown,
            images: output.images,
            textLength: output.textLength
        )
    }

    /// 下载正文图片到 `assets/web/<时间-标题>/`，并把 Markdown 里的占位链接替换为相对路径。
    static func materialize(
        _ article: WebArticle,
        folder: String,
        root: URL,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard !article.images.isEmpty else { return article.markdown }

        let paths = LibraryPaths(root: root)
        let directoryName = "\(timestamp())-\(slug(article.title))"
        let directoryRelative = "assets/web/\(directoryName)"
        let directory = try paths.resolve(relative: directoryRelative)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var names: [Int: String] = [:]
        var completed = 0
        let total = article.images.count
        let referer = article.sourceURL

        await withTaskGroup(of: (Int, String?).self) { group in
            var pending = Array(article.images.enumerated())

            func enqueue() {
                guard !pending.isEmpty else { return }
                let (index, image) = pending.removeFirst()
                group.addTask {
                    let name = await ImageDownloader.download(
                        image.url,
                        referer: referer,
                        directory: directory,
                        index: index
                    )
                    return (index, name)
                }
            }

            for _ in 0..<min(4, pending.count) { enqueue() }
            while let result = await group.next() {
                completed += 1
                if let name = result.1 {
                    names[result.0] = name
                }
                await progress("正在下载图片 \(completed)/\(total)…")
                enqueue()
            }
        }

        let depth = folder.split(separator: "/").count
        let prefix = String(repeating: "../", count: depth) + directoryRelative + "/"

        var markdown = article.markdown
        for (index, image) in article.images.enumerated() {
            let replacement = names[index].map { prefix + $0 } ?? image.url.absoluteString
            markdown = markdown.replacingOccurrences(of: image.token, with: replacement)
        }

        if names.isEmpty {
            try? FileManager.default.removeItem(at: directory)
        }
        return markdown
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func slug(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: #"[\\/:*?"<>|\n\r\t ]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        let prefix = String(cleaned.prefix(36))
        return prefix.isEmpty ? "web" : prefix
    }
}

enum ImageDownloader {
    static func download(_ url: URL, referer: URL, directory: URL, index: Int) async -> String? {
        let data: Data
        if url.scheme?.lowercased() == "data" {
            guard let decoded = decodeDataURL(url.absoluteString) else { return nil }
            data = decoded
        } else {
            let request = WebPageFetcher.imageRequest(url, referer: referer)
            guard let (payload, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  payload.count > 200 else {
                return nil
            }
            data = payload
        }

        let ext = imageExtension(data)
        let name = String(format: "%03d.%@", index + 1, ext)
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    private static func decodeDataURL(_ raw: String) -> Data? {
        guard let comma = raw.firstIndex(of: ","), raw[..<comma].contains("base64") else { return nil }
        let encoded = String(raw[raw.index(after: comma)...])
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
    }

    private static func imageExtension(_ data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if data.count > 12,
           data.starts(with: [0x52, 0x49, 0x46, 0x46]),
           String(data: data[8..<12], encoding: .ascii) == "WEBP" {
            return "webp"
        }
        if data.starts(with: [0x42, 0x4D]) { return "bmp" }
        return "jpg"
    }
}
