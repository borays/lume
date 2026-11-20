import AppKit
import CoreServices

final class FileWatcher: NSObject {
    private var stream: FSEventStreamRef?
    private var handler: (() -> Void)?
    private let queue = DispatchQueue(label: "com.admin.mynote.fswatch")
    private var watchedPath: String = ""
    private var debounceWorkItem: DispatchWorkItem?

    override init() {
        super.init()
    }

    func start(path: String, handler: @escaping () -> Void) {
        stop()
        watchedPath = path
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.queue.async {
                DispatchQueue.main.async {
                    watcher.scheduleFire()
                }
            }
        }

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer)
        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else { return }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
    }

    private func scheduleFire() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.handler?()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        handler = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
