import Foundation

/// What kind of Bluetooth accessory a battery belongs to, for its icon and
/// its place in the 电池 widget.
public enum AccessoryKind: String, CaseIterable, Codable, Sendable {
    case airpods, airpodsPro, airpodsMax, headphones, mouse, trackpad,
         keyboard, speaker, gameController, other

    public var title: String {
        switch self {
        case .airpods: "AirPods"
        case .airpodsPro: "AirPods Pro"
        case .airpodsMax: "AirPods Max"
        case .headphones: tr("耳机")
        case .mouse: tr("鼠标")
        case .trackpad: tr("触控板")
        case .keyboard: tr("键盘")
        case .speaker: tr("音箱")
        case .gameController: tr("游戏手柄")
        case .other: tr("蓝牙设备")
        }
    }

    /// SF Symbols names. All of them date from macOS 11 or 12; the views
    /// still check each one and fall back to `fallbackSymbol`.
    public var symbol: String {
        switch self {
        case .airpods: "airpods"
        case .airpodsPro: "airpodspro"
        case .airpodsMax: "airpodsmax"
        case .headphones: "headphones"
        case .mouse: "magicmouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .keyboard: "keyboard"
        case .speaker: "hifispeaker"
        case .gameController: "gamecontroller"
        case .other: Self.fallbackSymbol
        }
    }

    public static let fallbackSymbol = "dot.radiowaves.left.and.right"

    public var isAirPods: Bool { self == .airpods || self == .airpodsPro || self == .airpodsMax }

    /// Earbuds and headphones die fastest and are the ones in use when they
    /// do, so they lead; then what the hands are on; then the rest.
    public var rank: Int {
        switch self {
        case .airpods, .airpodsPro, .airpodsMax, .headphones: 0
        case .mouse: 1
        case .trackpad: 2
        case .keyboard: 3
        case .gameController: 4
        case .speaker: 5
        case .other: 6
        }
    }
}

/// Everything the registry or System Information says about one accessory
/// that can tell what it is.
public struct AccessoryHints: Sendable {
    public var name: String
    public var productID: Int?
    public var vendorID: Int?
    /// System Information's `device_minorType`: "Headphones", "Mouse", ...
    public var minorType: String?
    /// The HID primary usage page and usage, where the registry has them.
    public var usagePage: Int?
    public var usage: Int?
    /// Reports separate left and right buds.
    public var hasBuds: Bool

    public init(name: String, productID: Int? = nil, vendorID: Int? = nil, minorType: String? = nil,
                usagePage: Int? = nil, usage: Int? = nil, hasBuds: Bool = false) {
        self.name = name
        self.productID = productID
        self.vendorID = vendorID
        self.minorType = minorType
        self.usagePage = usagePage
        self.usage = usage
        self.hasBuds = hasBuds
    }
}

public enum AccessoryClassifier {
    /// Apple's Bluetooth vendor ID, and its USB one (Magic accessories keep
    /// the same product ID over both).
    public static let appleVendors: Set<Int> = [0x004C, 0x05AC]

    /// Apple and Beats product IDs. Sources: The Apple Wiki "Bluetooth PIDs"
    /// for audio, Linux `hid-ids.h` for the Magic accessories. A product
    /// missing here still goes through the type and name checks below.
    public static let appleProducts: [Int: AccessoryKind] = [
        0x2002: .airpods, 0x200F: .airpods, 0x2013: .airpods, 0x2019: .airpods, 0x201B: .airpods,
        0x200E: .airpodsPro, 0x2014: .airpodsPro, 0x2024: .airpodsPro,
        0x200A: .airpodsMax, 0x201F: .airpodsMax, 0x202D: .airpodsMax,
        // Beats headphones and earbuds.
        0x2003: .headphones, 0x2005: .headphones, 0x2006: .headphones, 0x2009: .headphones,
        0x200B: .headphones, 0x200C: .headphones, 0x200D: .headphones, 0x2010: .headphones,
        0x2011: .headphones, 0x2012: .headphones, 0x2016: .headphones, 0x2017: .headphones,
        0x2025: .headphones, 0x2026: .headphones,
        // Beats speakers.
        0x201A: .speaker, 0x2600: .speaker,
        // Magic Mouse, Magic Trackpad, Magic Keyboard.
        0x030D: .mouse, 0x0269: .mouse, 0x0323: .mouse,
        0x030E: .trackpad, 0x0265: .trackpad, 0x0324: .trackpad,
        0x0267: .keyboard, 0x026C: .keyboard, 0x029A: .keyboard, 0x029C: .keyboard,
        0x029F: .keyboard, 0x0320: .keyboard, 0x0321: .keyboard, 0x0322: .keyboard,
    ]

    /// Product ID first, since it cannot be renamed. Then the AirPods family
    /// by name, the class the device declares, the name's keywords, and the
    /// HID usage. Anything left is `.other`.
    public static func kind(_ hints: AccessoryHints) -> AccessoryKind {
        let apple = hints.vendorID.map { appleVendors.contains($0) } ?? false
        if apple, let id = hints.productID, let kind = appleProducts[id] {
            return kind
        }
        let name = hints.name.lowercased()
        if let pods = airPods(name) { return pods }
        if let minor = hints.minorType.flatMap(fromMinorType) { return minor }
        if let named = fromName(name) { return named }
        if let usage = fromUsage(page: hints.usagePage, usage: hints.usage) { return usage }
        return hints.hasBuds ? .headphones : .other
    }

    static func airPods(_ name: String) -> AccessoryKind? {
        guard name.contains("airpods") else { return nil }
        if name.contains("max") { return .airpodsMax }
        if name.contains("pro") { return .airpodsPro }
        return .airpods
    }

    public static func fromMinorType(_ raw: String) -> AccessoryKind? {
        let type = raw.lowercased()
        if type.contains("trackpad") || type.contains("touchpad") { return .trackpad }
        if type.contains("mouse") || type.contains("pointing") { return .mouse }
        if type.contains("keyboard") { return .keyboard }
        if type.contains("gamepad") || type.contains("joystick") || type.contains("game") { return .gameController }
        if type.contains("speaker") || type.contains("loudspeaker") || type.contains("hifi")
            || type.contains("portable audio") { return .speaker }
        if type.contains("headphone") || type.contains("headset") || type.contains("earbud")
            || type.contains("handsfree") || type.contains("hands-free") { return .headphones }
        return nil
    }

    /// Order matters. "Beats Pill" is a speaker though "beats" alone means
    /// headphones, and "Xbox Wireless Headset" is a headset though "xbox"
    /// alone means a controller, so the definite words go first and the
    /// brand words last.
    static func fromName(_ name: String) -> AccessoryKind? {
        func has(_ words: [String]) -> Bool { words.contains { name.contains($0) } }
        if has(["trackpad", "touchpad", tr("触控板"), tr("妙控板")]) { return .trackpad }
        if has(["mouse", tr("鼠标"), "mx master", "mx anywhere"]) { return .mouse }
        if has(["keyboard", tr("键盘"), "keychron"]) { return .keyboard }
        if has(["headphone", "headset", "earphone", "earbud", tr("耳机"), tr("耳麦")]) { return .headphones }
        if has(["controller", "gamepad", tr("手柄"), "xbox", "dualsense", "dualshock", "joy-con",
                "8bitdo"]) { return .gameController }
        if has(["speaker", tr("音箱"), tr("音响"), "soundbar", "soundlink", "beats pill", "homepod",
                "jbl flip", "jbl charge", "jbl go", "megaboom", "wonderboom"]) { return .speaker }
        if has(["buds", "beats", "powerbeats", "wh-1000", "wf-1000", "quietcomfort", "freebuds"]) {
            return .headphones
        }
        return nil
    }

    /// HID usage page 1 (generic desktop): 2 mouse, 4 joystick, 5 gamepad,
    /// 6 keyboard. Page 0x0D (digitizer) usage 5 is a touch pad.
    static func fromUsage(page: Int?, usage: Int?) -> AccessoryKind? {
        switch (page, usage) {
        case (1, 2): .mouse
        case (1, 4), (1, 5): .gameController
        case (1, 6), (1, 7): .keyboard
        case (0x0D, 5): .trackpad
        default: nil
        }
    }
}

/// One Bluetooth accessory's battery, as the 电池 widget shows it.
///
/// Levels are whole percentages, 1...100, or nil when that part did not
/// report. A buds pair has `left`/`right` (and maybe `caseLevel`); anything
/// else has `main`.
public struct BluetoothBattery: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: AccessoryKind
    public var main: Int?
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var charging: Bool
    public var address: String?
    /// 这份电量是什么时候读到的。注册表每秒都在读，记 nil（算「刚读到」）；
    /// 系统信息几分钟才读一次，记那次快照开始的时刻。
    public var readAt: Date?
    /// 读数已经超过 `BluetoothBatteries.staleAfter`，界面要标「数据已过期」。
    /// 由采样器按 `BluetoothBatteries.markStale` 算好放进来，只在跨过阈值时变一次。
    public var stale: Bool

    public init(id: String, name: String, kind: AccessoryKind, main: Int? = nil, left: Int? = nil,
                right: Int? = nil, caseLevel: Int? = nil, charging: Bool = false, address: String? = nil,
                readAt: Date? = nil, stale: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.main = main
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.charging = charging
        self.address = address
        self.readAt = readAt
        self.stale = stale
    }

    /// 连着，但设备本身的电量读不到（充电盒单独报的不算设备电量）。
    public var isUnreadable: Bool { level == nil }

    /// 这一行电量能不能信：有新读数、读数过期、连着但读不到。
    public var readState: AccessoryReadState {
        if isUnreadable { return .unreadable }
        return stale ? .stale : .fresh
    }

    /// 有电量又不过期的排最前，过期的其次，读不到的最后。
    var validityRank: Int {
        switch readState {
        case .fresh: 0
        case .stale: 1
        case .unreadable: 2
        }
    }

    /// The reading that matters: the emptier bud, since it dies first, or
    /// the one battery there is. A case alone is not the device's level.
    public var level: Int? {
        [left, right].compactMap(\.self).min() ?? main
    }

    public var hasBuds: Bool { left != nil || right != nil }

    /// The name to print, never empty.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    /// "左 80% · 右 78% · 盒 45%", only the parts that reported.
    public var partsCaption: String? {
        let parts = [(tr("左"), left), (tr("右"), right), (tr("盒"), caseLevel)]
            .compactMap { label, value in value.map { "\(label) \($0)%" } }
        guard hasBuds || caseLevel != nil else { return nil }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Parsing helpers

    /// A percentage from the registry (an integer) or System Information
    /// ("80%"). Zero is a stale entry for something not connected, so it is
    /// unknown rather than empty.
    public static func percent(_ value: Any?) -> Int? {
        let raw: Double?
        switch value {
        case let number as NSNumber: raw = number.doubleValue
        case let int as Int: raw = Double(int)
        case let double as Double: raw = double
        case let string as String:
            raw = Double(string.trimmingCharacters(in: CharacterSet(charactersIn: "% \t")))
        default: raw = nil
        }
        guard let raw, raw > 0, raw <= 100 else { return nil }
        return Int(raw.rounded())
    }

    /// "0x004C", "76", or a number.
    public static func hexOrInt(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let int as Int: return int
        case let string as String:
            let s = string.trimmingCharacters(in: .whitespaces).lowercased()
            if s.hasPrefix("0x") { return Int(s.dropFirst(2), radix: 16) }
            return Int(s)
        default: return nil
        }
    }

    /// "AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff" and "aabbccddeeff" are one
    /// address. Nil unless it is twelve hex digits.
    public static func normalizedAddress(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let hex = raw.uppercased().filter { $0.isHexDigit }
        return hex.count == 12 ? hex : nil
    }

    static func normalizedName(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .filter { !$0.isWhitespace }
    }

    /// The stable identity: the address when known, else the name.
    public static func makeID(address: String?, name: String) -> String {
        if let address = normalizedAddress(address) { return address }
        return "name:" + normalizedName(name)
    }
}

/// 一个连着的配件，电量现在是什么情况。
public enum AccessoryReadState: Equatable, Sendable {
    /// 有电量，读数新。
    case fresh
    /// 有电量，但读数超过 `BluetoothBatteries.staleAfter` 没更新。
    case stale
    /// 连着，读不到电量：显示「电量不可获取」，不编百分比。
    case unreadable
}

// MARK: - System Information

/// Reads `system_profiler SPBluetoothDataType -json`.
///
/// Connected devices sit under `device_connected` as one-key dictionaries,
/// name to properties. Batteries are strings like "80%": `Main` for a mouse
/// or a third-party headset, `Left`/`Right`/`Case` for buds. Only devices
/// with at least one battery are returned.
public enum SystemProfilerBluetooth {
    /// `keepUnreadable` 为 true 时，耳机、鼠标、触控板、键盘这几类连着但没报电量的
    /// 也返回（电量全是 nil），界面写「电量不可获取」；音箱、手柄这类本来就常常不报电量，
    /// 照旧不列。`readAt` 是这次快照开始的时刻。
    public static func parse(_ data: Data, keepUnreadable: Bool = false,
                             readAt: Date? = nil) -> [BluetoothBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        var found: [BluetoothBattery] = []
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let props = value as? [String: Any],
                          var device = device(name: name, props, keepUnreadable: keepUnreadable)
                    else { continue }
                    device.readAt = readAt
                    BluetoothBatteries.insert(device, into: &found)
                }
            }
        }
        return found
    }

    static func device(name: String, _ props: [String: Any], keepUnreadable: Bool = false) -> BluetoothBattery? {
        let main = BluetoothBattery.percent(props["device_batteryLevelMain"])
            ?? BluetoothBattery.percent(props["device_batteryLevel"])
        let left = BluetoothBattery.percent(props["device_batteryLevelLeft"])
        let right = BluetoothBattery.percent(props["device_batteryLevelRight"])
        let caseLevel = BluetoothBattery.percent(props["device_batteryLevelCase"])
        let address = props["device_address"] as? String
        let kind = AccessoryClassifier.kind(AccessoryHints(
            name: name,
            productID: BluetoothBattery.hexOrInt(props["device_productID"]),
            vendorID: BluetoothBattery.hexOrInt(props["device_vendorID"]),
            minorType: props["device_minorType"] as? String,
            hasBuds: left != nil || right != nil))
        let reported = main != nil || left != nil || right != nil || caseLevel != nil
        guard reported || (keepUnreadable && BluetoothBatteries.tracksUnreadable(kind)) else { return nil }
        return BluetoothBattery(id: BluetoothBattery.makeID(address: address, name: name),
                                name: name, kind: kind, main: main, left: left, right: right,
                                caseLevel: caseLevel, charging: false,
                                address: BluetoothBattery.normalizedAddress(address))
    }
}

// MARK: - Merging and ordering

public enum BluetoothBatteries {
    /// 读数超过这么久没更新就标「数据已过期」。注册表每秒都读，只有电量来自系统信息的配件
    /// 会走到这一步，而那时系统信息每 `profilerFastInterval` 秒读一次：连着两轮没读上来才算过期。
    public static let staleAfter: TimeInterval = 4 * 60

    /// 系统信息平时多久读一次；有电量只能靠它的配件（注册表不知道的多数第三方耳机、鼠标，
    /// 或注册表里读不到电量的那台）时改成 `profilerFastInterval`，那台关机以后旧电量最多再挂一轮。
    public static let profilerNormalInterval: TimeInterval = 5 * 60
    public static let profilerFastInterval: TimeInterval = 90
    /// 系统信息快照超过这么久（读失败了好几轮）就整份不用，只靠它知道的配件跟着消失。
    public static let profilerDropAfter: TimeInterval = 11 * 60

    /// 下一次读系统信息要隔多久：上一份快照里有配件的电量只能靠它（注册表里没有这台，
    /// 或有但读不到电量）时用短间隔。
    public static func profilerInterval(registry: [BluetoothBattery],
                                        profiler: [BluetoothBattery]) -> TimeInterval {
        let reliesOnProfiler = profiler.contains { extra in
            guard let live = registry.first(where: { sameDevice($0, extra) }) else { return true }
            return live.level == nil && extra.level != nil
        }
        return reliesOnProfiler ? profilerFastInterval : profilerNormalInterval
    }

    /// 连着却读不到电量时也要列出来（写「电量不可获取」）的几类：耳机、鼠标、触控板、键盘。
    /// 音箱、手柄和不认识的设备本来就常常不报电量，列出来只是一排读不到的行。
    public static func tracksUnreadable(_ kind: AccessoryKind) -> Bool {
        switch kind {
        case .airpods, .airpodsPro, .airpodsMax, .headphones, .mouse, .trackpad, .keyboard: true
        case .speaker, .gameController, .other: false
        }
    }

    /// 注册表里一个没报电量的服务要不要当成「连着但读不到」：只认蓝牙连着的那几类。
    /// 有线连着的妙控键盘、USB 鼠标不是这里说的电池设备。`Built-In` 的在采样器那边就跳过了。
    public static func keepsUnreadable(kind: AccessoryKind, transport: String?) -> Bool {
        guard tracksUnreadable(kind), let transport else { return false }
        return transport.lowercased().contains("bluetooth")
    }

    /// 同一台设备：两边都有地址时比地址，否则比名字。
    public static func sameDevice(_ a: BluetoothBattery, _ b: BluetoothBattery) -> Bool {
        if let x = a.address, let y = b.address { return x == y }
        return BluetoothBattery.normalizedName(a.name) == BluetoothBattery.normalizedName(b.name)
    }

    /// 一台设备可能挂好几个服务：同一个 id 只留一份，先到的赢；但先到的那份读不到电量、
    /// 后到的读得到时换成后到的，免得一个不报电量的服务把真电量挡掉。
    public static func insert(_ device: BluetoothBattery, into list: inout [BluetoothBattery]) {
        guard let index = list.firstIndex(where: { $0.id == device.id }) else {
            list.append(device)
            return
        }
        let current = list[index]
        let currentReports = current.level != nil || current.caseLevel != nil
        let newReports = device.level != nil || device.caseLevel != nil
        if !currentReports && newReports { list[index] = device }
    }

    /// The registry's readings (live, every second) with System
    /// Information's (every few minutes) folded in.
    ///
    /// The same device matches by address, or by name when either side has
    /// no address. The registry's levels win; System Information fills the
    /// parts the registry did not report and a kind the registry could only
    /// guess at. Devices only System Information knows (most non-Apple
    /// headsets, speakers and controllers) are appended.
    ///
    /// `departed` 是上一份系统信息快照之后从注册表里消失的设备（AirPods 收进盒子、
    /// 妙控鼠标关机）：快照还记着它们连着、还有旧电量，但它们已经断开了，不能拿旧百分比
    /// 再画出来，等下一份快照再说。
    ///
    /// 结果里留下有电量的，以及连着但读不到电量的耳机、鼠标、触控板、键盘。
    public static func merge(registry: [BluetoothBattery], profiler: [BluetoothBattery],
                             departed: [BluetoothBattery] = []) -> [BluetoothBattery] {
        var result = registry
        for extra in profiler {
            if !registry.contains(where: { sameDevice($0, extra) }),
               departed.contains(where: { sameDevice($0, extra) }) { continue }
            let index = result.firstIndex { sameDevice($0, extra) }
            guard let index else {
                result.append(extra)
                continue
            }
            var merged = result[index]
            if merged.left == nil && merged.right == nil && merged.main == nil {
                merged.left = extra.left
                merged.right = extra.right
                merged.main = extra.main
                // 电量是系统信息那份给的，读到的时刻也跟着它，过期了照样要标出来。
                if merged.level != nil { merged.readAt = extra.readAt }
            }
            if merged.caseLevel == nil { merged.caseLevel = extra.caseLevel }
            if merged.address == nil { merged.address = extra.address }
            if merged.kind == .other || (merged.kind == .headphones && extra.kind.isAirPods) {
                merged.kind = extra.kind
            }
            result[index] = merged
        }
        return result.filter { $0.level != nil || $0.caseLevel != nil || tracksUnreadable($0.kind) }
    }

    /// 按 `readAt` 标出过期的读数。注册表读数（`readAt` 为 nil）永远不过期。
    public static func markStale(_ devices: [BluetoothBattery], now: Date,
                                 after: TimeInterval = staleAfter) -> [BluetoothBattery] {
        devices.map { device in
            var copy = device
            copy.stale = device.level != nil && (device.readAt.map { now.timeIntervalSince($0) > after } ?? false)
            return copy
        }
    }

    /// The panel's order: devices with a usable level first (fresh, then
    /// stale, then unreadable), then by kind, then by name, so rows do not
    /// reshuffle as levels change.
    public static func panelOrder(_ devices: [BluetoothBattery]) -> [BluetoothBattery] {
        devices.sorted {
            if $0.validityRank != $1.validityRank { return $0.validityRank < $1.validityRank }
            if $0.kind.rank != $1.kind.rank { return $0.kind.rank < $1.kind.rank }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// At or below this a device jumps the queue for a slot on the card.
    public static let lowLevel = 20

    /// Which accessories get the card's few slots.
    ///
    /// 1. A battery at or below 20% that is not charging and not stale: it needs seeing.
    /// 2. A fresh reading before a stale one.
    /// 3. Then by kind: earbuds and headphones, mouse, trackpad, keyboard,
    ///    controller, speaker, anything else.
    /// 4. Then the emptier first, then by name.
    ///
    /// Devices with no level are left out; `excluding` holds devices the
    /// card already shows in a slot of their own (a configured AirPods or
    /// keyboard), so nothing appears twice.
    public static func tilePicks(_ devices: [BluetoothBattery], excluding: Set<String> = [],
                                 limit: Int) -> [BluetoothBattery] {
        guard limit > 0 else { return [] }
        func urgent(_ d: BluetoothBattery) -> Bool { !d.charging && !d.stale && (d.level ?? 101) <= lowLevel }
        return Array(devices
            .filter { !excluding.contains($0.id) && $0.level != nil }
            .sorted {
                if urgent($0) != urgent($1) { return urgent($0) }
                if $0.stale != $1.stale { return !$0.stale }
                if $0.kind.rank != $1.kind.rank { return $0.kind.rank < $1.kind.rank }
                if ($0.level ?? 0) != ($1.level ?? 0) { return ($0.level ?? 0) < ($1.level ?? 0) }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            .prefix(limit))
    }

    /// 旧的固定「耳机」格读哪一台：读得到电量的 AirPods（带左右耳的优先），再是读得到电量的
    /// 其他带左右耳的耳机，都没有才轮到连着但读不到电量的 AirPods（那一格写「电量不可获取」）。
    /// 过期的读数排在新读数后面。
    public static func budsSource(_ devices: [BluetoothBattery]) -> BluetoothBattery? {
        for rank in 0...1 {
            let tier = devices.filter { $0.validityRank == rank }
            if let pick = tier.first(where: { $0.kind.isAirPods && $0.hasBuds })
                ?? tier.first(where: { $0.kind.isAirPods })
                ?? tier.first(where: { $0.hasBuds }) {
                return pick
            }
        }
        return devices.first { $0.kind.isAirPods }
    }

    /// 旧的固定「键盘」格读哪一台：读得到电量的优先，新读数优先。
    public static func keyboardSource(_ devices: [BluetoothBattery]) -> BluetoothBattery? {
        devices.filter { $0.kind == .keyboard }.min { $0.validityRank < $1.validityRank }
    }

    /// 多设备卡片第四格放哪一台外设：先按电量能不能信分层（新读数、过期、读不到），
    /// 同一层里鼠标、触控板、键盘、其他。AirPods 和耳机那一格已经在读的那台不放进来。
    /// 读不到电量的只有 `tracksUnreadable` 那几类会在清单里，这一格写「电量不可获取」。
    public static func peripheralPick(_ devices: [BluetoothBattery], excluding budsID: String?) -> BluetoothBattery? {
        let candidates = devices.filter { !$0.kind.isAirPods && $0.id != budsID }
        for rank in 0...2 {
            let tier = candidates.filter { $0.validityRank == rank }
            if let pick = tier.first(where: { $0.kind == .mouse })
                ?? tier.first(where: { $0.kind == .trackpad })
                ?? tier.first(where: { $0.kind == .keyboard })
                ?? tier.first {
                return pick
            }
        }
        return nil
    }

    /// One alert reading per battery, the case on its own, ids stable per
    /// device so a level speaks once however the device is listed.
    public static func alertReadings(_ devices: [BluetoothBattery]) -> [AccessoryReading] {
        var readings: [AccessoryReading] = []
        for device in devices {
            if let level = device.level {
                readings.append(AccessoryReading(id: "bt.\(device.id)", name: device.displayName, percent: level))
            }
            if let caseLevel = device.caseLevel {
                readings.append(AccessoryReading(id: "bt.\(device.id).case",
                                                 name: tr("\(device.displayName) 充电盒"), percent: caseLevel))
            }
        }
        return readings
    }
}

// MARK: - The card's slots

/// How many slots the 电池 card has, read from its configuration alone so
/// the shelf can size it before anything is connected.
public enum BatteryShelf {
    public static let bluetoothKey = "bluetooth"
    /// Extra slots a card keeps for connected Bluetooth accessories.
    public static let accessorySlots = 2

    /// On unless switched off, which is what a widget saved before the
    /// option existed gets too.
    public static func showsBluetooth(_ config: WidgetConfig) -> Bool {
        config.bool(bluetoothKey, default: true)
    }

    public static func configuredCount(_ config: WidgetConfig) -> Int {
        max(1, config.strings("devices", default: ["mac"]).count)
    }

    /// The single-device 电量 card keeps its own size and swaps to gauges
    /// when accessories are connected; it gets no extra slots.
    public static func isStatusCard(_ config: WidgetConfig) -> Bool {
        configuredCount(config) == 1 && config.string("layout", default: "status") == "status"
    }

    /// Slots across a row (or down a column).
    public static func slotCount(_ config: WidgetConfig) -> Int {
        configuredCount(config) + (showsBluetooth(config) ? accessorySlots : 0)
    }

    /// How many accessories the card can add beyond its configured devices.
    public static func accessoryRoom(_ config: WidgetConfig) -> Int {
        showsBluetooth(config) ? accessorySlots : 0
    }
}

// MARK: - Registry departures

/// 记下哪些配件从注册表里消失了，好让上一份系统信息快照不再把它们的旧电量画回来。
///
/// 注册表每秒读一次，AirPods 收进盒子、妙控鼠标关机，下一秒就不在了；系统信息几分钟才读
/// 一次，快照里它们还「连着」、电量还是几分钟前的。消失的设备在这里记一笔（带消失时刻），
/// 重新出现就划掉；新快照到了，把快照开始前（留 `snapshotSlack` 秒余量，系统信息自己也会
/// 慢半拍）就消失的划掉，这时快照已经反映了它们断开。
public struct AccessoryDepartures: Sendable {
    public static let snapshotSlack: TimeInterval = 10

    private var seen: [BluetoothBattery] = []
    private var gone: [String: (device: BluetoothBattery, at: Date)] = [:]

    public init() {}

    /// 喂这一秒注册表里的设备，返回现在算「已断开」的那些。
    @discardableResult
    public mutating func update(registry: [BluetoothBattery], now: Date) -> [BluetoothBattery] {
        for device in seen where !registry.contains(where: { BluetoothBatteries.sameDevice($0, device) }) {
            if gone[device.id] == nil { gone[device.id] = (device, now) }
        }
        for device in registry {
            gone = gone.filter { !BluetoothBatteries.sameDevice($0.value.device, device) }
        }
        seen = registry
        return departed
    }

    /// 一份在 `startedAt` 开始读的系统信息快照到了。
    public mutating func snapshotArrived(startedAt: Date) {
        gone = gone.filter { $0.value.at >= startedAt.addingTimeInterval(-Self.snapshotSlack) }
    }

    public var departed: [BluetoothBattery] {
        gone.values.map { $0.device }.sorted { $0.id < $1.id }
    }
}
