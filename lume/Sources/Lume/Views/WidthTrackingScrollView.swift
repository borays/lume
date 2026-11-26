import AppKit

/// 文本视图放进滚动视图后，文档宽度必须始终等于裁剪区宽度。
/// 用旧 SDK 链接时 AppKit 只会按增量拉伸文档视图（初始宽度 + 窗格宽），
/// 窄窗格下正文被挤出可视区并出现横向滚动，这里每次布局都强制对齐。
final class WidthTrackingScrollView: NSScrollView {
    override func layout() {
        super.layout()
        syncDocumentWidth()
    }

    private func syncDocumentWidth() {
        guard let documentView else { return }
        let width = contentView.bounds.width
        guard width > 1 else { return }
        if abs(documentView.frame.width - width) > 0.5 {
            var frame = documentView.frame
            frame.size.width = width
            documentView.frame = frame
        }
        let origin = contentView.bounds.origin
        if origin.x != 0 {
            contentView.scroll(to: NSPoint(x: 0, y: origin.y))
        }
    }
}
