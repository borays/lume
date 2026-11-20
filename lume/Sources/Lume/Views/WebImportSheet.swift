import AppKit
import SwiftUI

@MainActor
final class WebImportModel: ObservableObject {
    enum Phase: Equatable {
        case input
        case working(String)
        case review
        case importing(String)
    }

    @Published var urlString = ""
    @Published var title = ""
    @Published var folder = ""
    @Published var tagsText = ""
    @Published var phase: Phase = .input
    @Published var errorText: String?
    @Published private(set) var article: WebArticle?

    private var task: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .working, .importing: return true
        case .input, .review: return false
        }
    }

    var parsedTags: [String] {
        tagsText.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func configure(folder: String) {
        if self.folder.isEmpty { self.folder = folder }
    }

    func prefillFromPasteboard() {
        guard urlString.isEmpty,
              let text = NSPasteboard.general.string(forType: .string),
              WebImportService.normalizeURL(text) != nil else { return }
        urlString = text
    }

    func parse() {
        guard !isBusy else { return }
        guard WebImportService.normalizeURL(urlString) != nil else {
            errorText = WebImportError.invalidURL.localizedDescription
            return
        }
        errorText = nil
        article = nil
        phase = .working("正在获取网页…")
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let article = try await WebImportService.parse(self.urlString)
                guard !Task.isCancelled else { return }
                self.article = article
                self.title = article.title
                self.tagsText = article.suggestedTags.joined(separator: ", ")
                self.phase = .review
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = error.localizedDescription
                self.phase = .input
            }
        }
    }

    func backToInput() {
        guard !isBusy else { return }
        phase = .input
        errorText = nil
    }

    func cancelWork() {
        task?.cancel()
        task = nil
        switch phase {
        case .working:
            phase = article == nil ? .input : .review
        case .importing:
            phase = .review
        case .input, .review:
            break
        }
    }

    func importArticle(into store: LibraryStore, completion: @escaping () -> Void) {
        guard let article, !isBusy else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorText = "标题不能为空"
            return
        }
        errorText = nil
        phase = .importing("正在准备导入…")
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let folder = self.folder
                let markdown = try await WebImportService.materialize(
                    article,
                    folder: folder,
                    root: store.rootURL
                ) { [weak self] text in
                    self?.phase = .importing(text)
                }
                guard !Task.isCancelled else { return }
                if store.importWebNote(
                    title: cleanTitle,
                    folder: folder,
                    tags: self.parsedTags,
                    body: markdown,
                    sourceURL: article.sourceURL
                ) {
                    completion()
                } else {
                    self.phase = .review
                    self.errorText = store.errorMessage ?? "导入失败"
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .review
                self.errorText = error.localizedDescription
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

struct WebImportSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = WebImportModel()
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
            if let error = model.errorText {
                errorBanner(error)
            }
        }
        .padding(24)
        .frame(width: 720)
        .onAppear {
            model.configure(folder: store.defaultNewNoteFolder)
            model.prefillFromPasteboard()
            urlFocused = true
        }
        .onDisappear {
            model.cancelWork()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("导入网页")
                .font(.system(size: 20, weight: .semibold))
            Text("把公开网页的正文解析为 Markdown，图片下载到知识库 assets 目录，离线也能查看。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .input:
            inputView
        case .working(let text):
            workingView(text)
        case .review:
            if let article = model.article {
                reviewView(article)
            }
        case .importing(let text):
            workingView(text)
        }
    }

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("网页地址") {
                HStack(spacing: 8) {
                    TextField("https://mp.weixin.qq.com/s/…", text: $model.urlString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13.5))
                        .controlSize(.large)
                        .focused($urlFocused)
                        .onSubmit { model.parse() }
                    Button("解析") { model.parse() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isBusy)
                }
            }
            Text("支持微信公众号文章、技术博客等公开页面；需要登录或人机验证的页面可能无法直接解析。")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.top, 2)
    }

    private func workingView(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Button("取消") { model.cancelWork() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func reviewView(_ article: WebArticle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(article.sourceHost)
                    .font(.system(size: 12, weight: .medium))
                Text(article.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(article.textLength) 字 · \(article.images.count) 张图片")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            field("标题") {
                TextField("标题", text: $model.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13.5))
            }

            HStack(alignment: .top, spacing: 16) {
                field("保存目录") {
                    Picker("", selection: $model.folder) {
                        ForEach(store.folderOptions) { option in
                            Text(option.indent + option.name).tag(option.path)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(width: 260)

                field("标签（可选）") {
                    TextField("用逗号分隔", text: $model.tagsText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if !model.parsedTags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(model.parsedTags, id: \.self) { tag in
                        TagChip(tag: tag)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Markdown 预览")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("导入时会把图片替换为本地路径")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                ScrollView {
                    Text(previewText(article))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                }
                .frame(height: 230)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.8)
                )
            }

            HStack {
                Button("重新输入") { model.backToInput() }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入笔记") {
                    model.importArticle(into: store) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func previewText(_ article: WebArticle) -> String {
        let limit = 2600
        if article.markdown.count <= limit { return article.markdown }
        return String(article.markdown.prefix(limit)) + "\n\n…（预览只显示前 \(limit) 字）"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
