import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// 设置 ▸ 通用 ▸ 导出诊断信息：把版本、机器、设置摘要、最近的日志和崩溃报告打成一个 zip，
/// 用户可以直接发给开发者。
///
/// 包里有：
/// - info.txt：版本、macOS、机型、屏幕、程序坞、语言、Pro 是否激活（不写激活码和邮箱）、
///   扩展栏上的卡片、桌面宠物。
/// - log.txt：最近 24 小时本进程的统一日志（码头自己的条目，加上本进程里任何错误级别的），
///   最多 `Diagnostics.logLineLimit` 行。
/// - crashes/：DiagnosticReports 里本 App 最近的 .ips。
/// - preferences.plist：本 App 的 UserDefaults，剔除敏感键（`Diagnostics.sanitizedDefaults`）。
@MainActor
enum DiagnosticsExporter {
    /// 弹存储面板，导出成功返回 zip 的位置；用户取消返回 nil。
    static func run(state: PersistedState) async throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Diagnostics.fileName(date: .now, english: L10n.isEnglish)
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.message = tr("诊断信息不含激活码、邮箱和密钥。")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let target = panel.url else { return nil }

        let info = infoText(state: state)
        let defaults = UserDefaults.standard.persistentDomain(forName: DockLog.subsystem) ?? [:]
        let preferences = try PropertyListSerialization.data(
            fromPropertyList: Diagnostics.sanitizedDefaults(defaults), format: .xml, options: 0)
        let processNames = [ProcessInfo.processInfo.processName, "Dockling"]

        try await Task.detached(priority: .userInitiated) {
            try build(target: target, info: info, preferences: preferences, processNames: processNames)
        }.value
        NSWorkspace.shared.activateFileViewerSelecting([target])
        return target
    }

    // MARK: - 打包

    nonisolated private static func build(target: URL, info: String, preferences: Data,
                                          processNames: [String]) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("dockling-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let folder = staging.appendingPathComponent(target.deletingPathExtension().lastPathComponent,
                                                    isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        try Data(info.utf8).write(to: folder.appendingPathComponent("info.txt"))
        try Data((logLines().joined(separator: "\n") + "\n").utf8)
            .write(to: folder.appendingPathComponent("log.txt"))
        try preferences.write(to: folder.appendingPathComponent("preferences.plist"))
        copyCrashReports(into: folder.appendingPathComponent("crashes", isDirectory: true),
                         processNames: processNames)

        try? fm.removeItem(at: target)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, target.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            DockLog.error(.diagnostics, "ditto failed with status \(process.terminationStatus)")
            throw DiagnosticsExportError.zip(process.terminationStatus)
        }
    }

    /// 最近 24 小时本进程的日志。取不到时写一行说明。
    nonisolated private static func logLines() -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = store.position(date: Date().addingTimeInterval(-Diagnostics.logWindow))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
            var lines: [String] = []
            for entry in try store.getEntries(at: start) {
                guard let log = entry as? OSLogEntryLog else { continue }
                let own = log.subsystem == DockLog.subsystem
                let serious = log.level == .error || log.level == .fault
                guard own || serious else { continue }
                let where_ = log.category.isEmpty ? log.subsystem : "\(log.subsystem)/\(log.category)"
                lines.append("\(formatter.string(from: log.date)) [\(name(log.level))] \(where_): \(log.composedMessage)")
                // 一边读一边截，免得一天的日志全攒在内存里。
                if lines.count > Diagnostics.logLineLimit * 2 { lines = Diagnostics.trimmedLog(lines) }
            }
            let trimmed = Diagnostics.trimmedLog(lines)
            return trimmed.isEmpty ? ["No log entries from Dockling in the last 24 hours."] : trimmed
        } catch {
            return ["Could not read the unified log: \(error.localizedDescription)"]
        }
    }

    nonisolated private static func name(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }

    /// ~/Library/Logs/DiagnosticReports 里本 App 最近的 .ips，读不到就跳过。
    nonisolated private static func copyCrashReports(into folder: URL, processNames: [String]) {
        let fm = FileManager.default
        let reports = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        let files = urls.map { url in
            (name: url.lastPathComponent,
             modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast)
        }
        let picked = Diagnostics.crashReports(files, processNames: processNames)
        guard !picked.isEmpty, (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return }
        for name in picked {
            try? fm.copyItem(at: reports.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
    }

    // MARK: - info.txt

    private static func infoText(state: PersistedState) -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        typealias Rows = [(String, String)]
        var system: Rows = [
            ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            ("Model", hardwareModel()),
            ("Screens", "\(NSScreen.screens.count)"),
        ]
        for (index, screen) in NSScreen.screens.enumerated() {
            let size = screen.frame.size
            system.append(("Screen \(index + 1)",
                           "\(Int(size.width))x\(Int(size.height)) pt @\(screen.backingScaleFactor)x, \(screen.localizedName)"))
        }

        let dockOrientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        let dockAutohide = CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool
        let dock: Rows = [
            ("macOS Dock position", dockOrientation ?? "bottom"),
            ("macOS Dock autohide", dockAutohide == true ? "yes" : "no"),
            ("Setup", "\(state.setup)"),
            ("Shelf position", "\(state.customDock.position)"),
            ("Shelf follows macOS Dock", state.customDock.followSystemDock ? "yes" : "no"),
        ]

        let app: Rows = [("Version", version), ("Build", build), ("Bundle ID", DockLog.subsystem)]
        let language: Rows = [
            ("App language setting", AppLanguage.current().rawValue),
            ("Interface", L10n.isEnglish ? "en" : "zh-Hans"),
            ("Preferred languages", Locale.preferredLanguages.prefix(3).joined(separator: ", ")),
        ]
        // 只写是否激活，激活码、邮箱一概不写。
        let pro: Rows = [("Active", ProAccess.isUnlocked ? "yes" : "no")]

        let widgets: [String] = (state.activeCustomProfile?.items ?? []).flatMap { widgetKinds($0) }
        let cards: Rows = [
            ("Count", "\(widgets.count)"),
            ("Kinds", widgets.isEmpty ? "none" : widgets.joined(separator: ", ")),
        ]

        let pet = state.desktopPet
        let petRows: Rows = [
            ("Enabled", pet.enabled ? "yes" : "no"),
            ("Anchor", pet.anchor.rawValue),
            ("Size", pet.size.rawValue),
        ]
        let switcher: Rows = [("Takes over Command-Tab", state.windowSwitcher.commandTab ? "yes" : "no")]

        let sections: [(title: String, rows: Rows)] = [
            ("App", app), ("System", system), ("Dock", dock), ("Language", language), ("Pro", pro),
            ("Shelf cards", cards), ("Desktop pet", petRows), ("Window switcher", switcher),
        ]
        return Diagnostics.infoText(sections)
    }

    /// 布局里的小组件种类，分组里的也算。
    private static func widgetKinds(_ item: DockItem) -> [String] {
        switch item {
        case .widget(let widget): [widget.kind.rawValue]
        case .group(let group): group.items.flatMap { widgetKinds($0) }
        default: []
        }
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "?" }
        return String(cString: buffer)
    }
}

/// ditto 没能打出 zip，带着它的退出码。
enum DiagnosticsExportError: Error, Sendable {
    case zip(Int32)
}
