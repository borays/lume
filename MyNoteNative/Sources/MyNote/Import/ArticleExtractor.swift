import Foundation
import SwiftSoup

enum ArticleExtractor {
    struct Output: Sendable {
        let title: String
        let author: String?
        let publishedAt: String?
        let suggestedTags: [String]
        let markdown: String
        let images: [WebImage]
        let textLength: Int
        let imageUses: Int
    }

    private static let contentSelectors = [
        "#js_content",
        "article",
        "main",
        "[role=main]",
        ".article-content",
        ".post-content",
        ".entry-content",
        ".rich_media_content",
        "#content",
        ".content"
    ]

    private static let noiseSelector = [
        "script", "style", "noscript", "svg", "canvas", "iframe", "form",
        "button", "input", "select", "textarea", "nav", "footer", "aside",
        ".js_ad_link", ".rich_media_tool", ".rich_media_area_extra",
        "#js_pc_qr_code", "mp-common-profile", "mp-style-type",
        "mp-common-miniprogram", "mpvoice", "mpprofile"
    ].joined(separator: ", ")

    static func extract(html: String, pageURL: URL) throws -> Output {
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)

        let title = firstText([
            textOf(document, "#activity-name"),
            attributeOf(document, "meta[property=og:title]", "content"),
            (try? document.title()),
            textOf(document, "h1")
        ]) ?? "未命名网页"

        if title.contains("环境异常") || title.contains("访问过于频繁") {
            throw WebImportError.blocked
        }

        let author = firstText([
            textOf(document, "#js_name"),
            attributeOf(document, "meta[name=author]", "content"),
            textOf(document, ".author")
        ])

        let publishedAt = firstText([
            textOf(document, "#publish_time"),
            attributeOf(document, "meta[property=article:published_time]", "content")
        ])

        let suggestedTags = keywords(document)

        let root = contentRoot(document)
        clean(root)

        let plainLength = (try? root.text())?.count ?? 0
        if plainLength < 80 {
            throw WebImportError.emptyContent
        }

        let converter = HTMLToMarkdown(baseURL: pageURL)
        var markdown = converter.convert(root)
        markdown = stripDuplicateTitle(markdown, title: title)
        markdown = stripLeadingDecorations(markdown)

        if markdown.count < 40 {
            throw WebImportError.emptyContent
        }

        return Output(
            title: title,
            author: author,
            publishedAt: publishedAt,
            suggestedTags: suggestedTags,
            markdown: markdown,
            images: converter.images,
            textLength: plainLength,
            imageUses: converter.imageUses
        )
    }

    private static func contentRoot(_ document: Document) -> Element {
        var best: Element?
        var bestScore = 0
        for selector in contentSelectors {
            let candidates = (try? document.select(selector)) ?? Elements()
            for candidate in candidates {
                let score = (try? candidate.text())?.count ?? 0
                if score > bestScore {
                    best = candidate
                    bestScore = score
                }
            }
            if selector == "#js_content", bestScore >= 100 {
                break
            }
        }
        if let best, bestScore >= 200 {
            return best
        }
        return document.body() ?? document
    }

    private static func clean(_ root: Element) {
        if let noise = try? root.select(noiseSelector) {
            for element in noise {
                try? element.remove()
            }
        }
        if let styled = try? root.select("[style]") {
            for element in styled {
                let style = element.safeAttr("style")
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "")
                if style.contains("display:none") {
                    try? element.remove()
                }
            }
        }
    }

    private static func stripDuplicateTitle(_ markdown: String, title: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return markdown }
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("#") else { return markdown }
        let heading = line
            .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard heading == title || (heading.count > 8 && title.contains(heading))
                || (title.count > 8 && heading.contains(title)) else {
            return markdown
        }
        lines.remove(at: index)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingDecorations(_ markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        var index = 0
        while index < lines.count, isDecorativeLabel(lines[index]) {
            index += 1
        }
        guard index > 0 else { return markdown }
        let rest = lines[index...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.count >= 40 ? rest : markdown
    }

    private static func isDecorativeLabel(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[-—–_=*]{3,}$"#, options: .regularExpression) != nil {
            return true
        }
        return trimmed.count <= 12
            && trimmed.range(of: #"^(?i)(part|section|chapter)\s*\d*$"#, options: .regularExpression) != nil
    }

    private static func keywords(_ document: Document) -> [String] {
        guard let raw = attributeOf(document, "meta[name=keywords]", "content") else { return [] }
        let separators = CharacterSet(charactersIn: ",，、;；|")
        var seen = Set<String>()
        var result: [String] = []
        for part in raw.components(separatedBy: separators) {
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, tag.count <= 24, seen.insert(tag).inserted else { continue }
            result.append(tag)
            if result.count == 5 { break }
        }
        return result
    }

    // MARK: - SwiftSoup helpers

    private static func textOf(_ document: Document, _ selector: String) -> String? {
        guard let element = try? document.select(selector).first(),
              let text = try? element.text() else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func attributeOf(_ document: Document, _ selector: String, _ attribute: String) -> String? {
        guard let element = try? document.select(selector).first() else { return nil }
        let value = element.safeAttr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func firstText(_ values: [String?]) -> String? {
        for value in values {
            if let value, !value.isEmpty {
                return collapse(value)
            }
        }
        return nil
    }

    private static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
