import Foundation

/// Footnote definitions extracted before parsing, so swift-markdown never sees them.
final class FootnoteRegistry {
    struct Definition {
        let id: String
        let content: String
    }

    let definitions: [Definition]
    private let indexByID: [String: Int]
    private var numbers: [String: Int] = [:]
    private var referenceOrder: [String] = []

    init(definitions: [Definition]) {
        self.definitions = definitions
        var index: [String: Int] = [:]
        for (offset, definition) in definitions.enumerated() {
            index[definition.id] = offset
        }
        self.indexByID = index
    }

    func number(for id: String) -> Int? {
        guard indexByID[id] != nil else { return nil }
        return number(forReference: id)
    }

    private func number(forReference id: String) -> Int {
        if let existing = numbers[id] { return existing }
        let next = numbers.count + 1
        numbers[id] = next
        referenceOrder.append(id)
        return next
    }

    func number(forReferenceID id: String) -> Int? {
        number(for: id)
    }

    /// Referenced definitions first (in reference order), then the remaining ones.
    var orderedDefinitions: [(number: Int, definition: Definition)] {
        var result: [(Int, Definition)] = []
        var seen = Set<String>()
        for id in referenceOrder {
            guard let index = indexByID[id] else { continue }
            result.append((numbers[id] ?? 0, definitions[index]))
            seen.insert(id)
        }
        var next = result.count + 1
        for (offset, definition) in definitions.enumerated() where !seen.contains(definition.id) {
            _ = offset
            result.append((next, definition))
            next += 1
        }
        return result
    }
}

enum FootnoteParser {
    private static let definitionPattern = try! NSRegularExpression(
        pattern: "^ {0,3}\\[\\^([^\\]\\s]+)\\]:[ \\t]*(.*)$"
    )

    static func extract(_ source: String) -> (body: String, definitions: [FootnoteRegistry.Definition]) {
        var lines = source.components(separatedBy: "\n")
        var definitions: [FootnoteRegistry.Definition] = []
        var kept: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let ns = line as NSString
            guard let match = definitionPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                kept.append(line)
                index += 1
                continue
            }

            let id = ns.substring(with: match.range(at: 1))
            var contentLines = [ns.substring(with: match.range(at: 2))]
            index += 1

            while index < lines.count {
                let continuation = lines[index]
                if continuation.hasPrefix("\t") {
                    contentLines.append(String(continuation.dropFirst()))
                    index += 1
                } else if continuation.hasPrefix("    ") {
                    contentLines.append(String(continuation.dropFirst(4)))
                    index += 1
                } else if continuation.trimmingCharacters(in: .whitespaces).isEmpty,
                          index + 1 < lines.count,
                          lines[index + 1].hasPrefix("    ") || lines[index + 1].hasPrefix("\t") {
                    contentLines.append("")
                    index += 1
                } else {
                    break
                }
            }

            var content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { content = id }
            definitions.append(FootnoteRegistry.Definition(id: id, content: content))

            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            }
        }

        return (kept.joined(separator: "\n"), definitions)
    }
}
