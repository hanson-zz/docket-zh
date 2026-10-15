import XCTest

/// Bluetooth accessories in the 电池 widget: what each one is, reading
/// System Information, merging it with the registry, and who gets the
/// card's few slots.
final class BluetoothBatteryTests: XCTestCase {
    private func kind(_ name: String, product: Int? = nil, vendor: Int? = nil, minor: String? = nil,
                      page: Int? = nil, usage: Int? = nil, buds: Bool = false) -> AccessoryKind {
        AccessoryClassifier.kind(AccessoryHints(name: name, productID: product, vendorID: vendor,
                                                minorType: minor, usagePage: page, usage: usage,
                                                hasBuds: buds))
    }

    // MARK: Classifying

    func testAppleProductIDsWinOverTheName() {
        XCTAssertEqual(kind("韩志鹏的耳机", product: 0x2014, vendor: 0x004C), .airpodsPro)
        XCTAssertEqual(kind("Studio", product: 0x200A, vendor: 76), .airpodsMax)
        XCTAssertEqual(kind("x", product: 0x2002, vendor: 0x004C), .airpods)
        XCTAssertEqual(kind("x", product: 0x0269, vendor: 0x05AC), .mouse)
        XCTAssertEqual(kind("x", product: 0x0265, vendor: 0x004C), .trackpad)
        XCTAssertEqual(kind("x", product: 0x029C, vendor: 0x004C), .keyboard)
        XCTAssertEqual(kind("x", product: 0x2012, vendor: 0x004C), .headphones)
        XCTAssertEqual(kind("x", product: 0x201A, vendor: 0x004C), .speaker)
    }

    /// The same product number from another vendor means nothing.
    func testProductIDsNeedAppleAsTheVendor() {
        XCTAssertEqual(kind("Gadget", product: 0x0269, vendor: 0x046D), .other)
        XCTAssertEqual(kind("Gadget", product: 0x0269), .other)
    }

    func testAirPodsByName() {
        XCTAssertEqual(kind("Zhipeng's AirPods Pro"), .airpodsPro)
        XCTAssertEqual(kind("AirPods Max"), .airpodsMax)
        XCTAssertEqual(kind("韩志鹏的AirPods"), .airpods)
        // The name beats a generic class: AirPods say "Headphones".
        XCTAssertEqual(kind("AirPods Pro", minor: "Headphones"), .airpodsPro)
    }

    func testMinorType() {
        XCTAssertEqual(kind("WH-X", minor: "Headphones"), .headphones)
        XCTAssertEqual(kind("Thing", minor: "Headset"), .headphones)
        XCTAssertEqual(kind("Thing", minor: "Mouse"), .mouse)
        XCTAssertEqual(kind("Thing", minor: "Trackpad"), .trackpad)
        XCTAssertEqual(kind("Thing", minor: "Keyboard"), .keyboard)
        XCTAssertEqual(kind("Thing", minor: "Speaker"), .speaker)
        XCTAssertEqual(kind("Thing", minor: "Gamepad"), .gameController)
        XCTAssertEqual(kind("Thing", minor: "Joystick"), .gameController)
        // A class this does not know falls through to the name.
        XCTAssertEqual(kind("Logi Mouse", minor: "Unknown"), .mouse)
    }

    func testEnglishNameKeywords() {
        XCTAssertEqual(kind("MX Master 3S"), .mouse)
        XCTAssertEqual(kind("Magic Trackpad"), .trackpad)
        XCTAssertEqual(kind("Magic Keyboard"), .keyboard)
        XCTAssertEqual(kind("Xbox Wireless Controller"), .gameController)
        XCTAssertEqual(kind("DualSense Wireless Controller"), .gameController)
        XCTAssertEqual(kind("Bose SoundLink Flex"), .speaker)
        XCTAssertEqual(kind("Beats Pill"), .speaker)
        XCTAssertEqual(kind("Beats Studio Buds"), .headphones)
        XCTAssertEqual(kind("Galaxy Buds2 Pro"), .headphones)
        XCTAssertEqual(kind("WH-1000XM5"), .headphones)
    }

    func testChineseNameKeywords() {
        XCTAssertEqual(kind("妙控鼠标"), .mouse)
        XCTAssertEqual(kind("妙控板"), .trackpad)
        XCTAssertEqual(kind("罗技触控板"), .trackpad)
        XCTAssertEqual(kind("妙控键盘"), .keyboard)
        XCTAssertEqual(kind("小米蓝牙音箱"), .speaker)
        XCTAssertEqual(kind("客厅音响"), .speaker)
        XCTAssertEqual(kind("Switch 手柄"), .gameController)
        XCTAssertEqual(kind("华为耳机"), .headphones)
    }

    /// A headset from a console brand is still a headset.
    func testDefiniteWordsBeatBrandWords() {
        XCTAssertEqual(kind("Xbox Wireless Headset"), .headphones)
        XCTAssertEqual(kind("游戏耳机"), .headphones)
    }

    func testHIDUsageAndBudsAsLastResorts() {
        XCTAssertEqual(kind("BT-123", page: 1, usage: 2), .mouse)
        XCTAssertEqual(kind("BT-123", page: 1, usage: 6), .keyboard)
        XCTAssertEqual(kind("BT-123", page: 1, usage: 5), .gameController)
        XCTAssertEqual(kind("BT-123", page: 0x0D, usage: 5), .trackpad)
        XCTAssertEqual(kind("BT-123", buds: true), .headphones)
        XCTAssertEqual(kind("BT-123"), .other)
    }

    func testEveryKindHasATitleAndASymbol() {
        for kind in AccessoryKind.allCases {
            XCTAssertFalse(kind.title.isEmpty, "\(kind)")
            XCTAssertFalse(kind.symbol.isEmpty, "\(kind)")
        }
        XCTAssertEqual(AccessoryKind.other.symbol, AccessoryKind.fallbackSymbol)
        XCTAssertEqual(AccessoryKind.speaker.symbol, "hifispeaker")
        XCTAssertEqual(AccessoryKind.gameController.symbol, "gamecontroller")
        XCTAssertEqual(AccessoryKind.airpodsMax.symbol, "airpodsmax")
    }

    /// No two entries for one product; a duplicate key in a dictionary
    /// literal is a crash at launch, not a compile error.
    func testTheProductTableLoads() {
        XCTAssertGreaterThan(AccessoryClassifier.appleProducts.count, 30)
    }

    // MARK: Values

    func testPercentReadsBothShapes() {
        XCTAssertEqual(BluetoothBattery.percent(NSNumber(value: 64)), 64)
        XCTAssertEqual(BluetoothBattery.percent("80%"), 80)
        XCTAssertEqual(BluetoothBattery.percent(" 7 %"), 7)
        XCTAssertNil(BluetoothBattery.percent(0), "a stale entry, not an empty battery")
        XCTAssertNil(BluetoothBattery.percent("0%"))
        XCTAssertNil(BluetoothBattery.percent(140))
        XCTAssertNil(BluetoothBattery.percent("n/a"))
        XCTAssertNil(BluetoothBattery.percent(nil))
    }

    func testHexOrInt() {
        XCTAssertEqual(BluetoothBattery.hexOrInt("0x004C"), 76)
        XCTAssertEqual(BluetoothBattery.hexOrInt("0x2014"), 0x2014)
        XCTAssertEqual(BluetoothBattery.hexOrInt("1452"), 1452)
        XCTAssertEqual(BluetoothBattery.hexOrInt(NSNumber(value: 615)), 615)
        XCTAssertNil(BluetoothBattery.hexOrInt("zz"))
    }

    func testAddressesNormalise() {
        XCTAssertEqual(BluetoothBattery.normalizedAddress("aa-bb-cc-dd-ee-ff"), "AABBCCDDEEFF")
        XCTAssertEqual(BluetoothBattery.normalizedAddress("AA:BB:CC:DD:EE:FF"), "AABBCCDDEEFF")
        XCTAssertNil(BluetoothBattery.normalizedAddress("AA:BB"))
        XCTAssertNil(BluetoothBattery.normalizedAddress(nil))
        XCTAssertEqual(BluetoothBattery.makeID(address: nil, name: "My Mouse"), "name:mymouse")
    }

    func testLevelIsTheEmptierBud() {
        let pods = BluetoothBattery(id: "p", name: "AirPods", kind: .airpods, left: 80, right: 35, caseLevel: 60)
        XCTAssertEqual(pods.level, 35)
        XCTAssertEqual(pods.partsCaption, "左 80% · 右 35% · 盒 60%")
        let oneBud = BluetoothBattery(id: "p", name: "AirPods", kind: .airpods, right: 50)
        XCTAssertEqual(oneBud.level, 50)
        XCTAssertEqual(oneBud.partsCaption, "右 50%")
        let mouse = BluetoothBattery(id: "m", name: "", kind: .mouse, main: 64)
        XCTAssertEqual(mouse.level, 64)
        XCTAssertNil(mouse.partsCaption)
        XCTAssertEqual(mouse.displayName, "鼠标", "an unnamed device falls back to its kind")
        let caseOnly = BluetoothBattery(id: "c", name: "AirPods", kind: .airpods, caseLevel: 40)
        XCTAssertNil(caseOnly.level, "a case alone is not the buds' level")
    }

    // MARK: System Information

    private let sample = """
    {
      "SPBluetoothDataType" : [
        {
          "controller_properties" : { "controller_address" : "11:22:33:44:55:66" },
          "device_connected" : [
            { "Zhipeng's AirPods Pro" : {
                "device_address" : "AA:BB:CC:DD:EE:01",
                "device_batteryLevelCase" : "45%",
                "device_batteryLevelLeft" : "90%",
                "device_batteryLevelRight" : "88%",
                "device_minorType" : "Headphones",
                "device_productID" : "0x2014",
                "device_vendorID" : "0x004C" } },
            { "MX Master 3S" : {
                "device_address" : "AA:BB:CC:DD:EE:02",
                "device_batteryLevelMain" : "62%",
                "device_minorType" : "Mouse",
                "device_productID" : "0xB034",
                "device_vendorID" : "0x046D" } },
            { "Xbox Wireless Controller" : {
                "device_address" : "AA:BB:CC:DD:EE:03",
                "device_batteryLevelMain" : "30%",
                "device_minorType" : "Gamepad" } },
            { "JBL Flip 6" : {
                "device_address" : "AA:BB:CC:DD:EE:04",
                "device_minorType" : "Speaker" } }
          ],
          "device_not_connected" : [
            { "Old Headphones" : {
                "device_address" : "AA:BB:CC:DD:EE:05",
                "device_batteryLevelMain" : "70%",
                "device_minorType" : "Headphones" } }
          ]
        }
      ]
    }
    """

    func testParsesConnectedDevicesWithABattery() {
        let devices = SystemProfilerBluetooth.parse(Data(sample.utf8))
        XCTAssertEqual(devices.map(\.name).sorted(),
                       ["MX Master 3S", "Xbox Wireless Controller", "Zhipeng's AirPods Pro"],
                       "no battery means no row; not connected means no row")

        let pods = devices.first { $0.kind == .airpodsPro }
        XCTAssertEqual(pods?.left, 90)
        XCTAssertEqual(pods?.right, 88)
        XCTAssertEqual(pods?.caseLevel, 45)
        XCTAssertEqual(pods?.id, "AABBCCDDEE01")

        let mouse = devices.first { $0.name == "MX Master 3S" }
        XCTAssertEqual(mouse?.kind, .mouse)
        XCTAssertEqual(mouse?.main, 62)

        XCTAssertEqual(devices.first { $0.name.hasPrefix("Xbox") }?.kind, .gameController)
    }

    func testParsingRubbishGivesNothing() {
        XCTAssertEqual(SystemProfilerBluetooth.parse(Data("not json".utf8)), [])
        XCTAssertEqual(SystemProfilerBluetooth.parse(Data("{}".utf8)), [])
        XCTAssertEqual(SystemProfilerBluetooth.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)), [])
    }

    // MARK: Merging

    func testMergeMatchesByAddressAndKeepsTheRegistryLevel() {
        let registry = [BluetoothBattery(id: "AABBCCDDEE01", name: "Zhipeng's AirPods Pro", kind: .airpodsPro,
                                         left: 70, right: 72, address: "AABBCCDDEE01")]
        let profiler = SystemProfilerBluetooth.parse(Data(sample.utf8))
        let merged = BluetoothBatteries.merge(registry: registry, profiler: profiler)
        XCTAssertEqual(merged.count, 3, "the AirPods once, plus the two only System Information knows")
        let pods = merged.first { $0.kind == .airpodsPro }
        XCTAssertEqual(pods?.left, 70, "the registry is live; its reading wins")
        XCTAssertEqual(pods?.caseLevel, 45, "a part the registry did not report is filled in")
    }

    func testMergeFallsBackToTheName() {
        let registry = [BluetoothBattery(id: "name:magicmouse", name: "Magic Mouse", kind: .mouse, main: 50)]
        let profiler = [BluetoothBattery(id: "AABBCCDDEE09", name: "Magic  Mouse", kind: .mouse, main: 48,
                                         address: "AABBCCDDEE09")]
        let merged = BluetoothBatteries.merge(registry: registry, profiler: profiler)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.main, 50)
        XCTAssertEqual(merged.first?.address, "AABBCCDDEE09")
    }

    func testMergeTakesABetterKind() {
        let registry = [BluetoothBattery(id: "a", name: "Pad", kind: .other, main: 50)]
        let profiler = [BluetoothBattery(id: "b", name: "Pad", kind: .trackpad, main: 50)]
        XCTAssertEqual(BluetoothBatteries.merge(registry: registry, profiler: profiler).first?.kind, .trackpad)
    }

    // MARK: Order and slots

    private let mouse = BluetoothBattery(id: "m", name: "妙控鼠标", kind: .mouse, main: 80)
    private let trackpad = BluetoothBattery(id: "t", name: "妙控板", kind: .trackpad, main: 90)
    private let pods = BluetoothBattery(id: "p", name: "AirPods", kind: .airpods, left: 60, right: 62)
    private let pad = BluetoothBattery(id: "g", name: "Xbox", kind: .gameController, main: 12)
    private let speaker = BluetoothBattery(id: "s", name: "音箱", kind: .speaker, main: 50)

    func testThePanelOrdersByKindThenName() {
        let ordered = BluetoothBatteries.panelOrder([speaker, pad, trackpad, mouse, pods])
        XCTAssertEqual(ordered.map(\.id), ["p", "m", "t", "g", "s"])
    }

    func testTheCardTakesLowBatteriesFirstThenByKind() {
        let picks = BluetoothBatteries.tilePicks([speaker, trackpad, mouse, pods, pad], limit: 2)
        XCTAssertEqual(picks.map(\.id), ["g", "p"], "the controller at 12% jumps the queue")

        var charging = pad
        charging.charging = true
        XCTAssertEqual(BluetoothBatteries.tilePicks([speaker, trackpad, mouse, pods, charging], limit: 2).map(\.id),
                       ["p", "m"], "a low battery on the cable is not urgent")
    }

    func testTheCardSkipsWhatItAlreadyShows() {
        let picks = BluetoothBatteries.tilePicks([pods, mouse, trackpad], excluding: ["p"], limit: 2)
        XCTAssertEqual(picks.map(\.id), ["m", "t"])
        XCTAssertEqual(BluetoothBatteries.tilePicks([pods], limit: 0), [])
    }

    func testAlertReadingsCoverEveryBatteryOnce() {
        let withCase = BluetoothBattery(id: "p", name: "AirPods", kind: .airpods, left: 60, right: 10, caseLevel: 5)
        let readings = BluetoothBatteries.alertReadings([withCase, mouse])
        XCTAssertEqual(readings.map(\.id), ["bt.p", "bt.p.case", "bt.m"])
        XCTAssertEqual(readings.map(\.percent), [10, 5, 80])
        XCTAssertEqual(readings[1].name, "AirPods 充电盒")
    }

    /// The existing tracker does the not-repeating: a new accessory is just
    /// another id to it.
    func testANewKindOfAccessoryWarnsOnce() {
        var tracker = BatteryAlertTracker()
        let low = BluetoothBatteries.alertReadings([pad])
        let settings = BatteryAlertSettings()
        XCTAssertEqual(tracker.check(nil, accessories: low, settings: settings).map(\.id), ["accessory.bt.g"])
        XCTAssertEqual(tracker.check(nil, accessories: low, settings: settings), [])
        XCTAssertEqual(tracker.check(nil, accessories: [], settings: settings), [], "gone for a moment")
        XCTAssertEqual(tracker.check(nil, accessories: low, settings: settings), [], "back, still low: quiet")
    }

    // MARK: The card's configuration

    func testBluetoothIsOnForOldAndNewWidgets() {
        XCTAssertTrue(BatteryShelf.showsBluetooth(WidgetConfig()))
        XCTAssertEqual(WidgetCatalog.make(.battery)?.config.bool(BatteryShelf.bluetoothKey), true)
        XCTAssertFalse(BatteryShelf.showsBluetooth(WidgetConfig([BatteryShelf.bluetoothKey: .bool(false)])))
    }

    func testSlotsAndSizes() {
        let gauges = WidgetConfig(["layout": .string("gauge"), "devices": .list([.string("mac")])])
        XCTAssertEqual(BatteryShelf.slotCount(gauges), 3)
        var off = gauges
        off.set(BatteryShelf.bluetoothKey, .bool(false))
        XCTAssertEqual(BatteryShelf.slotCount(off), 1)

        let wide = WidgetCatalog.naturalSize(WidgetInstance(kind: .battery, config: gauges))
        let narrow = WidgetCatalog.naturalSize(WidgetInstance(kind: .battery, config: off))
        XCTAssertGreaterThan(wide.width, narrow.width)

        // The default 状态 card keeps its size either way.
        let status = WidgetCatalog.make(.battery)!
        XCTAssertTrue(BatteryShelf.isStatusCard(status.config))
        XCTAssertEqual(WidgetCatalog.naturalSize(status).width, 168)
        XCTAssertEqual(WidgetCatalog.verticalHeight(status), 3 * 62)
    }
}
