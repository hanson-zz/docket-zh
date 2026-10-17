import AppKit
import Observation

/// Mirrors the user's real Dock preferences.
///
/// The whole point of the shelf is that it feels like the Dock, and the user
/// has already told macOS exactly how they like their Dock: how big, how much
/// magnification, which edge, whether it hides. Reading those values is both
/// more accurate and less work than asking again in our own settings.
///
/// `com.apple.dock` is a public preferences domain but an undocumented schema.
/// Every read here is defensive and falls back to Apple's own defaults.
@MainActor
@Observable
public final class SystemDockSettings {
    public static let shared = SystemDockSettings()

    /// Apple's defaults, used whenever a key is missing or nonsensical.
    public private(set) var tileSize: Double = 48
    public private(set) var largeSize: Double = 64
    public private(set) var magnification: Bool = false
    public private(set) var position: DockPosition = .bottom
    public private(set) var autoHide: Bool = false

    /// The apps pinned to the real Dock, in Dock order.
    ///
    /// Mirrored live rather than imported once, so pinning an app in the real
    /// Dock puts it on the shelf immediately and there is no stale copy to
    /// reconcile.
    public private(set) var pinnedApps: [DockItem] = []

    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() { refresh() }

    /// Shelf scale that renders icons at the same size as the real Dock's.
    ///
    /// Inverts `Geometry.contentScale`, since a shelf icon is `48 * contentScale(scale)`.
    public var matchedScale: Double {
        let factor = tileSize / 48
        let scale = factor < 1 ? factor / 2 : (factor - 0.75) / 0.5
        return Geometry.clamp(scale, Geometry.scaleRange)
    }

    /// How much the biggest magnified icon exceeds a resting one.
    public var magnificationPeak: Double {
        guard tileSize > 0, largeSize > tileSize else { return Geometry.magnificationPeak }
        return Geometry.clamp(largeSize / tileSize - 1, 0, 1.5)
    }

    /// Apple's falloff spans roughly three tiles either side of the pointer.
    public var magnificationRadius: Double {
        max(60, tileSize * 3)
    }

    /// Called after a reading changes, for whoever has to act on it.
    ///
    /// One observer rather than two. The shelf also needs to know when the
    /// Dock's preferences change, and having it watch the same notification
    /// separately left the two in a race: nothing orders the observers, so the
    /// shelf could re-place itself against a size and an edge this had not
    /// re-read yet. Now the values are refreshed first and the callback runs
    /// after, which is the order the shelf actually needs.
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    public func start() {
        guard observer == nil else { return }
        // The Dock posts this whenever its preferences change, so the shelf can
        // follow a size slider being dragged in System Settings live.
        //
        // Distributed, not the ordinary centre: another process posts it, and
        // NotificationCenter.default never sees it at all.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.dock.prefchanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.onChange?()
            }
        }
    }

    public func refresh() {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else { return }

        if let size = defaults.object(forKey: "tilesize") as? Double, size > 8, size < 256 {
            tileSize = size
        }
        if let size = defaults.object(forKey: "largesize") as? Double, size > 8, size < 256 {
            largeSize = size
        }
        if let value = defaults.object(forKey: "magnification") as? Bool {
            magnification = value
        }
        if let raw = defaults.string(forKey: "orientation"),
           let parsed = DockPosition(rawValue: raw), parsed.isSystemDockEdge {
            // Apple's Dock only knows left, bottom and right. `.top` is the
            // shelf's own and never read from here, so following keeps
            // mapping just those three.
            position = parsed
        }
        if let value = defaults.object(forKey: "autohide") as? Bool {
            autoHide = value
        }
        refreshPinnedApps(defaults)
    }

    private func refreshPinnedApps(_ defaults: UserDefaults) {
        guard let raw = defaults.array(forKey: "persistent-apps") as? [[String: Any]] else { return }
        var items: [DockItem] = []
        for entry in raw {
            let type = entry["tile-type"] as? String ?? ""
            if type.hasSuffix("spacer-tile") {
                items.append(.spacer(id: .stable(from: "spacer-\(items.count)"),
                                     size: type == "small-spacer-tile" ? .small : .regular))
                continue
            }
            guard let tile = entry["tile-data"] as? [String: Any],
                  let urlString = (tile["file-data"] as? [String: Any])?["_CFURLString"] as? String,
                  let url = URL(string: urlString)
            else { continue }
            let bundleID = tile["bundle-identifier"] as? String ?? ""
            // Identity from the bundle id so a Dock refresh does not churn
            // SwiftUI's view identity every time the notification fires.
            items.append(.app(id: .stable(from: bundleID.isEmpty ? urlString : bundleID),
                              bundleID: bundleID,
                              ref: FileRef(url: url)))
        }
        // Only publish a genuine change; the Dock posts its notification freely.
        if items != pinnedApps { pinnedApps = items }
    }

    /// One-line summary for the settings UI.
    public var summary: String {
        let edge = position.displayName
        let mag = magnification ? tr("放大 \(Int((magnificationPeak * 100).rounded()))%") : tr("不放大")
        return tr("\(edge) · \(Int(tileSize))pt 图标 · \(mag)")
    }
}
