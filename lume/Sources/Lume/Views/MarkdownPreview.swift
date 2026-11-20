import AppKit
import Quartz
import SwiftUI

struct MarkdownPreview: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?
    var title: String? = nil
    var fontFamily: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = PreviewTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 600), textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.updateInsets(for: 600)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.refresh = { [weak scrollView, weak textView, weak coordinator = context.coordinator] in
            guard let scrollView, let textView else { return }
            Self.renderSource(
                markdown: markdown,
                title: title,
                baseURL: baseURL,
                fontFamily: fontFamily,
                scrollView: scrollView,
                textView: textView,
                preserveScroll: true,
                coordinator: coordinator
            )
        }
        textView.onWidthChange = { [weak coordinator = context.coordinator] _ in
            DispatchQueue.main.async {
                coordinator?.adjustImageWidths()
                coordinator?.scheduleWidthRefresh()
            }
        }
        context.coordinator.observeHighlightUpdates()
        render(context: context, scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.scrollView = scrollView
        context.coordinator.refresh = { [weak scrollView, weak textView, weak coordinator = context.coordinator] in
            guard let scrollView, let textView else { return }
            Self.renderSource(
                markdown: markdown,
                title: title,
                baseURL: baseURL,
                fontFamily: fontFamily,
                scrollView: scrollView,
                textView: textView,
                preserveScroll: true,
                coordinator: coordinator
            )
        }
        render(context: context, scrollView: scrollView, textView: textView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    private static func renderSource(
        markdown: String,
        title: String?,
        baseURL: URL?,
        fontFamily: String,
        scrollView: NSScrollView,
        textView: NSTextView,
        preserveScroll: Bool,
        coordinator: Coordinator?
    ) {
        let source = MarkdownRenderer.bodyWithoutTitleHeading(markdown, title: title)
        let origin = preserveScroll ? scrollView.contentView.bounds.origin : .zero
        let selection = textView.selectedRange()
        var options = MarkdownRenderOptions()
        options.baseURL = baseURL
        options.maxImageWidth = Self.availableContentWidth(scrollView: scrollView, textView: textView)
        options.baseFontSize = 14
        options.baseFontFamily = fontFamily.isEmpty ? nil : fontFamily
        let attributed = MarkdownRenderer.render(source, options: options)
        textView.textStorage?.setAttributedString(attributed)
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
        }
        coordinator?.patchedHighlightKeys.removeAll()
        Self.restoreSelection(textView, selection)
        (textView as? PreviewTextView)?.refreshHoverAtMouse()
        textView.window?.invalidateCursorRects(for: textView)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        // 记录本次渲染对应的缓存键，否则下一次 updateNSView 会再做一次全量渲染，
        // 高亮/宽度刷新后用户会看到颜色连闪两次。
        coordinator?.lastMarkdown = Self.cacheKey(
            source: source,
            title: title,
            fontFamily: fontFamily,
            width: scrollView.contentSize.width
        )
        coordinator?.lastBaseURL = baseURL
    }

    private static func cacheKey(source: String, title: String?, fontFamily: String, width: CGFloat) -> String {
        let appearance = NSApp.effectiveAppearance.name.rawValue
        return source + "\u{1F}" + (title ?? "") + "\u{1F}" + appearance + "\u{1F}"
            + String(Int(width.rounded())) + "\u{1F}" + fontFamily
    }

    private static func availableContentWidth(scrollView: NSScrollView, textView: NSTextView) -> CGFloat {
        if let width = textView.textContainer?.containerSize.width, width > 80 {
            return max(140, width - 16)
        }
        return max(140, scrollView.contentSize.width - 92)
    }

    /// 重渲染会清空选区，这里把用户选中的文字按新长度裁剪后还回去。
    private static func restoreSelection(_ textView: NSTextView, _ selection: NSRange) {
        guard selection.length > 0, let storage = textView.textStorage else { return }
        let limit = storage.length
        guard selection.location < limit else { return }
        let length = min(selection.length, limit - selection.location)
        guard length > 0 else { return }
        textView.setSelectedRange(NSRange(location: selection.location, length: length))
    }

    private func render(context: Context, scrollView: NSScrollView, textView: NSTextView) {
        let coordinator = context.coordinator
        let source = MarkdownRenderer.bodyWithoutTitleHeading(markdown, title: title)
        let cacheKey = Self.cacheKey(source: source, title: title, fontFamily: fontFamily, width: scrollView.contentSize.width)
        let baseChanged = coordinator.lastBaseURL != baseURL
        guard coordinator.lastMarkdown != cacheKey || baseChanged else {
            return
        }

        let visibleOrigin = baseChanged ? NSPoint.zero : scrollView.contentView.bounds.origin
        let selection = textView.selectedRange()
        var options = MarkdownRenderOptions()
        options.baseURL = baseURL
        options.maxImageWidth = Self.availableContentWidth(scrollView: scrollView, textView: textView)
        options.baseFontSize = 14
        options.baseFontFamily = fontFamily.isEmpty ? nil : fontFamily
        let attributed = MarkdownRenderer.render(source, options: options)
        textView.textStorage?.setAttributedString(attributed)
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
        }
        coordinator.patchedHighlightKeys.removeAll()
        Self.restoreSelection(textView, selection)
        (textView as? PreviewTextView)?.refreshHoverAtMouse()
        textView.window?.invalidateCursorRects(for: textView)
        scrollView.contentView.scroll(to: visibleOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        coordinator.lastMarkdown = cacheKey
        coordinator.lastBaseURL = baseURL
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var lastMarkdown: String?
        var lastBaseURL: URL?
        var refresh: (() -> Void)?
        /// 本次渲染里已经补过色的代码块，避免同一段高亮结果被反复写回。
        var patchedHighlightKeys = Set<String>()
        private var lastImageWidth: CGFloat = 0
        private var pendingWidthRefresh: DispatchWorkItem?
        private var pendingHighlightRefresh: DispatchWorkItem?
        private var highlightObserver: NSObjectProtocol?

        // Code block header tabs are absolute points, so they need a full re-render once resizing settles.
        func scheduleWidthRefresh() {
            pendingWidthRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastMarkdown = nil
                self.refresh?()
            }
            pendingWidthRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        func adjustImageWidths() {
            guard let textView, let scrollView, let storage = textView.textStorage else { return }
            let width = MarkdownPreview.availableContentWidth(scrollView: scrollView, textView: textView)
            guard abs(width - lastImageWidth) >= 1 else { return }
            lastImageWidth = width
            let origin = scrollView.contentView.bounds.origin
            MarkdownRenderer.resizeImages(in: storage, maxWidth: width)
            if let container = textView.textContainer, let layout = textView.layoutManager {
                layout.ensureLayout(for: container)
            }
            scrollView.contentView.scroll(to: origin)
        }

        func observeHighlightUpdates() {
            highlightObserver = NotificationCenter.default.addObserver(
                forName: .lumeCodeHighlightUpdated,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleHighlightRefresh()
            }
        }

        /// 异步高亮完成后按块原地补色：不重建 attributedString，
        /// 所以选区、滚动位置和悬停按钮都不会被打断。
        private func scheduleHighlightRefresh() {
            pendingHighlightRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applyCachedHighlights()
            }
            pendingHighlightRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func applyCachedHighlights() {
            guard let textView,
                  let storage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            var targets: [(NSRange, NSAttributedString)] = []
            storage.enumerateAttribute(
                .lumeCodeHighlightKey,
                in: NSRange(location: 0, length: storage.length)
            ) { value, range, _ in
                guard let key = value as? String,
                      !patchedHighlightKeys.contains(key),
                      let cached = CodeHighlightService.cached(key: key),
                      range.length > 0 else { return }
                targets.append((range, cached))
                patchedHighlightKeys.insert(key)
            }
            guard !targets.isEmpty else { return }

            var dirty = NSRect.zero
            let text = storage.string as NSString
            for (range, cached) in targets {
                let length = min(cached.length, range.length)
                guard length > 0,
                      text.substring(with: NSRange(location: range.location, length: length))
                          == (cached.string as NSString).substring(to: length) else { continue }
                let source = NSRange(location: 0, length: length)
                var location = 0
                while location < length {
                    var run = NSRange()
                    let attributes = cached.attributes(at: location, longestEffectiveRange: &run, in: source)
                    let target = NSRange(location: range.location + run.location, length: run.length)
                    for (name, value) in attributes
                    where name == .font || name == .foregroundColor || name == .backgroundColor {
                        storage.addAttribute(name, value: value, range: target)
                    }
                    location = NSMaxRange(run)
                }
                let glyphs = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: range.location, length: length),
                    actualCharacterRange: nil
                )
                dirty = dirty.union(layoutManager.boundingRect(forGlyphRange: glyphs, in: container))
            }
            guard dirty != .zero else { return }
            dirty.origin.x += textView.textContainerOrigin.x
            dirty.origin.y += textView.textContainerOrigin.y
            textView.setNeedsDisplay(dirty.insetBy(dx: -10, dy: -10))
        }

        func stopObserving() {
            pendingWidthRefresh?.cancel()
            pendingWidthRefresh = nil
            pendingHighlightRefresh?.cancel()
            pendingHighlightRefresh = nil
            if let highlightObserver {
                NotificationCenter.default.removeObserver(highlightObserver)
                self.highlightObserver = nil
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NotificationCenter.default.post(name: .mynoteOpenLink, object: url)
                return true
            }
            if let string = link as? String, let url = URL(string: string) {
                NotificationCenter.default.post(name: .mynoteOpenLink, object: url)
                return true
            }
            return false
        }
    }
}

final class PreviewTextView: NSTextView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let maxContentWidth: CGFloat = 740
    private let minimumInset: CGFloat = 28
    var onWidthChange: ((CGFloat) -> Void)?
    private(set) var previewURL: URL?

    private var hoverRange: NSRange?
    private var hoverCode: String?
    private var hoverIconRect: NSRect = .zero
    private var hoverTrackingArea: NSTrackingArea?

    private static let copyButtonFill = NSColor(name: "mynote.code.copy.fill") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x4E / 255, green: 0x4F / 255, blue: 0x50 / 255, alpha: 1)
            : NSColor.white
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousWidth = frame.width
        super.setFrameSize(newSize)
        updateInsets(for: newSize.width)
        if abs(newSize.width - previousWidth) > 6 {
            onWidthChange?(newSize.width)
        }
    }

    func updateInsets(for width: CGFloat) {
        let inset = max(minimumInset, (width - maxContentWidth) / 2)
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: 28)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // 尺寸没变就复用现有区域；反复 remove/add 会让 AppKit 合成
        // entered/exited 事件，悬停状态被不断打断。
        if let hoverTrackingArea, hoverTrackingArea.rect == bounds { return }
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        resetHover()
        super.mouseExited(with: event)
    }

    /// 只重绘悬停按钮（含语言角标让位）所在的那一行，避免整篇文档反复重画。
    private func invalidateHoverStrip(oldRect: NSRect, newRect: NSRect) {
        var strip = oldRect.union(newRect)
        if strip == .zero { return }
        strip = strip.insetBy(dx: -140, dy: -28)
        strip = strip.intersection(visibleRect)
        guard strip.width > 0, strip.height > 0 else { return }
        setNeedsDisplay(strip)
    }

    func resetHover() {
        guard hoverRange != nil || hoverIconRect != .zero else { return }
        let old = hoverIconRect
        hoverRange = nil
        hoverCode = nil
        hoverIconRect = .zero
        window?.invalidateCursorRects(for: self)
        invalidateHoverStrip(oldRect: old, newRect: .zero)
    }

    /// 重渲染后按鼠标当前位置重新判定悬停，复制图标不会先消失再出现。
    func refreshHoverAtMouse() {
        guard window != nil else {
            resetHover()
            return
        }
        updateHover(at: convert(NSEvent.mouseLocation, from: nil))
    }

    private func updateHover(at point: NSPoint) {
        guard let storage = textStorage, let layoutManager, let container = textContainer else {
            resetHover()
            return
        }
        var range: NSRange?
        var code: String?
        if let index = characterIndex(at: point),
           storage.attribute(.lumeCopyLink, at: index, effectiveRange: nil) == nil,
           let c = storage.attribute(.lumeCopyCode, at: index, effectiveRange: nil) as? String {
            var effRange = NSRange()
            storage.attribute(.lumeCopyCode, at: index, effectiveRange: &effRange)
            range = effRange
            code = c
        }
        if range == nil {
            // 单行代码块行尾右侧命中不到字符，按整行几何范围兜底，
            // 保证鼠标横向移动到复制按钮途中图标不消失。
            for hit in codeBlockHits() where hit.rect.contains(point) {
                range = hit.range
                code = hit.code
                break
            }
        }
        guard let range, let code else {
            resetHover()
            return
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        blockRect.origin.x += textContainerOrigin.x
        blockRect.origin.y += textContainerOrigin.y
        // 悬停热区扩展到整个段落宽度，文字之外的空白区同样属于这个代码块。
        let hitRect = NSRect(
            x: 0,
            y: blockRect.minY,
            width: textContainerOrigin.x + container.size.width,
            height: blockRect.height
        )
        guard hitRect.insetBy(dx: 0, dy: -16).contains(point) else {
            resetHover()
            return
        }
        let size: CGFloat = 22
        let iconRect = NSRect(
            x: textContainerOrigin.x + container.size.width - size - 10,
            y: blockRect.minY - 4,
            width: size,
            height: size
        )
        if range != hoverRange || iconRect != hoverIconRect {
            let old = hoverIconRect
            hoverRange = range
            hoverCode = code
            hoverIconRect = iconRect
            window?.invalidateCursorRects(for: self)
            invalidateHoverStrip(oldRect: old, newRect: iconRect)
        }
    }

    private struct CodeBlockHit {
        let range: NSRange
        let code: String
        let rect: NSRect
    }

    private func codeBlockHits() -> [CodeBlockHit] {
        guard let storage = textStorage, let layoutManager, let container = textContainer else { return [] }
        var hits: [CodeBlockHit] = []
        storage.enumerateAttribute(
            .lumeCopyCode,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard let code = value as? String,
                  storage.attribute(.lumeCopyLink, at: range.location, effectiveRange: nil) == nil else {
                return
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var runRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            runRect.origin.x += textContainerOrigin.x
            runRect.origin.y += textContainerOrigin.y
            // 热区与 updateHover 一致：整行宽度，上下各扩 16。
            hits.append(
                CodeBlockHit(
                    range: range,
                    code: code,
                    rect: NSRect(
                        x: 0,
                        y: runRect.minY - 16,
                        width: textContainerOrigin.x + container.size.width,
                        height: runRect.height + 32
                    )
                )
            )
        }
        return hits
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawLanguageBadges(in: dirtyRect)
        drawCopyLinkButtons(in: dirtyRect)
        guard hoverRange != nil, hoverIconRect != .zero else { return }
        drawCopyButton(in: hoverIconRect, symbolPointSize: 10.5)
    }

    private static var copySymbolCache: [String: NSImage] = [:]

    /// layer-backed 视图里禁止 lockFocus，图标按外观缓存一次，绘制时直接复用。
    private static func tintedCopySymbol(pointSize: CGFloat) -> NSImage? {
        let appearance = NSApp.effectiveAppearance.name.rawValue
        let key = appearance + "|" + String(Int(pointSize * 10))
        if let cached = copySymbolCache[key] {
            return cached
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let base = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.secondaryLabelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        copySymbolCache[key] = tinted
        return tinted
    }

    private func drawCopyButton(in button: NSRect, symbolPointSize: CGFloat) {
        let fill = NSBezierPath(roundedRect: button, xRadius: 4, yRadius: 4)
        Self.copyButtonFill.setFill()
        fill.fill()
        RenderTheme.codeBorder.setStroke()
        fill.lineWidth = 1
        fill.stroke()

        guard let image = Self.tintedCopySymbol(pointSize: symbolPointSize) else { return }
        let origin = NSPoint(
            x: button.midX - image.size.width / 2,
            y: button.midY - image.size.height / 2
        )
        image.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private struct CopyLinkButton {
        let rect: NSRect
        let code: String
    }

    private func copyLinkButtons() -> [CopyLinkButton] {
        guard let storage = textStorage, let layoutManager, let container = textContainer else { return [] }
        var buttons: [CopyLinkButton] = []
        storage.enumerateAttribute(
            .lumeCopyLink,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard value != nil,
                  let code = storage.attribute(.lumeCopyCode, at: range.location, effectiveRange: nil) as? String else {
                return
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var runRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            runRect.origin.x += textContainerOrigin.x
            runRect.origin.y += textContainerOrigin.y
            let side: CGFloat = 18
            buttons.append(
                CopyLinkButton(
                    rect: NSRect(
                        x: runRect.midX - side / 2,
                        y: runRect.midY - side / 2,
                        width: side,
                        height: side
                    ),
                    code: code
                )
            )
        }
        return buttons
    }

    private func drawCopyLinkButtons(in dirtyRect: NSRect) {
        for button in copyLinkButtons() where button.rect.intersects(dirtyRect) {
            drawCopyButton(in: button.rect, symbolPointSize: 10)
        }
    }

    private func drawLanguageBadges(in dirtyRect: NSRect) {
        guard let storage = textStorage, let layoutManager, let container = textContainer else { return }
        let text = storage.string as NSString
        var location = 0
        while location < text.length {
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            text.getParagraphStart(
                &paragraphStart,
                end: &paragraphEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            let isBlockStart = paragraphStart == 0
                || storage.attribute(.lumeCopyCode, at: paragraphStart - 1, effectiveRange: nil) == nil
            if isBlockStart,
               let language = storage.attribute(.lumeCodeLanguage, at: paragraphStart, effectiveRange: nil) as? String,
               !language.isEmpty {
                drawLanguageBadge(
                    language,
                    paragraphStart: paragraphStart,
                    layoutManager: layoutManager,
                    container: container,
                    dirtyRect: dirtyRect
                )
            }
            location = max(paragraphEnd, paragraphStart + 1)
        }
    }

    private func drawLanguageBadge(
        _ language: String,
        paragraphStart: Int,
        layoutManager: NSLayoutManager,
        container: NSTextContainer,
        dirtyRect: NSRect
    ) {
        guard let storage = textStorage else { return }
        let paragraphRange = (storage.string as NSString).paragraphRange(
            for: NSRange(location: paragraphStart, length: 0)
        )
        let glyphRange = layoutManager.glyphRange(forCharacterRange: paragraphRange, actualCharacterRange: nil)
        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        lineRect.origin.x += textContainerOrigin.x
        lineRect.origin.y += textContainerOrigin.y
        guard lineRect.height > 0 else { return }

        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = (language as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 6
        let height = ceil(size.height) + 2
        let badge = NSRect(
            x: textContainerOrigin.x + container.size.width - size.width - horizontalPadding * 2 - 12,
            y: lineRect.midY - height / 2,
            width: size.width + horizontalPadding * 2,
            height: height
        )
        guard badge.intersects(dirtyRect) else { return }
        // 鼠标悬停时该角落换成复制按钮，语言角标让位。
        guard !(hoverIconRect != .zero && hoverIconRect.intersects(badge)) else { return }

        let path = NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3)
        RenderTheme.codeBackground.setFill()
        path.fill()
        (language as NSString).draw(
            at: NSPoint(x: badge.minX + horizontalPadding, y: badge.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if hoverRange != nil, hoverIconRect != .zero {
            addCursorRect(hoverIconRect, cursor: .pointingHand)
        }
        for button in copyLinkButtons() {
            addCursorRect(button.rect, cursor: .pointingHand)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let code = codeBlockString(at: convert(event.locationInWindow, from: nil)) {
            let menu = NSMenu()
            let item = NSMenuItem(title: "复制代码", action: #selector(copyCodeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            menu.addItem(item)
            return menu
        }
        return super.menu(for: event)
    }

    @objc private func copyCodeFromMenu(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        copyToPasteboard(code)
    }

    private func codeBlockString(at point: NSPoint) -> String? {
        guard let storage = textStorage, let index = characterIndex(at: point) else { return nil }
        return storage.attribute(.lumeCopyCode, at: index, effectiveRange: nil) as? String
    }

    private func copyToPasteboard(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        NotificationCenter.default.post(name: .lumeCodeCopied, object: nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hoverRange != nil, hoverIconRect.contains(point), let code = hoverCode {
            copyToPasteboard(code)
            return
        }
        if let button = copyLinkButtons().first(where: { $0.rect.contains(point) }) {
            copyToPasteboard(button.code)
            return
        }
        if let index = characterIndex(at: point) {
            let attributes = textStorage?.attributes(at: index, effectiveRange: nil) ?? [:]
            if let url = attributes[.lumeImageURL] as? URL {
                previewURL = url
                if let panel = QLPreviewPanel.shared() {
                    panel.makeKeyAndOrderFront(nil)
                }
                return
            }
            if let taskIndex = attributes[.lumeTaskIndex] as? Int {
                NotificationCenter.default.post(name: .lumeToggleTask, object: taskIndex)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let adjusted = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let index = layoutManager.characterIndex(
            for: adjusted,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard index >= 0, index < (textStorage?.length ?? 0) else { return nil }
        return index
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        previewURL != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}
