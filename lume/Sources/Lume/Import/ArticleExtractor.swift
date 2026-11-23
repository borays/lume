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
        "mp-common-miniprogram", "mpvoice", "mpprofile",
        ".mp_profile_iframe_wrp"
    ].joined(separator: ", ")

    private static let promotionMarkers = [
        "文末福利", "文末推荐", "近期好文", "往期好文", "往期推荐", "往期回顾",
        "往期精选", "推荐阅读", "相关推荐", "更多推荐", "推荐关注", "活动推荐",
        "直播推荐", "课程推荐", "福利时间", "粉丝福利", "扫码关注", "长按识别",
        "扫码领取"
    ]

    private static let leadingPromotions = [
        "点击名片", "点击上方蓝字", "点击蓝字关注", "关注我们不迷路"
    ]

    static func extract(html: String, pageURL: URL) throws -> Output {
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)

        let title = firstText([
            textOf(document, "#activity-name"),
            textOf(document, "#articleContentId"),
            attributeOf(document, "meta[property=og:title]", "content"),
            (try? document.title()),
            textOf(document, "h1")
        ]) ?? "未命名网页"

        if title.contains("环境异常") || title.contains("访问过于频繁") {
            throw WebImportError.blocked
        }

        let author = firstText([
            textOf(document, "#js_name"),
            attributeOf(document, "#uid", "title"),
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
        trimPromotions(root)

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
        // 微信、CSDN 等站点有明确的正文容器，命中即用，避免被页头、推荐位等外层容器抢走
        for selector in ["#js_content", "#content_views"] {
            guard let candidate = try? document.select(selector).first() else { continue }
            let score = (try? candidate.text())?.count ?? 0
            if score >= 100 { return candidate }
        }
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

    /// 去掉正文容器内的公众号导流和文末推广：开头“点击名片关注”行、文末“文末福利/近期好文”等资料包与二维码。
    /// 推广块必须在正文 60% 之后、自身文本就是标记词，且截断后剩余正文不少于 200 字，避免误伤正常段落。
    private static func trimPromotions(_ root: Element) {
        dropLeadingPromotions(root)
        dropTailPromotion(root)
        dropTrailingDecorations(root)
    }

    private static func dropLeadingPromotions(_ root: Element) {
        var seenBlocks = 0
        for child in root.children().array() {
            let text = normalizeLabel((try? child.text()) ?? "")
            if text.isEmpty { continue }
            seenBlocks += 1
            if seenBlocks > 2 { break }
            guard text.count <= 30,
                  leadingPromotions.contains(where: { text.contains($0) }) else { continue }
            try? child.remove()
        }
    }

    private static func dropTailPromotion(_ root: Element) {
        let total = (try? root.text())?.count ?? 0
        guard total >= 200,
              let candidates = try? root.select(
                  "p, section, div, h1, h2, h3, h4, h5, h6, blockquote"
              ) else { return }

        for candidate in candidates.array() {
            let text = normalizeLabel((try? candidate.text()) ?? "")
            guard !text.isEmpty, text.count <= 20,
                  promotionMarkers.contains(text) else { continue }
            let selfLength = (try? candidate.text())?.count ?? 0
            let afterLength = textLength(after: candidate)
            let position = total - selfLength - afterLength
            guard position >= total * 3 / 5, position >= 200 else { continue }
            removeTrailingMedia(before: candidate)
            removeFrom(candidate, root: root)
            return
        }
    }

    private static func textLength(after element: Element) -> Int {
        var length = 0
        var current: Element? = element
        while let node = current {
            var sibling = try? node.nextElementSibling()
            while let next = sibling {
                length += (try? next.text())?.count ?? 0
                sibling = try? next.nextElementSibling()
            }
            current = node.parent() as? Element
        }
        return length
    }

    /// 推广块的封面图常作为独立图片块紧挨在标记词前面，一并移除
    private static func removeTrailingMedia(before element: Element) {
        var previous = try? element.previousElementSibling()
        var removed = 0
        while let node = previous, removed < 2 {
            let text = (try? node.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let imageCount = (try? node.select("img").size()) ?? 0
            guard text.isEmpty, imageCount > 0 else { break }
            let earlier = try? node.previousElementSibling()
            try? node.remove()
            removed += 1
            previous = earlier
        }
    }

    private static func removeFrom(_ element: Element, root: Element) {
        // 只删标记块本身和它之后的内容；上层容器里可能还有标记之前的正文，不能整块删掉
        var current: Element? = element
        var removeSelf = true
        while let node = current, node !== root {
            var sibling = try? node.nextElementSibling()
            while let next = sibling {
                try? next.remove()
                sibling = try? node.nextElementSibling()
            }
            let parent = node.parent() as? Element
            if removeSelf {
                try? node.remove()
                removeSelf = false
            }
            current = parent
        }
    }

    private static func dropTrailingDecorations(_ root: Element) {
        while let last = root.children().last() {
            let tag = last.tagName().lowercased()
            if tag == "hr" {
                try? last.remove()
                continue
            }
            let text = (try? last.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let imageCount = (try? last.select("img").size()) ?? 0
            if text.isEmpty && imageCount == 0 {
                try? last.remove()
                continue
            }
            break
        }
    }

    private static func normalizeLabel(_ raw: String) -> String {
        let collapsed = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        var text = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, "*_# ".contains(first) {
            text.removeFirst()
        }
        while let last = text.last, "*_# ：:，,。.！!？?、".contains(last) {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
