import SwiftSoup

extension Element {
    /// SwiftSoup 的 attr 是 throwing 的；解析 HTML 时缺属性很常见，统一按空字符串处理。
    func safeAttr(_ key: String) -> String {
        (try? attr(key)) ?? ""
    }
}
