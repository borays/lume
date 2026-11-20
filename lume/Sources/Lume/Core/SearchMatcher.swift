import Foundation

struct SearchMatcher {
    private var blobs: [String: String] = [:]

    init(notes: [Note]) {
        blobs.reserveCapacity(notes.count)
        for note in notes {
            blobs[note.id] = Self.blob(for: note)
        }
    }

    mutating func update(_ note: Note) {
        blobs[note.id] = Self.blob(for: note)
    }

    mutating func remove(id: String) {
        blobs.removeValue(forKey: id)
    }

    func matches(_ note: Note, query: String) -> Bool {
        let terms = query.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "　" })
        guard !terms.isEmpty else { return true }
        let blob = blobs[note.id] ?? note.title.lowercased()
        for term in terms {
            if term.hasPrefix("#") {
                let tag = String(term.dropFirst())
                if !note.tags.contains(where: { $0.lowercased() == tag }) { return false }
            } else if !blob.contains(term) {
                return false
            }
        }
        return true
    }

    func rank(_ notes: [Note], query: String) -> [Note] {
        let lowered = query.lowercased()
        let terms = lowered.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "　" })
        guard !terms.isEmpty else { return notes }
        return notes
            .filter { matches($0, query: query) }
            .sorted { lhs, rhs in
                let leftTitle = lhs.title.lowercased().contains(lowered)
                let rightTitle = rhs.title.lowercased().contains(lowered)
                if leftTitle != rightTitle { return leftTitle }
                let leftTag = lhs.tags.contains { $0.lowercased().contains(lowered) }
                let rightTag = rhs.tags.contains { $0.lowercased().contains(lowered) }
                if leftTag != rightTag { return leftTag }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private static func blob(for note: Note) -> String {
        (note.title + "\n" + note.tags.joined(separator: " ") + "\n" + note.body).lowercased()
    }
}
