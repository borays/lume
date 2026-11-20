import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var confirmICloudSync = false
    @State private var selection: SettingsSection? = .general
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var bridge = EditorBridge.shared
    @AppStorage(ReadingPreferences.fontSizeKey) private var previewFontSize = ReadingPreferences.defaultFontSize
    @AppStorage(ReadingPreferences.contentWidthKey) private var previewContentWidth = ReadingPreferences.defaultContentWidth

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                switch selection ?? .general {
                case .general:
                    generalPane
                case .shortcuts:
                    ShortcutsSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 560)
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

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("通用", systemImage: "gearshape")
                    .tag(SettingsSection.general)
                Label("快捷键", systemImage: "keyboard")
                    .tag(SettingsSection.shortcuts)
            }
            .listStyle(.sidebar)

            Divider()
            Text("微光 \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .frame(width: 172)
    }

    private var generalPane: some View {
        Form {
            Section {
                Picker("外观", selection: $theme.mode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("外观")
            } footer: {
                Text("跟随系统时随 macOS 深浅色模式自动切换。")
            }

            Section {
                Picker("字体族", selection: $bridge.fontFamily) {
                    Text("系统默认").tag("")
                    Divider()
                    ForEach(EditorBridge.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("编辑区字号") {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { Double(bridge.fontSize) },
                                set: { bridge.setFontSize(CGFloat($0)) }
                            ),
                            in: 11...20,
                            step: 1
                        )
                        .frame(width: 170)
                        Text(editorSizeLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Button("恢复默认") { bridge.resetFontSize() }
                            .controlSize(.small)
                            .disabled(bridge.fontSize == 13.5)
                    }
                }
            } header: {
                Text("字体")
            } footer: {
                Text("所选字体同时用于编辑区与预览正文，代码块始终使用等宽字体；字号只影响编辑区。")
            }

            Section {
                LabeledContent("正文字号") {
                    HStack(spacing: 10) {
                        Slider(value: $previewFontSize, in: 12...20, step: 1)
                            .frame(width: 170)
                        Text("\(Int(previewFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Button("恢复默认") { previewFontSize = ReadingPreferences.defaultFontSize }
                            .controlSize(.small)
                            .disabled(previewFontSize == ReadingPreferences.defaultFontSize)
                    }
                }

                LabeledContent("内容宽度") {
                    Picker("内容宽度", selection: $previewContentWidth) {
                        Text("窄").tag(640.0)
                        Text("标准").tag(740.0)
                        Text("宽").tag(900.0)
                        Text("全宽").tag(0.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }
            } header: {
                Text("预览阅读")
            } footer: {
                Text("预览字号独立于编辑区；窄宽度适合长文阅读，全宽更适合宽表格、图表与截图。")
            }

            Section {
                LabeledContent("位置") {
                    Text(store.rootURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: 320, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Button("更改…") { chooseLibrary() }
                    Button("重新扫描") { store.reload() }
                    Button("在 Finder 中显示") { store.revealLibrary() }
                    Spacer()
                }
            } header: {
                Text("知识库")
            }

            iCloudSection

            Section {
                LabeledContent("版本") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("知识库规模") {
                    Text("\(store.notes.count) 篇笔记 · \(store.tags.count) 个标签")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
    }

    private var iCloudSection: some View {
        Section {
            Label {
                Text(store.iCloudAvailable ? "iCloud Drive 可用" : "未检测到 iCloud Drive")
            } icon: {
                Image(systemName: store.iCloudAvailable ? "icloud" : "icloud.slash")
                    .foregroundStyle(store.iCloudAvailable ? Color.accentColor : Color.secondary)
            }

            if !store.iCloudAvailable {
                Text("请在系统设置 → Apple 账户 中开启 iCloud 云盘后重试。")
                    .foregroundStyle(.secondary)
            } else if store.isLibraryInICloud {
                Text("知识库已位于 iCloud Drive，文件变更会随 iCloud 自动同步。")
                    .foregroundStyle(.secondary)
                if store.localLibraryExists {
                    Button("切回本地目录") { store.openLocalLibrary() }
                }
            } else {
                if let path = store.iCloudLibraryPath {
                    Text(path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button("同步到 iCloud…") { confirmICloudSync = true }
                        .disabled(store.isSyncingToICloud)
                    Button("打开 iCloud 知识库") { store.openICloudLibrary() }
                        .disabled(!store.iCloudLibraryExists)
                    Spacer()
                }
                if store.isSyncingToICloud {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在拷贝知识库到 iCloud Drive…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("iCloud 同步")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    }

    private var editorSizeLabel: String {
        let size = bridge.fontSize
        return size == size.rounded() ? "\(Int(size)) pt" : String(format: "%.1f pt", size)
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

private enum SettingsSection: Hashable {
    case general
    case shortcuts
}
