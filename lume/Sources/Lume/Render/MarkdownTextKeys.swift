import Foundation

extension NSAttributedString.Key {
    /// 代码块“复制”点击区域携带的原始代码。
    static let lumeCopyCode = NSAttributedString.Key("LumeCopyCode")
    /// 预览中可点击的“复制源码”链接文本（如图表下方的复制入口）。
    static let lumeCopyLink = NSAttributedString.Key("LumeCopyLink")
    /// 代码块的标注语言（如 swift、bash），用于在预览中显示语言角标。
    static let lumeCodeLanguage = NSAttributedString.Key("LumeCodeLanguage")
    /// 代码块对应的高亮缓存键，异步高亮完成后按块原地补色，无需整篇重渲染。
    static let lumeCodeHighlightKey = NSAttributedString.Key("LumeCodeHighlightKey")
    /// 预览中的图片附带本地文件地址，用于点击放大。
    static let lumeImageURL = NSAttributedString.Key("LumeImageURL")
    /// 图片在图库中的原始像素尺寸，供窗口缩放时重新排版。
    static let lumeImagePixelSize = NSAttributedString.Key("LumeImagePixelSize")
    /// 任务清单复选框在文档中的序号（从 0 开始），点击时用于回写。
    static let lumeTaskIndex = NSAttributedString.Key("LumeTaskIndex")
}

extension Notification.Name {
    /// 代码已复制到剪贴板，附带 message 字符串。
    static let lumeCodeCopied = Notification.Name("LumeCodeCopied")
    /// 预览中点击任务复选框，object 为任务序号。
    static let lumeToggleTask = Notification.Name("LumeToggleTask")
}
