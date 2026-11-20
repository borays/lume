import AppKit
import SwiftUI

/// 行内快捷键控件：平时显示组合键文字，点击后在原位捕捉下一次按键。
struct ShortcutField: View {
    let shortcut: Shortcut?
    var conflicted = false
    let onRecord: (Shortcut?) -> Void

    @State private var recording = false
    @State private var hovering = false

    private var label: String {
        if recording { return "按下组合键…" }
        return shortcut?.display ?? "未设置"
    }

    private var foreground: Color {
        if recording { return .accentColor }
        if conflicted { return .red }
        return shortcut == nil ? Color(nsColor: .tertiaryLabelColor) : Color(nsColor: .labelColor)
    }

    private var background: Color {
        if recording { return Color.accentColor.opacity(0.14) }
        if hovering { return Color(nsColor: .quaternaryLabelColor).opacity(0.28) }
        return .clear
    }

    var body: some View {
        Button {
            recording = true
        } label: {
            Text(label)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(foreground)
                .lineLimit(1)
                .frame(minWidth: 78, alignment: .trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 && !recording }
        .help(recording ? "按 ⎋ 取消，按 ⌫ 清除" : "点击后按下新的快捷键")
        .overlay {
            if recording {
                KeyCaptureView(
                    onCapture: { value in
                        recording = false
                        onRecord(value)
                    },
                    onCancel: { recording = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// 只负责捕获按键的透明视图；用本地事件监听，保证 ⌘ 组合先被录制而不是触发菜单。
struct KeyCaptureView: NSViewRepresentable {
    let onCapture: (Shortcut?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
    }

    static func dismantleNSView(_ view: CaptureView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class CaptureView: NSView {
    var onCapture: ((Shortcut?) -> Void)?
    var onCancel: (() -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopMonitoring()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.startMonitoring()
        }
    }

    override func becomeFirstResponder() -> Bool {
        startMonitoring()
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopMonitoring()
        return true
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.window?.firstResponder === self else { return event }
            self.handle(event)
            return nil
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if (event.keyCode == 51 || event.keyCode == 117), modifiers.subtracting(.shift).isEmpty {
            onCapture?(nil)
            return
        }
        if let shortcut = Shortcut(event: event) {
            onCapture?(shortcut)
        }
    }

    deinit {
        stopMonitoring()
    }
}
