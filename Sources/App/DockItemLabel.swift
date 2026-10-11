import AppKit
import SwiftUI

/// What to call an item, and what to draw for it.
///
/// Both of these existed already, privately, inside `DockShelfView`, which is
/// the only place that needed them until Settings grew a list of the items on
/// the shelf. Shared rather than copied: two functions that name the same
/// thing differently is how a shelf and its settings start disagreeing about
/// what a row is.
public extension DockItem {
    @MainActor var displayName: String {
        switch self {
        case .app(_, let bundleID, let ref):
            ref.resolve()?.deletingPathExtension().lastPathComponent
                ?? AppCatalog.shared.running.first { $0.id == bundleID }?.name
                ?? bundleID
        case .folder(_, let ref, _), .file(_, let ref):
            ref.resolve()?.lastPathComponent ?? "项目缺失"
        case .link(_, _, let title): title
        case .group(let group): group.name
        case .spacer(_, let size): size == .small ? "小间隔" : "间隔"
        case .widget(let widget): WidgetCatalog.entry(widget.kind)?.name ?? widget.kind.rawValue
        }
    }

    /// A word for what kind of thing this is, for a list that mixes them.
    var kindName: String {
        switch self {
        case .app: "应用"
        case .folder: "文件夹"
        case .file: "文件"
        case .link: "链接"
        case .spacer: "间隔"
        case .widget: "小组件"
        case .group: "分组"
        }
    }

    /// The real icon where the system has one, and a glyph where it does not.
    ///
    /// A widget has no file to ask about and a spacer is not a thing at all,
    /// so those get symbols. Everything else resolves through `AppCatalog`,
    /// which caches: `NSWorkspace.icon(forFile:)` hits the disk.
    @MainActor var listIcon: NSImage? {
        switch self {
        case .app(_, let bundleID, let ref):
            if let url = ref.resolve() { return AppCatalog.shared.icon(for: url) }
            return AppCatalog.shared.icon(forBundleID: bundleID)
        case .folder(_, let ref, _), .file(_, let ref):
            guard let url = ref.resolve() else { return nil }
            return AppCatalog.shared.icon(for: url)
        case .link, .spacer, .widget, .group:
            return nil
        }
    }

    var listSymbol: String {
        switch self {
        case .app: "app"
        case .folder: "folder"
        case .file: "doc"
        case .link: "link"
        case .spacer: "arrow.left.and.right"
        case .widget: "square.grid.2x2"
        case .group: "square.stack"
        }
    }
}

/// Fades and lifts a row into place, a beat after the one before it.
///
/// A settings pane that appears all at once reads as a screenshot. Staggering
/// gives the eye an order to read the sections in, which is the actual point:
/// it is not decoration, it is the difference between arriving at a wall of
/// controls and being walked down it.
///
/// Deliberately short. 45ms a step and under a third of a second in total,
/// because this runs every time someone opens Settings and an animation you
/// wait for is worse than none.
public struct StaggeredAppear: ViewModifier {
    public var index: Int
    /// Seconds between one row and the next.
    public var step: Double = 0.045

    @State private var shown = false

    public init(index: Int, step: Double = 0.045) {
        self.index = index
        self.step = step
    }

    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                // Capped, so a shelf with thirty items does not take a second
                // and a half to finish arriving.
                let delay = min(Double(index) * step, 0.40)
                withAnimation(.smooth(duration: 0.30).delay(delay)) { shown = true }
            }
    }
}

public extension View {
    func staggered(_ index: Int, step: Double = 0.045) -> some View {
        modifier(StaggeredAppear(index: index, step: step))
    }
}
