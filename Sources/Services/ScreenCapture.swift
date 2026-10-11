import AppKit
import Foundation

/// Runs `/usr/sbin/screencapture`, the same tool ⇧⌘3 and ⇧⌘4 drive.
///
/// The file goes where the user's own screenshots go, named the way macOS
/// names them, so the Screenshots widget picks it up like any other. The
/// tool is told the path as an argument rather than through a shell, so a
/// folder name with spaces needs no quoting.
///
/// Capturing other apps' windows needs Screen Recording consent for Docket:
/// without it the system hands back the desktop and the menu bar only.
@MainActor
enum ScreenCapture {
    enum Mode: CaseIterable {
        case window, region, screen

        var arguments: [String] {
            switch self {
            case .window: ["-i", "-W"]
            case .region: ["-i", "-s"]
            case .screen: []
            }
        }

        var symbol: String {
            switch self {
            case .window: "macwindow"
            case .region: "rectangle.dashed"
            case .screen: "display"
            }
        }

        var title: String {
            switch self {
            case .window: "截取窗口"
            case .region: "截取区域"
            case .screen: "截取全屏"
            }
        }
    }

    private static var running = false

    static func capture(_ mode: Mode) {
        guard !running else { return }
        running = true
        let folder = FolderFeed.folder(for: .screenshots)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = folder.appendingPathComponent("截屏\(formatter.string(from: .now)).png")
        let arguments = mode.arguments + [url.path]
        Task {
            _ = await Self.run(arguments)
            running = false
            FolderFeed.shared(.screenshots).refresh(force: true)
        }
    }

    nonisolated private static func run(_ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            // Waited on from a background thread, so the process object stays
            // alive exactly as long as the capture does.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }
}
