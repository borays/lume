import AppKit

// 代码块语法高亮：轻量词法着色，配色对齐 MarkText：
// 浅色 Prism 默认主题，深色 Monokai。

enum CodeTheme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: "lume.code") { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1
            )
        }
    }

    static let keyword = dynamic(0x0077AA, 0x66D9EF)
    static let string = dynamic(0x669900, 0xA6E22E)
    static let number = dynamic(0x990055, 0xAE81FF)
    static let comment = dynamic(0x708090, 0x708090)
    static let command = dynamic(0xDD4A68, 0xE6DB74)
    static let key = dynamic(0x990055, 0xF92672)
    static let variable = dynamic(0xEE9900, 0xFD971F)
    static let plain = dynamic(0x4D4D4D, 0xF8F8F2)
}

enum CodeHighlighter {

    // MARK: - 入口

    static func normalizeLanguage(_ info: String) -> String {
        let token = info.lowercased()
            .split(separator: " ").first.map(String.init) ?? ""
        switch token {
        case "sh", "bash", "zsh", "ksh", "shell", "console", "terminal", "shell-session":
            return "shell"
        case "yml", "yaml":
            return "yaml"
        case "json", "json5", "jsonc":
            return "json"
        case "py", "python", "python3":
            return "python"
        case "js", "javascript", "jsx", "ts", "typescript", "tsx", "node":
            return "clike"
        case "go", "golang", "java", "c", "cpp", "c++", "objc", "swift", "rust", "rs",
             "kotlin", "scala", "php", "perl", "ruby", "rb", "dart", "groovy":
            return "clike"
        case "sql", "mysql", "pgsql", "plsql":
            return "sql"
        case "ini", "conf", "config", "cfg", "toml", "properties", "env", "profile":
            return "ini"
        case "text", "txt", "plaintext", "plain", "log", "output", "":
            return "plain"
        default:
            return "generic"
        }
    }

    static func highlight(_ code: String, language: String, font: NSFont) -> NSAttributedString {
        let normalized = normalizeLanguage(language)
        switch normalized {
        case "plain":
            return plain(code, font: font)
        case "shell":
            return shell(code, font: font)
        case "yaml":
            return yaml(code, font: font)
        case "json":
            return json(code, font: font)
        case "ini":
            return ini(code, font: font)
        case "sql":
            return scan(code, config: .sql, font: font)
        case "python":
            return scan(code, config: .python, font: font)
        case "clike":
            return scan(code, config: .clike, font: font)
        default:
            return scan(code, config: .generic, font: font)
        }
    }

    // MARK: - 配置

    private struct Config {
        var keywords: Set<String>
        var builtins: Set<String> = []
        var lineComments: [String]
        var blockComment: (open: String, close: String)? = nil
        var quoteChars: [Character]
        var caseInsensitiveKeywords = false
        var commandAfter: [Character] = []

        static let shellKeywords: Set<String> = [
            "if", "then", "elif", "else", "fi", "for", "while", "until", "do", "done",
            "case", "esac", "in", "function", "return", "exit", "local", "export",
            "set", "unset", "source", "alias", "break", "continue", "read"
        ]
        static let shellBuiltins: Set<String> = [
            "echo", "printf", "cd", "ls", "cat", "grep", "awk", "sed", "cut", "sort",
            "head", "tail", "wc", "tr", "find", "chmod", "chown", "mkdir", "rm", "cp",
            "mv", "ln", "tar", "gzip", "curl", "wget", "ssh", "scp", "systemctl",
            "journalctl", "yum", "apt", "dnf", "docker", "kubectl", "git", "make",
            "python", "python3", "ping", "nc", "netstat", "ss", "ip", "top", "ps",
            "kill", "sudo", "su", "vi", "vim", "less", "more", "df", "du", "free",
            "date", "sleep", "test", "which", "whereis", "xargs", "tee", "mount",
            "umount", "fdisk", "parted", "lsof", "strace", "rsync", "crontab"
        ]

        static let pythonKeywords: Set<String> = [
            "def", "class", "import", "from", "return", "if", "elif", "else", "for",
            "while", "with", "as", "try", "except", "finally", "raise", "pass",
            "lambda", "yield", "global", "nonlocal", "assert", "del", "in", "is",
            "not", "and", "or", "None", "True", "False", "async", "await", "break",
            "continue"
        ]
        static let pythonBuiltins: Set<String> = [
            "print", "len", "range", "open", "int", "str", "float", "list", "dict",
            "set", "tuple", "type", "isinstance", "enumerate", "zip", "map", "filter",
            "sorted", "sum", "min", "max", "abs", "format", "super", "self"
        ]

        static let clikeKeywords: Set<String> = [
            "func", "package", "import", "var", "const", "let", "type", "struct",
            "interface", "map", "chan", "go", "defer", "select", "range", "return",
            "if", "else", "for", "while", "switch", "case", "default", "break",
            "continue", "class", "extends", "implements", "new", "this", "super",
            "static", "final", "public", "private", "protected", "void", "null",
            "nil", "true", "false", "true", "try", "catch", "throw", "throws",
            "async", "await", "yield", "enum", "func", "in", "of", "instanceof",
            "typeof", "delete", "with", "do", "then", "module", "require", "export"
        ]

        static let sqlKeywords: Set<String> = [
            "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
            "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "ADD", "INDEX", "VIEW",
            "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "ON", "AS", "AND",
            "OR", "NOT", "NULL", "IN", "LIKE", "BETWEEN", "ORDER", "BY", "GROUP",
            "HAVING", "LIMIT", "OFFSET", "DISTINCT", "COUNT", "SUM", "AVG", "MIN",
            "MAX", "CASE", "WHEN", "THEN", "ELSE", "END", "UNION", "ALL", "EXISTS",
            "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "UNIQUE", "CASCADE"
        ]

        static var shell: Config {
            Config(
                keywords: shellKeywords,
                builtins: shellBuiltins,
                lineComments: ["#"],
                quoteChars: ["\"", "'", "`"],
                commandAfter: ["\n", ";", "|", "&", "(", "$", "`"]
            )
        }
        static var python: Config {
            Config(keywords: pythonKeywords, builtins: pythonBuiltins, lineComments: ["#"], quoteChars: ["\"", "'"])
        }
        static var clike: Config {
            Config(
                keywords: clikeKeywords,
                lineComments: ["//"],
                blockComment: ("/*", "*/"),
                quoteChars: ["\"", "'"]
            )
        }
        static var sql: Config {
            Config(keywords: sqlKeywords, lineComments: ["--"], quoteChars: ["'"], caseInsensitiveKeywords: true)
        }
        static var generic: Config {
            Config(keywords: [], lineComments: ["#", "//", ";"], quoteChars: ["\"", "'"])
        }
    }

    // MARK: - 通用扫描器

    private static func scan(_ code: String, config: Config, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(code)
        let n = chars.count
        var i = 0
        var atCommandStart = config.commandAfter.contains("\n")

        func append(_ text: String, color: NSColor, italic: Bool = false) {
            guard !text.isEmpty else { return }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font,
                .foregroundColor: color
            ]
            result.append(NSAttributedString(string: text, attributes: attributes))
            _ = attributes.removeValue(forKey: .foregroundColor)
        }

        while i < n {
            // 行注释
            if let prefix = config.lineComments.first(where: { matches(chars, at: i, prefix: $0) }),
               config.blockComment == nil || !matches(chars, at: i, prefix: "/*") || prefix != "/" {
                var comment = ""
                while i < n && chars[i] != "\n" {
                    comment.append(chars[i])
                    i += 1
                }
                append(comment, color: CodeTheme.comment)
                atCommandStart = true
                continue
            }

            // 块注释
            if let block = config.blockComment, matches(chars, at: i, prefix: block.open) {
                var comment = ""
                i += block.open.count
                while i < n {
                    if matches(chars, at: i, prefix: block.close) {
                        comment.append(block.close)
                        i += block.close.count
                        break
                    }
                    comment.append(chars[i])
                    i += 1
                }
                append(comment, color: CodeTheme.comment)
                continue
            }

            let ch = chars[i]

            // 字符串
            if config.quoteChars.contains(ch) {
                var text = String(ch)
                i += 1
                while i < n {
                    if chars[i] == "\\" && i + 1 < n {
                        text.append(chars[i])
                        text.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    text.append(chars[i])
                    if chars[i] == ch {
                        i += 1
                        break
                    }
                    i += 1
                }
                append(text, color: CodeTheme.string)
                continue
            }

            // 数字
            if ch.isNumber && (i == 0 || !isWordChar(chars[i - 1])) {
                var text = ""
                while i < n && (chars[i].isNumber || chars[i] == "." || chars[i] == "x"
                                 || (chars[i].isLetter && !text.isEmpty)) {
                    text.append(chars[i])
                    i += 1
                }
                append(text, color: CodeTheme.number)
                atCommandStart = false
                continue
            }

            // 单词
            if isWordChar(ch) {
                var word = ""
                var j = i
                while j < n && isWordChar(chars[j]) {
                    word.append(chars[j])
                    j += 1
                }
                i = j
                let matched = config.caseInsensitiveKeywords
                    ? config.keywords.contains(word.uppercased())
                    : config.keywords.contains(word)
                if config.commandAfter.contains("\n"), atCommandStart, !matched {
                    append(word, color: CodeTheme.command)
                } else if matched {
                    append(word, color: CodeTheme.keyword)
                } else if config.builtins.contains(word)
                    || (config.caseInsensitiveKeywords && config.builtins.contains(word.uppercased())) {
                    append(word, color: CodeTheme.command)
                } else {
                    append(word, color: CodeTheme.plain)
                }
                atCommandStart = false
                continue
            }

            // 其他字符
            append(String(ch), color: CodeTheme.plain)
            if config.commandAfter.contains(ch) {
                atCommandStart = true
            }
            if ch == "\n" && config.commandAfter.contains("\n") {
                atCommandStart = true
            }
            i += 1
        }

        return result
    }

    // MARK: - Shell（含变量着色）

    private static func shell(_ code: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(code)
        let n = chars.count
        var i = 0

        func append(_ text: String, color: NSColor, italic: Bool = false) {
            guard !text.isEmpty else { return }
            let useFont = italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
            result.append(NSAttributedString(string: text, attributes: [
                .font: useFont,
                .foregroundColor: color
            ]))
        }

        while i < n {
            let ch = chars[i]

            // 行注释
            if ch == "#" && !isWordChar(previous(chars: chars, i)) {
                var comment = ""
                while i < n && chars[i] != "\n" {
                    comment.append(chars[i])
                    i += 1
                }
                append(comment, color: CodeTheme.comment)
                continue
            }

            // 变量 $VAR / ${...} / $?
            if ch == "$" && i + 1 < n {
                var text = "$"
                var j = i + 1
                if chars[j] == "{" {
                    while j < n && chars[j] != "}" {
                        text.append(chars[j])
                        j += 1
                    }
                    if j < n { text.append("}"); j += 1 }
                } else {
                    while j < n && (isWordChar(chars[j]) || chars[j] == "?") {
                        text.append(chars[j])
                        j += 1
                    }
                }
                if text.count > 1 {
                    append(text, color: CodeTheme.variable)
                    i = j
                    continue
                }
            }

            // 字符串
            if ch == "\"" || ch == "'" || ch == "`" {
                var text = String(ch)
                i += 1
                while i < n {
                    if ch == "\"" && chars[i] == "\\" && i + 1 < n {
                        text.append(chars[i])
                        text.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    text.append(chars[i])
                    if chars[i] == ch {
                        i += 1
                        break
                    }
                    i += 1
                }
                append(text, color: CodeTheme.string)
                continue
            }

            // 单词：关键字 / 内置命令 / 普通命令
            if isWordChar(ch) || ch == "/" || ch == "." {
                var word = ""
                var j = i
                if ch == "/" || ch == "." {
                    // 路径开头的命令，如 /usr/sbin/xfs_repair
                    while j < n && (isWordChar(chars[j]) || "/._-".contains(chars[j])) {
                        word.append(chars[j])
                        j += 1
                    }
                    let hasWordChar = word.contains { isWordChar($0) }
                    if !hasWordChar {
                        append(String(ch), color: CodeTheme.plain)
                        i += 1
                        continue
                    }
                } else {
                    while j < n && (isWordChar(chars[j]) || "._-".contains(chars[j])) && !(chars[j] == "-" && j == i) {
                        word.append(chars[j])
                        j += 1
                    }
                }
                i = j
                let firstToken = word.split(separator: "/").last.map { String($0) } ?? word
                if Config.shellKeywords.contains(firstToken) {
                    append(word, color: CodeTheme.keyword)
                } else if Config.shellBuiltins.contains(firstToken)
                    || Config.shellBuiltins.contains(word.split(separator: "-").first.map(String.init) ?? word) {
                    append(word, color: CodeTheme.command)
                } else {
                    append(word, color: CodeTheme.plain)
                }
                continue
            }

            append(String(ch), color: CodeTheme.plain)
            i += 1
        }

        return result
    }

    // MARK: - YAML

    private static func yaml(_ code: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in code.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                appendLine(line, color: CodeTheme.comment, font: font, to: result)
                continue
            }
            // key: value 结构
            if let colon = firstColonOutsideQuotes(line) {
                let keyPart = String(line[line.startIndex..<colon])
                let valuePart = String(line[line.index(after: colon)...])
                appendLine(keyPart, color: CodeTheme.key, font: font, to: result)
                let valueTrimmed = valuePart.trimmingCharacters(in: .whitespaces)
                let leading = String(valuePart.prefix(valuePart.count - valueTrimmed.count))
                result.append(NSAttributedString(string: leading + ":", attributes: [
                    .font: font, .foregroundColor: CodeTheme.plain
                ]))
                if valueTrimmed.hasPrefix("#") {
                    appendLine(valueTrimmed, color: CodeTheme.comment, font: font, to: result)
                } else if ["true", "false", "null", "yes", "no", "on", "off"].contains(valueTrimmed.lowercased()) {
                    appendLine(valueTrimmed, color: CodeTheme.keyword, font: font, to: result)
                } else if valueTrimmed.isNumberLike() {
                    appendLine(valueTrimmed, color: CodeTheme.number, font: font, to: result)
                } else {
                    appendLine(valueTrimmed, color: valueTrimmed.hasPrefix("\"") || valueTrimmed.hasPrefix("'")
                        ? CodeTheme.string : CodeTheme.plain, font: font, to: result)
                }
            } else {
                let hasComment = trimmed.contains("#")
                if hasComment, let hash = line.firstIndex(of: "#"), isSpaceBefore(line, at: hash) {
                    appendLine(String(line[line.startIndex..<hash]), color: CodeTheme.plain, font: font, to: result)
                    appendLine(String(line[hash...]), color: CodeTheme.comment, font: font, to: result)
                } else {
                    appendLine(line, color: CodeTheme.plain, font: font, to: result)
                }
            }
        }
        return result
    }

    // MARK: - JSON

    private static func json(_ code: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(code)
        let n = chars.count
        var i = 0

        func append(_ text: String, color: NSColor, italic: Bool = false) {
            guard !text.isEmpty else { return }
            let useFont = italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
            result.append(NSAttributedString(string: text, attributes: [
                .font: useFont, .foregroundColor: color
            ]))
        }

        while i < n {
            let ch = chars[i]
            if ch == "\"" {
                var text = "\""
                i += 1
                while i < n && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < n {
                        text.append(chars[i])
                        text.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    text.append(chars[i])
                    i += 1
                }
                if i < n { text.append("\""); i += 1 }
                // 向后看是否为键（后跟可选空白 + 冒号）
                var j = i
                while j < n && chars[j] == " " { j += 1 }
                let isKey = j < n && chars[j] == ":"
                append(text, color: isKey ? CodeTheme.key : CodeTheme.string)
                continue
            }
            if ch.isNumber || (ch == "-" && i + 1 < n && chars[i + 1].isNumber) {
                var text = ""
                while i < n && (chars[i].isNumber || chars[i] == "." || chars[i] == "e"
                                 || chars[i] == "E" || chars[i] == "-" || chars[i] == "+") {
                    text.append(chars[i])
                    i += 1
                }
                append(text, color: CodeTheme.number)
                continue
            }
            if isWordChar(ch) {
                var word = ""
                while i < n && isWordChar(chars[i]) {
                    word.append(chars[i])
                    i += 1
                }
                append(word, color: ["true", "false", "null"].contains(word) ? CodeTheme.keyword : CodeTheme.plain)
                continue
            }
            append(String(ch), color: CodeTheme.plain)
            i += 1
        }
        return result
    }

    // MARK: - INI / conf

    private static func ini(_ code: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in code.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                appendLine(line, color: CodeTheme.comment, font: font, to: result)
            } else if trimmed.hasPrefix("[") {
                appendLine(line, color: CodeTheme.command, font: font, to: result)
            } else if let eq = line.firstIndex(of: "=") {
                appendLine(String(line[line.startIndex..<eq]), color: CodeTheme.key, font: font, to: result)
                result.append(NSAttributedString(string: "=", attributes: [.font: font, .foregroundColor: CodeTheme.plain]))
                appendLine(String(line[line.index(after: eq)...]), color: CodeTheme.string, font: font, to: result)
            } else {
                appendLine(line, color: CodeTheme.plain, font: font, to: result)
            }
        }
        return result
    }

    private static func plain(_ code: String, font: NSFont) -> NSAttributedString {
        NSMutableAttributedString(string: code, attributes: [
            .font: font, .foregroundColor: CodeTheme.plain
        ])
    }

    // MARK: - 工具

    private static func appendLine(_ text: String, color: NSColor, italic: Bool = false, font: NSFont, to result: NSMutableAttributedString) {
        guard !text.isEmpty else { return }
        let useFont = italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
        result.append(NSAttributedString(string: text, attributes: [
            .font: useFont, .foregroundColor: color
        ]))
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        ch.isLetter || ch == "_"
    }

    private static func previous(chars: [Character], _ i: Int) -> Character {
        i > 0 ? chars[i - 1] : " "
    }

    private static func matches(_ chars: [Character], at index: Int, prefix: String) -> Bool {
        let array = Array(prefix)
        guard index + array.count <= chars.count else { return false }
        for (offset, char) in array.enumerated() where chars[index + offset] != char {
            return false
        }
        return true
    }

    private static func firstColonOutsideQuotes(_ line: String) -> String.Index? {
        var inQuote: Character? = nil
        for index in line.indices {
            let ch = line[index]
            if let quote = inQuote {
                if ch == quote { inQuote = nil }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch == ":" {
                let next = line.index(after: index)
                if next == line.endIndex || line[next].isWhitespace {
                    return index
                }
            }
        }
        return nil
    }

    private static func isSpaceBefore(_ line: String, at index: String.Index) -> Bool {
        index == line.startIndex || line[line.index(before: index)].isWhitespace
    }
}

private extension String {
    func isNumberLike() -> Bool {
        guard !isEmpty else { return false }
        return allSatisfy { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" || $0 == "e" }
            && contains(where: { $0.isNumber })
    }
}
