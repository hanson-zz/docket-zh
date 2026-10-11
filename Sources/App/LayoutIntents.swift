import AppIntents
import Foundation

// Switching layouts with a Focus.
//
// macOS has no public way to ask which Focus is on. What it does offer is a
// Focus filter: the app declares one, the user attaches it to a Focus in
// System Settings and picks its parameters there, and the system runs it when
// that Focus starts and again, with default parameters, when it ends. So the
// choice of layout lives with the Focus, and Docket only has to act on it.

/// Hands intent results to the running app.
///
/// The system can run an intent while the app is still launching, before
/// `AppDelegate` has an `AppState` to give it. A Focus change that arrives
/// then is held and replayed on attach rather than dropped, because dropping
/// it would leave the wrong shelf up for the whole Focus.
@MainActor
enum LayoutIntentBridge {
    private enum Pending {
        case focus(UUID?)
    }

    private static var app: AppState?
    private static var pending: Pending?

    static func attach(_ state: AppState) {
        app = state
        if case .focus(let id) = pending {
            state.focusChanged(to: id)
        }
        pending = nil
    }

    static func focusChanged(to id: UUID?) {
        guard let app else {
            pending = .focus(id)
            return
        }
        app.focusChanged(to: id)
    }

    /// Every layout, for the picker in System Settings.
    ///
    /// Read from disk when the app has not finished launching, so the picker
    /// is never empty just because the system asked early. Decoded directly
    /// instead of through `Store.load()`, which sets an unreadable file aside:
    /// a query is not the place to start moving the user's files.
    static func profiles() -> [DockProfile] {
        if let app { return app.state.profiles }
        guard let data = try? Data(contentsOf: Store().url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PersistedState.self, from: data))?.profiles ?? []
    }
}

/// A layout, as the Focus filter's picker lists it.
struct LayoutEntity: AppEntity {
    let id: UUID
    let name: String
    let isShelf: Bool

    init(_ profile: DockProfile) {
        id = profile.id
        name = profile.name
        isShelf = profile.kind == .customDock
    }

    // Computed rather than stored statics: Swift 6 rejects a mutable static,
    // and computing these costs nothing.
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Docket 布局")
    }

    static var defaultQuery: LayoutEntityQuery { LayoutEntityQuery() }

    var displayRepresentation: DisplayRepresentation {
        let kind: LocalizedStringResource = isShelf ? "扩展栏布局" : "系统程序坞布局"
        return DisplayRepresentation(title: "\(name)", subtitle: kind)
    }
}

struct LayoutEntityQuery: EntityQuery {
    func entities(for identifiers: [LayoutEntity.ID]) async throws -> [LayoutEntity] {
        let wanted = Set(identifiers)
        let all = await LayoutIntentBridge.profiles()
        return all.filter { wanted.contains($0.id) }.map(LayoutEntity.init)
    }

    func suggestedEntities() async throws -> [LayoutEntity] {
        let all = await LayoutIntentBridge.profiles()
        return all.map(LayoutEntity.init)
    }
}

/// The filter users add under System Settings > Focus > Focus Filters.
struct DocketFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource { "切换 Docket 布局" }

    @Parameter(title: "布局")
    var layout: LayoutEntity?

    var displayRepresentation: DisplayRepresentation {
        guard let layout else { return DisplayRepresentation(title: "未选择布局") }
        return DisplayRepresentation(title: "\(layout.name)", subtitle: "切换到此 Docket 布局")
    }

    func perform() async throws -> some IntentResult {
        // Only the identifier crosses to the main actor, so nothing about the
        // intent's own isolation matters here. A nil is the system reporting
        // that the Focus has ended, or a filter saved without a layout.
        let id = layout?.id
        await LayoutIntentBridge.focusChanged(to: id)
        return .result()
    }
}
