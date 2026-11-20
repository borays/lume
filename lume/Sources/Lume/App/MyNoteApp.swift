import AppKit
import SwiftUI

@main
struct MyNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.runAndExit()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render"),
           index + 1 < CommandLine.arguments.count {
            SelfTest.renderDebugAndExit(CommandLine.arguments[index + 1])
        }
        if let index = CommandLine.arguments.firstIndex(of: "--importweb"),
           index + 1 < CommandLine.arguments.count {
            SelfTest.webImportDebugAndExit(CommandLine.arguments[index + 1])
        }
    }

    var body: some Scene {
        WindowGroup("微光 Lume") {
            ContentView()
                .environmentObject(store)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            AppCommands(store: store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeManager.shared.apply()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
