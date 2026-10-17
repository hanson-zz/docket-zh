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

    public init(id: String, name: String, kind: AccessoryKind, main: Int? = nil, left: Int? = nil,
                right: Int? = nil, caseLevel: Int? = nil, charging: Bool = false, address: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.main = main
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.charging = charging
        self.address = address
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

// MARK: - System Information

/// Reads `system_profiler SPBluetoothDataType -json`.
///
/// Connected devices sit under `device_connected` as one-key dictionaries,
/// name to properties. Batteries are strings like "80%": `Main` for a mouse
/// or a third-party headset, `Left`/`Right`/`Case` for buds. Only devices
/// with at least one battery are returned.
public enum SystemProfilerBluetooth {
    public static func parse(_ data: Data) -> [BluetoothBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        var found: [BluetoothBattery] = []
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let props = value as? [String: Any],
                          let device = device(name: name, props) else { continue }
                    if !found.contains(where: { $0.id == device.id }) { found.append(device) }
                }
            }
        }
        return found
    }

    static func device(name: String, _ props: [String: Any]) -> BluetoothBattery? {
        let main = BluetoothBattery.percent(props["device_batteryLevelMain"])
            ?? BluetoothBattery.percent(props["device_batteryLevel"])
        let left = BluetoothBattery.percent(props["device_batteryLevelLeft"])
        let right = BluetoothBattery.percent(props["device_batteryLevelRight"])
        let caseLevel = BluetoothBattery.percent(props["device_batteryLevelCase"])
        guard main != nil || left != nil || right != nil || caseLevel != nil else { return nil }
        let address = props["device_address"] as? String
        let kind = AccessoryClassifier.kind(AccessoryHints(
            name: name,
            productID: BluetoothBattery.hexOrInt(props["device_productID"]),
            vendorID: BluetoothBattery.hexOrInt(props["device_vendorID"]),
            minorType: props["device_minorType"] as? String,
            hasBuds: left != nil || right != nil))
        return BluetoothBattery(id: BluetoothBattery.makeID(address: address, name: name),
                                name: name, kind: kind, main: main, left: left, right: right,
                                caseLevel: caseLevel, charging: false,
                                address: BluetoothBattery.normalizedAddress(address))
    }
}

// MARK: - Merging and ordering

public enum BluetoothBatteries {
    /// The registry's readings (live, every second) with System
    /// Information's (every few minutes) folded in.
    ///
    /// The same device matches by address, or by name when either side has
    /// no address. The registry's levels win; System Information fills the
    /// parts the registry did not report and a kind the registry could only
    /// guess at. Devices only System Information knows (most non-Apple
    /// headsets, speakers and controllers) are appended.
    public static func merge(registry: [BluetoothBattery], profiler: [BluetoothBattery]) -> [BluetoothBattery] {
        var result = registry
        for extra in profiler {
            let index = result.firstIndex { current in
                if let a = current.address, let b = extra.address { return a == b }
                return BluetoothBattery.normalizedName(current.name) == BluetoothBattery.normalizedName(extra.name)
            }
            guard let index else {
                result.append(extra)
                continue
            }
            var merged = result[index]
            if merged.left == nil && merged.right == nil && merged.main == nil {
                merged.left = extra.left
                merged.right = extra.right
                merged.main = extra.main
            }
            if merged.caseLevel == nil { merged.caseLevel = extra.caseLevel }
            if merged.address == nil { merged.address = extra.address }
            if merged.kind == .other || (merged.kind == .headphones && extra.kind.isAirPods) {
                merged.kind = extra.kind
            }
            result[index] = merged
        }
        return result.filter { $0.level != nil || $0.caseLevel != nil }
    }

    /// The panel's order: by kind, then by name, so rows do not reshuffle as
    /// levels change.
    public static func panelOrder(_ devices: [BluetoothBattery]) -> [BluetoothBattery] {
        devices.sorted {
            if $0.kind.rank != $1.kind.rank { return $0.kind.rank < $1.kind.rank }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// At or below this a device jumps the queue for a slot on the card.
    public static let lowLevel = 20

    /// Which accessories get the card's few slots.
    ///
    /// 1. A battery at or below 20% that is not charging: it needs seeing.
    /// 2. Then by kind: earbuds and headphones, mouse, trackpad, keyboard,
    ///    controller, speaker, anything else.
    /// 3. Then the emptier first, then by name.
    ///
    /// `excluding` holds devices the card already shows in a slot of their
    /// own (a configured AirPods or keyboard), so nothing appears twice.
    public static func tilePicks(_ devices: [BluetoothBattery], excluding: Set<String> = [],
                                 limit: Int) -> [BluetoothBattery] {
        guard limit > 0 else { return [] }
        func urgent(_ d: BluetoothBattery) -> Bool { !d.charging && (d.level ?? 101) <= lowLevel }
        return Array(devices
            .filter { !excluding.contains($0.id) && $0.level != nil }
            .sorted {
                if urgent($0) != urgent($1) { return urgent($0) }
                if $0.kind.rank != $1.kind.rank { return $0.kind.rank < $1.kind.rank }
                if ($0.level ?? 0) != ($1.level ?? 0) { return ($0.level ?? 0) < ($1.level ?? 0) }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            .prefix(limit))
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

    /// The single-device 状态 card keeps its own size and swaps to gauges
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
