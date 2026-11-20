import AppKit

enum PDFExporter {
    static func export(markdown: String, baseURL: URL?, to url: URL, title: String) throws {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792)
        printInfo.topMargin = 54
        printInfo.bottomMargin = 54
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let contentWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 792), textContainer: container)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        var options = MarkdownRenderOptions()
        options.baseURL = baseURL
        options.maxImageWidth = contentWidth
        options.baseFontSize = 12
        options.isPrinting = true
        let attributed = MarkdownRenderer.render(markdown, options: options)
        textStorage.setAttributedString(attributed)
        layoutManager.ensureLayout(for: container)

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        if !operation.run() {
            throw NSError(domain: "MyNote", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "打印服务未能生成 PDF"
            ])
        }
    }
}
