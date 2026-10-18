import AppKit
import Foundation

/// 「打开某张小组件的面板」的请求都从这里分派：到点提醒弹出卡片上点了主体、
/// 点了带小组件 id 的系统通知（股票到价、久坐）。
///
/// 原来请求直接交给扩展栏，扩展栏只在自己当前那一层里找卡片，所以卡片在
/// 文件夹里、在别的布局里、扩展栏没开时什么都不发生。现在按 `WidgetPanelRoute`：
///
/// - 卡片就在扩展栏上：从它的位置长出来；扩展栏自动隐藏着就先滑出来。
/// - 卡片在当前布局的文件夹里：从文件夹的位置长出来，不用先打开文件夹。
/// - 卡片在别的布局里、只用系统程序坞、或卡片被条件隐藏着：以独立的浮动面板
///   打开，挂在屏幕顶部正中（弹出卡片刚才的位置）。不切换布局：到点看一眼就
///   换掉整条扩展栏太打扰，面板里的改动照样写回那个布局里的小组件。
@MainActor
final class WidgetPanelOpener {
    static let shared = WidgetPanelOpener()

    /// 请扩展栏从某张卡片（或装着它的文件夹）长出面板。`userInfo["id"]` 是小组件 id，
    /// `userInfo["folder"]` 有的话是当前布局顶层那个文件夹的 id。
    static let shelfRequest = Notification.Name("com.docket-zh.widget-panel.open-on-shelf")

    /// DocketApp 接上。
    var currentItems: @MainActor () -> [DockItem] = { [] }

    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: ReminderPopupCenter.openPanelRequest,
                                                          object: nil, queue: .main) { note in
            let raw = note.userInfo?["id"] as? String
            MainActor.assumeIsolated {
                guard let raw, let id = UUID(uuidString: raw) else { return }
                WidgetPanelOpener.shared.open(id)
            }
        }
    }

    func open(_ id: UUID) {
        let instance = WidgetWriter.current(id)
        let route = WidgetPanelRoute.decide(widget: id, current: currentItems(),
                                            existsAnywhere: instance != nil,
                                            shelfShown: ShelfPresence.shared.isShown(),
                                            hasDetail: instance.map { WidgetDetail.exists(for: $0.kind) } ?? false)
        switch route {
        case .none:
            return
        case .tile:
            NotificationCenter.default.post(name: Self.shelfRequest, object: nil, userInfo: ["id": id.uuidString])
        case .folder(let folder):
            NotificationCenter.default.post(name: Self.shelfRequest, object: nil,
                                            userInfo: ["id": id.uuidString, "folder": folder.uuidString])
        case .floating:
            openFloating(id)
        }
    }

    /// 扩展栏上找不到可挂的位置时（卡片被条件隐藏）也走这里。
    func openFloating(_ id: UUID) {
        guard let instance = WidgetWriter.current(id), WidgetDetail.exists(for: instance.kind) else { return }
        TooltipWindow.shared.hide()
        GroupWindow.shared.close()
        WidgetDetailWindow.shared.openFloating(instance, now: .now)
    }
}
