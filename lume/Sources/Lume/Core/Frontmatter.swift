import Foundation

enum Frontmatter {
    struct Document {
        var hasHeader: Bool
        var headerLines: [String]
        var body: String
    }

    struct Parsed {
        var title: String?
        var date: Date?
        var tags: [String]
        var type: String?
        var body: String
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func split(_ text: String) -> Document {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return Document(hasHeader: false, headerLines: [], body: normalized)
        }
        var closeIndex: Int?
        var index = 1
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                closeIndex = index
                break
            }
            index += 1
        }
        guard let close = closeIndex else {
            return Document(hasHeader: false, headerLines: [], body: normalized)
        }
        let header = Array(lines[1..<close])
        let bodyLines = Array(lines[(close + 1)...])
        var body = bodyLines.joined(separator: "\n")
        while body.hasPrefix("\n") { body.removeFirst() }
        return Document(hasHeader: true, headerLines: header, body: body)
    }

    static func parse(_ text: String) -> Parsed {
        let document = split(text)
        var title: String?
        var date: Date?
        var tags: [String] = []
        var type: String?
        var index = 0
        while index < document.headerLines.count {
            let line = document.headerLines[index]
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"),
                  let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "title":
                title = unquote(value)
            case "date":
                let clean = unquote(value)
                date = dateFormatter.date(from: clean) ?? isoFormatter.date(from: clean)
            case "type":
                type = unquote(value)
            case "tags":
                if value.hasPrefix("[") {
                    let inner = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    tags = parseInlineArray(inner)
                } else if value.isEmpty {
                    var next = index + 1
                    while next < document.headerLines.count {
                        let candidate = document.headerLines[next]
                        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("- ") {
                            let tag = unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                            if !tag.isEmpty { tags.append(tag) }
                            next += 1
                        } else {
                            break
                        }
                    }
                    index = next - 1
                } else {
                    tags = parseInlineArray(value)
                }
            default:
                break
            }
            index += 1
        }
        if title?.isEmpty == true { title = nil }
        return Parsed(title: title, date: date, tags: tags, type: type, body: document.body)
    }

    static func firstHeading(in body: String) -> String? {
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            if !trimmed.isEmpty { return nil }
        }
        return nil
    }

    static func setTitle(_ title: String, in text: String) -> String {
        let document = split(text)
        var lines = document.headerLines
        let keyIndex = lines.firstIndex { isKey($0, "title") }
        let line = "title: \(quote(title))"
        if let index = keyIndex {
            lines[index] = line
        } else if document.hasHeader {
            lines.insert(line, at: 0)
        } else {
            lines = defaultHeader(title: title, tags: [], type: "note")
        }
        return compose(headerLines: lines, body: document.body)
    }

    static func setTags(_ tags: [String], in text: String) -> String {
        let document = split(text)
        var lines = document.headerLines
        let keyIndex = lines.firstIndex { isKey($0, "tags") }
        let line = "tags: \(inlineArray(tags))"
        if let index = keyIndex {
            lines[index] = line
            var remove: [Int] = []
            var cursor = index + 1
            while cursor < lines.count {
                let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") && lines[cursor].hasPrefix(" ") {
                    remove.append(cursor)
                    cursor += 1
                } else {
                    break
                }
            }
            for idx in remove.reversed() { lines.remove(at: idx) }
        } else if document.hasHeader {
            if let titleIndex = lines.firstIndex(where: { isKey($0, "title") }) {
                lines.insert(line, at: titleIndex + 1)
            } else {
                lines.insert(line, at: 0)
            }
        } else {
            lines = defaultHeader(title: nil, tags: tags, type: "note")
        }
        return compose(headerLines: lines, body: document.body)
    }

    static func setH1(_ title: String, in text: String) -> String {
        let document = split(text)
        var lines = document.body.components(separatedBy: "\n")
        let heading = "# \(title)"
        if let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                lines[index] = heading
            } else {
                lines.insert(contentsOf: [heading, ""], at: index)
            }
        } else {
            lines = [heading, ""]
        }
        return compose(headerLines: document.headerLines, body: lines.joined(separator: "\n"), hadHeader: document.hasHeader)
    }

    static func createDocument(title: String, tags: [String], date: Date = Date(), body: String = "") -> String {
        let header = defaultHeader(title: title, tags: tags, type: "note", date: date)
        let content = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyText = content.isEmpty ? "# \(title)\n\n" : content
        return compose(headerLines: header, body: bodyText, hadHeader: true)
    }

    static func defaultHeader(title: String?, tags: [String], type: String, date: Date = Date()) -> [String] {
        var lines: [String] = []
        if let title { lines.append("title: \(quote(title))") }
        lines.append("date: \"\(dateFormatter.string(from: date))\"")
        lines.append("tags: \(inlineArray(tags))")
        lines.append("type: \"\(type)\"")
        return lines
    }

    static func compose(headerLines: [String], body: String, hadHeader: Bool = true) -> String {
        var cleanBody = body
        while cleanBody.hasPrefix("\n") { cleanBody.removeFirst() }
        guard hadHeader else {
            return cleanBody.hasSuffix("\n") ? cleanBody : cleanBody + "\n"
        }
        let header = headerLines.joined(separator: "\n")
        let suffix = cleanBody.isEmpty ? "" : "\n\n" + cleanBody
        var result = "---\n\(header)\n---\(suffix)"
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    static func inlineArray(_ values: [String]) -> String {
        if values.isEmpty { return "[]" }
        return "[" + values.map { quote($0) }.joined(separator: ", ") + "]"
    }

    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func unquote(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
            text = text.replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            return text
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            return String(text.dropFirst().dropLast())
        }
        return text
    }

    static func parseInlineArray(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuote = false
        var quoteChar: Character = "\""
        for char in value {
            if inQuote {
                if char == quoteChar {
                    inQuote = false
                } else {
                    current.append(char)
                }
            } else if char == "\"" || char == "'" {
                inQuote = true
                quoteChar = char
            } else if char == "," {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func isKey(_ line: String, _ key: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        return line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == key
    }
}
