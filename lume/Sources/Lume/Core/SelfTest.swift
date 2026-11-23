import AppKit
import Foundation

enum SelfTest {
    static func webImportDebugAndExit(_ raw: String) {
        Task { @MainActor in
            do {
                let article = try await WebImportService.parse(raw, allowWebKitFallback: false)
                print("title=\(article.title)")
                print("host=\(article.sourceHost)")
                print("author=\(article.author ?? "-")")
                print("images=\(article.images.count)")
                print("chars=\(article.markdown.count)")
                print("textLength=\(article.textLength)")
                let output = "/tmp/mynote-web-import.md"
                try? article.markdown.write(toFile: output, atomically: true, encoding: .utf8)
                print("wrote=\(output)")

                if let root = ProcessInfo.processInfo.environment["MYNOTE_WEB_ROOT"], !root.isEmpty {
                    let folder = ProcessInfo.processInfo.environment["MYNOTE_WEB_FOLDER"] ?? "00-收件箱"
                    let rootURL = URL(fileURLWithPath: root)
                    let markdown = try await WebImportService.materialize(
                        article, folder: folder, root: rootURL
                    ) { text in
                        print(text)
                    }
                    let paths = LibraryPaths(root: rootURL)
                    let folderURL = folder.isEmpty ? rootURL : try paths.resolve(relative: folder)
                    try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    let folderDir = URL(fileURLWithPath: folderURL.path, isDirectory: true)
                    let title = LibraryStore.sanitizeFileName(article.title)
                    let fileURL = folderDir.appendingPathComponent("\(title).md")
                    let content = Frontmatter.createDocument(
                        title: title,
                        tags: article.suggestedTags,
                        body: "# \(title)\n\n> 来源：[原文](<\(article.sourceURL.absoluteString)>)\n\n\(markdown)"
                    )
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("saved=\(fileURL.path)")

                    let pattern = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)
                    let ns = markdown as NSString
                    var local = 0
                    var missing: [String] = []
                    for match in pattern.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
                        let link = ns.substring(with: match.range(at: 1))
                        guard !link.hasPrefix("http") else { continue }
                        local += 1
                        let target = URL(string: link, relativeTo: folderDir)?.standardizedFileURL
                        guard let target else {
                            missing.append(link + " (路径无法解析)")
                            continue
                        }
                        if !FileManager.default.fileExists(atPath: target.path) {
                            missing.append(link)
                        } else if NSImage(contentsOf: target) == nil {
                            missing.append(link + " (无法解码)")
                        }
                    }
                    print("localImages=\(local) broken=\(missing.count)")
                    for item in missing { print("  broken: \(item)") }

                    let rendered = MarkdownRenderer.render(
                        content,
                        options: MarkdownRenderOptions(baseURL: folderDir)
                    )
                    var renderedImages = 0
                    rendered.enumerateAttribute(
                        .attachment,
                        in: NSRange(location: 0, length: rendered.length)
                    ) { value, _, _ in
                        if let attachment = value as? NSTextAttachment, attachment.image != nil {
                            renderedImages += 1
                        }
                    }
                    print("renderedImages=\(renderedImages)")
                }
                print("--- preview ---")
                print(String(article.markdown.prefix(1500)))
                exit(0)
            } catch {
                print("FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
        while true {
            RunLoop.main.run(until: Date().addingTimeInterval(3600))
        }
    }

    static func renderDebugAndExit(_ path: String) -> Never {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let document = Frontmatter.split(text)
        let rendered = MarkdownRenderer.render(text)
        print("hasHeader=\(document.hasHeader)")
        print("bodyPrefix=\(document.body.prefix(60).debugDescription)")
        print("renderPrefix=\(rendered.string.prefix(80).debugDescription)")
        var tableBlocks = 0
        rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle,
               style.textBlocks.contains(where: { $0 is NSTextTableBlock }) {
                tableBlocks += 1
            }
        }
        print("tableBlocks=\(tableBlocks)")

        // 等待 SwiftHighlight 异步高亮完成后重新渲染，验证「自动渲染」生效
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let upgraded = MarkdownRenderer.render(text)
        var coloredRuns = 0
        let upgradedRange = NSRange(location: 0, length: upgraded.length)
        upgraded.enumerateAttribute(.foregroundColor, in: upgradedRange) { value, _, _ in
            if let color = value as? NSColor, color != NSColor.labelColor {
                coloredRuns += 1
            }
        }
        print("coloredRuns=\(coloredRuns)")

        let probe = "struct Probe { let value: Int }"
        _ = CodeHighlightService.highlight(code: probe, language: "swift", fontSize: 12)
        let probeDeadline = Date().addingTimeInterval(1.5)
        while Date() < probeDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        print("swiftHighlightCacheHit=\(CodeHighlightService.highlight(code: probe, language: "swift", fontSize: 12) != nil)")

        let textStorage = NSTextStorage(attributedString: upgraded)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 1400), textContainer: container)
        textView.isEditable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.layoutManager?.ensureLayout(for: container)
        print("usesProvidedManager=\(textView.layoutManager === layoutManager)")
        print("usedRect=\(layoutManager.usedRect(for: container))")
        if let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) {
            textView.cacheDisplay(in: textView.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/mynote-render-debug.png"))
                print("wrote /tmp/mynote-render-debug.png")
            }
        }
        exit(0)
    }

    static func runAndExit() -> Never {
        var failures: [String] = []
        var checks = 0

        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            checks += 1
            if !condition() {
                failures.append(label)
                print("FAIL  \(label)")
            } else {
                print("ok    \(label)")
            }
        }

        let root = testRoot()
        print("Lume self-test")
        print("library: \(root.path)")

        let scanner = LibraryScanner(root: root)
        var result: ScanResult?
        do {
            result = try scanner.scan()
        } catch {
            failures.append("扫描失败：\(error.localizedDescription)")
            print("FAIL  扫描知识库：\(error.localizedDescription)")
        }

        if let result {
            print("notes: \(result.notes.count)  tags: \(result.tags.count)  top folders: \(result.folderTree.children.count)")
            check(result.notes.count >= 400, "扫描到至少 400 篇笔记（实际 \(result.notes.count)）")
            check(result.notes.allSatisfy { !$0.title.isEmpty }, "所有笔记都有标题")
            check(Set(result.notes.map(\.id)).count == result.notes.count, "笔记相对路径唯一")
            check(result.notes.allSatisfy { !$0.body.isEmpty }, "所有笔记内容非空")
            check(result.notes.allSatisfy { $0.relPath.hasSuffix(".md") }, "笔记均为 Markdown")
            check(result.tags.count >= 20, "标签数量正常（实际 \(result.tags.count)）")
            check(result.folderTree.children.contains { $0.name.hasPrefix("01-") }, "目录树包含一级分类")
            check(result.notes.contains { $0.tags.contains("Ceph") }, "Ceph 标签存在")

            let matcher = SearchMatcher(notes: result.notes)
            let cephHits = matcher.rank(result.notes, query: "ceph")
            check(cephHits.count >= 10, "搜索 ceph 命中（实际 \(cephHits.count)）")
            let tagHits = matcher.rank(result.notes, query: "#Ceph")
            check(!tagHits.isEmpty && tagHits.allSatisfy { $0.tags.contains("Ceph") }, "标签搜索 #Ceph")
            let chinese = matcher.rank(result.notes, query: "存储")
            check(!chinese.isEmpty, "中文全文搜索命中（\(chinese.count)）")
            let multi = matcher.rank(result.notes, query: "ceph 集群")
            check(multi.allSatisfy { note in
                let blob = (note.title + note.body).lowercased()
                return blob.contains("ceph") && blob.contains("集群")
            }, "多关键词同时命中")
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mynote-selftest-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            let title = "测试 \"引号\" 与 #井号"
            let doc = Frontmatter.createDocument(title: title, tags: ["存储", "Ceph"], body: "# 旧标题\n\n正文内容")
            let parsed = Frontmatter.parse(doc)
            check(parsed.title == title, "frontmatter 标题往返一致")
            check(parsed.tags == ["存储", "Ceph"], "frontmatter 标签往返一致")
            check(parsed.body.contains("正文内容"), "frontmatter 正文提取")

            let retitled = Frontmatter.setTitle("新标题", in: doc)
            check(Frontmatter.parse(retitled).title == "新标题", "更新 frontmatter 标题")
            let tagged = Frontmatter.setTags(["a", "b,c"], in: retitled)
            check(Frontmatter.parse(tagged).tags == ["a", "b,c"], "更新标签支持逗号")
            let headed = Frontmatter.setH1("新标题", in: tagged)
            check(headed.contains("\n# 新标题\n"), "同步一级标题")

            let file = tempRoot.appendingPathComponent("测试.md")
            try headed.write(to: file, atomically: true, encoding: .utf8)
            let reloaded = try LibraryScanner(root: tempRoot).scan()
            check(reloaded.notes.count == 1, "临时库扫描一篇")
            check(reloaded.notes.first?.title == "新标题", "临时库标题解析")
            check(reloaded.notes.first?.tags == ["a", "b,c"], "临时库标签解析")
            try? FileManager.default.removeItem(at: tempRoot)
        } catch {
            failures.append("临时库测试失败：\(error.localizedDescription)")
            print("FAIL  临时库测试：\(error.localizedDescription)")
        }

        let paths = LibraryPaths(root: root)
        do {
            _ = try paths.resolve(relative: "../outside.md")
            failures.append("路径安全：未能拒绝 ../outside.md")
            print("FAIL  路径安全拒绝 ../outside.md")
        } catch {
            checks += 1
            print("ok    路径安全拒绝 ../outside.md")
        }
        do {
            _ = try paths.resolve(relative: "/etc/passwd")
            failures.append("路径安全：未能拒绝绝对路径")
            print("FAIL  路径安全拒绝绝对路径")
        } catch {
            checks += 1
            print("ok    路径安全拒绝绝对路径")
        }
        do {
            let url = try paths.resolve(relative: "04-存储/Ceph")
            check(paths.contains(url), "合法相对路径解析并通过包含校验")
        } catch {
            failures.append("合法相对路径解析失败：\(error.localizedDescription)")
            print("FAIL  合法相对路径解析：\(error.localizedDescription)")
        }

        let sample = """
        # 标题

        这是 **粗体** 与 `代码`，链接 [示例](https://example.com)。

        ```bash
        ceph -s
        ```

        | 名称 | 值 |
        | --- | --- |
        | osd | 3 |

        - 项目一
        - [x] 已完成
        """
        let rendered = MarkdownRenderer.render(sample)
        check(rendered.length > 40, "Markdown 渲染输出非空（\(rendered.length) 字符）")
        check(rendered.string.contains("ceph -s"), "代码块内容保留")
        check(rendered.string.contains("osd"), "表格内容保留")
        check(rendered.string.contains("标题"), "标题内容保留")
        var codeLanguages: Set<String> = []
        rendered.enumerateAttribute(.lumeCodeLanguage, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let value = value as? String, !value.isEmpty { codeLanguages.insert(value) }
        }
        check(codeLanguages.contains("bash"), "代码块携带语言标识（实际 \(codeLanguages.sorted())）")

        let extended = MarkdownRenderer.render("""
        行内 $E = mc^2$ 与 ==高亮==，H~2~O 与 x^2^，脚注[^a]。

        > [!WARNING]
        > 告警内容
        > - 列表项

        | 左 | 中 | 右 |
        | :-- | :-: | --: |
        | a | b | c |

        <details>
        <summary>展开</summary>
        内部 **Markdown**
        </details>

        - [ ] 未完成
        - [x] 已完成

        [^a]: 第一条脚注，含公式 $x_1$。
        """)
        check(extended.string.contains("高亮") && !extended.string.contains("=="), "行内高亮语法移除标记")
        check(extended.string.contains("Warning") && !extended.string.contains("[!WARNING]"), "GitHub 告警识别为卡片")
        check(extended.string.contains("内部") && extended.string.contains("Markdown"), "details 正文渲染")
        check(extended.string.contains("第一条脚注"), "脚注定义渲染")
        var mathAttachments = 0
        var taskMarks = 0
        extended.enumerateAttribute(.attachment, in: NSRange(location: 0, length: extended.length)) { value, _, _ in
            if value is NSTextAttachment { mathAttachments += 1 }
        }
        extended.enumerateAttribute(.lumeTaskIndex, in: NSRange(location: 0, length: extended.length)) { value, _, _ in
            if value != nil { taskMarks += 1 }
        }
        check(mathAttachments >= 2, "公式渲染为图像附件（实际 \(mathAttachments)）")
        check(taskMarks == 2, "任务清单可点击索引（实际 \(taskMarks)）")

        let extra = MarkdownRenderer.render("""
        术语1
        : 术语1的解释文本

        术语2
        : 术语2的解释，可以换行
        多行描述内容

        ```
        flowchart LR
            A[开始] --> B{判断条件}
        ```

        ```
        graph TD
            subgraph 存储层
                S1[(MySQL)]
            end
            API[API服务] --> S1
        ```

        H~2~O 与 2^10^ = 1024，<u>下划线</u> 和 <span style="color:#1a237e">深蓝</span>。

        ~~删除线~~ 与 `a~b~c` 保持原样。
        """)
        let extraRange = NSRange(location: 0, length: extra.length)
        var diagramCopies = 0
        var indentedDefinitions = 0
        var subscriptRuns = 0
        var superscriptRuns = 0
        var underlinedRuns = 0
        var struckRuns = 0
        extra.enumerateAttribute(.lumeCopyLink, in: extraRange) { value, _, _ in
            if value != nil { diagramCopies += 1 }
        }
        extra.enumerateAttribute(.paragraphStyle, in: extraRange) { value, _, _ in
            if let style = value as? NSParagraphStyle, style.headIndent == 22 { indentedDefinitions += 1 }
        }
        extra.enumerateAttribute(.baselineOffset, in: extraRange) { value, _, _ in
            guard let offset = value as? CGFloat else { return }
            if offset < 0 { subscriptRuns += 1 }
            if offset > 0 { superscriptRuns += 1 }
        }
        extra.enumerateAttribute(.underlineStyle, in: extraRange) { value, _, _ in
            if value != nil { underlinedRuns += 1 }
        }
        extra.enumerateAttribute(.strikethroughStyle, in: extraRange) { value, _, _ in
            if value != nil { struckRuns += 1 }
        }
        check(!extra.string.contains("flowchart LR") && diagramCopies >= 2,
              "无语言围栏识别为 Mermaid 图表（复制入口 \(diagramCopies)）")
        check(extra.string.contains("术语1的解释文本") && !extra.string.contains(": 术语1"),
              "定义列表去掉行首冒号")
        check(indentedDefinitions > 0, "定义列表解释文本缩进（\(indentedDefinitions) 段）")
        check(extra.string.contains("H2O") && !extra.string.contains("~2~") && subscriptRuns > 0,
              "下标 ~2~ 渲染（\(subscriptRuns) 段）")
        check(extra.string.contains("1024") && !extra.string.contains("^10^") && superscriptRuns > 0,
              "上标 ^10^ 渲染（\(superscriptRuns) 段）")
        check(extra.string.contains("下划线") && !extra.string.contains("<u>") && underlinedRuns > 0,
              "行内 HTML <u> 渲染为下划线")
        check(extra.string.contains("深蓝") && !extra.string.contains("<span"),
              "行内 HTML <span> 保留文本")
        check(extra.string.contains("删除线") && struckRuns > 0, "双波浪线仍渲染为删除线（\(struckRuns) 段）")
        check(extra.string.contains("a~b~c"), "行内代码里的波浪线不被改写")

        // 标题字号随阅读字号缩放
        do {
            func maxFontSize(_ attributed: NSAttributedString) -> CGFloat {
                var size: CGFloat = 0
                attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                    if let font = value as? NSFont { size = max(size, font.pointSize) }
                }
                return size
            }
            let normal = MarkdownRenderer.render("# 标题\n\n正文", options: MarkdownRenderOptions(baseFontSize: 13.5))
            let large = MarkdownRenderer.render("# 标题\n\n正文", options: MarkdownRenderOptions(baseFontSize: 20))
            let normalSize = maxFontSize(normal)
            let largeSize = maxFontSize(large)
            check(abs(normalSize - 26) < 0.6, "标题字号基准 26（实际 \(normalSize)）")
            check(largeSize > normalSize * 1.3, "阅读字号放大后标题同步放大（\(normalSize) → \(largeSize)）")
        }

        // 超长 URL 的换行机会
        do {
            let raw = "https://example.com/some/very/long/path/to/a/resource?token=abcdefghijklmnopqrstuvwxyz0123456789"
            let renderedURL = MarkdownRenderer.render("下载地址：\(raw)")
            check(renderedURL.string.contains("\u{200B}"), "超长 URL 插入换行机会")
            var linked: URL?
            renderedURL.enumerateAttribute(.link, in: NSRange(location: 0, length: renderedURL.length)) { value, _, stop in
                if let url = value as? URL { linked = url; stop.pointee = true }
            }
            check(linked?.absoluteString == raw, "换行机会不影响链接目标（\(linked?.absoluteString ?? "nil")）")
            let shortRendered = MarkdownRenderer.render("https://example.com/a")
            check(!shortRendered.string.contains("\u{200B}"), "短链接不插入零宽空格")
        }

        // 独占一段的图片：居中并显示题注
        do {
            let imageRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("mynote-selftest-img-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: imageRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: imageRoot) }
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 60, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            )
            if let data = rep?.representation(using: .png, properties: [:]) {
                try? data.write(to: imageRoot.appendingPathComponent("diagram.png"))
                var options = MarkdownRenderOptions(baseURL: imageRoot)
                options.maxImageWidth = 300
                let figure = MarkdownRenderer.render("![示意图](diagram.png)", options: options)
                var attachments = 0
                figure.enumerateAttribute(.attachment, in: NSRange(location: 0, length: figure.length)) { value, _, _ in
                    if value is NSTextAttachment { attachments += 1 }
                }
                check(attachments == 1, "独占一段的图片渲染为附件")
                check(figure.string.contains("示意图"), "图片 alt 作为题注显示")

                // 异步模式：缺图先占位，加载完成后直接使用缓存补图
                try? data.write(to: imageRoot.appendingPathComponent("diagram-async.png"))
                var asyncOptions = MarkdownRenderOptions(baseURL: imageRoot)
                asyncOptions.maxImageWidth = 300
                asyncOptions.asynchronousImages = true
                let pending = MarkdownRenderer.render("![示意图](diagram-async.png)", options: asyncOptions)
                check(
                    pending.attribute(.lumeImagePendingURL, at: 0, effectiveRange: nil) != nil,
                    "异步模式首次渲染先显示占位"
                )
                check(
                    MarkdownImageStore.image(for: imageRoot.appendingPathComponent("diagram-async.png")) != nil,
                    "图片可同步读入共享缓存"
                )
                let filled = MarkdownRenderer.render("![示意图](diagram-async.png)", options: asyncOptions)
                check(
                    filled.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment,
                    "缓存命中后异步模式直接显示图片"
                )

                // 公众号导入的图片常无 alt 或为远程地址，渲染为空段落时不能越界读取属性
                let remoteEmptyAlt = MarkdownRenderer.render("![](https://example.com/a.png)", options: options)
                check(remoteEmptyAlt.length == 0, "无 alt 的远程图片渲染为空段落且不崩溃")
                let missingEmptyAlt = MarkdownRenderer.render("![](no-such-file.png)", options: options)
                check(missingEmptyAlt.length == 0, "无 alt 的缺失图片渲染为空段落且不崩溃")
            } else {
                check(false, "无法生成测试图片")
            }
        }

        // 快捷键存储：覆盖、唯一性、禁用与重置
        do {
            let suiteName = "Lume.selftest.shortcuts.\(UUID().uuidString)"
            if let defaults = UserDefaults(suiteName: suiteName) {
                defaults.removePersistentDomain(forName: suiteName)
                let store = ShortcutStore(defaults: defaults, storageKey: "test")
                check(store.shortcut(for: .bold)?.display == "⌘B", "默认快捷键 ⌘B")
                store.set(Shortcut(key: "j", command: true), for: .bold)
                check(store.shortcut(for: .bold)?.display == "⌘J", "自定义快捷键生效")
                let reloaded = ShortcutStore(defaults: defaults, storageKey: "test")
                check(reloaded.shortcut(for: .bold)?.display == "⌘J", "快捷键写入后重新加载仍生效")
                store.set(Shortcut(key: "i", command: true), for: .bold)
                check(store.shortcut(for: .italic) == nil, "重复组合自动从其他命令移除")
                store.set(nil, for: .bold)
                check(store.shortcut(for: .bold) == nil && store.shortcut(for: .italic) == nil,
                      "清空组合后两项都不占用")
                store.resetAll()
                check(store.shortcut(for: .bold)?.display == "⌘B" && store.shortcut(for: .italic)?.display == "⌘I",
                      "恢复默认后还原内置组合")
                defaults.removePersistentDomain(forName: suiteName)
            } else {
                check(false, "无法创建临时 UserDefaults")
            }
        }

        // 网页导入：正文提取与 HTML→Markdown
        do {
            let html = """
            <html><head>
            <title>页面标题</title>
            <meta property="og:title" content="测试文章标题">
            <meta name="keywords" content="GPU, 运维, GPU">
            </head><body>
            <nav>站内导航</nav>
            <div id="js_content">
            <h1>测试文章标题</h1>
            <section style="display: flex"><span style="display:block">01</span><span style="display:block">PART</span><span style="display:block">一、故障排查</span></section>
            <p>正文第一段，说明 GPU 故障排查的入口和观测顺序。这一段故意写长一些，确保正文评分高于页面其他区域，也覆盖中文标点与<strong>加粗</strong>内容。</p>
            <p>正文第二段包含 <a href="/rel/path?x=1&amp;y=2">相对链接</a>，以及行内代码 <code>nvidia-smi -q</code>。</p>
            <p><img data-src="https://mmbiz.qpic.cn/img/640?wx_fmt=png&amp;tp=webp" alt="示意图"></p>
            <pre><code class="language-bash">ceph -s
            ceph osd tree</code></pre>
            <ul><li>第一项</li><li>第二项<ul><li>嵌套项</li></ul></li></ul>
            <table><tr><th>观测点</th><th>含义</th></tr><tr><td>ECC</td><td>显存纠错</td></tr></table>
            <blockquote>引用内容</blockquote>
            </div>
            </body></html>
            """
            let pageURL = URL(string: "https://example.com/post/1")!
            let output = try ArticleExtractor.extract(html: html, pageURL: pageURL)
            check(output.title == "测试文章标题", "网页标题提取（\(output.title)）")
            check(!output.markdown.contains("# 测试文章标题") && output.markdown.contains("一、故障排查"),
                  "网页正文去掉重复大标题")
            check(output.markdown.hasPrefix("一、故障排查") && !output.markdown.contains("PART"),
                  "网页正文去掉开头装饰标签（01/PART）")
            check(!output.markdown.contains("站内导航"), "网页导航噪声已移除")
            check(output.markdown.contains("**加粗**"), "网页 strong 转 Markdown")
            check(output.markdown.contains("[相对链接](https://example.com/rel/path?x=1&y=2)"),
                  "网页相对链接补全为绝对地址")
            check(output.markdown.contains("```bash"), "网页代码块保留语言")
            check(output.markdown.contains("  - 嵌套项"), "网页嵌套列表缩进")
            check(output.markdown.contains("| 观测点 | 含义 |") && output.markdown.contains("| ECC | 显存纠错 |"),
                  "网页表格转 GFM")
            check(output.markdown.contains("> 引用内容"), "网页引用块转 Markdown")
            check(output.images.count == 1
                  && output.images.first?.url.absoluteString.contains("wx_fmt=png") == true
                  && output.images.first?.url.absoluteString.contains("tp=webp") == false,
                  "网页懒加载图片转本地占位并去掉 webp 参数")
            check(output.markdown.contains("lume-img://0"), "网页图片占位符写入正文")
            check(output.suggestedTags == ["GPU", "运维"], "网页关键词去重为标签建议")
            check(WebImportService.normalizeURL("mp.weixin.qq.com/s/abc")?.absoluteString == "https://mp.weixin.qq.com/s/abc",
                  "网页地址自动补全 https")
            check(WebImportService.normalizeURL("ftp://example.com/a") == nil, "非 http 地址被拒绝")
        } catch {
            check(false, "网页导入解析失败：\(error.localizedDescription)")
        }

        // 网页导入：CSDN 正文容器优先，推荐位与页头噪声不进正文
        do {
            let html = """
            <html><head>
            <title>CSDN 测试文章完整标题-CSDN博客</title>
            <meta property="og:title" content="CSDN 测试文章">
            <meta property="article:published_time" content="2026-11-20T20:14:46+08:00">
            <meta name="keywords" content="html,前端">
            </head><body>
            <main>
            <div class="article-header-box">
            <h1 class="title-article" id="articleContentId">CSDN 测试文章完整标题</h1>
            <a id="uid" title="某作者">某作者</a>阅读量 123 收藏 4
            </div>
            <article class="baidu_pl">
            <div class="article_content clearfix">
            <div id="content_views" class="htmledit_views">
            <p>CSDN 正文第一段，说明语义化标签在实际页面中的作用与常见误区，篇幅需要足够长，避免正文容器被页头或推荐位抢走评分。</p>
            <p>CSDN 正文第二段，继续补充 header 与 nav 的适用场景、可访问性收益以及和 div 的取舍建议。</p>
            <h4>2. nav 导航区域</h4>
            <pre><code>&lt;nav&gt;navigate&lt;/nav&gt;</code></pre>
            </div>
            </div>
            </article>
            <div class="recommend-box"><div class="recommend-item-box">推荐阅读：其他文章标题</div></div>
            </main>
            </body></html>
            """
            let output = try ArticleExtractor.extract(
                html: html,
                pageURL: URL(string: "https://blog.csdn.net/someone/article/details/1")!
            )
            check(output.title == "CSDN 测试文章完整标题", "CSDN 标题取 h1 完整标题（\(output.title)）")
            check(output.author == "某作者", "CSDN 作者取 uid 标题（\(output.author ?? "nil")）")
            check(output.publishedAt == "2026-11-20T20:14:46+08:00", "CSDN 发布时间取 meta")
            check(output.markdown.contains("CSDN 正文第一段"), "CSDN 正文容器内容保留")
            check(!output.markdown.contains("推荐阅读"), "CSDN 推荐位不进入正文")
            check(!output.markdown.contains("阅读量 123"), "CSDN 页头统计不进入正文")
            check(output.suggestedTags == ["html", "前端"], "CSDN 关键词作为标签建议")
        } catch {
            check(false, "CSDN 网页导入解析失败：\(error.localizedDescription)")
        }

        // 网页导入：开头导流与文末推广截断
        do {
            let html = """
            <html><head>
            <meta property="og:title" content="推广截断测试">
            </head><body>
            <div id="js_content">
            <p>★ 点击名片，关注我们不迷路 ★</p>
            <p>这段正文用于验证文末推广截断逻辑：正文第一段解释为什么需要去掉公众号导流，说明文末资料包和二维码会把正文撑得很长，也会下载一批与文章内容无关的推广图片。这一段继续补充细节，确保正文长度超过两百个字符，从而触发百分之六十的位置判断，同时验证正常内容不会被误删。</p>
            <p>正文第二段继续陈述：文章真正有价值的部分应当保留，包括命令、结论和作者观点；推广信息则应当被截断，避免污染搜索索引和阅读体验。为保证测试稳定，这里再多写一些内容，让正文总长度明确超过两百个字符，同时保持语义通顺。</p>
            <p><img data-src="https://mmbiz.qpic.cn/body.png" alt="正文配图"></p>
            <hr>
            <section>
            <p>近期好文：</p>
            <p>另一篇文章的标题链接。</p>
            <p><img data-src="https://mmbiz.qpic.cn/qrcode.png" alt="二维码"></p>
            <p>“点赞”+“红心”，让我元气满满</p>
            </section>
            </div>
            </body></html>
            """
            let output = try ArticleExtractor.extract(
                html: html,
                pageURL: URL(string: "https://mp.weixin.qq.com/s/promo")!
            )
            check(!output.markdown.contains("点击名片"), "开头导流名片行已移除")
            check(!output.markdown.contains("近期好文") && !output.markdown.contains("点赞"),
                  "文末近期好文推广已截断")
            check(output.markdown.contains("正文第二段继续陈述"), "截断保留正文全部段落")
            check(output.images.count == 1
                  && output.images.first?.url.absoluteString.contains("body.png") == true,
                  "文末推广图片不进入下载列表")
            check(!output.markdown.hasSuffix("---"), "截断后不残留分隔线")
        } catch {
            check(false, "推广截断解析失败：\(error.localizedDescription)")
        }

        // 网页导入：文末福利资料包（封面 + 多张截图 + 二维码）整段移除
        do {
            let html = """
            <html><head>
            <meta property="og:title" content="文末福利测试">
            </head><body>
            <div id="js_content">
            <div class="article-body">
            <p>这篇文章的正文全部保留：先描述时间同步的测量模型，再解释 chrony 的滤波策略与内核时钟接口。为了让位置判断落在正文之后，这里继续补充足够长的正文内容，确保标记词出现时已经超过全文的百分之六十，也保证截断后剩余正文不少于两百个字。</p>
            <p>第二段继续说明生产环境基线、硬件时间戳与四维拆解方法。这些内容都是真正的技术细节，需要在导入后完整保留，不能因为文末存在推广资料包就被误删，因此测试同时校验正文段落仍然存在。</p>
            <section>
            <p><img data-src="https://mmbiz.qpic.cn/cover.jpg" alt="封面"></p>
            <p>文末福利</p>
            <p>今天分享一份很长的学习笔记，需要的尽管收藏。</p>
            <h2>笔记介绍</h2>
            <p><img data-src="https://mmbiz.qpic.cn/page1.png" alt="笔记截图"></p>
            <h2>笔记展示</h2>
            <p><img data-src="https://mmbiz.qpic.cn/page2.png" alt="笔记截图"></p>
            <h2>笔记下载</h2>
            <p>扫描下方二维码，回复暗号领取。</p>
            <p><img data-src="https://mmbiz.qpic.cn/qr.png" alt="二维码"></p>
            </section>
            </div>
            </div>
            </body></html>
            """
            let output = try ArticleExtractor.extract(
                html: html,
                pageURL: URL(string: "https://mp.weixin.qq.com/s/fuli")!
            )
            check(output.markdown.contains("先描述时间同步的测量模型"), "外层容器中的正文不被误删")
            check(!output.markdown.contains("文末福利") && !output.markdown.contains("笔记下载"),
                  "文末福利资料包整段移除")
            check(output.markdown.contains("第二段继续说明生产环境基线"), "资料包前面的正文保留")
            check(output.images.isEmpty && !output.markdown.contains("lume-img://"),
                  "资料包图片不下载也不留占位")
        } catch {
            check(false, "文末福利截断解析失败：\(error.localizedDescription)")
        }

        // 网页导入：正文中间出现“推荐阅读”不误伤
        do {
            let html = """
            <html><head>
            <meta property="og:title" content="正常文章测试">
            </head><body>
            <div id="js_content">
            <p>正文第一段说明推荐系统的召回与排序并不是本文重点，这里只是顺带提到推荐阅读相关的话题，用来说明段落中间的普通词汇不应该触发截断逻辑，正文需要完整保留下来。这一段继续补充背景，让全文长度超过两百个字符，确保位置判断真正参与计算，而不是被长度下限直接跳过。</p>
            <h2>推荐阅读</h2>
            <p>正文第二段继续讨论渲染性能、图片加载与缓存策略，并给出具体的观测命令和调优建议，确保文章在导入后仍然保留全部章节与内容结构，不因为标题命中关键词而被截掉后半部分。这里再补充一些说明，让后半段也有足够的篇幅，便于验证截断逻辑确实没有执行。</p>
            </div>
            </body></html>
            """
            let output = try ArticleExtractor.extract(
                html: html,
                pageURL: URL(string: "https://mp.weixin.qq.com/s/normal")!
            )
            check(output.markdown.contains("## 推荐阅读") && output.markdown.contains("正文第二段继续讨论"),
                  "正文中段的推荐标题不触发截断")
        } catch {
            check(false, "正常文章解析失败：\(error.localizedDescription)")
        }

        let taskText = """
        - [ ] 一
        ```text
        - [ ] 代码内不算
        ```
        - [x] 二
        """
        let taskLocations = LibraryStore.taskMarkerLocations(in: taskText)
        check(taskLocations.count == 2, "任务标记定位跳过代码围栏（实际 \(taskLocations.count)）")
        check(taskLocations.count == 2
              && (taskText as NSString).substring(with: NSRange(location: taskLocations[1], length: 1)) == "x",
              "任务标记位置指向勾选状态字符")

        // 悬停复制图标：同一代码块内切换行时图标位置与像素不变
        do {
            let source = "```bash\nceph -s\nceph osd tree\n```\n"
            let storage = NSTextStorage(attributedString: MarkdownRenderer.render(source))
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            let container = NSTextContainer(size: NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude))
            container.widthTracksTextView = true
            layout.addTextContainer(container)
            let view = PreviewTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 400), textContainer: container)
            view.isEditable = false
            view.isSelectable = true
            view.updateInsets(for: 520)
            let window = NSWindow(
                contentRect: NSRect(x: -4000, y: -4000, width: 520, height: 400),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.contentView = view
            layout.ensureLayout(for: container)

            var block = NSRange(location: NSNotFound, length: 0)
            storage.enumerateAttribute(.lumeCopyCode, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                if value != nil, block.location == NSNotFound {
                    block = range
                    stop.pointee = true
                }
            }
            let glyphs = layout.glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            let blockRect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let origin = view.textContainerOrigin
            let iconRect = NSRect(
                x: origin.x + container.size.width - 22 - 10,
                y: origin.y + blockRect.minY - 4,
                width: 22,
                height: 22
            ).insetBy(dx: -8, dy: -8)

            func hover(_ point: NSPoint) {
                guard let event = NSEvent.mouseEvent(
                    with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
                ) else { return }
                view.mouseMoved(with: event)
            }
            func iconPixels() -> Data? {
                guard let rep = view.bitmapImageRepForCachingDisplay(in: iconRect) else { return nil }
                view.cacheDisplay(in: iconRect, to: rep)
                return rep.representation(using: .png, properties: [:])
            }

            view.resetHover()
            let idle = iconPixels()
            let firstFragment = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let lastFragment = layout.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            let x = origin.x + container.size.width / 2
            hover(view.convert(NSPoint(x: x, y: origin.y + firstFragment.midY), to: nil))
            let first = iconPixels()
            hover(view.convert(NSPoint(x: x, y: origin.y + lastFragment.midY), to: nil))
            let second = iconPixels()

            check(block.location != NSNotFound && blockRect.height > 20, "预览代码块可定位悬停区域")
            check(idle != nil && first != nil && first != idle, "悬停代码块显示复制图标")
            check(first != nil && second == first, "同一代码块内切换行图标不闪")
        }

        if let result {
            var renderFailures = 0
            for note in result.notes.prefix(40) {
                let renderedNote = MarkdownRenderer.render(
                    note.body,
                    options: MarkdownRenderOptions(baseURL: note.url.deletingLastPathComponent())
                )
                if renderedNote.length == 0 { renderFailures += 1 }
            }
            check(renderFailures == 0, "抽样渲染 40 篇笔记均有输出")
        }

        print("")
        if failures.isEmpty {
            print("PASS  \(checks) checks")
            exit(0)
        } else {
            print("FAILED  \(failures.count)/\(checks) checks")
            exit(1)
        }
    }

    private static func testRoot() -> URL {
        if let index = CommandLine.arguments.firstIndex(of: "--root"),
           index + 1 < CommandLine.arguments.count {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        if let env = ProcessInfo.processInfo.environment["MYNOTE_ROOT"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Notes/MyNote")
    }
}
