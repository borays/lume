import SwiftUI

struct EditorFormatBar: View {
    @ObservedObject private var bridge = EditorBridge.shared
    @ObservedObject private var shortcuts = ShortcutStore.shared

    private static let codeLanguages: [(label: String, fence: String)] = [
        ("代码块", ""),
        ("Swift", "swift"),
        ("Shell", "bash"),
        ("Python", "python"),
        ("SQL", "sql"),
        ("YAML", "yaml"),
        ("JSON", "json"),
        ("Go", "go"),
        ("Rust", "rust"),
        ("Nginx", "nginx"),
        ("Diff", "diff"),
        ("Markdown", "markdown")
    ]

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    headingMenu
                    separator
                    iconButton("bold", tip(.bold, "加粗")) { bridge.toggleWrap("**") }
                    iconButton("italic", tip(.italic, "斜体")) { bridge.toggleWrap("*") }
                    iconButton("strikethrough", tip(.strikethrough, "删除线")) { bridge.toggleStrike() }
                    iconButton("highlighter", tip(.highlight, "高亮（==文字==）")) { bridge.toggleHighlight() }
                    iconButton("chevron.left.forwardslash.chevron.right", tip(.inlineCode, "行内代码")) { bridge.toggleWrap("`") }
                    separator
                    iconButton("text.quote", tip(.quote, "引用")) { bridge.applyQuote() }
                    iconButton("list.bullet", tip(.bulletList, "项目符号")) { bridge.applyList(ordered: false) }
                    iconButton("list.number", tip(.numberedList, "编号列表")) { bridge.applyList(ordered: true) }
                    iconButton("checklist", tip(.taskList, "任务列表")) { bridge.applyTaskList() }
                    separator
                    iconButton("link", tip(.link, "插入链接")) { bridge.insertLink() }
                    iconButton("photo", tip(.image, "插入图片")) { bridge.insertImage() }
                    iconButton("paperclip", "插入附件") { bridge.insertAttachment() }
                    iconButton("tablecells", tip(.table, "插入表格")) { bridge.insertTable() }
                    mathMenu
                    iconButton("number.circle", tip(.footnote, "插入脚注（自动编号）")) { bridge.insertFootnote() }
                    alertMenu
                    codeMenu
                    diagramMenu
                    iconButton("minus", tip(.divider, "插入分隔线")) { bridge.insertDivider() }
                    iconButton("calendar", tip(.date, "插入当前日期")) { bridge.insertDate() }

                    Spacer(minLength: 8)
                    separator

                    fontSizeControls
                }
                .frame(minWidth: proxy.size.width - 28, minHeight: proxy.size.height, alignment: .leading)
                .padding(.horizontal, 14)
            }
        }
        .frame(height: 34)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.55))
                .frame(height: 0.5)
        }
    }

    private var headingMenu: some View {
        Menu {
            Button("正文") { bridge.setHeading(level: 0) }
            Divider()
            Button("一级标题") { bridge.setHeading(level: 1) }
            Button("二级标题") { bridge.setHeading(level: 2) }
            Button("三级标题") { bridge.setHeading(level: 3) }
            Button("四级标题") { bridge.setHeading(level: 4) }
            Button("五级标题") { bridge.setHeading(level: 5) }
            Button("六级标题") { bridge.setHeading(level: 6) }
        } label: {
            HStack(spacing: 3) {
                Text("标题")
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("段落样式：正文与标题")
    }

    private var codeMenu: some View {
        Menu {
            ForEach(Self.codeLanguages, id: \.fence) { item in
                Button(item.label) {
                    if item.fence.isEmpty {
                        bridge.toggleCodeBlock()
                    } else {
                        bridge.insertCodeBlock(language: item.fence)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .frame(width: 34, height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("插入代码块，可指定语言以获得语法着色")
    }

    private var mathMenu: some View {
        Menu {
            Button("行内公式 $…$") { bridge.toggleInlineMath() }
            Button("块级公式 $$…$$") { bridge.insertBlockMath() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "function")
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .frame(width: 34, height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("插入 LaTeX 公式：行内 $…$ 或块级 $$…$$")
    }

    private var alertMenu: some View {
        Menu {
            Button("Note 提示") { bridge.insertAlert(kind: "NOTE") }
            Button("Tip 技巧") { bridge.insertAlert(kind: "TIP") }
            Button("Important 重点") { bridge.insertAlert(kind: "IMPORTANT") }
            Button("Warning 警告") { bridge.insertAlert(kind: "WARNING") }
            Button("Caution 注意") { bridge.insertAlert(kind: "CAUTION") }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .frame(width: 34, height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("插入 GitHub 告警卡片：Note / Tip / Important / Warning / Caution")
    }

    private var diagramMenu: some View {
        Menu {
            ForEach(EditorBridge.diagramTemplates, id: \.title) { item in
                Button(item.title) { bridge.insertDiagram(item.code) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "flowchart")
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
            .frame(width: 34, height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("插入 Mermaid 图表：流程图、时序图、状态图、ER 图、甘特图、Git 图、脑图、C4 架构图")
    }

    private var fontSizeControls: some View {
        HStack(spacing: 2) {
            Button {
                bridge.adjustFontSize(by: -1)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("缩小编辑区字号")

            Text("\(Int(bridge.fontSize))")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 16)
                .help("编辑区当前字号，点击恢复默认")
                .onTapGesture { bridge.resetFontSize() }

            Button {
                bridge.adjustFontSize(by: 1)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("放大编辑区字号")
        }
        .padding(.horizontal, 4)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }

    private func tip(_ id: AppCommandID, _ title: String) -> String {
        guard let display = shortcuts.display(for: id) else { return title }
        return "\(title)（\(display)）"
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.5))
            .frame(width: 0.5, height: 15)
            .padding(.horizontal, 4)
    }
}
