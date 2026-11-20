import AppKit

/// MarkText 代码块外观：3px 圆角、1px 边框、无表头。
final class CodeBlockTextBlock: NSTextBlock {
    private let fill: NSColor
    private let stroke: NSColor
    private let radius: CGFloat

    init(fill: NSColor, stroke: NSColor, radius: CGFloat = 3) {
        self.fill = fill
        self.stroke = stroke
        self.radius = radius
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let rect = frameRect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
