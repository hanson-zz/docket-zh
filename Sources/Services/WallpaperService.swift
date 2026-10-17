import AppKit
import Observation

/// The desktop picture: what it is now, and setting a new one.
///
/// Through `NSWorkspace`, the public API for exactly this. It sets the
/// picture of the current Space on each screen; other Spaces keep their own,
/// which is how macOS itself behaves when a picture is chosen in System
/// Settings with "Show on all Spaces" off.
@MainActor @Observable
final class WallpaperService {
    static let shared = WallpaperService()

    /// The main screen's picture, re-read whenever it may have changed.
    private(set) var current: URL?
    private(set) var lastError: String?

    @ObservationIgnored private var observing = false

    private init() {}

    func start() {
        read()
        guard !observing else { return }
        observing = true
        // Another app, System Settings or a Space change can all swap the
        // picture under us.
        let center = NSWorkspace.shared.notificationCenter
        _ = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                           object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WallpaperService.shared.read() }
        }
    }

    func read() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let url = NSWorkspace.shared.desktopImageURL(for: screen)
        if url != current { current = url }
    }

    /// Sets the picture on every screen, or the main one only.
    func set(_ url: URL, allScreens: Bool) {
        let screens = allScreens ? NSScreen.screens : [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        var failed = false
        for screen in screens {
            // Keep each screen's own scaling and fill colour rather than
            // resetting them to defaults.
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            } catch {
                failed = true
            }
        }
        lastError = failed ? tr("无法设置桌面图片。") : nil
        read()
    }

    /// Moves through `files` one step from whatever is showing now.
    func step(_ step: WallpaperCycle.Step, in files: [URL], allScreens: Bool) {
        let here = current.flatMap { now in files.firstIndex { $0.standardizedFileURL == now.standardizedFileURL } }
        guard let index = WallpaperCycle.index(after: here, count: files.count, step: step,
                                               roll: Double.random(in: 0..<1)) else { return }
        set(files[index], allScreens: allScreens)
    }
}
