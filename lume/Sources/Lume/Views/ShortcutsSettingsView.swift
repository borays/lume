import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject private var store = ShortcutStore.shared
    @State private var query = ""

    private var groups: [(category: ShortcutCategory, commands: [AppCommandID])] {
        ShortcutCategory.allCases.compactMap { category in
            let commands = AppCommandID.allCases.filter { $0.category == category && matches($0) }
            return commands.isEmpty ? nil : (category, commands)
        }
    }

    private func matches(_ command: AppCommandID) -> Bool {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return true }
        if command.title.localizedCaseInsensitiveContains(keyword) { return true }
        if let display = store.display(for: command), display.localizedCaseInsensitiveContains(keyword) {
            return true
        }
        return command.category.rawValue.localizedCaseInsensitiveContains(keyword)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("搜索命令", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("全部恢复默认") { store.resetAll() }
                    .disabled(store.usesDefaults)
                    .help("清除所有自定义快捷键")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Form {
                    ForEach(groups, id: \.category.id) { group in
                        Section {
                            ForEach(group.commands) { command in
                                ShortcutRow(command: command)
                            }
                        } header: {
                            Text(group.category.rawValue)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}

private struct ShortcutRow: View {
    let command: AppCommandID
    @ObservedObject private var store = ShortcutStore.shared
    @State private var hovering = false

    var body: some View {
        let shortcut = store.shortcut(for: command)
        let conflicted = store.conflict(for: command) != nil
        HStack(spacing: 8) {
            Text(command.title)
            if conflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("与其他命令的组合键冲突")
            }
            Spacer(minLength: 12)
            if hovering && shortcut != command.defaultShortcut {
                Button {
                    store.reset(command)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("恢复默认\(command.defaultShortcut.map { "（\($0.display)）" } ?? "")")
            }
            ShortcutField(shortcut: shortcut, conflicted: conflicted) { value in
                store.set(value, for: command)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
