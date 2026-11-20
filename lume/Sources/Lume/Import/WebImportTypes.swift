import Foundation

struct WebImage: Sendable, Hashable {
    let token: String
    let url: URL
    let alt: String
}

struct WebArticle: Sendable {
    let sourceURL: URL
    let finalURL: URL
    let title: String
    let author: String?
    let publishedAt: String?
    let suggestedTags: [String]
    let markdown: String
    let images: [WebImage]
    let textLength: Int

    var sourceHost: String {
        sourceURL.host ?? sourceURL.absoluteString
    }
}

enum WebImportError: LocalizedError {
    case invalidURL
    case fetchFailed(String)
    case emptyContent
    case blocked
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请输入以 http:// 或 https:// 开头的网页地址"
        case .fetchFailed(let message):
            return message
        case .emptyContent:
            return "没有从页面中识别出正文，可能需要在浏览器中打开后再复制"
        case .blocked:
            return "页面要求人机验证，暂时无法直接解析"
        case .cancelled:
            return "已取消"
        }
    }
}
