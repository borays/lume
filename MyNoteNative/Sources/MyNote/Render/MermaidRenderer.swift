import AppKit

struct MermaidDiagram {
    let image: NSImage
    let kind: String
}

/// 轻量原生 Mermaid 渲染：常见语法给出基础图形，无法识别时返回 nil 由调用方回退为源码。
enum MermaidRenderer {
    static func render(code: String, maxWidth: CGFloat) -> MermaidDiagram? {
        let rawLines = code.components(separatedBy: .newlines)
        guard let headerIndex = rawLines.firstIndex(where: {
            let text = $0.trimmingCharacters(in: .whitespaces)
            return !text.isEmpty && !text.hasPrefix("%%")
        }) else { return nil }
        let header = rawLines[headerIndex].trimmingCharacters(in: .whitespaces)
        let lines = Array(rawLines[(headerIndex + 1)...])
        let parts = header.split(separator: " ").map(String.init)
        let keyword = parts.first?.lowercased() ?? ""

        switch keyword {
        case "flowchart", "graph":
            let direction = parts.count > 1 ? parts[1].uppercased() : "TD"
            guard let image = renderFlow(lines: lines, direction: direction, title: nil) else { return nil }
            return MermaidDiagram(image: image, kind: "流程图")
        case "sequencediagram":
            guard let image = renderSequence(lines: lines) else { return nil }
            return MermaidDiagram(image: image, kind: "时序图")
        case "statediagram-v2", "statediagram":
            guard let image = renderState(lines: lines) else { return nil }
            return MermaidDiagram(image: image, kind: "状态图")
        case "erdiagram":
            guard let image = renderER(lines: lines) else { return nil }
            return MermaidDiagram(image: image, kind: "ER 图")
        case "gantt":
            guard let image = renderGantt(lines: lines, maxWidth: maxWidth) else { return nil }
            return MermaidDiagram(image: image, kind: "甘特图")
        case "gitgraph":
            guard let image = renderGitGraph(lines: lines) else { return nil }
            return MermaidDiagram(image: image, kind: "Git 图")
        case "mindmap":
            guard let image = renderMindmap(lines: lines) else { return nil }
            return MermaidDiagram(image: image, kind: "脑图")
        case "c4context", "c4container", "c4component", "c4dynamic", "c4deployment":
            guard let image = renderC4(lines: lines) else { return nil }
            return MermaidDiagram(image: image, kind: "C4 架构图")
        default:
            return nil
        }
    }

    // MARK: - Flowchart / State

    private enum NodeShape {
        case rect, rounded, stadium, diamond, circle
    }

    private enum Tone {
        case normal, muted, accent
    }

    private struct GraphNode {
        let id: String
        var label: String
        var shape: NodeShape
        var tone: Tone
    }

    private struct GraphEdge {
        let from: String
        let to: String
        let label: String?
        let dashed: Bool
    }

    private struct NodeToken {
        let id: String
        let label: String
        let shape: NodeShape
        let tone: Tone
        let explicit: Bool
    }

    private enum Direction {
        case topDown, leftRight
    }

    private static func renderState(lines: [String]) -> NSImage? {
        renderFlow(lines: lines, direction: "LR", title: nil)
    }

    private static func renderFlow(lines: [String], direction: String, title: String?) -> NSImage? {
        var nodeMap: [String: GraphNode] = [:]
        var order: [String] = []
        var edges: [GraphEdge] = []
        var pseudoCount = 0

        func ensure(_ token: NodeToken) {
            if var existing = nodeMap[token.id] {
                if token.explicit {
                    existing.label = token.label
                    existing.shape = token.shape
                    existing.tone = token.tone
                } else if existing.label == existing.id, token.label != token.id {
                    existing.label = token.label
                }
                nodeMap[token.id] = existing
            } else {
                nodeMap[token.id] = GraphNode(
                    id: token.id,
                    label: token.label,
                    shape: token.shape,
                    tone: token.tone
                )
                order.append(token.id)
            }
        }

        func parseToken(_ raw: String) -> NodeToken? {
            var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            token = token.trimmingCharacters(in: CharacterSet(charactersIn: ";,|"))
            guard !token.isEmpty else { return nil }
            if token == "[*]" {
                pseudoCount += 1
                return NodeToken(id: "__lume_pseudo_\(pseudoCount)", label: "", shape: .circle, tone: .accent, explicit: true)
            }
            guard let groups = groups("^([^\\s\\[\\]\\(\\)\\{\\}>]+)\\s*(\\(\\(.*\\)\\)|\\[\\[.*\\]\\]|\\[.*\\]|\\(.*\\)|\\{.*\\}|>.*\\])?$", token) else {
                return nil
            }
            let id = groups[1]
            let spec = groups[2]
            guard !id.isEmpty else { return nil }
            if spec.isEmpty {
                return NodeToken(id: id, label: cleanLabel(id), shape: .rounded, tone: .normal, explicit: false)
            }
            if spec.hasPrefix("((") && spec.hasSuffix("))") {
                return NodeToken(id: id, label: inner(spec, 2), shape: .circle, tone: .normal, explicit: true)
            }
            if spec.hasPrefix("[[") && spec.hasSuffix("]]") {
                return NodeToken(id: id, label: inner(spec, 2), shape: .rect, tone: .normal, explicit: true)
            }
            if spec.hasPrefix("[") {
                return NodeToken(id: id, label: inner(spec, 1), shape: .rect, tone: .normal, explicit: true)
            }
            if spec.hasPrefix("{") {
                return NodeToken(id: id, label: inner(spec, 1), shape: .diamond, tone: .normal, explicit: true)
            }
            if spec.hasPrefix("(") {
                return NodeToken(id: id, label: inner(spec, 1), shape: .stadium, tone: .normal, explicit: true)
            }
            if spec.hasPrefix(">") {
                let label = String(spec.dropFirst().dropLast())
                return NodeToken(id: id, label: cleanLabel(label), shape: .rect, tone: .normal, explicit: true)
            }
            return NodeToken(id: id, label: cleanLabel(spec), shape: .rounded, tone: .normal, explicit: true)
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("subgraph") || lower == "end" || lower.hasPrefix("direction ")
                || lower.hasPrefix("classdef") || lower.hasPrefix("class ") || lower.hasPrefix("style ")
                || lower.hasPrefix("linkstyle") || lower.hasPrefix("click ") || lower.hasPrefix("state ")
                || lower.hasPrefix("note ") {
                continue
            }

            guard let match = groups("^(.*?)\\s*(-\\.->|==>|-->|---|--x|--o|--|==)\\s*(.*)$", line) else {
                if let token = parseToken(line) { ensure(token) }
                continue
            }

            var op = match[2]
            let leftRaw = match[1]
            var rightRaw = match[3]
            var edgeLabel: String?

            if let pipe = groups("^\\|([^|]*)\\|\\s*(.*)$", rightRaw) {
                edgeLabel = cleanLabel(pipe[1])
                rightRaw = pipe[2]
            }
            if op == "--" || op == "==",
               let nested = groups("^(.*?)\\s*(-->|---|==>|--x|--o)\\s*(.*)$", rightRaw),
               !nested[1].isEmpty {
                edgeLabel = edgeLabel ?? cleanLabel(nested[1])
                op = nested[2]
                rightRaw = nested[3]
            }

            var rightTokens: [NodeToken] = []
            for piece in rightRaw.components(separatedBy: "&") {
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                if let token = parseToken(trimmed) {
                    rightTokens.append(token)
                } else if let colon = groups("^([^\\s:]+?)\\s*:\\s*(.+)$", trimmed),
                          let token = parseToken(colon[1]) {
                    edgeLabel = cleanLabel(colon[2])
                    rightTokens.append(token)
                }
            }
            guard let left = parseToken(leftRaw), !rightTokens.isEmpty else { continue }
            ensure(left)
            for right in rightTokens {
                ensure(right)
                edges.append(GraphEdge(
                    from: left.id,
                    to: right.id,
                    label: edgeLabel,
                    dashed: op.contains(".")
                ))
            }
        }

        let nodes = order.compactMap { nodeMap[$0] }
        guard !nodes.isEmpty else { return nil }
        let resolvedDirection: Direction = direction.hasPrefix("LR") || direction.hasPrefix("RL") ? .leftRight : .topDown
        return drawGraph(nodes: nodes, edges: edges, direction: resolvedDirection, title: title)
    }

    // MARK: - Graph layout & drawing

    private static func drawGraph(nodes: [GraphNode], edges: [GraphEdge], direction: Direction, title: String?) -> NSImage? {
        guard !nodes.isEmpty else { return nil }
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var levels: [String: Int] = [:]
        var adjacency: [String: [String]] = [:]
        var indegree: [String: Int] = [:]

        for edge in edges {
            guard nodeMap[edge.from] != nil, nodeMap[edge.to] != nil, edge.from != edge.to else { continue }
            adjacency[edge.from, default: []].append(edge.to)
            indegree[edge.to, default: 0] += 1
        }

        var queue = nodes.filter { indegree[$0.id, default: 0] == 0 }.map(\.id)
        if queue.isEmpty, let first = nodes.first { queue = [first.id] }
        for id in queue { levels[id] = 0 }
        var head = 0
        while head < queue.count {
            let id = queue[head]
            head += 1
            let level = levels[id] ?? 0
            for next in adjacency[id] ?? [] where levels[next] == nil {
                levels[next] = level + 1
                queue.append(next)
            }
        }
        var isolatedLevel = (levels.values.max() ?? 0) + 1
        for node in nodes where levels[node.id] == nil {
            levels[node.id] = isolatedLevel
            isolatedLevel += 1
        }

        let levelCount = (levels.values.max() ?? 0) + 1
        var buckets = Array(repeating: [String](), count: levelCount)
        for node in nodes {
            let level = min(max(levels[node.id] ?? 0, 0), levelCount - 1)
            buckets[level].append(node.id)
        }
        var sizes: [String: NSSize] = [:]
        for node in nodes { sizes[node.id] = nodeSize(node) }

        let margin: CGFloat = 26
        let titleHeight: CGFloat = title == nil ? 0 : 34
        let mainGap: CGFloat = 54
        let crossGap: CGFloat = 24
        var positions: [String: NSRect] = [:]
        var canvasWidth: CGFloat = 300
        var canvasHeight: CGFloat = 180

        switch direction {
        case .topDown:
            let rowHeights = buckets.map { ids in ids.map { sizes[$0]?.height ?? 34 }.max() ?? 34 }
            let rowWidths = buckets.map { ids in
                ids.map { sizes[$0]?.width ?? 72 }.reduce(0, +) + CGFloat(max(0, ids.count - 1)) * crossGap
            }
            let contentWidth = max(rowWidths.max() ?? 200, 220)
            canvasWidth = contentWidth + margin * 2
            var y = margin + titleHeight
            for (row, ids) in buckets.enumerated() {
                var x = margin + (contentWidth - rowWidths[row]) / 2
                let rowHeight = rowHeights[row]
                for id in ids {
                    let size = sizes[id] ?? NSSize(width: 72, height: 34)
                    positions[id] = NSRect(x: x, y: y + (rowHeight - size.height) / 2, width: size.width, height: size.height)
                    x += size.width + crossGap
                }
                y += rowHeight + mainGap
            }
            canvasHeight = max(y - mainGap + margin, 160)
        case .leftRight:
            let colWidths = buckets.map { ids in ids.map { sizes[$0]?.width ?? 72 }.max() ?? 72 }
            let colHeights = buckets.map { ids in
                ids.map { sizes[$0]?.height ?? 34 }.reduce(0, +) + CGFloat(max(0, ids.count - 1)) * crossGap
            }
            let contentHeight = max(colHeights.max() ?? 140, 160)
            canvasHeight = contentHeight + margin * 2 + titleHeight
            var x = margin
            for (column, ids) in buckets.enumerated() {
                var y = margin + titleHeight + (contentHeight - colHeights[column]) / 2
                let columnWidth = colWidths[column]
                for id in ids {
                    let size = sizes[id] ?? NSSize(width: 72, height: 34)
                    positions[id] = NSRect(x: x + (columnWidth - size.width) / 2, y: y, width: size.width, height: size.height)
                    y += size.height + crossGap
                }
                x += columnWidth + mainGap
            }
            canvasWidth = max(x - mainGap + margin, 320)
        }

        let size = NSSize(width: ceil(canvasWidth), height: ceil(canvasHeight))
        return makeImage(size: size) {
            if let title {
                draw(title, in: NSRect(x: margin, y: 8, width: size.width - margin * 2, height: 22),
                     font: .systemFont(ofSize: 13, weight: .semibold),
                     color: .labelColor,
                     alignment: .center)
            }
            for edge in edges {
                drawEdge(edge, positions: positions, direction: direction)
            }
            for node in nodes {
                guard let rect = positions[node.id] else { continue }
                drawNode(node, in: rect)
            }
        }
    }

    private static func nodeFont(_ node: GraphNode) -> NSFont {
        if node.tone == .muted {
            return .systemFont(ofSize: 12, weight: .regular)
        }
        return .systemFont(ofSize: 12.5, weight: node.tone == .accent ? .semibold : .medium)
    }

    private static func nodeSize(_ node: GraphNode) -> NSSize {
        if node.shape == .circle && node.label.isEmpty {
            return NSSize(width: 16, height: 16)
        }
        let font = nodeFont(node)
        let text = measure(node.label, font: font, maxWidth: 190)
        var width = max(64, text.width + 30)
        var height = max(34, text.height + 16)
        switch node.shape {
        case .diamond:
            width += 34
            height = max(50, height + 18)
        case .circle:
            let side = max(width, height)
            width = side
            height = side
        case .stadium:
            width += 10
        default:
            break
        }
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private static func drawNode(_ node: GraphNode, in rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let path: NSBezierPath
        switch node.shape {
        case .rect:
            path = NSBezierPath(rect: rect)
        case .rounded:
            path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        case .stadium:
            path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        case .diamond:
            path = diamondPath(rect)
        case .circle:
            path = NSBezierPath(ovalIn: rect)
        }

        let fill: NSColor
        let stroke: NSColor
        switch node.tone {
        case .normal:
            fill = Palette.nodeFill
            stroke = Palette.nodeStroke
        case .muted:
            fill = Palette.mutedFill
            stroke = Palette.nodeStroke.withAlphaComponent(0.65)
        case .accent:
            fill = NSColor.controlAccentColor.withAlphaComponent(0.18)
            stroke = NSColor.controlAccentColor.withAlphaComponent(0.8)
        }
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = node.tone == .accent ? 1.5 : 1
        path.stroke()

        guard !node.label.isEmpty else { return }
        let inset = node.shape == .diamond ? rect.width * 0.2 : 8
        draw(node.label, in: rect.insetBy(dx: inset, dy: 5),
             font: nodeFont(node),
             color: .labelColor,
             alignment: .center)
    }

    private static func diamondPath(_ rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        path.line(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.midY))
        path.close()
        return path
    }

    private static func drawEdge(_ edge: GraphEdge, positions: [String: NSRect], direction: Direction) {
        guard let from = positions[edge.from], let to = positions[edge.to] else { return }
        let color = Palette.edge
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineJoinStyle = .round
        if edge.from == edge.to {
            let start = NSPoint(x: from.maxX - 2, y: from.midY - 6)
            let end = NSPoint(x: from.maxX - 2, y: from.midY + 6)
            path.move(to: start)
            path.curve(
                to: end,
                controlPoint1: NSPoint(x: from.maxX + 34, y: from.midY - 20),
                controlPoint2: NSPoint(x: from.maxX + 34, y: from.midY + 20)
            )
            if edge.dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
            path.stroke()
            drawArrowhead(at: end, angle: .pi, color: color, size: 6)
            if let label = edge.label, !label.isEmpty {
                drawEdgeLabel(label, at: NSPoint(x: from.maxX + 32, y: from.midY - 30))
            }
            return
        }

        let start: NSPoint
        let end: NSPoint
        let cp1: NSPoint
        let cp2: NSPoint
        switch direction {
        case .topDown:
            start = NSPoint(x: from.midX, y: from.maxY)
            end = NSPoint(x: to.midX, y: to.minY)
            let bend = max(20, abs(end.y - start.y) * 0.45)
            cp1 = NSPoint(x: start.x, y: start.y + bend)
            cp2 = NSPoint(x: end.x, y: end.y - bend)
        case .leftRight:
            start = NSPoint(x: from.maxX, y: from.midY)
            end = NSPoint(x: to.minX, y: to.midY)
            let bend = max(22, abs(end.x - start.x) * 0.45)
            cp1 = NSPoint(x: start.x + bend, y: start.y)
            cp2 = NSPoint(x: end.x - bend, y: end.y)
        }

        path.move(to: start)
        path.curve(to: end, controlPoint1: cp1, controlPoint2: cp2)
        if edge.dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
        path.stroke()

        let angle = atan2(end.y - cp2.y, end.x - cp2.x)
        drawArrowhead(at: end, angle: angle, color: color, size: 6.5)

        if let label = edge.label, !label.isEmpty {
            let mid = cubicPoint(start, cp1, cp2, end, 0.5)
            drawEdgeLabel(label, at: mid)
        }
    }

    private static func cubicPoint(_ p0: NSPoint, _ p1: NSPoint, _ p2: NSPoint, _ p3: NSPoint, _ t: CGFloat) -> NSPoint {
        let mt = 1 - t
        let x = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x + 3 * mt * t * t * p2.x + t * t * t * p3.x
        let y = mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y + 3 * mt * t * t * p2.y + t * t * t * p3.y
        return NSPoint(x: x, y: y)
    }

    private static func drawArrowhead(at point: NSPoint, angle: CGFloat, color: NSColor, size: CGFloat) {
        let back = NSPoint(x: point.x - cos(angle) * size, y: point.y - sin(angle) * size)
        let perp = NSPoint(x: -sin(angle), y: cos(angle))
        let path = NSBezierPath()
        path.move(to: point)
        path.line(to: NSPoint(x: back.x + perp.x * size * 0.5, y: back.y + perp.y * size * 0.5))
        path.line(to: NSPoint(x: back.x - perp.x * size * 0.5, y: back.y - perp.y * size * 0.5))
        path.close()
        color.setFill()
        path.fill()
    }

    private static func drawEdgeLabel(_ text: String, at point: NSPoint) {
        let font = NSFont.systemFont(ofSize: 10.5)
        let size = measure(text, font: font, maxWidth: 170)
        let rect = NSRect(
            x: point.x - size.width / 2 - 4,
            y: point.y - size.height / 2 - 2,
            width: size.width + 8,
            height: size.height + 4
        )
        NSColor.textBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        draw(text, in: rect.insetBy(dx: 4, dy: 2), font: font, color: .secondaryLabelColor, alignment: .center)
    }

    // MARK: - Sequence

    private struct SequenceParticipant {
        var id: String
        var label: String
    }

    private enum SequenceEvent {
        case message(from: String, to: String, text: String, dashed: Bool)
        case note(columns: [String], text: String)
    }

    private static func renderSequence(lines: [String]) -> NSImage? {
        var participants: [SequenceParticipant] = []
        var events: [SequenceEvent] = []

        func ensure(_ id: String, label: String? = nil) {
            if let index = participants.firstIndex(where: { $0.id == id }) {
                if let label, !label.isEmpty { participants[index].label = label }
            } else {
                participants.append(SequenceParticipant(id: id, label: label ?? id))
            }
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("autonumber") || lower.hasPrefix("activate ")
                || lower.hasPrefix("deactivate ") || lower.hasPrefix("loop ")
                || lower == "end" || lower.hasPrefix("alt ") || lower.hasPrefix("else")
                || lower.hasPrefix("opt ") || lower.hasPrefix("par ") || lower.hasPrefix("critical ")
                || lower.hasPrefix("break ") || lower.hasPrefix("rect ") {
                continue
            }
            if let group = groups("^(participant|actor)\\s+([^\\s]+)(?:\\s+as\\s+(.+))?$", line) {
                ensure(group[2], label: cleanLabel(group[3].isEmpty ? group[2] : group[3]))
                continue
            }
            if let group = groups("^Note\\s+(?:over|left of|right of)\\s+([^:]+?)\\s*:\\s*(.+)$", line) {
                let columns = group[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                columns.forEach { ensure($0) }
                events.append(.note(columns: columns, text: cleanLabel(group[2])))
                continue
            }
            if let group = groups("^([^\\s:]+?)\\s*(-->>|->>|-->|->|--x|-x|--\\)|-\\))\\s*([^\\s:]+?)\\s*:\\s*(.*)$", line) {
                let from = group[1]
                let to = group[3]
                ensure(from)
                ensure(to)
                events.append(.message(from: from, to: to, text: cleanLabel(group[4]), dashed: group[2].hasPrefix("--")))
                continue
            }
            if let group = groups("^([^\\s:]+?)\\s*(-->>|->>|-->|->)\\s*([^\\s:]+)$", line) {
                ensure(group[1])
                ensure(group[3])
                events.append(.message(from: group[1], to: group[3], text: "", dashed: group[2].hasPrefix("--")))
            }
        }

        guard !participants.isEmpty, !events.isEmpty else { return nil }

        let margin: CGFloat = 30
        let columnGap: CGFloat = 165
        let headerY: CGFloat = 22
        let headerHeight: CGFloat = 34
        let eventTop: CGFloat = 88
        let step: CGFloat = 46
        let noteStep: CGFloat = 64

        var xByID: [String: CGFloat] = [:]
        for (index, participant) in participants.enumerated() {
            xByID[participant.id] = margin + 60 + CGFloat(index) * columnGap
        }

        var totalHeight = eventTop
        for event in events {
            switch event {
            case .message:
                totalHeight += step
            case .note:
                totalHeight += noteStep
            }
        }
        totalHeight += 30
        let width = margin * 2 + CGFloat(max(0, participants.count - 1)) * columnGap + 120

        return makeImage(size: NSSize(width: width, height: totalHeight)) {
            let lineBottom = totalHeight - 24
            for participant in participants {
                guard let x = xByID[participant.id] else { continue }
                let header = NSRect(x: x - 60, y: headerY, width: 120, height: headerHeight)
                let path = NSBezierPath(roundedRect: header, xRadius: 6, yRadius: 6)
                NSColor.controlAccentColor.withAlphaComponent(0.13).setFill()
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 1
                path.stroke()
                draw(participant.label, in: header.insetBy(dx: 8, dy: 6),
                     font: .systemFont(ofSize: 11.5, weight: .semibold),
                     color: .labelColor,
                     alignment: .center)

                let life = NSBezierPath()
                life.move(to: NSPoint(x: x, y: headerY + headerHeight + 2))
                life.line(to: NSPoint(x: x, y: lineBottom))
                life.lineWidth = 1
                life.setLineDash([3, 4], count: 2, phase: 0)
                Palette.edge.withAlphaComponent(0.7).setStroke()
                life.stroke()
            }

            var y = eventTop
            for event in events {
                switch event {
                case let .message(from, to, text, dashed):
                    guard let fromX = xByID[from], let toX = xByID[to] else { continue }
                    Palette.edge.setStroke()
                    let color = NSColor.controlAccentColor
                    color.setStroke()
                    if fromX == toX {
                        let path = NSBezierPath()
                        path.move(to: NSPoint(x: fromX, y: y - 8))
                        path.line(to: NSPoint(x: fromX + 34, y: y - 8))
                        path.line(to: NSPoint(x: fromX + 34, y: y + 8))
                        path.line(to: NSPoint(x: fromX + 3, y: y + 8))
                        path.lineWidth = 1.2
                        if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
                        path.stroke()
                        drawArrowhead(at: NSPoint(x: fromX + 3, y: y + 8), angle: .pi, color: color, size: 6)
                        if !text.isEmpty {
                            draw(text, in: NSRect(x: fromX + 44, y: y - 8, width: 180, height: 16),
                                 font: .systemFont(ofSize: 10.5), color: .secondaryLabelColor, alignment: .left)
                        }
                    } else {
                        let path = NSBezierPath()
                        path.move(to: NSPoint(x: fromX, y: y))
                        path.line(to: NSPoint(x: toX, y: y))
                        path.lineWidth = 1.2
                        if dashed { path.setLineDash([4, 3], count: 2, phase: 0) }
                        path.stroke()
                        let angle: CGFloat = toX > fromX ? 0 : .pi
                        drawArrowhead(at: NSPoint(x: toX, y: y), angle: angle, color: color, size: 6)
                        if !text.isEmpty {
                            let left = min(fromX, toX)
                            let width = abs(toX - fromX)
                            draw(text, in: NSRect(x: left + 6, y: y - 19, width: max(40, width - 12), height: 16),
                                 font: .systemFont(ofSize: 10.5), color: .labelColor, alignment: .center)
                        }
                    }
                    y += step
                case let .note(columns, text):
                    let xs = columns.compactMap { xByID[$0] }
                    let minX = xs.min() ?? margin + 60
                    let maxX = xs.max() ?? minX
                    let rect = NSRect(x: minX - 70, y: y - 16, width: max(140, maxX - minX + 140), height: 32)
                    let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
                    NSColor.systemYellow.withAlphaComponent(0.14).setFill()
                    path.fill()
                    NSColor.systemYellow.withAlphaComponent(0.55).setStroke()
                    path.lineWidth = 1
                    path.stroke()
                    draw(text, in: rect.insetBy(dx: 8, dy: 7),
                         font: .systemFont(ofSize: 10.5), color: .labelColor, alignment: .center)
                    y += noteStep
                }
            }
        }
    }

    // MARK: - ER

    private static func renderER(lines: [String]) -> NSImage? {
        var entityOrder: [String] = []
        var attributes: [String: [(String, String)]] = [:]
        var relations: [(from: String, to: String, left: String, right: String, label: String)] = []
        var current: String?

        func ensureEntity(_ name: String) {
            if attributes[name] == nil {
                attributes[name] = []
                entityOrder.append(name)
            }
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            if line.contains("{") {
                let name = line.split(separator: " ").first.map(String.init) ?? ""
                if !name.isEmpty {
                    current = name
                    ensureEntity(name)
                }
                continue
            }
            if line == "}" {
                current = nil
                continue
            }
            if let current {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    let type = String(parts[0])
                    let name = String(parts[1])
                    attributes[current, default: []].append((type, name))
                }
                continue
            }
            if let group = groups("^([A-Za-z0-9_]+)\\s+([|}{o]+)--([|}{o]+)\\s+([A-Za-z0-9_]+)\\s*:\\s*(.+)$", line) {
                ensureEntity(group[1])
                ensureEntity(group[4])
                relations.append((group[1], group[4], group[2], group[3], cleanLabel(group[5])))
            }
        }

        guard !entityOrder.isEmpty else { return nil }

        let margin: CGFloat = 28
        let boxWidth: CGFloat = 196
        let columnGap: CGFloat = 76
        let rowGap: CGFloat = 62
        let columns = entityOrder.count <= 2 ? entityOrder.count : (entityOrder.count <= 6 ? 2 : 3)
        var rowHeights: [CGFloat] = []
        var heights: [String: CGFloat] = [:]
        for name in entityOrder {
            let count = attributes[name]?.count ?? 0
            let height = 34 + CGFloat(count) * 17 + 12
            heights[name] = height
        }
        let rows = Int(ceil(Double(entityOrder.count) / Double(columns)))
        rowHeights = Array(repeating: 0, count: rows)
        for (index, name) in entityOrder.enumerated() {
            let row = index / columns
            rowHeights[row] = max(rowHeights[row], heights[name] ?? 60)
        }

        var frames: [String: NSRect] = [:]
        var y = margin
        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < entityOrder.count else { continue }
                let name = entityOrder[index]
                let height = heights[name] ?? 60
                let x = margin + CGFloat(column) * (boxWidth + columnGap)
                frames[name] = NSRect(x: x, y: y + (rowHeights[row] - height) / 2, width: boxWidth, height: height)
            }
            y += rowHeights[row] + rowGap
        }
        let width = margin * 2 + CGFloat(columns) * boxWidth + CGFloat(max(0, columns - 1)) * columnGap
        let height = y - rowGap + margin

        return makeImage(size: NSSize(width: width, height: height)) {
            for relation in relations {
                guard let a = frames[relation.from], let b = frames[relation.to] else { continue }
                let start = rectEdgePoint(a, toward: NSPoint(x: b.midX, y: b.midY))
                let end = rectEdgePoint(b, toward: NSPoint(x: a.midX, y: a.midY))
                let path = NSBezierPath()
                path.move(to: start)
                path.line(to: end)
                path.lineWidth = 1.1
                Palette.edge.setStroke()
                path.stroke()

                draw(relation.left, in: NSRect(x: start.x - 18, y: start.y - 8, width: 36, height: 14),
                     font: .monospacedSystemFont(ofSize: 9.5, weight: .medium),
                     color: .secondaryLabelColor, alignment: .center)
                draw(relation.right, in: NSRect(x: end.x - 18, y: end.y - 8, width: 36, height: 14),
                     font: .monospacedSystemFont(ofSize: 9.5, weight: .medium),
                     color: .secondaryLabelColor, alignment: .center)
                if !relation.label.isEmpty {
                    drawEdgeLabel(relation.label, at: NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
                }
            }

            for name in entityOrder {
                guard let rect = frames[name] else { continue }
                let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
                Palette.nodeFill.setFill()
                path.fill()
                Palette.nodeStroke.setStroke()
                path.lineWidth = 1
                path.stroke()

                let header = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 30)
                let headerPath = NSBezierPath(roundedRect: header, xRadius: 7, yRadius: 7)
                NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
                headerPath.fill()
                draw(name, in: header.insetBy(dx: 10, dy: 7),
                     font: .systemFont(ofSize: 12, weight: .semibold),
                     color: .labelColor, alignment: .left)

                var attributeY = rect.minY + 36
                for (type, attribute) in attributes[name] ?? [] {
                    draw(type, in: NSRect(x: rect.minX + 10, y: attributeY, width: 62, height: 15),
                         font: .systemFont(ofSize: 10), color: .tertiaryLabelColor, alignment: .left)
                    draw(attribute, in: NSRect(x: rect.minX + 76, y: attributeY, width: rect.width - 88, height: 15),
                         font: .systemFont(ofSize: 10.5), color: .labelColor, alignment: .left)
                    attributeY += 17
                }
            }
        }
    }

    private static func rectEdgePoint(_ rect: NSRect, toward target: NSPoint) -> NSPoint {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        let scaleX = abs(dx) > 0.001 ? halfW / abs(dx) : .greatestFiniteMagnitude
        let scaleY = abs(dy) > 0.001 ? halfH / abs(dy) : .greatestFiniteMagnitude
        let scale = min(scaleX, scaleY)
        return NSPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    // MARK: - Gantt

    private static func renderGantt(lines: [String], maxWidth: CGFloat) -> NSImage? {
        struct Task {
            var name: String
            var id: String
            var start: Date
            var days: Int
            var section: String?
        }

        var tasks: [Task] = []
        var title = ""
        var section: String?
        var endByID: [String: Date] = [:]
        var lastEnd: Date?
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        func parseDate(_ text: String) -> Date? {
            formatter.date(from: text.trimmingCharacters(in: .whitespaces))
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("title ") || lower.hasPrefix("title:") {
                title = line.replacingOccurrences(of: "title:", with: "").replacingOccurrences(of: "title ", with: "")
                continue
            }
            if lower.hasPrefix("dateformat") || lower.hasPrefix("axisformat")
                || lower.hasPrefix("excludes") || lower.hasPrefix("todaymarker")
                || lower.hasPrefix("weekday") || lower.hasPrefix("tickinterval") {
                continue
            }
            if lower.hasPrefix("section ") {
                section = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let right = String(line[line.index(after: colon)...])
            let components = right.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !name.isEmpty, !components.isEmpty else { continue }

            var id = ""
            var startSpec: String?
            var duration = "1d"
            if components.count >= 3 {
                id = components[0]
                startSpec = components[1]
                duration = components[2]
            } else if components.count == 2 {
                if components[0].lowercased().hasPrefix("after") || parseDate(components[0]) != nil {
                    startSpec = components[0]
                    duration = components[1]
                } else {
                    id = components[0]
                    duration = components[1]
                }
            } else {
                duration = components[0]
            }

            var start = lastEnd ?? today
            if let startSpec {
                if startSpec.lowercased().hasPrefix("after") {
                    let reference = startSpec.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    start = endByID[reference] ?? lastEnd ?? today
                } else if let date = parseDate(startSpec) {
                    start = date
                }
            }
            let days = durationDays(duration)
            let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
            tasks.append(Task(name: name, id: id, start: start, days: days, section: section))
            if !id.isEmpty { endByID[id] = end }
            if let existing = lastEnd { lastEnd = max(existing, end) } else { lastEnd = end }
        }

        guard !tasks.isEmpty else { return nil }
        let minStart = tasks.map(\.start).min() ?? today
        let maxEnd = tasks.compactMap { calendar.date(byAdding: .day, value: $0.days, to: $0.start) }.max() ?? minStart
        let totalDays = max(1, calendar.dateComponents([.day], from: minStart, to: maxEnd).day ?? 1)

        let margin: CGFloat = 26
        let titleHeight: CGFloat = title.isEmpty ? 0 : 30
        let labelWidth: CGFloat = min(210, max(140, tasks.map { measure($0.name, font: .systemFont(ofSize: 11), maxWidth: 200).width }.max() ?? 140))
        let rowHeight: CGFloat = 30
        let sectionHeight: CGFloat = 26
        let contentTop = margin + titleHeight + 40
        var rowCount = 0
        var lastSection: String?
        for task in tasks {
            if task.section != lastSection {
                if task.section != nil { rowCount += 1 }
                lastSection = task.section
            }
            rowCount += 1
        }
        let height = contentTop + CGFloat(rowCount) * rowHeight + margin

        let timelineWidth = max(220, maxWidth - margin * 2 - labelWidth - 24)
        let dayScale = max(9, min(30, timelineWidth / CGFloat(totalDays)))
        let width = margin * 2 + labelWidth + 24 + CGFloat(totalDays) * dayScale
        let startX = margin + labelWidth + 24

        return makeImage(size: NSSize(width: max(width, 420), height: height)) {
            if !title.isEmpty {
                draw(title, in: NSRect(x: margin, y: 8, width: width - margin * 2, height: 22),
                     font: .systemFont(ofSize: 13, weight: .semibold),
                     color: .labelColor, alignment: .left)
            }

            let axisY = margin + titleHeight + 8
            let tickEvery = max(1, Int(ceil(64 / dayScale)))
            var tick = 0
            while tick <= totalDays {
                let x = startX + CGFloat(tick) * dayScale
                let date = calendar.date(byAdding: .day, value: tick, to: minStart) ?? minStart
                draw(formatter.string(from: date), in: NSRect(x: x - 26, y: axisY, width: 60, height: 14),
                     font: .systemFont(ofSize: 9.5), color: .tertiaryLabelColor, alignment: .left)
                let grid = NSBezierPath()
                grid.move(to: NSPoint(x: x, y: axisY + 20))
                grid.line(to: NSPoint(x: x, y: height - margin))
                grid.lineWidth = 0.7
                Palette.edge.withAlphaComponent(0.18).setStroke()
                grid.stroke()
                tick += tickEvery
            }

            var y = contentTop
            lastSection = nil
            for task in tasks {
                if task.section != lastSection {
                    if let section = task.section {
                        draw(section, in: NSRect(x: margin, y: y + 4, width: labelWidth + 10, height: 16),
                             font: .systemFont(ofSize: 10.5, weight: .semibold),
                             color: .secondaryLabelColor, alignment: .left)
                        let band = NSRect(x: margin, y: y, width: width - margin * 2, height: sectionHeight)
                        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
                        NSBezierPath(rect: band).fill()
                        y += sectionHeight
                    }
                    lastSection = task.section
                }

                draw(task.name, in: NSRect(x: margin, y: y + 7, width: labelWidth, height: 17),
                     font: .systemFont(ofSize: 11), color: .labelColor, alignment: .right)

                let offsetDays = max(0, calendar.dateComponents([.day], from: minStart, to: task.start).day ?? 0)
                let barX = startX + CGFloat(offsetDays) * dayScale
                let barWidth = max(6, CGFloat(task.days) * dayScale)
                let bar = NSRect(x: barX, y: y + 9, width: barWidth, height: 13)
                NSColor.controlAccentColor.withAlphaComponent(0.78).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()

                if barWidth > 46 {
                    draw("\(task.days)d", in: NSRect(x: bar.maxX + 6, y: y + 8, width: 48, height: 15),
                         font: .systemFont(ofSize: 9.5), color: .tertiaryLabelColor, alignment: .left)
                }
                y += rowHeight
            }
        }
    }

    private static func durationDays(_ raw: String) -> Int {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("w"), let value = Double(text.dropLast()) {
            return max(1, Int((value * 7).rounded()))
        }
        if text.hasSuffix("d"), let value = Double(text.dropLast()) {
            return max(1, Int(value.rounded()))
        }
        if text.hasSuffix("h"), let value = Double(text.dropLast()) {
            return max(1, Int(ceil(value / 24)))
        }
        if let value = Double(text) {
            return max(1, Int(value.rounded()))
        }
        return 1
    }

    // MARK: - Git graph

    private struct GitCommit {
        let id: String
        let tag: String?
        let lane: Int
        let x: Int
        let parents: [(lane: Int, x: Int)]
    }

    private static func renderGitGraph(lines: [String]) -> NSImage? {
        var laneOf: [String: Int] = ["main": 0]
        var branches: [String] = ["main"]
        var heads: [String: Int] = [:]
        var commits: [GitCommit] = []
        var current = "main"
        var sequence = 0

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            if line.lowercased().hasPrefix("commit") {
                var id = ""
                if let group = groups("id\\s*:\\s*\"?([^\"\\s]+)\"?", line) { id = group[1] }
                if id.isEmpty { id = "c\(sequence + 1)" }
                var tag: String?
                if let group = groups("tag\\s*:\\s*\"?([^\"\\s]+)\"?", line) { tag = group[1] }
                var parents: [(lane: Int, x: Int)] = []
                if let index = heads[current], index >= 0, index < commits.count {
                    parents.append((commits[index].lane, commits[index].x))
                }
                let lane = laneOf[current] ?? 0
                commits.append(GitCommit(id: id, tag: tag, lane: lane, x: sequence, parents: parents))
                heads[current] = commits.count - 1
                sequence += 1
                continue
            }
            if let group = groups("^branch\\s+([^\\s]+)", line) {
                let name = group[1]
                if laneOf[name] == nil {
                    laneOf[name] = branches.count
                    branches.append(name)
                }
                heads[name] = heads[current]
                continue
            }
            if let group = groups("^(?:checkout|switch)\\s+([^\\s]+)", line) {
                let name = group[1]
                if laneOf[name] == nil {
                    laneOf[name] = branches.count
                    branches.append(name)
                }
                current = name
                continue
            }
            if let group = groups("^merge\\s+([^\\s]+)", line) {
                let name = group[1]
                var parents: [(lane: Int, x: Int)] = []
                if let index = heads[current], index >= 0, index < commits.count {
                    parents.append((commits[index].lane, commits[index].x))
                }
                if let index = heads[name], index >= 0, index < commits.count {
                    parents.append((commits[index].lane, commits[index].x))
                }
                let lane = laneOf[current] ?? 0
                commits.append(GitCommit(id: "merge", tag: nil, lane: lane, x: sequence, parents: parents))
                heads[current] = commits.count - 1
                sequence += 1
                continue
            }
        }

        guard !commits.isEmpty else { return nil }
        let margin: CGFloat = 26
        let laneGap: CGFloat = 54
        let commitGap: CGFloat = 66
        let leftPad: CGFloat = 84
        let laneCount = max(1, (commits.map(\.lane).max() ?? 0) + 1)
        let width = margin * 2 + leftPad + CGFloat(max(0, sequence - 1)) * commitGap + 40
        let height = margin * 2 + CGFloat(laneCount) * laneGap + 24

        return makeImage(size: NSSize(width: max(width, 380), height: height)) {
            func point(_ lane: Int, _ x: Int) -> NSPoint {
                NSPoint(x: margin + leftPad + CGFloat(x) * commitGap, y: margin + 20 + CGFloat(lane) * laneGap)
            }

            for (lane, name) in branches.enumerated() where lane < laneCount {
                let color = laneColor(lane)
                let y = point(lane, 0).y
                draw(name, in: NSRect(x: margin, y: y - 20, width: 74, height: 15),
                     font: .systemFont(ofSize: 10.5, weight: .semibold),
                     color: color, alignment: .left)
            }

            for commit in commits {
                let target = point(commit.lane, commit.x)
                for parent in commit.parents {
                    let source = point(parent.lane, parent.x)
                    let path = NSBezierPath()
                    path.move(to: source)
                    if parent.lane == commit.lane {
                        path.line(to: target)
                    } else {
                        let midX = (source.x + target.x) / 2
                        path.curve(
                            to: target,
                            controlPoint1: NSPoint(x: midX, y: source.y),
                            controlPoint2: NSPoint(x: midX, y: target.y)
                        )
                    }
                    path.lineWidth = 1.8
                    laneColor(parent.lane).withAlphaComponent(0.75).setStroke()
                    path.stroke()
                }
            }

            for commit in commits {
                let center = point(commit.lane, commit.x)
                let color = laneColor(commit.lane)
                let circle = NSBezierPath(ovalIn: NSRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11))
                color.setFill()
                circle.fill()
                NSColor.textBackgroundColor.setStroke()
                circle.lineWidth = 1.4
                circle.stroke()

                draw(commit.id, in: NSRect(x: center.x - 40, y: center.y + 10, width: 80, height: 13),
                     font: .systemFont(ofSize: 9.5), color: .secondaryLabelColor, alignment: .center)
                if let tag = commit.tag {
                    draw(tag, in: NSRect(x: center.x - 40, y: center.y - 27, width: 80, height: 13),
                         font: .systemFont(ofSize: 9.5, weight: .medium), color: color, alignment: .center)
                }
            }
        }
    }

    private static func laneColor(_ lane: Int) -> NSColor {
        let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemTeal, .systemPink]
        return colors[lane % colors.count]
    }

    // MARK: - Mindmap

    private final class MindNode {
        let label: String
        var children: [MindNode] = []
        var size: NSSize = .zero
        var depth: Int = 0
        var subtreeHeight: CGFloat = 0
        var origin: NSPoint = .zero

        init(label: String) {
            self.label = label
        }
    }

    private static func renderMindmap(lines: [String]) -> NSImage? {
        var root: MindNode?
        var stack: [(indent: Int, node: MindNode)] = []

        for raw in lines {
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            var indent = 0
            for character in raw {
                if character == " " { indent += 1 }
                else if character == "\t" { indent += 4 }
                else { break }
            }
            let content = raw.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.lowercased() == "mindmap" || content.hasPrefix("%%") { continue }
            let node = MindNode(label: mindLabel(content))
            if root == nil {
                root = node
                stack = [(indent, node)]
                continue
            }
            while let last = stack.last, last.indent >= indent {
                stack.removeLast()
            }
            let parent = stack.last?.node ?? root!
            parent.children.append(node)
            stack.append((indent, node))
        }

        guard let root else { return nil }

        func measureTree(_ node: MindNode, depth: Int) {
            node.depth = depth
            let size = depth == 0 ? 14.5 : (depth == 1 ? 12.5 : 11.5)
            let weight: NSFont.Weight = depth == 0 ? .semibold : (depth == 1 ? .medium : .regular)
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            let text = measure(node.label, font: font, maxWidth: 170)
            node.size = NSSize(width: ceil(max(54, text.width + 24)), height: ceil(max(28, text.height + 14)))
            for child in node.children {
                measureTree(child, depth: depth + 1)
            }
        }
        measureTree(root, depth: 0)

        var maxWidthAtDepth: [CGFloat] = []
        func collectWidths(_ node: MindNode) {
            while maxWidthAtDepth.count <= node.depth { maxWidthAtDepth.append(0) }
            maxWidthAtDepth[node.depth] = max(maxWidthAtDepth[node.depth], node.size.width)
            for child in node.children { collectWidths(child) }
        }
        collectWidths(root)

        var columnX: [CGFloat] = []
        var x: CGFloat = 30
        for (depth, width) in maxWidthAtDepth.enumerated() {
            columnX.append(x)
            x += width + 46
            if depth == maxWidthAtDepth.count - 1 { x -= 46 }
        }

        func computeHeight(_ node: MindNode) -> CGFloat {
            if node.children.isEmpty {
                node.subtreeHeight = node.size.height + 14
                return node.subtreeHeight
            }
            let total = node.children.map(computeHeight).reduce(0, +)
            node.subtreeHeight = max(node.size.height + 14, total)
            return node.subtreeHeight
        }
        let totalHeight = computeHeight(root)

        func assign(_ node: MindNode, top: CGFloat) {
            let centerY = top + node.subtreeHeight / 2
            node.origin = NSPoint(x: columnX[min(node.depth, columnX.count - 1)], y: centerY - node.size.height / 2)
            guard !node.children.isEmpty else { return }
            let childrenHeight = node.children.map(\.subtreeHeight).reduce(0, +)
            var childTop = top + (node.subtreeHeight - childrenHeight) / 2
            for child in node.children {
                assign(child, top: childTop)
                childTop += child.subtreeHeight
            }
        }
        assign(root, top: 30)

        var rightEdge: CGFloat = 0
        func collectRight(_ node: MindNode) {
            rightEdge = max(rightEdge, node.origin.x + node.size.width)
            for child in node.children { collectRight(child) }
        }
        collectRight(root)

        let width = rightEdge + 30
        let height = totalHeight + 60

        func drawLinks(_ node: MindNode) {
            for child in node.children {
                let start = NSPoint(x: node.origin.x + node.size.width, y: node.origin.y + node.size.height / 2)
                let end = NSPoint(x: child.origin.x, y: child.origin.y + child.size.height / 2)
                let path = NSBezierPath()
                path.move(to: start)
                let midX = (start.x + end.x) / 2
                path.curve(
                    to: end,
                    controlPoint1: NSPoint(x: midX, y: start.y),
                    controlPoint2: NSPoint(x: midX, y: end.y)
                )
                path.lineWidth = node.depth == 0 ? 1.6 : 1.2
                NSColor.controlAccentColor.withAlphaComponent(node.depth == 0 ? 0.55 : 0.32).setStroke()
                path.stroke()
                drawLinks(child)
            }
        }

        func drawNodes(_ node: MindNode) {
            let rect = NSRect(origin: node.origin, size: node.size)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            if node.depth == 0 {
                NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 1.6
            } else if node.depth == 1 {
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.45).setStroke()
                path.lineWidth = 1.2
            } else {
                Palette.nodeFill.setFill()
                path.fill()
                Palette.nodeStroke.setStroke()
                path.lineWidth = 1
            }
            path.stroke()
            let size = node.depth == 0 ? 14.5 : (node.depth == 1 ? 12.5 : 11.5)
            let weight: NSFont.Weight = node.depth == 0 ? .semibold : (node.depth == 1 ? .medium : .regular)
            draw(node.label, in: rect.insetBy(dx: 10, dy: 6),
                 font: .systemFont(ofSize: size, weight: weight),
                 color: .labelColor, alignment: .center)
            for child in node.children { drawNodes(child) }
        }

        return makeImage(size: NSSize(width: max(width, 320), height: max(height, 180))) {
            drawLinks(root)
            drawNodes(root)
        }
    }

    // MARK: - C4

    private static func renderC4(lines: [String]) -> NSImage? {
        var nodes: [GraphNode] = []
        var nodeIndex: [String: Int] = [:]
        var edges: [GraphEdge] = []
        var title: String?

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            if let group = groups("^title\\s*:?\\s*(.+)$", line) {
                title = cleanLabel(group[1])
                continue
            }
            if let group = groups("^(SystemDb_Ext|SystemDb|System_Ext|System|ContainerDb_Ext|ContainerDb|Container_Ext|Container|Component_Ext|Component|Person_Ext|Person)\\s*\\(\\s*([A-Za-z0-9_]+)\\s*,\\s*\"([^\"]*)\"", line) {
                let type = group[1]
                let id = group[2]
                let label = cleanLabel(group[3])
                if nodeIndex[id] == nil {
                    let tone: Tone = type.contains("_Ext") ? .muted : (type.hasPrefix("Person") ? .accent : .normal)
                    let shape: NodeShape = type.hasPrefix("Person") ? .stadium : .rounded
                    nodeIndex[id] = nodes.count
                    nodes.append(GraphNode(id: id, label: label, shape: shape, tone: tone))
                }
                continue
            }
            if let group = groups("^(?:Bi)?Rel(?:_Back|_Neighbor)?\\s*\\(\\s*([A-Za-z0-9_]+)\\s*,\\s*([A-Za-z0-9_]+)\\s*(?:,\\s*\"([^\"]*)\")?", line) {
                edges.append(GraphEdge(from: group[1], to: group[2], label: group[3].isEmpty ? nil : cleanLabel(group[3]), dashed: false))
                continue
            }
        }

        guard !nodes.isEmpty else { return nil }
        return drawGraph(nodes: nodes, edges: edges, direction: .leftRight, title: title)
    }

    // MARK: - Canvas

    private enum Palette {
        static let nodeFill = dynamic(NSColor(white: 0.97, alpha: 1), NSColor(white: 0.24, alpha: 1))
        static let mutedFill = dynamic(NSColor(white: 0.935, alpha: 1), NSColor(white: 0.19, alpha: 1))
        static let nodeStroke = dynamic(NSColor(white: 0.76, alpha: 1), NSColor(white: 0.45, alpha: 1))
        static let edge = dynamic(NSColor(white: 0.48, alpha: 1), NSColor(white: 0.66, alpha: 1))

        private static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            }
        }
    }

    private static func makeImage(size: NSSize, draw: @escaping () -> Void) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        // 自测等无 NSApplication 的场景下 NSApp 为 nil，退回当前外观。
        guard let appearance = NSApp?.effectiveAppearance
            ?? NSAppearance.current
            ?? NSAppearance(named: .aqua) else { return nil }
        return NSImage(size: size, flipped: true) { _ in
            appearance.performAsCurrentDrawingAppearance {
                draw()
            }
            return true
        }
    }

    // MARK: - Text helpers

    private static func groups(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var result: [String] = []
        for index in 0..<match.numberOfRanges {
            let groupRange = match.range(at: index)
            result.append(groupRange.location == NSNotFound ? "" : (text as NSString).substring(with: groupRange))
        }
        return result
    }

    private static func inner(_ spec: String, _ count: Int) -> String {
        guard spec.count >= count * 2 else { return spec }
        return cleanLabel(String(spec.dropFirst(count).dropLast(count)))
    }

    private static func cleanLabel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            text = String(text.dropFirst().dropLast())
        }
        text = text
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return text
    }

    private static func mindLabel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if let group = groups("^([^\\s\\(\\[\\{]+)\\s*(\\(\\(.*\\)\\)|\\(.*\\)|\\[.*\\]|\\{.*\\})$", text),
           !group[2].isEmpty {
            text = group[2]
        }
        let pairs: [(String, String)] = [("((", "))"), ("{{", "}}"), ("[", "]"), ("(", ")"), (">", "]")]
        for (open, close) in pairs where text.hasPrefix(open) && text.hasSuffix(close) {
            text = String(text.dropFirst(open.count).dropLast(close.count))
            break
        }
        return cleanLabel(text)
    }

    private static func measure(_ text: String, font: NSFont, maxWidth: CGFloat) -> NSSize {
        guard !text.isEmpty else { return .zero }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return NSSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    private static func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        NSAttributedString(string: text, attributes: attributes).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
    }
}
