import AppKit
import Foundation
import WebKit

enum WebPageFetcher {
    struct Page {
        let html: String
        let finalURL: URL
    }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static func fetchWithSession(_ url: URL) async throws -> Page {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...399).contains(http.statusCode) {
            throw WebImportError.fetchFailed("网页返回状态码 \(http.statusCode)")
        }
        guard !data.isEmpty else {
            throw WebImportError.fetchFailed("网页内容为空")
        }
        return Page(
            html: decodeHTML(data, response: response),
            finalURL: response.url ?? url
        )
    }

    @MainActor
    static func fetchWithWebKit(_ url: URL, timeout: TimeInterval = 30) async throws -> Page {
        try await WebKitPageLoader().load(url: url, timeout: timeout)
    }

    static func imageRequest(_ url: URL, referer: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    private static func decodeHTML(_ data: Data, response: URLResponse) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let text = String(data: data, encoding: gb18030) {
            return text
        }
        return ""
    }
}

@MainActor
private final class WebKitPageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<WebPageFetcher.Page, Error>?
    private var timeoutTask: Task<Void, Never>?

    func load(url: URL, timeout: TimeInterval) async throws -> WebPageFetcher.Page {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            let webView = WKWebView(
                frame: NSRect(x: 0, y: 0, width: 1280, height: 900),
                configuration: configuration
            )
            webView.customUserAgent = WebPageFetcher.userAgent
            webView.navigationDelegate = self

            let window = NSWindow(
                contentRect: NSRect(x: -20000, y: -20000, width: 1280, height: 900),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            // 窗口生命周期由 ARC 管理；close() 的排序动画在 macOS 26 上会被重复释放而崩溃
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.contentView = webView
            window.orderBack(nil)
            self.window = window
            self.webView = webView

            webView.load(URLRequest(url: url, timeoutInterval: timeout))
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(WebImportError.fetchFailed("网页加载超时")))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.capture()
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in
            self.finish(.failure(WebImportError.fetchFailed("网页加载失败：\(error.localizedDescription)")))
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in
            self.finish(.failure(WebImportError.fetchFailed("网页加载失败：\(error.localizedDescription)")))
        }
    }

    private func capture() {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }
                if let html = value as? String, !html.isEmpty {
                    self.finish(.success(WebPageFetcher.Page(
                        html: html,
                        finalURL: webView.url ?? URL(string: "about:blank")!
                    )))
                } else {
                    let message = error?.localizedDescription ?? "无法读取网页内容"
                    self.finish(.failure(WebImportError.fetchFailed(message)))
                }
            }
        }
    }

    private func finish(_ result: Result<WebPageFetcher.Page, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        }
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
    }
}
