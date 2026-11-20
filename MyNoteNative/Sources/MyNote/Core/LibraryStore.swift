import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    static let libraryPathKey = "MyNote.libraryPath"
    static let lastFolderKey = "MyNote.lastFolder"

    @Published private(set) var rootURL: URL
    @Published private(set) var notes: [Note] = []
    @Published private(set) var folderTree: FolderNode = .root
    @Published private(set) var tags: [TagCount] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanAt: Date?

    @Published var sidebarSelection: SidebarSelection? = .all
    @Published private(set) var selectedNoteID: String?
    @Published var searchText = ""
    @Published var editorMode: EditorMode = .split
    @Published var sortOrder: NoteSortOrder = .title
    @Published var draft = ""
    @Published var titleDraft = ""
    @Published var previewMarkdown = ""
    @Published private(set) var saveState: SaveState = .idle
    @Published private(set) var savePulse = 0
    @Published var conflict: ConflictState?
    @Published var activeSheet: ActiveSheet?
    @Published var pendingTrashNote: Note?
    @Published var pendingTrashFolder: FolderNode?
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var lastFolder: String

    private var searchIndex = SearchMatcher(notes: [])
    private var lastSavedContent = ""
    private var watcher: FileWatcher?
    private var autosaveTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var deferredScanTask: Task<Void, Never>?
    private var pendingScan: ScanRequest?
    private var lastOwnWriteAt: Date = .distantPast
    private var didBootstrap = false

    private struct ScanRequest {
        var selectID: String?
        var selectMostRecent: Bool
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.libraryPathKey)
        let root: URL
        if let saved, !saved.isEmpty {
            root = URL(fileURLWithPath: saved)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Notes/MyNote")
        }
        rootURL = root.standardizedFileURL
        lastFolder = UserDefaults.standard.string(forKey: Self.lastFolderKey) ?? ""
    }

    var paths: LibraryPaths { LibraryPaths(root: rootURL) }

    var selectedNote: Note? { note(id: selectedNoteID) }

    var isEmpty: Bool { notes.isEmpty }

    var filteredNotes: [Note] {
        var base: [Note]
        switch sidebarSelection ?? .all {
        case .all:
            base = notes
        case .folder(let path):
            base = notes.filter { $0.folderPath == path || $0.folderPath.hasPrefix(path + "/") }
        case .tag(let tag):
            base = notes.filter { $0.tags.contains(tag) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return searchIndex.rank(base, query: query)
        }
        switch sortOrder {
        case .title:
            return base.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .modified:
            return base.sorted { $0.modified > $1.modified }
        case .modifiedAscending:
            return base.sorted { $0.modified < $1.modified }
        }
    }

    var folderOptions: [FolderOption] {
        var options: [FolderOption] = []
        func walk(_ node: FolderNode, depth: Int) {
            if !node.path.isEmpty {
                options.append(FolderOption(path: node.path, name: node.name, depth: depth))
            }
            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }
        for child in folderTree.children {
            walk(child, depth: 1)
        }
        if !options.contains(where: { $0.path == "00-收件箱" }) {
            options.insert(FolderOption(path: "00-收件箱", name: "00-收件箱", depth: 1), at: 0)
        }
        return options
    }

    var defaultNewNoteFolder: String {
        if case .folder(let path)? = sidebarSelection, !path.isEmpty,
           folderOptions.contains(where: { $0.path == path }) {
            return path
        }
        if !lastFolder.isEmpty, folderOptions.contains(where: { $0.path == lastFolder }) {
            return lastFolder
        }
        return "00-收件箱"
    }

    var searchScopeTitle: String {
        switch sidebarSelection ?? .all {
        case .all: return "全部笔记"
        case .folder(let path): return path.components(separatedBy: "/").last ?? path
        case .tag(let tag): return "#\(tag)"
        }
    }

    var currentFolderURL: URL {
        guard let note = selectedNote, !note.folderPath.isEmpty,
              let url = try? paths.resolve(relative: note.folderPath) else {
            return rootURL
        }
        return url
    }

    // MARK: - Lifecycle

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        startWatcher()
        rescan(selectMostRecent: true)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.flushImmediately()
            }
        }
    }

    private func startWatcher() {
        watcher?.stop()
        let watcher = FileWatcher()
        watcher.start(path: rootURL.path) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // 自己保存也会触发 FSEvents，但笔记元数据已就地更新，无需重扫；
                // 重扫反而会用旧快照覆盖正在编辑的内容。
                guard Date().timeIntervalSince(self.lastOwnWriteAt) > 2.5 else { return }
                self.rescan()
            }
        }
        self.watcher = watcher
    }

    private func scheduleDeferredRescan(after seconds: Double = 1.0) {
        deferredScanTask?.cancel()
        deferredScanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.rescan()
        }
    }

    func reload() {
        rescan(selectMostRecent: selectedNoteID == nil)
    }

    func setLibraryRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = "目录不存在或不可访问：\(standardized.path)"
            return
        }
        UserDefaults.standard.set(standardized.path, forKey: Self.libraryPathKey)
        watcher?.stop()
        watcher = nil
        scanTask?.cancel()
        scanTask = nil
        deferredScanTask?.cancel()
        deferredScanTask = nil
        pendingScan = nil
        isScanning = false
        rootURL = standardized
        selectedNoteID = nil
        clearEditor()
        notes = []
        folderTree = .root
        tags = []
        searchIndex = SearchMatcher(notes: [])
        didBootstrap = false
        bootstrap()
    }

    // MARK: - iCloud 同步

    @Published private(set) var isSyncingToICloud = false

    static var iCloudDriveURL: URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        return library.appendingPathComponent("Mobile Documents/com~apple~CloudDocs")
    }

    var iCloudAvailable: Bool {
        guard let url = Self.iCloudDriveURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var iCloudLibraryURL: URL? {
        Self.iCloudDriveURL?.appendingPathComponent("微光")
    }

    var iCloudLibraryPath: String? {
        iCloudLibraryURL?.path
    }

    var iCloudLibraryExists: Bool {
        guard let url = iCloudLibraryURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var isLibraryInICloud: Bool {
        guard let iCloud = Self.iCloudDriveURL else { return false }
        return rootURL.path == iCloud.path || rootURL.path.hasPrefix(iCloud.path + "/")
    }

    var localLibraryExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: Self.defaultLocalLibraryURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static var defaultLocalLibraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Notes/MyNote")
    }

    func openICloudLibrary() {
        if let url = iCloudLibraryURL, iCloudLibraryExists {
            setLibraryRoot(url)
        }
    }

    func openLocalLibrary() {
        setLibraryRoot(Self.defaultLocalLibraryURL)
    }

    func syncToICloud() {
        guard !isSyncingToICloud else { return }
        guard iCloudAvailable, let destination = iCloudLibraryURL else {
            errorMessage = "未检测到 iCloud Drive"
            return
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: destination.path)) ?? []
            guard contents.allSatisfy({ $0 == ".DS_Store" }) else {
                errorMessage = "iCloud 目标目录已有内容，为避免覆盖已取消：\(destination.path)"
                return
            }
            try? fm.removeItem(at: destination)
        }
        let source = rootURL
        isSyncingToICloud = true
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                do {
                    let copy = FileManager.default
                    try copy.createDirectory(at: destination, withIntermediateDirectories: true)
                    let items = try copy.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    for item in items {
                        try copy.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
                    }
                    return .success(destination)
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            self.isSyncingToICloud = false
            switch outcome {
            case .success(let url):
                self.setLibraryRoot(url)
                self.infoMessage = "知识库已同步到 iCloud Drive，本地目录保持不变"
            case .failure(let error):
                self.errorMessage = "同步到 iCloud 失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Scanning

    func rescan(selectID: String? = nil, selectMostRecent: Bool = false) {
        if scanTask != nil {
            pendingScan = ScanRequest(
                selectID: selectID ?? pendingScan?.selectID,
                selectMostRecent: selectMostRecent || (pendingScan?.selectMostRecent ?? false)
            )
            return
        }
        let root = rootURL
        isScanning = true
        scanTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ScanResult, Error> in
                do {
                    return .success(try LibraryScanner(root: root).scan())
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            self.finishScan(outcome, request: ScanRequest(selectID: selectID, selectMostRecent: selectMostRecent))
        }
    }

    private func finishScan(_ outcome: Result<ScanResult, Error>, request: ScanRequest) {
        scanTask = nil
        isScanning = false
        switch outcome {
        case .failure(let error):
            errorMessage = "扫描知识库失败：\(error.localizedDescription)"
        case .success(let result):
            apply(result, request: request)
        }
        if let pending = pendingScan {
            pendingScan = nil
            rescan(selectID: pending.selectID, selectMostRecent: pending.selectMostRecent)
        }
    }

    private func apply(_ result: ScanResult, request: ScanRequest) {
        let previousID = selectedNoteID
        let wasDirty = previousID != nil && draft != lastSavedContent

        notes = result.notes
        folderTree = result.folderTree
        tags = result.tags
        searchIndex = SearchMatcher(notes: result.notes)
        lastScanAt = result.scannedAt

        if case .folder(let path)? = sidebarSelection, !path.isEmpty,
           !folderOptions.contains(where: { $0.path == path }) {
            sidebarSelection = .all
        }

        if let selectID = request.selectID,
           let note = result.notes.first(where: { $0.id == selectID }) {
            selectedNoteID = selectID
            load(note: note)
            return
        }

        if let previousID, let updated = result.notes.first(where: { $0.id == previousID }) {
            let diskText = verifiedDiskText(for: updated)
            if wasDirty {
                if let diskText {
                    if conflict != nil {
                        if diskText == normalized(lastSavedContent) || diskText == normalized(draft) {
                            conflict = nil
                        }
                    } else if diskText != normalized(lastSavedContent),
                              diskText != normalized(draft) {
                        conflict = ConflictState(noteID: previousID, diskContent: diskText)
                    }
                    if draft == diskText {
                        lastSavedContent = diskText
                        saveState = .idle
                    }
                } else {
                    // iCloud 文件可能正在落地，读不到内容时不要误报冲突
                    scheduleDeferredRescan(after: 1.5)
                }
                if normalized(draft) == normalized(updated.body) {
                    titleDraft = updated.title
                }
            } else if let diskText {
                if diskText != normalized(draft) {
                    load(note: updated, content: diskText)
                } else {
                    titleDraft = updated.title
                    saveState = .idle
                }
            } else if normalized(updated.body) != normalized(draft) {
                // 磁盘暂时不可读时，扫描快照可能早于最新输入，不能用它覆盖编辑器
                scheduleDeferredRescan(after: 1.0)
            } else {
                titleDraft = updated.title
                saveState = .idle
            }
            return
        }

        if previousID != nil {
            selectedNoteID = nil
            clearEditor()
            if !result.notes.isEmpty {
                infoMessage = "当前笔记已在知识库中移除"
            }
            return
        }

        if request.selectMostRecent, let recent = result.notes.max(by: { $0.modified < $1.modified }) {
            selectedNoteID = recent.id
            load(note: recent)
        }
    }

    // MARK: - Selection

    func selectFirstInScope() {
        guard let first = filteredNotes.first else { return }
        if selectedNoteID != first.id {
            select(first.id)
        }
    }

    func select(_ id: String?) {
        guard id != selectedNoteID else { return }
        if selectedNoteID != nil {
            persistBeforeSwitch()
        }
        autosaveTask?.cancel()
        previewTask?.cancel()
        selectedNoteID = id
        conflict = nil
        guard let id, let note = note(id: id) else {
            clearEditor()
            return
        }
        load(note: note)
    }

    private func load(note: Note) {
        draft = note.body
        lastSavedContent = note.body
        titleDraft = note.title
        previewMarkdown = note.body
        saveState = .idle
        conflict = nil
        autosaveTask?.cancel()
        previewTask?.cancel()
    }

    private func load(note: Note, content: String) {
        draft = content
        lastSavedContent = content
        let parsed = Frontmatter.parse(content)
        titleDraft = parsed.title ?? note.title
        previewMarkdown = content
        saveState = .idle
        conflict = nil
        autosaveTask?.cancel()
        previewTask?.cancel()
        refreshNoteMetadata(id: note.id, content: content)
    }

    private func clearEditor() {
        draft = ""
        lastSavedContent = ""
        titleDraft = ""
        previewMarkdown = ""
        saveState = .idle
        conflict = nil
        autosaveTask?.cancel()
        previewTask?.cancel()
    }

    private func persistBeforeSwitch() {
        guard let id = selectedNoteID else { return }
        if conflict != nil {
            writeConflictCopy()
            conflict = nil
            return
        }
        guard draft != lastSavedContent else { return }
        _ = writeDraft(for: id, content: draft, force: false, silent: true)
    }

    private func flushImmediately() {
        guard selectedNoteID != nil, conflict == nil, draft != lastSavedContent else { return }
        _ = writeDraft(for: selectedNoteID!, content: draft, force: false, silent: true)
    }

    // MARK: - Editing & saving

    func updateDraft(_ value: String) {
        guard selectedNoteID != nil else { return }
        draft = value
        if value == lastSavedContent {
            saveState = .idle
            return
        }
        saveState = .dirty
        schedulePreview()
        scheduleAutosave()
    }

    func toggleTask(at index: Int) {
        guard selectedNoteID != nil else { return }
        guard conflict == nil else {
            infoMessage = "检测到外部修改，请先处理冲突"
            return
        }
        let ns = draft as NSString
        let positions = Self.taskMarkerLocations(in: draft)
        guard index >= 0, index < positions.count else { return }
        let markRange = NSRange(location: positions[index], length: 1)
        let checked = ns.substring(with: markRange).lowercased() == "x"
        let replacement = checked ? " " : "x"
        let updated = NSMutableString(string: draft)
        updated.replaceCharacters(in: markRange, with: replacement)
        updateDraft(updated as String)
        saveIfNeeded()
        infoMessage = checked ? "已恢复为未完成" : "已完成任务"
    }

    nonisolated static func taskMarkerLocations(in text: String) -> [Int] {
        let pattern = try! NSRegularExpression(
            pattern: "^(\\s*(?:>\\s*)*(?:[-*+]|\\d+\\.)\\s+)\\[([ xX])\\]"
        )
        var positions: [Int] = []
        var offset = 0
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
            } else if !inFence,
                      let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                positions.append(offset + match.range(at: 2).location)
            }
            offset += (line as NSString).length + 1
        }
        return positions
    }

    func commitTitle() {
        guard let note = selectedNote else { return }
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleDraft = note.title
            return
        }
        guard trimmed != note.title else { return }
        var text = Frontmatter.setTitle(trimmed, in: draft)
        text = Frontmatter.setH1(trimmed, in: text)
        updateDraft(text)
        saveIfNeeded()
    }

    /// 停笔 30 秒后才自动保存，避免写作过程中频繁落盘打断输入。
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // 拼音等输入法拼写中不落盘，提交后会重新触发 textDidChange
            guard !EditorBridge.shared.isComposing else { return }
            self.saveIfNeeded()
        }
    }

    private func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.previewMarkdown = self.draft
        }
    }

    /// `manual` 为真时（⌘S 或工具栏按钮）才触发保存动效，自动保存保持静默。
    func saveIfNeeded(force: Bool = false, manual: Bool = false) {
        guard let id = selectedNoteID else { return }
        if !manual && EditorBridge.shared.isComposing { return }
        if conflict != nil && !force { return }
        if !force && draft == lastSavedContent {
            saveState = .idle
            return
        }
        saveState = .saving
        _ = writeDraft(for: id, content: draft, force: force, silent: false, pulse: manual)
    }

    @discardableResult
    private func writeDraft(for id: String, content: String, force: Bool, silent: Bool, pulse: Bool = false) -> Bool {
        guard let note = note(id: id) else { return false }
        do {
            let url = try paths.resolve(relative: note.relPath, mustExist: true)
            if !force, let disk = verifiedDiskText(for: note),
               disk != normalized(lastSavedContent),
               disk != normalized(content) {
                conflict = ConflictState(noteID: id, diskContent: disk)
                if !silent { saveState = .failed("检测到外部修改") }
                return false
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            lastOwnWriteAt = Date()
            if id == selectedNoteID {
                lastSavedContent = content
                saveState = .saved(Date())
                if pulse { savePulse += 1 }
            }
            refreshNoteMetadata(id: id, content: content)
            return true
        } catch {
            if !silent {
                saveState = .failed("保存失败")
                errorMessage = "保存失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    private func refreshNoteMetadata(id: String, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let parsed = Frontmatter.parse(content)
        var note = notes[index]
        if let title = parsed.title, !title.isEmpty {
            note.title = title
        }
        note.tags = parsed.tags
        note.date = parsed.date
        note.body = content
        note.excerpt = LibraryScanner.excerpt(from: parsed.body)
        note.size = content.utf8.count
        note.modified = Date()
        notes[index] = note
        searchIndex.update(note)
        rebuildTags()
    }

    private func rebuildTags() {
        var counts: [String: Int] = [:]
        for note in notes {
            for tag in note.tags {
                counts[tag, default: 0] += 1
            }
        }
        tags = counts.map { TagCount(name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func currentText(for id: String) -> String {
        if id == selectedNoteID { return draft }
        return note(id: id)?.body ?? ""
    }

    func note(id: String?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    func noteFolderURL(_ note: Note) -> URL {
        guard !note.folderPath.isEmpty,
              let url = try? paths.resolve(relative: note.folderPath) else {
            return rootURL
        }
        return url
    }

    // MARK: - Note operations

    func createNote(title: String, folder: String, tags: [String]) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorMessage = "标题不能为空"
            return false
        }
        do {
            let folderRel = normalizeFolder(folder)
            let folderURL = folderRel.isEmpty ? rootURL : try paths.resolve(relative: folderRel)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let base = Self.sanitizeFileName(cleanTitle)
            let name = try uniqueFileName(base: base, folder: folderRel, excluding: nil)
            let rel = folderRel.isEmpty ? name : folderRel + "/" + name
            let url = try paths.resolve(relative: rel)
            let content = Frontmatter.createDocument(title: cleanTitle, tags: tags)
            try content.write(to: url, atomically: true, encoding: .utf8)
            rememberFolder(folderRel)
            if editorMode == .preview {
                editorMode = .editor
            }
            rescan(selectID: rel)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard selectedNoteID == rel else { return }
                EditorBridge.shared.focusAtEnd()
            }
            infoMessage = "已新建笔记：\(cleanTitle)"
            return true
        } catch {
            errorMessage = "新建笔记失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 网页导入：正文已由导入器转换成 Markdown，图片已落到 assets，这里只负责建文件。
    func importWebNote(title: String, folder: String, tags: [String], body: String, sourceURL: URL) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorMessage = "标题不能为空"
            return false
        }
        do {
            let folderRel = normalizeFolder(folder)
            let folderURL = folderRel.isEmpty ? rootURL : try paths.resolve(relative: folderRel)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let base = Self.sanitizeFileName(cleanTitle)
            let name = try uniqueFileName(base: base, folder: folderRel, excluding: nil)
            let rel = folderRel.isEmpty ? name : folderRel + "/" + name
            let url = try paths.resolve(relative: rel)
            let source = sourceURL.absoluteString
            let content = Frontmatter.createDocument(
                title: cleanTitle,
                tags: tags,
                body: "# \(cleanTitle)\n\n> 来源：[原文](<\(source)>)\n\n\(body)"
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            rememberFolder(folderRel)
            if !folderRel.isEmpty {
                sidebarSelection = .folder(folderRel)
            }
            editorMode = .preview
            rescan(selectID: rel)
            infoMessage = "已导入网页：\(cleanTitle)"
            return true
        } catch {
            errorMessage = "导入网页失败：\(error.localizedDescription)"
            return false
        }
    }

    func createFolder(parent: String, name: String) -> Bool {        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "目录名不能为空"
            return false
        }
        let clean = Self.sanitizeFileName(trimmed)
        guard clean != "assets" else {
            errorMessage = "资源目录已存在"
            return false
        }
        let parentRel = normalizeFolder(parent)
        let rel = parentRel.isEmpty ? clean : parentRel + "/" + clean
        do {
            let url = try paths.resolve(relative: rel)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                errorMessage = isDirectory.boolValue ? "目录已存在：\(clean)" : "同名文件已存在：\(clean)"
                return false
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            sidebarSelection = .folder(rel)
            rescan()
            infoMessage = "已新建目录：\(clean)"
            return true
        } catch {
            errorMessage = "新建目录失败：\(error.localizedDescription)"
            return false
        }
    }

    func copyToPasteboard(_ string: String, message: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        infoMessage = message
    }

    func copyNotePath(_ note: Note) {
        guard let url = try? paths.resolve(relative: note.relPath) else { return }
        copyToPasteboard(url.path, message: "已复制文件路径")
    }

    func copyNoteLink(_ note: Note) {
        copyToPasteboard("[\(note.title)](<\(note.relPath)>)", message: "已复制 Markdown 链接")
    }

    func copyFolderPath(_ path: String) {
        let url = (try? paths.resolve(relative: path)) ?? rootURL
        copyToPasteboard(url.path, message: "已复制目录路径")
    }

    func renameNote(id: String, to newTitle: String) -> Bool {
        guard let note = note(id: id) else { return false }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "标题不能为空"
            return false
        }
        var text = currentText(for: id)
        text = Frontmatter.setTitle(trimmed, in: text)
        text = Frontmatter.setH1(trimmed, in: text)
        do {
            let oldURL = try paths.resolve(relative: note.relPath, mustExist: true)
            let base = Self.sanitizeFileName(trimmed)
            let name = try uniqueFileName(base: base, folder: note.folderPath, excluding: note.relPath)
            let newRel = note.folderPath.isEmpty ? name : note.folderPath + "/" + name
            let newURL = try paths.resolve(relative: newRel)
            try text.write(to: oldURL, atomically: true, encoding: .utf8)
            if newURL.standardizedFileURL != oldURL.standardizedFileURL {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            }
            if selectedNoteID == id {
                draft = text
                lastSavedContent = text
                titleDraft = trimmed
                previewMarkdown = text
                saveState = .saved(Date())
            }
            rescan(selectID: newRel)
            return true
        } catch {
            errorMessage = "重命名失败：\(error.localizedDescription)"
            return false
        }
    }

    func duplicateNote(id: String) -> Bool {
        guard let note = note(id: id) else { return false }
        let text = currentText(for: id)
        let copyTitle = note.title + " 副本"
        var content = Frontmatter.setTitle(copyTitle, in: text)
        content = Frontmatter.setH1(copyTitle, in: content)
        do {
            let base = Self.sanitizeFileName(copyTitle)
            let name = try uniqueFileName(base: base, folder: note.folderPath, excluding: nil)
            let rel = note.folderPath.isEmpty ? name : note.folderPath + "/" + name
            let url = try paths.resolve(relative: rel)
            try content.write(to: url, atomically: true, encoding: .utf8)
            rescan(selectID: rel)
            return true
        } catch {
            errorMessage = "创建副本失败：\(error.localizedDescription)"
            return false
        }
    }

    func moveNote(id: String, to folder: String) -> Bool {
        guard let note = note(id: id) else { return false }
        let folderRel = normalizeFolder(folder)
        guard folderRel != note.folderPath else { return true }
        guard folderRel != "assets", !folderRel.hasPrefix("assets/") else {
            errorMessage = "不能移动到资源目录"
            return false
        }
        if selectedNoteID == id, draft != lastSavedContent, conflict == nil {
            guard writeDraft(for: id, content: draft, force: false, silent: false) else { return false }
        }
        do {
            let oldURL = try paths.resolve(relative: note.relPath, mustExist: true)
            let destinationFolder = folderRel.isEmpty ? rootURL : try paths.resolve(relative: folderRel)
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let fileName = (note.relPath as NSString).lastPathComponent
            let base = (fileName as NSString).deletingPathExtension
            let name = try uniqueFileName(base: base, folder: folderRel, excluding: note.relPath)
            let newRel = folderRel.isEmpty ? name : folderRel + "/" + name
            let newURL = try paths.resolve(relative: newRel)
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            rememberFolder(folderRel)
            rescan(selectID: newRel)
            return true
        } catch {
            errorMessage = "移动失败：\(error.localizedDescription)"
            return false
        }
    }

    func requestTrash(_ note: Note) {
        pendingTrashNote = note
    }

    func renameFolder(path: String, to newName: String) -> Bool {
        let source = normalizeFolder(path)
        guard !source.isEmpty else { return false }
        guard source != "assets", !source.hasPrefix("assets/") else {
            errorMessage = "不能重命名资源目录"
            return false
        }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "文件夹名称不能为空"
            return false
        }
        let clean = Self.sanitizeFileName(trimmed)
        guard clean != "assets" else {
            errorMessage = "资源目录已存在"
            return false
        }
        let parent = source.contains("/") ? String(source[..<source.lastIndex(of: "/")!]) : ""
        let dest = parent.isEmpty ? clean : parent + "/" + clean
        guard dest != source else { return true }

        if let id = selectedNoteID, isInside(id, folder: source),
           draft != lastSavedContent, conflict == nil {
            guard writeDraft(for: id, content: draft, force: false, silent: false) else { return false }
        }

        do {
            let oldURL = try paths.resolve(relative: source, mustExist: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: oldURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                errorMessage = "目录不存在：\(source)"
                return false
            }
            let newURL = try paths.resolve(relative: dest)
            guard !FileManager.default.fileExists(atPath: newURL.path) else {
                errorMessage = "同名目录或文件已存在：\(clean)"
                return false
            }
            try FileManager.default.moveItem(at: oldURL, to: newURL)

            if case .folder(let selected)? = sidebarSelection, isInside(selected, folder: source) {
                sidebarSelection = .folder(dest + String(selected.dropFirst(source.count)))
            }
            if !lastFolder.isEmpty, isInside(lastFolder, folder: source) {
                rememberFolder(dest + String(lastFolder.dropFirst(source.count)))
            }
            if let conflict, isInside(conflict.noteID, folder: source) {
                self.conflict = ConflictState(
                    noteID: dest + String(conflict.noteID.dropFirst(source.count)),
                    diskContent: conflict.diskContent
                )
            }

            var nextID = selectedNoteID
            if let id = selectedNoteID, isInside(id, folder: source) {
                nextID = dest + String(id.dropFirst(source.count))
                selectedNoteID = nil
            }
            rescan(selectID: nextID)
            infoMessage = "已重命名目录：\(clean)"
            return true
        } catch {
            errorMessage = "重命名目录失败：\(error.localizedDescription)"
            return false
        }
    }

    func requestTrashFolder(_ folder: FolderNode) {
        guard !folder.path.isEmpty else { return }
        pendingTrashFolder = folder
    }

    func confirmTrashFolder() {
        guard let folder = pendingTrashFolder else { return }
        pendingTrashFolder = nil
        let path = normalizeFolder(folder.path)
        guard !path.isEmpty else { return }
        guard path != "assets", !path.hasPrefix("assets/") else {
            errorMessage = "不能删除资源目录"
            return
        }
        do {
            let url = try paths.resolve(relative: path, mustExist: true)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)

            if case .folder(let selected)? = sidebarSelection, isInside(selected, folder: path) {
                sidebarSelection = .all
            }
            if let id = selectedNoteID, isInside(id, folder: path) {
                selectedNoteID = nil
                clearEditor()
            }
            if !lastFolder.isEmpty, isInside(lastFolder, folder: path) {
                rememberFolder("")
            }
            if let conflict, isInside(conflict.noteID, folder: path) {
                self.conflict = nil
            }
            rescan()
            infoMessage = "已移到废纸篓：\(folder.name)"
        } catch {
            errorMessage = "删除目录失败：\(error.localizedDescription)"
        }
    }

    func confirmTrash() {
        guard let note = pendingTrashNote else { return }
        pendingTrashNote = nil
        do {
            let url = try paths.resolve(relative: note.relPath, mustExist: true)
            guard url.pathExtension.lowercased() == "md" else { return }
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if selectedNoteID == note.id {
                selectedNoteID = nil
                clearEditor()
            }
            notes.removeAll { $0.id == note.id }
            searchIndex.remove(id: note.id)
            rebuildTags()
            rescan()
            infoMessage = "已移到废纸篓：\(note.title)"
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func setTags(id: String, tags newTags: [String]) -> Bool {
        guard let note = note(id: id) else { return false }
        let normalized = newTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let baseText: String
        if id == selectedNoteID {
            baseText = draft
        } else if let url = try? paths.resolve(relative: note.relPath, mustExist: true),
                  let disk = try? String(contentsOf: url, encoding: .utf8) {
            baseText = disk
        } else {
            baseText = note.body
        }
        let text = Frontmatter.setTags(normalized, in: baseText)
        guard text != baseText else { return true }
        do {
            let url = try paths.resolve(relative: note.relPath, mustExist: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if id == selectedNoteID {
                draft = text
                lastSavedContent = text
                previewMarkdown = text
                saveState = .saved(Date())
            }
            refreshNoteMetadata(id: id, content: text)
            return true
        } catch {
            errorMessage = "更新标签失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Conflicts

    func resolveConflictUsingDisk() {
        guard let conflict, let note = note(id: conflict.noteID) else {
            self.conflict = nil
            return
        }
        draft = conflict.diskContent
        lastSavedContent = conflict.diskContent
        titleDraft = note.title
        previewMarkdown = draft
        saveState = .idle
        self.conflict = nil
        refreshNoteMetadata(id: note.id, content: draft)
    }

    func resolveConflictKeepingMine() {
        guard let conflict else { return }
        self.conflict = nil
        _ = writeDraft(for: conflict.noteID, content: draft, force: true, silent: false)
    }

    func resolveConflictSavingCopy() {
        guard let conflict, let note = note(id: conflict.noteID) else {
            self.conflict = nil
            return
        }
        do {
            let copyTitle = note.title + " 冲突副本"
            var content = Frontmatter.setTitle(copyTitle, in: draft)
            content = Frontmatter.setH1(copyTitle, in: content)
            let base = Self.sanitizeFileName(copyTitle + " " + Self.timestamp())
            let name = try uniqueFileName(base: base, folder: note.folderPath, excluding: nil)
            let rel = note.folderPath.isEmpty ? name : note.folderPath + "/" + name
            try content.write(to: try paths.resolve(relative: rel), atomically: true, encoding: .utf8)
            draft = conflict.diskContent
            lastSavedContent = conflict.diskContent
            titleDraft = note.title
            previewMarkdown = draft
            saveState = .idle
            self.conflict = nil
            refreshNoteMetadata(id: note.id, content: draft)
            rescan(selectID: note.relPath)
            infoMessage = "已将你的修改保存为副本：\(name)"
        } catch {
            errorMessage = "保存冲突副本失败：\(error.localizedDescription)"
        }
    }

    private func writeConflictCopy() {
        guard let note = selectedNote else { return }
        do {
            let copyTitle = note.title + " 冲突副本 " + Self.timestamp()
            var content = Frontmatter.setTitle(copyTitle, in: draft)
            content = Frontmatter.setH1(copyTitle, in: content)
            let base = Self.sanitizeFileName(copyTitle)
            let name = try uniqueFileName(base: base, folder: note.folderPath, excluding: nil)
            let rel = note.folderPath.isEmpty ? name : note.folderPath + "/" + name
            try content.write(to: try paths.resolve(relative: rel), atomically: true, encoding: .utf8)
            infoMessage = "已保留冲突副本：\(name)"
            rescan()
        } catch {
            errorMessage = "无法保留冲突副本：\(error.localizedDescription)"
        }
    }

    // MARK: - Tools

    func quickOpenResults(_ query: String) -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Array(notes.sorted { $0.modified > $1.modified }.prefix(12))
        }
        return Array(searchIndex.rank(notes, query: trimmed).prefix(20))
    }

    func openLink(_ url: URL) {
        if url.isFileURL {
            let target = url.standardizedFileURL
            guard paths.contains(target) else {
                NSWorkspace.shared.open(target)
                return
            }
            let rel = paths.relativePath(of: target)
            if note(id: rel) != nil {
                select(rel)
            } else if FileManager.default.fileExists(atPath: target.path) {
                rescan(selectID: rel)
            } else {
                errorMessage = "链接目标不存在：\(rel)"
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ note: Note) {
        if let url = try? paths.resolve(relative: note.relPath, mustExist: true) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func revealLibrary() {
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    func revealFolder(_ path: String) {
        if let url = try? paths.resolve(relative: path) {
            NSWorkspace.shared.open(url)
        }
    }

    func exportCurrentPDF() {
        guard let note = selectedNote else { return }
        let panel = NSSavePanel()
        panel.title = "导出 PDF"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.sanitizeFileName(note.title) + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PDFExporter.export(
                markdown: draft,
                baseURL: noteFolderURL(note),
                to: url,
                title: note.title
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
            infoMessage = "已导出 PDF：\(url.lastPathComponent)"
        } catch {
            errorMessage = "导出 PDF 失败：\(error.localizedDescription)"
        }
    }

    func insertImageFromPanel() -> String? {
        guard selectedNote != nil else {
            errorMessage = "请先打开一篇笔记"
            return nil
        }
        let panel = NSOpenPanel()
        panel.title = "插入图片"
        panel.allowedContentTypes = ImageInserter.allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        do {
            let markdown = try ImageInserter.importImage(
                from: source,
                noteFolder: selectedNote?.folderPath ?? "",
                root: rootURL
            )
            return markdown
        } catch {
            errorMessage = "插入图片失败：\(error.localizedDescription)"
            return nil
        }
    }

    func insertAttachmentFromPanel() -> String? {
        guard selectedNote != nil else {
            errorMessage = "请先打开一篇笔记"
            return nil
        }
        let panel = NSOpenPanel()
        panel.title = "插入附件"
        panel.allowedContentTypes = [.item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let source = panel.url else { return nil }
        do {
            return try AttachmentInserter.copy(
                from: source,
                noteFolder: selectedNote?.folderPath ?? "",
                root: rootURL
            )
        } catch {
            errorMessage = "插入附件失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Helpers

    static func normalizeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private func normalized(_ text: String) -> String {
        Self.normalizeText(text)
    }

    /// 直接读盘并归一化。文件暂时不可读（iCloud 落地中）时返回 nil，调用方不应据此判定冲突。
    private func verifiedDiskText(for note: Note) -> String? {
        guard let url = try? paths.resolve(relative: note.relPath),
              let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return normalized(text)
    }

    private func normalizeFolder(_ folder: String) -> String {
        var value = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private func isInside(_ path: String, folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    private func rememberFolder(_ folder: String) {
        lastFolder = folder
        UserDefaults.standard.set(folder, forKey: Self.lastFolderKey)
    }

    private func uniqueFileName(base: String, folder: String, excluding: String?) throws -> String {
        var candidate = "\(base).md"
        var counter = 2
        while true {
            let rel = folder.isEmpty ? candidate : folder + "/" + candidate
            if rel == excluding { return candidate }
            let url = try paths.resolve(relative: rel)
            if !FileManager.default.fileExists(atPath: url.path) {
                return candidate
            }
            candidate = "\(base) \(counter).md"
            counter += 1
        }
    }

    static func sanitizeFileName(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.count > 80 { name = String(name.prefix(80)) }
        return name.isEmpty ? "未命名笔记" : name
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
