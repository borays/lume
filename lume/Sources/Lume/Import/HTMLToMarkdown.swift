import Foundation
import SwiftSoup

/// 把正文 DOM 转成 GitHub 风格 Markdown。图片先写成 `lume-img://序号` 占位，
/// 导入时再统一下载到本地并替换。
final class HTMLToMarkdown {
    private let baseURL: URL
    private(set) var images: [WebImage] = []
    private(set) var imageUses = 0
    private var imageIndexByURL: [String: Int] = [:]

    private let blockTags: Set<String> = [
        "p", "div", "section", "article", "main", "header", "figure", "figcaption",
        "details", "summary", "blockquote", "pre", "ul", "ol", "li", "table", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6", "dl", "dt", "dd", "address"
    ]

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func convert(_ root: Element) -> String {
        finalize(renderChildren(root))
    }

    // MARK: - Nodes

    private func renderChildren(_ element: Element) -> String {
        var output = ""
        for node in element.getChildNodes() {
            output += render(node)
        }
        return output
    }

    private func render(_ node: Node) -> String {
        if let text = node as? TextNode {
            return escapeText(collapseWhitespace(text.getWholeText()))
        }
        guard let element = node as? Element else { return "" }
        let tag = element.tagName().lowercased()

        switch tag {
        case "script", "style", "noscript", "svg", "canvas", "form", "button", "input",
             "select", "textarea", "nav", "footer", "aside", "iframe",
             "mp-common-profile", "mp-style-type", "mp-common-miniprogram",
             "mpvoice", "mpprofile":
            return ""
        case "mpvideo":
            if let src = mediaSource(element) {
                return "\n\n[视频](\(escapeDestination(src)))\n\n"
            }
            return ""
        case "br":
            return "\n\n"
        case "hr":
            return "\n\n---\n\n"
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            let content = inline(element)
            return content.isEmpty ? "" : "\n\n\(String(repeating: "#", count: level)) \(content)\n\n"
        case "p", "address", "summary":
            let content = blockContent(element)
            return content.isEmpty ? "" : "\n\n\(content)\n\n"
        case "figcaption":
            let content = inline(element)
            return content.isEmpty ? "" : "\n\n*\(content)*\n\n"
        case "div", "section", "article", "main", "header", "figure", "details", "center":
            if hasBlockChild(element) {
                return renderChildren(element) + "\n\n"
            }
            let content = inline(element)
            return content.isEmpty ? "" : "\n\n\(content)\n\n"
        case "span":
            if isBlockStyled(element) {
                let content = blockContent(element)
                return content.isEmpty ? "" : "\n\n\(content)\n\n"
            }
            return renderChildren(element)
        case "blockquote":
            let inner = finalize(renderChildren(element))
            guard !inner.isEmpty else { return "" }
            let quoted = inner.components(separatedBy: "\n")
                .map { $0.isEmpty ? ">" : "> " + $0 }
                .joined(separator: "\n")
            return "\n\n\(quoted)\n\n"
        case "pre":
            return renderCodeBlock(element)
        case "code":
            return inlineCode(rawText(element))
        case "ul", "ol":
            return renderList(element, ordered: tag == "ol", depth: 0)
        case "table":
            return renderTable(element)
        case "img":
            return renderImage(element)
        case "a":
            let inner = inline(element)
            guard let destination = linkDestination(element) else { return inner }
            if inner.isEmpty {
                return "[\(escapeBrackets(destination))](\(escapeDestination(destination)))"
            }
            return "[\(inner)](\(escapeDestination(destination)))"
        case "strong", "b":
            let inner = inline(element)
            return inner.isEmpty ? "" : "**\(inner)**"
        case "em", "i":
            let inner = inline(element)
            return inner.isEmpty ? "" : "*\(inner)*"
        case "del", "s", "strike":
            let inner = inline(element)
            return inner.isEmpty ? "" : "~~\(inner)~~"
        case "video", "audio", "source":
            if let src = mediaSource(element) {
                return "\n\n[媒体](\(escapeDestination(src)))\n\n"
            }
            return ""
        case "dl":
            var output = "\n\n"
            for child in element.children() {
                let content = inline(child)
                guard !content.isEmpty else { continue }
                if child.tagName().lowercased() == "dt" {
                    output += "**\(content)**\n\n"
                } else {
                    output += "\(content)\n\n"
                }
            }
            return output
        default:
            return renderChildren(element)
        }
    }

    // MARK: - Inline helpers

    private func inline(_ element: Element) -> String {
        let raw = renderChildren(element)
        let collapsed = raw.replacingOccurrences(
            of: #"\s*\n+\s*"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func blockContent(_ element: Element) -> String {
        finalize(renderChildren(element))
    }

    private func hasBlockChild(_ element: Element) -> Bool {
        for child in element.children() {
            let tag = child.tagName().lowercased()
            if blockTags.contains(tag) { return true }
            if tag == "span" && isBlockStyled(child) { return true }
        }
        return false
    }

    private func isBlockStyled(_ element: Element) -> Bool {
        let style = element.safeAttr("style").lowercased().replacingOccurrences(of: " ", with: "")
        return style.contains("display:block")
            || style.contains("display:flex")
            || style.contains("display:grid")
    }

    private func collapseWhitespace(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        return cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func escapeText(_ text: String) -> String {
        var output = ""
        for character in text {
            switch character {
            case "\\", "`", "*", "_", "[", "]", "<", ">", "~":
                output.append("\\")
                output.append(character)
            default:
                output.append(character)
            }
        }
        return output
    }

    private func escapeBrackets(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
    }

    private func escapeDestination(_ raw: String) -> String {
        raw.replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    private func inlineCode(_ raw: String) -> String {
        let text = collapseWhitespace(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if text.contains("`") {
            return "`` \(text) ``"
        }
        return "`\(text)`"
    }

    private func rawText(_ element: Element) -> String {
        var output = ""
        for node in element.getChildNodes() {
            if let text = node as? TextNode {
                output += text.getWholeText()
            } else if let child = node as? Element {
                if child.tagName().lowercased() == "br" {
                    output += "\n"
                } else {
                    output += rawText(child)
                }
            }
        }
        return output
    }

    // MARK: - Code

    private func renderCodeBlock(_ element: Element) -> String {
        let codeElement = (try? element.select("code").first()) ?? element
        let code = rawText(codeElement).trimmingCharacters(in: .newlines)
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let language = codeLanguage(codeElement) ?? codeLanguage(element) ?? ""
        var fence = "```"
        var run = 0
        for character in code {
            if character == "`" {
                run += 1
                if run >= fence.count { fence += "`" }
            } else {
                run = 0
            }
        }
        return "\n\n\(fence)\(language)\n\(code)\n\(fence)\n\n"
    }

    private func codeLanguage(_ element: Element) -> String? {
        let dataLang = element.safeAttr("data-lang").trimmingCharacters(in: .whitespaces)
        if dataLang.range(of: #"^[A-Za-z0-9+#._-]+$"#, options: .regularExpression) != nil {
            return dataLang.lowercased()
        }
        let candidates = [element.safeAttr("class"), element.safeAttr("lang")]
        for candidate in candidates where !candidate.isEmpty {
            let lower = candidate.lowercased()
            guard let regex = try? NSRegularExpression(
                pattern: #"(?:language|lang|brush)[\s:\-]+([a-z0-9+#._-]+)"#
            ) else { continue }
            let range = NSRange(location: 0, length: (lower as NSString).length)
            guard let match = regex.firstMatch(in: lower, range: range),
                  let valueRange = Range(match.range(at: 1), in: lower) else { continue }
            return String(lower[valueRange])
        }
        return nil
    }

    // MARK: - Lists

    private func renderList(_ element: Element, ordered: Bool, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        var output = "\n\n"
        var index = 1
        for item in element.children() where item.tagName().lowercased() == "li" {
            var content = ""
            var nested = ""
            for node in item.getChildNodes() {
                if let child = node as? Element {
                    let tag = child.tagName().lowercased()
                    if tag == "ul" || tag == "ol" {
                        nested += renderList(child, ordered: tag == "ol", depth: depth + 1)
                        continue
                    }
                }
                content += render(node)
            }
            let text = content.replacingOccurrences(
                of: #"\s*\n+\s*"#,
                with: " ",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let marker = ordered ? "\(index). " : "- "
            if !text.isEmpty {
                output += indent + marker + text + "\n"
            }
            let trimmedNested = nested.trimmingCharacters(in: .newlines)
            if !trimmedNested.isEmpty {
                output += trimmedNested + "\n"
            }
            index += 1
        }
        return output + "\n"
    }

    // MARK: - Tables

    private func renderTable(_ element: Element) -> String {
        let rows = (try? element.select("tr")) ?? Elements()
        var matrix: [[String]] = []
        for row in rows {
            let cells = row.children().filter {
                let tag = $0.tagName().lowercased()
                return tag == "td" || tag == "th"
            }
            guard !cells.isEmpty else { continue }
            let values = cells.map { cell -> String in
                let raw = renderChildren(cell)
                let collapsed = raw.replacingOccurrences(
                    of: #"\s*\n+\s*"#,
                    with: " ",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return collapsed.replacingOccurrences(of: "|", with: "\\|")
            }
            matrix.append(values)
        }
        guard let first = matrix.first, !first.isEmpty else { return "" }
        let columns = matrix.map(\.count).max() ?? first.count
        func padded(_ row: [String]) -> [String] {
            row + Array(repeating: "", count: max(0, columns - row.count))
        }
        var output = "\n\n| " + padded(first).joined(separator: " | ") + " |\n"
        output += "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |\n"
        for row in matrix.dropFirst() {
            output += "| " + padded(row).joined(separator: " | ") + " |\n"
        }
        return output + "\n"
    }

    // MARK: - Media

    private func renderImage(_ element: Element) -> String {
        let alt = escapeBrackets(element.safeAttr("alt").trimmingCharacters(in: .whitespacesAndNewlines))
        guard let raw = imageSource(element) else {
            return alt.isEmpty ? "" : escapeText(alt)
        }
        if isEmoji(raw) {
            return escapeText(alt)
        }
        if isTrackingPixel(element, raw: raw) {
            return ""
        }
        let key = normalizeImageURL(raw)
        guard let url = URL(string: key) else { return "" }

        let index: Int
        if let existing = imageIndexByURL[key] {
            index = existing
        } else {
            index = images.count
            images.append(WebImage(token: "lume-img://\(index)", url: url, alt: alt))
            imageIndexByURL[key] = index
        }
        imageUses += 1
        return "\n\n![\(alt)](lume-img://\(index))\n\n"
    }

    private func imageSource(_ element: Element) -> String? {
        let attributes = ["data-src", "data-original", "data-actualsrc", "data-lazy-src",
                          "data-lazyload", "data-url", "src"]
        for attribute in attributes {
            let value = element.safeAttr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsableImageSource(value) else { continue }
            return value
        }
        let srcset = element.safeAttr("srcset")
        if !srcset.isEmpty {
            let candidates = srcset.split(separator: ",")
            if let last = candidates.last {
                let value = last.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ").first ?? ""
                if isUsableImageSource(value) { return value }
            }
        }
        return nil
    }

    private func isUsableImageSource(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.hasPrefix("data:image/svg") { return false }
        if value == "about:blank" { return false }
        return value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("//")
            || value.hasPrefix("data:image/") || value.hasPrefix("/") || value.hasPrefix("./")
            || value.hasPrefix("../")
    }

    private func isEmoji(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("res.wx.qq.com") && (lower.contains("emoji") || lower.contains("we-emoji"))
    }

    private func isTrackingPixel(_ element: Element, raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.contains("spacer") || lower.contains("pixel.gif") { return true }
        if let width = Int(element.safeAttr("width")), width > 0, width <= 2 { return true }
        if let height = Int(element.safeAttr("height")), height > 0, height <= 2 { return true }
        return false
    }

    private func normalizeImageURL(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: "&amp;", with: "&")
        if value.hasPrefix("//") { value = "https:" + value }
        if value.hasPrefix("data:") { return value }
        guard let absolute = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else {
            return value
        }
        components.fragment = nil
        components.queryItems = components.queryItems?.filter {
            $0.name != "tp" && $0.name != "wx_lazy"
        }
        return components.url?.absoluteString ?? absolute.absoluteString
    }

    private func mediaSource(_ element: Element) -> String? {
        for attribute in ["src", "data-src", "data-url"] {
            let value = element.safeAttr(attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if isUsableImageSource(value) { return value }
        }
        return nil
    }

    private func linkDestination(_ element: Element) -> String? {
        var raw = element.safeAttr("href").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("javascript:") || lower.hasPrefix("#") { return nil }
        raw = raw.replacingOccurrences(of: "&amp;", with: "&")
        if raw.hasPrefix("//") { raw = "https:" + raw }
        guard let absolute = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
              var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else {
            return raw
        }
        components.fragment = nil
        return components.url?.absoluteString ?? absolute.absoluteString
    }

    // MARK: - Finalize

    private func finalize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
