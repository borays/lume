import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var confirmICloudSync = false
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var bridge = EditorBridge.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                fontSection
                librarySection
                appearanceSection
                iCloudSection
                statistics
                hints
            }
            .padding(24)
        }
        .frame(width: 600, height: 720)
        .confirmationDialog(
            "将知识库同步到 iCloud Drive？",
            isPresented: $confirmICloudSync,
            titleVisibility: .visible
        ) {
            Button("拷贝并切换到 iCloud") { store.syncToICloud() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("全部笔记与附件将复制到 iCloud Drive 的「微光」目录，之后由 iCloud 自动在设备间同步。本地原目录保持不变，可随时切回。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("微光")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Lume")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("微光 · 记下思绪里的每一点光亮")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("版本 1.0.0")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private var fontSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("字体")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("字体族")
                        .font(.system(size: 12))
                    Picker("字体族", selection: $bridge.fontFamily) {
                        Text("系统默认（编辑区等宽）").tag("")
                        Divider()
                        ForEach(EditorBridge.availableFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    Button("恢复系统默认") { bridge.fontFamily = "" }
                        .disabled(bridge.fontFamily.isEmpty)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("编辑区字号")
                        .font(.system(size: 12))
                    Slider(
                        value: Binding(
                            get: { Double(bridge.fontSize) },
                            set: { bridge.setFontSize(CGFloat($0)) }
                        ),
                        in: 11...20,
                        step: 1
                    )
                    .frame(width: 180)
                    Text("\(Int(bridge.fontSize)) pt")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .leading)
                    Button("恢复 13.5") { bridge.resetFontSize() }
                        .disabled(bridge.fontSize == 13.5)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("示例")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Text("微光 Lume · 记下思绪里的每一点光亮")
                        .font(sampleFont)
                    Text("The quick brown fox jumps over the lazy dog. 0123456789")
                        .font(sampleBodyFont)
                        .foregroundStyle(.secondary)
                    Text("func render(_ note: String) -> View { NoteView(note) }")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.8)
                )

                Text("所选字体同时用于编辑区与预览正文，代码块始终使用等宽字体；字号只影响编辑区。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var sampleFont: Font {
        if bridge.fontFamily.isEmpty {
            return .system(size: 15)
        }
        return .custom(bridge.fontFamily, size: 15)
    }

    private var sampleBodyFont: Font {
        if bridge.fontFamily.isEmpty {
            return .system(size: 12)
        }
        return .custom(bridge.fontFamily, size: 12)
    }

    private var librarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前知识库")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(store.rootURL.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Button("更改知识库…") { chooseLibrary() }
                    Button("重新扫描") { store.reload() }
                    Button("在 Finder 中显示") { store.revealLibrary() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var appearanceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("外观")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("外观", selection: $theme.mode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("跟随系统时会随 macOS 深浅色模式自动切换。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var iCloudSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: store.iCloudAvailable ? "icloud" : "icloud.slash")
                        .foregroundStyle(store.iCloudAvailable ? Color.accentColor : Color.secondary)
                    Text("iCloud 同步")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if !store.iCloudAvailable {
                    Text("未检测到 iCloud Drive。请在 系统设置 → Apple 账户 中开启 iCloud 云盘后重试。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else if store.isLibraryInICloud {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("知识库已位于 iCloud Drive，文件变更会随 iCloud 自动同步。", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        if store.localLibraryExists {
                            Button("切回本地目录") { store.openLocalLibrary() }
                        }
                    }
                    .font(.system(size: 11.5))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if let path = store.iCloudLibraryPath {
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 8) {
                            Button("同步到 iCloud…") { confirmICloudSync = true }
                                .disabled(store.isSyncingToICloud)
                            Button("打开 iCloud 知识库") { store.openICloudLibrary() }
                                .disabled(!store.iCloudLibraryExists)
                        }
                        if store.isSyncingToICloud {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在拷贝知识库到 iCloud Drive…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var statistics: some View {
        HStack(spacing: 22) {
            statistic("笔记", value: "\(store.notes.count)")
            statistic("标签", value: "\(store.tags.count)")
            statistic("一级目录", value: "\(store.folderTree.children.count)")
            if let last = store.lastScanAt {
                statistic("上次扫描", value: DateDisplay.compact(last))
            }
            Spacer()
            Text("更改会立即生效")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("编辑内容会在停止输入后自动保存。", systemImage: "checkmark.circle")
            Label("删除笔记会移到系统废纸篓，可在废纸篓中恢复。", systemImage: "trash")
            Label("外部修改会触发冲突提示，不会静默覆盖。", systemImage: "shield.lefthalf.filled")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "选择知识库目录"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            store.setLibraryRoot(url)
        }
    }
}
