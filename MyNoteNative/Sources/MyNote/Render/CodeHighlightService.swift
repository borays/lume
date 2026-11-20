import AppKit
@preconcurrency import SwiftHighlight

extension Notification.Name {
    static let lumeCodeHighlightUpdated = Notification.Name("lumeCodeHighlightUpdated")
}

enum CodeLanguages {
    static let swiftHighlightAliases: [String: String] = [
        "yaml": "yaml", "yml": "yaml",
        "ini": "ini", "toml": "ini", "conf": "ini", "cfg": "ini",
        "json": "json", "jsonc": "json", "json5": "json",
        "python": "python", "py": "python",
        "rust": "rust", "rs": "rust",
        "swift": "swift",
        "go": "go", "golang": "go",
        "diff": "diff", "patch": "diff",
        "markdown": "markdown", "md": "markdown", "mkdown": "markdown",
        "nginx": "nginx", "nginxconf": "nginx",
        "xml": "xml", "html": "xml", "xhtml": "xml", "svg": "xml", "plist": "xml"
    ]

    static func canonical(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return swiftHighlightAliases[key]
    }
}

enum CodeHighlightService {
    private static let cache = NSCache<NSString, NSAttributedString>()
    private static var pending: Set<String> = []
    private static var unavailable: Set<String> = []

    static func isDarkAppearance() -> Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// 同步读取：命中缓存立即返回，未命中返回 nil 并触发后台高亮。
    static func highlight(code: String, language: String, fontSize: CGFloat) -> NSAttributedString? {
        let key = cacheKey(code: code, language: language, fontSize: fontSize)
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard CodeLanguages.canonical(language) != nil || language.isEmpty else { return nil }
        let keyString = key as String
        guard !pending.contains(keyString), !unavailable.contains(keyString) else { return nil }
        pending.insert(keyString)
        let dark = isDarkAppearance()
        Task { @MainActor in
            defer { pending.remove(keyString) }
            let attributed = await HighlightEngine.shared.highlight(
                code: code,
                language: language,
                dark: dark,
                fontSize: fontSize
            )
            guard let attributed else {
                unavailable.insert(keyString)
                return
            }
            cache.setObject(attributed, forKey: key)
            NotificationCenter.default.post(name: .lumeCodeHighlightUpdated, object: nil)
        }
        return nil
    }

    private static func cacheKey(code: String, language: String, fontSize: CGFloat) -> NSString {
        let appearance = isDarkAppearance() ? "d" : "l"
        let size = Int((fontSize * 10).rounded())
        return "\(appearance)|\(size)|\(language.lowercased())|\(code)" as NSString
    }

    /// 渲染层把缓存键写进代码块属性，补色时按同一键取结果。
    static func cacheKeyString(code: String, language: String, fontSize: CGFloat) -> String {
        cacheKey(code: code, language: language, fontSize: fontSize) as String
    }

    static func cached(key: String) -> NSAttributedString? {
        cache.object(forKey: key as NSString)
    }
}

actor HighlightEngine {
    static let shared = HighlightEngine()
    private let hljs = Highlight()
    private var registered = false

    private func ensureRegistered() async {
        guard !registered else { return }
        await hljs.registerXml()
        await hljs.registerDiff()
        await hljs.registerGo()
        await hljs.registerIni()
        await hljs.registerJSON()
        await hljs.registerMarkdown()
        await hljs.registerNginx()
        await hljs.registerPython()
        await hljs.registerRust()
        await hljs.registerSwift()
        await hljs.registerYaml()
        registered = true
    }

    func highlight(code: String, language: String, dark: Bool, fontSize: CGFloat) async -> NSAttributedString? {
        guard !code.isEmpty else { return nil }
        await ensureRegistered()
        let renderer = NSAttributedStringRenderer(theme: Self.theme(dark: dark, fontSize: fontSize))
        if let canonical = CodeLanguages.canonical(language) {
            let result = await hljs.highlight(code, language: canonical, renderer: renderer)
            guard result.errorRaised == nil else { return nil }
            return result.value
        }
        let auto = await hljs.highlightAuto(code, renderer: renderer)
        guard auto.relevance > 0, auto.language != "plaintext" else { return nil }
        return auto.value
    }

    private static func style(_ color: String, _ textStyle: TextStyle = .regular) -> ScopeStyle {
        ScopeStyle(foregroundColor: ThemeColor(hex: color), textStyle: textStyle)
    }

    private static func theme(dark: Bool, fontSize: CGFloat) -> NSAttributedStringTheme {
        let styles: [String: ScopeStyle] = dark
            ? [
                "keyword": style("#66D9EF"),
                "string": style("#A6E22E"),
                "comment": style("#708090"),
                "quote": style("#708090"),
                "number": style("#AE81FF"),
                "literal": style("#AE81FF"),
                "title": style("#E6DB74"),
                "function": style("#E6DB74"),
                "section": style("#E6DB74"),
                "built_in": style("#A6E22E"),
                "type": style("#E6DB74"),
                "variable": style("#FD971F"),
                "attr": style("#A6E22E"),
                "attribute": style("#A6E22E"),
                "tag": style("#F92672"),
                "name": style("#F92672"),
                "meta": style("#E67E65"),
                "bullet": style("#F92672"),
                "link": style("#E67E65")
            ]
            : [
                "keyword": style("#0077AA"),
                "string": style("#669900"),
                "comment": style("#708090"),
                "quote": style("#708090"),
                "number": style("#990055"),
                "literal": style("#990055"),
                "title": style("#DD4A68"),
                "function": style("#DD4A68"),
                "section": style("#DD4A68"),
                "built_in": style("#669900"),
                "type": style("#DD4A68"),
                "variable": style("#EE9900"),
                "attr": style("#669900"),
                "attribute": style("#669900"),
                "tag": style("#990055"),
                "name": style("#990055"),
                "meta": style("#9A6E3A"),
                "bullet": style("#990055"),
                "link": style("#9A6E3A")
            ]
        return NSAttributedStringTheme(fontName: "Menlo", fontSize: fontSize, styles: styles)
    }
}
