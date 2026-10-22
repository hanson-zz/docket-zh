import AppKit

/// 菜单栏第二时区：码头图标之外单独一个状态项，“● 纽约 03:56”。
///
/// 设置 ▸ 通用 ▸ 菜单栏里打开（默认关）。城市来自第一张世界时钟卡片的列表
/// （没有卡片时是默认的伦敦），显示哪一个见 `WorldClockMenuBar.pick`：设置或
/// 下拉里选过的，否则第一个和此处有时差的。圆点颜色是现在适不适合联系对方。
///
/// 点开是各城市的时间和联系状态，点一行改成在菜单栏显示它；末尾“菜单栏显示纽约”
/// 再点一下就关掉，“打开世界时钟面板”打开那张卡片的面板。
///
/// 每到整分钟换一次字，醒来时立刻重算并重新对齐；关掉时连状态项和计时器一起拿走，
/// 不常驻任何东西。
@MainActor
final class WorldClockStatusItem: NSObject, NSMenuDelegate {
    private let app: AppState
    private var item: NSStatusItem?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(app: AppState) {
        self.app = app
        super.init()
        refresh()
    }

    /// 设置变了（开关、选的城市）时调用。
    func refresh() {
        guard app.state.menuBar.showWorldClock else {
            remove()
            return
        }
        if item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
            schedule()
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.schedule()
                    self?.updateTitle()
                }
            }
        }
        updateTitle()
    }

    private func remove() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    /// 对齐到下一个整分钟，之后每分钟一次。
    private func schedule() {
        timer?.invalidate()
        let now = Date.now
        let next = Calendar.current.dateInterval(of: .minute, for: now)?.end ?? now.addingTimeInterval(60)
        let timer = Timer(fire: next.addingTimeInterval(0.2), interval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: 数据

    /// 第一张世界时钟卡片（当前布局优先）。
    private var widget: WidgetInstance? {
        app.allWidgets.first { $0.kind == .world }
    }

    private var cities: [WorldCity] {
        WorldClockList.cities(widget?.config ?? WidgetConfig())
    }

    private func shown(now: Date) -> WorldCity? {
        WorldClockMenuBar.pick(cities, chosen: app.state.menuBar.worldClockCity, now: now)
    }

    private static func isHere(_ city: WorldCity) -> Bool {
        WorldCities.reference()?.id == city.id
    }

    // MARK: 菜单栏上的字

    private func updateTitle() {
        guard let button = item?.button else { return }
        let now = Date.now
        guard let city = shown(now: now) else {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let text = NSMutableAttributedString()
        if !Self.isHere(city) {
            let level = WorldClockContact.reason(there: city.timeZone ?? .current, now: now).level
            text.append(NSAttributedString(string: "\u{25CF} ", attributes: [
                .foregroundColor: NSColor(sky: level.dot),
                .font: NSFont.systemFont(ofSize: size * 0.7),
                .baselineOffset: 1,
            ]))
        }
        text.append(NSAttributedString(string: WorldClockMenuBar.title(city, now: now), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular),
        ]))
        button.attributedTitle = text
        button.toolTip = WorldClockContact.reason(there: city.timeZone ?? .current, now: now).text
        button.setAccessibilityLabel("\(city.name) \(ClockFormat.time(now, zone: city.timeZone ?? .current))")
    }

    // MARK: 下拉

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date.now
        updateTitle()
        let list = cities
        let current = shown(now: now)

        for city in WorldClockMenuBar.rows(list) {
            let entry = NSMenuItem(title: city.name, action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = city.isBuiltIn ? city.id : city.storageKey
            entry.attributedTitle = row(city, now: now)
            entry.state = city.id == current?.id ? .on : .off
            entry.toolTip = tr("在菜单栏显示\(city.name)")
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        if let current {
            let toggle = NSMenuItem(title: WorldClockMenuBar.toggleTitle(current),
                                    action: #selector(turnOff), keyEquivalent: "")
            toggle.target = self
            toggle.state = .on
            menu.addItem(toggle)
        }
        let open = NSMenuItem(title: tr("打开世界时钟面板"), action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        open.isEnabled = widget != nil
        if widget == nil { open.toolTip = tr("先在扩展栏上添加一张世界时钟卡片") }
        menu.addItem(open)
    }

    /// “● 纽约  03:56          对方在睡觉”，状态靠右，用状态色。
    private func row(_ city: WorldCity, now: Date) -> NSAttributedString {
        let zone = city.timeZone ?? .current
        let reason = WorldClockContact.reason(there: zone, now: now)
        let font = NSFont.menuFont(ofSize: 0)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 250)]
        let text = NSMutableAttributedString()
        if !Self.isHere(city) {
            text.append(NSAttributedString(string: "\u{25CF}  ", attributes: [
                .foregroundColor: NSColor(sky: reason.level.dot),
                .font: NSFont.systemFont(ofSize: font.pointSize * 0.8),
                .paragraphStyle: style,
            ]))
        }
        text.append(NSAttributedString(string: "\(city.name)  ", attributes: [
            .font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
            .paragraphStyle: style,
        ]))
        text.append(NSAttributedString(string: WorldClockInfo.hhmm(now, zone: zone), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
            .paragraphStyle: style,
        ]))
        if !Self.isHere(city) {
            let level = reason.level
            let ink = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(sky: level.inkDark) : NSColor(sky: level.inkLight)
            }
            text.append(NSAttributedString(string: "\t\(reason.text)", attributes: [
                .foregroundColor: ink,
                .font: font,
                .paragraphStyle: style,
            ]))
        }
        return text
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        app.state.menuBar.worldClockCity = key
        updateTitle()
    }

    @objc private func turnOff() {
        app.state.menuBar.showWorldClock = false
    }

    @objc private func openPanel() {
        guard let widget else { return }
        WidgetPanelOpener.shared.open(widget.id)
    }
}
