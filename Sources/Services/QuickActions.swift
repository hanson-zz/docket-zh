import AppKit
import Foundation

/// The quick toggles' actions, each through a public door.
///
/// Dark Mode and emptying the Trash are AppleScript to System Events and
/// Finder, which is what those apps publish for it; macOS asks once for
/// Automation consent. Locking is `pmset displaysleepnow`, which sleeps the
/// display and so locks the Mac when a password is required after sleep, the
/// macOS default. The screen saver is its own app. Do Not Disturb and Focus
/// have no public switch at all, so they are not offered.
@MainActor
enum QuickActions {
    enum Action: String, CaseIterable {
        case darkMode, lock, screenSaver, emptyTrash

        var symbol: String {
            switch self {
            case .darkMode: "circle.lefthalf.filled"
            case .lock: "lock.fill"
            case .screenSaver: "sparkles.tv"
            case .emptyTrash: "trash"
            }
        }

        var title: String {
            switch self {
            case .darkMode: "切换暗色模式"
            case .lock: "锁屏（关闭显示器）"
            case .screenSaver: "屏幕保护程序"
            case .emptyTrash: "清空废纸篓"
            }
        }
    }

    static var isDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func perform(_ action: Action) {
        switch action {
        case .darkMode:
            run("/usr/bin/osascript", ["-e",
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"])
        case .lock:
            run("/usr/bin/pmset", ["displaysleepnow"])
        case .screenSaver:
            let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration())
        case .emptyTrash:
            guard confirmEmptyTrash() else { return }
            run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
        }
    }

    /// Same brief promotion to a regular app the shelf uses for its other
    /// alerts, so the question is in front rather than behind the frontmost
    /// window.
    private static func confirmEmptyTrash() -> Bool {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let alert = NSAlert()
        alert.messageText = "要清空废纸篓吗？"
        alert.informativeText = "废纸篓中的所有项目将被永久抹掉，此操作无法撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空废纸篓")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
