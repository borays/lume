import AppKit

/// 预览图片的共享缓存与后台加载。
/// 知识库图片常在 iCloud 里处于“未下载”状态，首次读取会阻塞到云端回传，
/// 因此主线程只查内存缓存，缺图时交给后台队列读取，完成后再通知预览补图。
enum MarkdownImageStore {
    /// object 为 nil，userInfo 里带 "url" 与可选的 "image"。
    static let didFinishLoading = Notification.Name("LumeMarkdownImageDidLoad")

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 256 * 1024 * 1024
        cache.countLimit = 300
        return cache
    }()
    private static let queue = DispatchQueue(
        label: "com.admin.lume.image-load",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let lock = NSLock()
    private static var inFlight = Set<String>()

    static func key(for url: URL) -> NSString {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)|\(Int(modified))" as NSString
    }

    static func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: key(for: url))
    }

    /// 同步读取，导出、自测和后台队列使用。
    static func image(for url: URL) -> NSImage? {
        let key = key(for: url)
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.cacheMode = .always
        let rep = image.representations.max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        let cost = max(1, (rep?.pixelsWide ?? 0) * (rep?.pixelsHigh ?? 0) * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 已在缓存或加载中的图片不会重复排队。
    static func requestImage(for url: URL) {
        let key = key(for: url)
        if cache.object(forKey: key) != nil { return }
        lock.lock()
        let alreadyLoading = inFlight.contains(key as String)
        if !alreadyLoading { inFlight.insert(key as String) }
        lock.unlock()
        guard !alreadyLoading else { return }

        let url = url.standardizedFileURL
        queue.async {
            let image = self.image(for: url)
            DispatchQueue.main.async {
                self.lock.lock()
                self.inFlight.remove(key as String)
                self.lock.unlock()
                var info: [AnyHashable: Any] = ["url": url]
                if let image { info["image"] = image }
                NotificationCenter.default.post(name: didFinishLoading, object: nil, userInfo: info)
            }
        }
    }
}