import AppKit

/// A compact native LaTeX renderer covering the math used in technical notes.
/// It follows MarkText/KaTeX syntax for the common subset (symbols, scripts,
/// fractions, roots, text, aligned environments) and falls back to literal text
/// for unsupported commands, so notes never lose content.
enum MathRenderer {
    struct Rendered {
        let image: NSImage
        let size: CGSize
        let descent: CGFloat
    }

    private final class CacheBox {
        let rendered: Rendered
        init(_ rendered: Rendered) { self.rendered = rendered }
    }

    private static let cache = NSCache<NSString, CacheBox>()

    static func render(_ latex: String, fontSize: CGFloat, display: Bool, color: NSColor) -> Rendered? {
        let source = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }
        let appearance = NSApp?.effectiveAppearance.name.rawValue ?? "aqua"
        let key = "\(source)|\(fontSize)|\(display)|\(appearance)|\(color == .labelColor ? "label" : "custom")" as NSString
        if let hit = cache.object(forKey: key) { return hit.rendered }

        let parser = MathParser(source: source, fontSize: fontSize, display: display)
        guard let box = parser.parse(), box.width > 0, box.ascent + box.descent > 0 else { return nil }
        guard let rendered = draw(box, color: color, fontSize: fontSize) else { return nil }
        cache.setObject(CacheBox(rendered), forKey: key)
        return rendered
    }

    private static func draw(_ box: MathBox, color: NSColor, fontSize: CGFloat) -> Rendered? {
        let padding: CGFloat = 1
        let width = ceil(box.width) + padding * 2
        let height = ceil(box.ascent + box.descent) + padding * 2
        let scale: CGFloat = 2

        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: max(1, Int(width * scale)),
                  pixelsHigh: max(1, Int(height * scale)),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ) else { return nil }
        rep.size = NSSize(width: width, height: height)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.translateBy(x: padding, y: padding)
        context.shouldAntialias = true
        box.draw(in: context.cgContext, origin: .zero, baseline: box.descent, color: color)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.cacheMode = .always
        return Rendered(
            image: image,
            size: CGSize(width: width, height: height),
            descent: box.descent + padding
        )
    }
}

// MARK: - Fonts

private enum MathFont {
    static func regular(size: CGFloat) -> NSFont {
        NSFont(name: "STIXGeneral", size: size)
            ?? NSFont(name: "TimesNewRomanPSMT", size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    static func italic(size: CGFloat) -> NSFont {
        NSFont(name: "STIXGeneral-Italic", size: size)
            ?? NSFont(name: "TimesNewRomanPS-ItalicMT", size: size)
            ?? NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
    }

    static func bold(size: CGFloat) -> NSFont {
        NSFont(name: "STIXGeneral-Bold", size: size)
            ?? NSFont(name: "TimesNewRomanPS-BoldMT", size: size)
            ?? NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .boldFontMask)
    }
}

// MARK: - Boxes

private class MathBox {
    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0

    var height: CGFloat { ascent + descent }

    func draw(in context: CGContext, origin: CGPoint, baseline: CGFloat, color: NSColor) {}

    var isEmpty: Bool { width <= 0 }
}

private final class TextMathBox: MathBox {
    private let attributed: NSAttributedString

    init(_ string: String, font: NSFont, color: NSColor) {
        self.attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        super.init()
        let size = attributed.size()
        width = ceil(size.width)
        ascent = max(font.ascender, ceil(size.height + font.descender))
        descent = max(-font.descender, 0)
    }

    override func draw(in context: CGContext, origin: CGPoint, baseline: CGFloat, color: NSColor) {
        // `draw(at:)` anchors the bottom of the line fragment, not the baseline.
        attributed.draw(at: CGPoint(x: origin.x, y: baseline - descent))
    }
}

private final class HorizontalMathBox: MathBox {
    private let children: [(box: MathBox, spacing: CGFloat)]

    init(_ children: [(MathBox, CGFloat)]) {
        self.children = children
        super.init()
        ascent = children.map(\.0.ascent).max() ?? 0
        descent = children.map(\.0.descent).max() ?? 0
        width = children.reduce(0) { $0 + $1.0.width + $1.1 }
    }

    override func draw(in context: CGContext, origin: CGPoint, baseline: CGFloat, color: NSColor) {
        var x = origin.x
        for child in children {
            child.box.draw(in: context, origin: CGPoint(x: x, y: origin.y), baseline: baseline, color: color)
            x += child.box.width + child.spacing
        }
    }
}

private final class ScriptMathBox: MathBox {
    private let base: MathBox
    private var superscript: MathBox?
    private var subscriptBox: MathBox?
    private let scriptSize: CGFloat

    init(base: MathBox, scriptSize: CGFloat) {
        self.base = base
        self.scriptSize = scriptSize
        super.init()
        layout()
    }

    func setSuperscript(_ box: MathBox) {
        superscript = box
        layout()
    }

    func setSubscript(_ box: MathBox) {
        subscriptBox = box
        layout()
    }

    private func layout() {
        let supShift = max(base.ascent * 0.45, scriptSize * 0.42)
        let subShift = -max(base.descent + scriptSize * 0.18, scriptSize * 0.12)
        let supTop = superscript.map { supShift + $0.ascent } ?? 0
        let subBottom = subscriptBox.map { subShift - $0.descent } ?? 0
        ascent = max(base.ascent, supTop)
        descent = max(base.descent, -subBottom)
        width = base.width + max(superscript?.width ?? 0, subscriptBox?.width ?? 0) + 1
    }

    override func draw(in context: CGContext, origin: CGPoint, baseline: CGFloat, color: NSColor) {
        base.draw(in: context, origin: origin, baseline: baseline, color: color)
        let scriptX = origin.x + base.width
        if let superscript {
            superscript.draw(
                in: context,
                origin: CGPoint(x: scriptX, y: origin.y),
                baseline: baseline + max(base.ascent * 0.45, scriptSize * 0.42),
                color: color
            )
        }
        if let subscriptBox {
            subscriptBox.draw(
                in: context,
                origin: CGPoint(x: scriptX, y: origin.y),
                baseline: baseline - max(base.descent + scriptSize * 0.18, scriptSize * 0.12),
                color: color
            )
        }
    }
}

private final class FractionMathBox: MathBox {
    private let numerator: MathBox
    private let denominator: MathBox
    private let barThickness: CGFloat

    init(numerator: MathBox, denominator: MathBox, fontSize: CGFloat) {
        self.numerator = numerator
        self.denominator = denominator
        self.barThickness = max(0.6, fontSize * 0.045)
        super.init()
        width = max(numerator.width, denominator.width) + 6
        ascent = numerator.height + 4
        descent = denominator.height + 4
    }

    override func draw(in context: CGContext, origin: CGPoint, baseline: CGFloat, color: NSColor) {
        let barY = baseline
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: origin.x + 1, y: barY, width: width - 2, height: barThickness))
        let numX = origin.x + (width - numerator.width) / 2
        numerator.draw(in: context, origin: CGPoint(x: numX, y: origin.y),
                       baseline: barY + 3 + numerator.descent, color: color)
        let denX = origin.x + (width - denominator.width) / 2
        denominator.draw(in: context, origin: CGPoint(x: denX, y: origin.y),
                         baseline: barY - 3 - denominator.ascent, color: color)
    }
}

private final class RadicalMathBox: MathBox {
    private let content: MathBox
    private let radical: TextMathBox

    init(content: MathBox, fontSize: CGFloat, color: NSColor) {
        self.content = content
        let radicalSize = max(fontSize * 0.9, content.height * 0.92)
        self.radical = TextMathBox("√", font: MathFont.regular(size: radicalSize), color: color)
        super.init()
        ascent = content.ascent + 2
        descent = content.descent + 1
        width = radical.width + content.width + 1
    }

    override func draw(in context: CGContext, origin: CGPoint, baseline: CGFloat, color: NSColor) {
        radical.draw(in: context, origin: origin, baseline: baseline - content.descent + radical.descent, color: color)
        let contentX = origin.x + radical.width - 1
        content.draw(in: context, origin: CGPoint(x: contentX, y: origin.y), baseline: baseline, color: color)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.7)
        context.move(to: CGPoint(x: contentX, y: baseline + content.ascent + 1))
        context.addLine(to: CGPoint(x: contentX + content.width + 1, y: baseline + content.ascent + 1))
        context.strokePath()
    }
}

private final class SpaceMathBox: MathBox {
    init(width: CGFloat) {
        super.init()
        self.width = max(0, width)
    }
}

private final class StackMathBox: MathBox {
    private let rows: [MathBox]
    private let spacing: CGFloat

    init(rows: [MathBox], spacing: CGFloat) {
        self.rows = rows
        self.spacing = spacing
        super.init()
        let total = rows.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        ascent = total
        descent = rows.last?.descent ?? 0
        width = rows.map(\.width).max() ?? 0
    }

    override func draw(in context: CGContext, origin: CGPoint, baseline: CGFloat, color: NSColor) {
        var y = baseline + ascent - (rows.first?.ascent ?? 0)
        for (offset, row) in rows.enumerated() {
            if offset > 0 { y -= spacing + row.ascent }
            row.draw(in: context, origin: CGPoint(x: origin.x, y: origin.y), baseline: y, color: color)
            y -= row.descent
        }
    }
}

// MARK: - Parser

private final class MathParser {
    private enum FontStyle {
        case italic
        case upright
        case bold
    }

    private let characters: [Character]
    private var position = 0
    private let fontSize: CGFloat
    private let display: Bool
    private var fontStyle: FontStyle = .italic

    init(source: String, fontSize: CGFloat, display: Bool) {
        self.characters = Array(source)
        self.fontSize = fontSize
        self.display = display
    }

    func parse() -> MathBox? {
        let box = parseSequence(stop: nil)
        guard !box.isEmpty else { return nil }
        return box
    }

    private func parseSequence(stop: Character?) -> MathBox {
        var atoms: [MathBox] = []
        while position < characters.count {
            let character = characters[position]
            if let stop, character == stop { break }
            if character == "}" { break }
            if character.isWhitespace {
                position += 1
                continue
            }
            if character == "^" || character == "_" {
                position += 1
                guard let script = parseScriptArgument() else { continue }
                let base = atoms.popLast() ?? SpaceMathBox(width: 0)
                if let existing = base as? ScriptMathBox {
                    if character == "^" {
                        existing.setSuperscript(script)
                    } else {
                        existing.setSubscript(script)
                    }
                    atoms.append(existing)
                } else {
                    let wrapper = ScriptMathBox(base: base, scriptSize: fontSize * 0.68)
                    if character == "^" {
                        wrapper.setSuperscript(script)
                    } else {
                        wrapper.setSubscript(script)
                    }
                    atoms.append(wrapper)
                }
                continue
            }
            if let atom = parseAtom() {
                atoms.append(atom)
            }
        }
        return makeHorizontal(atoms)
    }

    private func parseAtom() -> MathBox? {
        guard position < characters.count else { return nil }
        let character = characters[position]

        if character == "{" {
            position += 1
            let box = parseSequence(stop: "}")
            if position < characters.count, characters[position] == "}" { position += 1 }
            return box
        }

        if character == "\\" {
            return parseCommand()
        }

        position += 1
        if character.isNumber || character == "." {
            var number = String(character)
            while position < characters.count,
                  characters[position].isNumber || characters[position] == "." {
                number.append(characters[position])
                position += 1
            }
            return text(number, style: .upright)
        }

        if character.isLetter {
            return text(String(character), style: fontStyle == .upright ? .upright : .italic)
        }

        switch character {
        case "-": return text("−", style: .upright)
        case "*": return text("∗", style: .upright)
        case "'": return text("′", style: .upright)
        case "~": return SpaceMathBox(width: fontSize * 0.28)
        case "&": return SpaceMathBox(width: fontSize * 0.5)
        case "`": return nil
        default: return text(String(character), style: .upright)
        }
    }

    private func parseScriptArgument() -> MathBox? {
        while position < characters.count, characters[position].isWhitespace { position += 1 }
        guard position < characters.count else { return nil }
        if characters[position] == "{" {
            position += 1
            let box = parseSequence(stop: "}")
            if position < characters.count, characters[position] == "}" { position += 1 }
            return box
        }
        return parseAtom()
    }

    private func parseCommand() -> MathBox? {
        position += 1
        guard position < characters.count else { return text("\\", style: .upright) }
        let start = position
        if characters[position].isLetter {
            while position < characters.count, characters[position].isLetter { position += 1 }
        } else {
            position += 1
        }
        let name = String(characters[start..<position])

        if let symbol = Self.symbols[name] {
            return text(symbol, style: Self.uprightCommands.contains(name) ? .upright : .italic)
        }

        switch name {
        case "frac", "dfrac", "tfrac":
            guard let numerator = parseGroupBox(), let denominator = parseGroupBox() else {
                return text("\\\(name)", style: .upright)
            }
            return FractionMathBox(numerator: numerator, denominator: denominator, fontSize: fontSize)
        case "sqrt":
            skipOptionalBracket()
            guard let content = parseGroupBox() else { return text("√", style: .upright) }
            return RadicalMathBox(content: content, fontSize: fontSize, color: .labelColor)
        case "text", "textrm", "operatorname":
            guard let raw = parseRawGroup() else { return nil }
            return text(raw, style: .upright)
        case "mathbf", "bm":
            return parseStyledGroup(.bold)
        case "mathrm", "mathup":
            return parseStyledGroup(.upright)
        case "mathit":
            return parseStyledGroup(.italic)
        case "left", "right":
            return parseDelimiter()
        case "begin":
            return parseEnvironment()
        case "overline":
            guard let content = parseGroupBox() else { return nil }
            let box = HorizontalMathBox([(content, 0)])
            box.width = max(box.width, 1)
            return box
        case "quad": return SpaceMathBox(width: fontSize)
        case "qquad": return SpaceMathBox(width: fontSize * 2)
        case "enspace": return SpaceMathBox(width: fontSize * 0.5)
        case "thinspace": return SpaceMathBox(width: fontSize * 0.17)
        case ",", ";", ":", " ":
            return SpaceMathBox(width: fontSize * (name == ";" ? 0.28 : 0.17))
        case "!": return SpaceMathBox(width: -fontSize * 0.08)
        case "\\": return SpaceMathBox(width: fontSize * 0.5)
        case "sin", "cos", "tan", "cot", "sec", "csc",
             "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
             "log", "ln", "lg", "exp", "lim", "max", "min", "sup", "inf",
             "det", "gcd", "lcm", "mod", "bmod", "arg", "dim", "ker", "deg", "Pr":
            return text(name, style: .upright)
        default:
            return text("\\\(name)", style: .upright)
        }
    }

    private func parseStyledGroup(_ style: FontStyle) -> MathBox? {
        let previous = fontStyle
        fontStyle = style
        defer { fontStyle = previous }
        return parseGroupBox() ?? parseAtom()
    }

    private func parseGroupBox() -> MathBox? {
        while position < characters.count, characters[position].isWhitespace { position += 1 }
        guard position < characters.count else { return nil }
        if characters[position] == "{" {
            position += 1
            let box = parseSequence(stop: "}")
            if position < characters.count, characters[position] == "}" { position += 1 }
            return box
        }
        return parseAtom()
    }

    private func parseRawGroup() -> String? {
        while position < characters.count, characters[position].isWhitespace { position += 1 }
        guard position < characters.count, characters[position] == "{" else {
            guard position < characters.count else { return nil }
            let character = characters[position]
            position += 1
            return String(character)
        }
        position += 1
        var depth = 1
        var result = ""
        var escaped = false
        while position < characters.count, depth > 0 {
            let character = characters[position]
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "{" {
                depth += 1
                result.append(character)
            } else if character == "}" {
                depth -= 1
                if depth > 0 { result.append(character) }
            } else {
                result.append(character)
            }
            position += 1
        }
        return result
    }

    private func skipOptionalBracket() {
        guard position < characters.count, characters[position] == "[" else { return }
        while position < characters.count, characters[position] != "]" { position += 1 }
        if position < characters.count { position += 1 }
    }

    private func parseDelimiter() -> MathBox? {
        while position < characters.count, characters[position].isWhitespace { position += 1 }
        guard position < characters.count else { return nil }
        let character = characters[position]
        if character == "\\" {
            position += 1
            guard position < characters.count else { return nil }
            let name = String(characters[position])
            position += 1
            return text(Self.symbols[name] ?? name, style: .upright)
        }
        position += 1
        if character == "." { return nil }
        return text(String(character), style: .upright)
    }

    private func parseEnvironment() -> MathBox? {
        guard let rawName = parseRawGroup() else { return nil }
        let close = "\\end{\(rawName)}"
        var depth = 1
        var raw = ""
        while position < characters.count {
            if characters[position] == "\\" {
                let rest = String(characters[position...])
                if rest.hasPrefix("\\begin{") { depth += 1 }
                if rest.hasPrefix(close) {
                    depth -= 1
                    if depth == 0 {
                        position += close.count
                        break
                    }
                }
            }
            raw.append(characters[position])
            position += 1
        }

        let rows = raw.components(separatedBy: "\\\\")
        var rowBoxes: [MathBox] = []
        for row in rows where !row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cells = row.components(separatedBy: "&")
            let cellBoxes = cells.map { cell -> MathBox in
                let parser = MathParser(source: cell, fontSize: fontSize, display: display)
                return parser.parse() ?? SpaceMathBox(width: 0)
            }
            rowBoxes.append(HorizontalMathBox(cellBoxes.map { ($0, fontSize * 0.9) }))
        }
        return StackMathBox(rows: rowBoxes, spacing: fontSize * 0.35)
    }

    private func text(_ string: String, style: FontStyle) -> MathBox {
        let font: NSFont
        switch style {
        case .italic: font = MathFont.italic(size: fontSize)
        case .upright: font = MathFont.regular(size: fontSize)
        case .bold: font = MathFont.bold(size: fontSize)
        }
        return TextMathBox(string, font: font, color: .labelColor)
    }

    private func makeHorizontal(_ atoms: [MathBox]) -> MathBox {
        guard !atoms.isEmpty else { return SpaceMathBox(width: 0) }
        if atoms.count == 1 { return atoms[0] }
        return HorizontalMathBox(atoms.map { ($0, 0) })
    }

    private static let uprightCommands: Set<String> = [
        "sin", "cos", "tan", "log", "ln", "lim", "max", "min"
    ]

    private static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ",
        "varepsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ",
        "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
        "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ",
        "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "ϕ", "varphi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators and relations
        "times": "×", "div": "÷", "cdot": "⋅", "pm": "±", "mp": "∓", "ast": "∗",
        "star": "⋆", "circ": "∘", "bullet": "∙", "oplus": "⊕", "ominus": "⊖",
        "otimes": "⊗", "oslash": "⊘", "odot": "⊙", "le": "≤", "leq": "≤",
        "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "approx": "≈", "sim": "∼",
        "simeq": "≃", "cong": "≅", "equiv": "≡", "propto": "∝", "ll": "≪",
        "gg": "≫", "subset": "⊂", "supset": "⊃", "subseteq": "⊆",
        "supseteq": "⊇", "in": "∈", "notin": "∉", "ni": "∋", "perp": "⊥",
        "parallel": "∥", "mid": "∣", "nmid": "∤", "prec": "≺", "succ": "≻",
        "infty": "∞", "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃",
        "nexists": "∄", "emptyset": "∅", "varnothing": "∅", "neg": "¬",
        "land": "∧", "lor": "∨", "wedge": "∧", "vee": "∨", "cap": "∩", "cup": "∪",
        "setminus": "∖", "therefore": "∴", "because": "∵",
        // Arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←",
        "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "Leftrightarrow": "⇔", "implies": "⟹", "iff": "⟺", "longrightarrow": "⟶",
        "longleftarrow": "⟵", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        "nearrow": "↗", "searrow": "↘", "swarrow": "↙", "nwarrow": "↖",
        // Big operators
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬",
        "iiint": "∭", "oint": "∮", "bigcup": "⋃", "bigcap": "⋂",
        "bigoplus": "⨁", "bigotimes": "⨂", "bigvee": "⋁", "bigwedge": "⋀",
        // Misc
        "ldots": "…", "dots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱",
        "prime": "′", "degree": "°", "angle": "∠", "triangle": "△",
        "square": "□", "checkmark": "✓", "dagger": "†", "ddagger": "‡",
        "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ",
        "wp": "℘", "surd": "√", "top": "⊤", "bot": "⊥", "vdash": "⊢",
        "models": "⊨", "colon": ":", "langle": "⟨", "rangle": "⟩",
        "lceil": "⌈", "rceil": "⌉", "lfloor": "⌊", "rfloor": "⌋",
        "vert": "|", "Vert": "‖", "lvert": "|", "rvert": "|",
        "lbrack": "[", "rbrack": "]", "lbrace": "{", "rbrace": "}",
        "backslash": "∖", "quad": " ", "%": "%", "$": "$", "&": "&", "#": "#",
        "{": "{", "}": "}", "_": "_", "|": "‖",
        // Accents applied as combining marks
        "hat": "\u{0302}", "bar": "\u{0304}", "vec": "\u{20D7}", "dot": "\u{0307}",
        "ddot": "\u{0308}", "tilde": "\u{0303}"
    ]
}
