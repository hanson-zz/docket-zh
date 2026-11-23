import XCTest

/// 电池稳定性：连着但读不到电量、断开后不留旧百分比、重连恢复、读数过期、多设备排序。
final class BatteryAccessoryStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private let podsLive = BluetoothBattery(id: "AABBCCDDEE01", name: "AirPods Pro", kind: .airpodsPro,
                                            left: 70, right: 72, address: "AABBCCDDEE01")

    private func snapshotPods(at date: Date) -> BluetoothBattery {
        BluetoothBattery(id: "AABBCCDDEE01", name: "AirPods Pro", kind: .airpodsPro, left: 90, right: 88,
                         caseLevel: 45, address: "AABBCCDDEE01", readAt: date)
    }

    // MARK: 连着但读不到电量

    private let unreadableSample = """
    {
      "SPBluetoothDataType" : [
        {
          "device_connected" : [
            { "MX Master 3S" : {
                "device_address" : "AA:BB:CC:DD:EE:02",
                "device_minorType" : "Mouse" } },
            { "Logi Keys" : {
                "device_address" : "AA:BB:CC:DD:EE:06",
                "device_batteryLevelMain" : "55%",
                "device_minorType" : "Keyboard" } },
            { "JBL Flip 6" : {
                "device_address" : "AA:BB:CC:DD:EE:04",
                "device_minorType" : "Speaker" } }
          ]
        }
      ]
    }
    """

    func testParsingKeepsAConnectedMouseWithoutABatteryOnlyWhenAsked() {
        let data = Data(unreadableSample.utf8)
        XCTAssertEqual(SystemProfilerBluetooth.parse(data).map(\.name), ["Logi Keys"],
                       "默认照旧只列报了电量的")
        let all = SystemProfilerBluetooth.parse(data, keepUnreadable: true, readAt: t0)
        XCTAssertEqual(all.map(\.name).sorted(), ["Logi Keys", "MX Master 3S"], "音箱不报电量是常态，不列")
        let mouse = all.first { $0.name == "MX Master 3S" }
        XCTAssertNil(mouse?.level)
        XCTAssertEqual(mouse?.readState, .unreadable)
        XCTAssertEqual(mouse?.readAt, t0)
    }

    func testOnlyHeadphonesMiceTrackpadsAndKeyboardsAreListedWithoutABattery() {
        for kind in [AccessoryKind.airpods, .airpodsPro, .airpodsMax, .headphones, .mouse, .trackpad, .keyboard] {
            XCTAssertTrue(BluetoothBatteries.tracksUnreadable(kind), kind.rawValue)
        }
        for kind in [AccessoryKind.speaker, .gameController, .other] {
            XCTAssertFalse(BluetoothBatteries.tracksUnreadable(kind), kind.rawValue)
        }
        XCTAssertTrue(BluetoothBatteries.keepsUnreadable(kind: .mouse, transport: "Bluetooth"))
        XCTAssertTrue(BluetoothBatteries.keepsUnreadable(kind: .keyboard, transport: "Bluetooth Low Energy"))
        XCTAssertFalse(BluetoothBatteries.keepsUnreadable(kind: .keyboard, transport: "USB"), "有线连着的不算")
        XCTAssertFalse(BluetoothBatteries.keepsUnreadable(kind: .mouse, transport: nil))
        XCTAssertFalse(BluetoothBatteries.keepsUnreadable(kind: .speaker, transport: "Bluetooth"))
    }

    func testMergeKeepsAnUnreadableMouseButNotAnUnreadableSpeaker() {
        let mouse = BluetoothBattery(id: "m", name: "Magic Mouse", kind: .mouse)
        let speaker = BluetoothBattery(id: "s", name: "Speaker", kind: .speaker)
        let merged = BluetoothBatteries.merge(registry: [mouse, speaker], profiler: [])
        XCTAssertEqual(merged.map(\.id), ["m"])
        XCTAssertEqual(merged.first?.readState, .unreadable)
    }

    func testAServiceWithoutABatteryDoesNotHideOneWithIt() {
        var list: [BluetoothBattery] = []
        BluetoothBatteries.insert(BluetoothBattery(id: "k", name: "Magic Keyboard", kind: .keyboard), into: &list)
        BluetoothBatteries.insert(BluetoothBattery(id: "k", name: "Magic Keyboard", kind: .keyboard, main: 66),
                                  into: &list)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.main, 66, "读得到电量的那个服务换进来")
        BluetoothBatteries.insert(BluetoothBattery(id: "k", name: "Magic Keyboard", kind: .keyboard, main: 10),
                                  into: &list)
        XCTAssertEqual(list.first?.main, 66, "两个都有电量时先到的赢，和原来一样")
    }

    func testARegistryDeviceWithoutABatteryTakesTheSnapshotLevelAndItsTime() {
        let registry = [BluetoothBattery(id: "AABBCCDDEE01", name: "AirPods Pro", kind: .airpodsPro,
                                         address: "AABBCCDDEE01")]
        let merged = BluetoothBatteries.merge(registry: registry, profiler: [snapshotPods(at: t0)])
        XCTAssertEqual(merged.first?.level, 88)
        XCTAssertEqual(merged.first?.readAt, t0, "电量来自快照，读到的时刻也跟着快照，过期照样标")
    }

    // MARK: 断开、重连

    func testAPairThatLeftTheRegistryIsNotDrawnFromTheOldSnapshot() {
        let snapshot = [snapshotPods(at: t0)]
        XCTAssertEqual(BluetoothBatteries.merge(registry: [], profiler: snapshot).count, 1,
                       "没记断开时快照里的照旧列出（只有系统信息知道的配件靠这个）")
        let merged = BluetoothBatteries.merge(registry: [], profiler: snapshot, departed: [podsLive])
        XCTAssertTrue(merged.isEmpty, "收进盒子的 AirPods 不能拿几分钟前的电量再画出来")
    }

    func testAReconnectedPairShowsItsLiveLevelAgain() {
        let merged = BluetoothBatteries.merge(registry: [podsLive], profiler: [snapshotPods(at: t0)],
                                              departed: [podsLive])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.left, 70, "注册表又读到了，用实时电量")
    }

    func testDeparturesFollowTheRegistryAndClearWithANewSnapshot() {
        var departures = AccessoryDepartures()
        XCTAssertEqual(departures.update(registry: [podsLive], now: t0), [])
        let gone = departures.update(registry: [], now: t0.addingTimeInterval(1))
        XCTAssertEqual(gone.map(\.id), [podsLive.id], "这一秒不见了就算断开")
        XCTAssertEqual(departures.update(registry: [podsLive], now: t0.addingTimeInterval(2)), [], "重连划掉")

        departures.update(registry: [], now: t0.addingTimeInterval(100))
        departures.snapshotArrived(startedAt: t0.addingTimeInterval(105))
        XCTAssertEqual(departures.departed.map(\.id), [podsLive.id],
                       "快照开始前 10 秒内断开的，快照可能还没反映，继续记着")
        departures.snapshotArrived(startedAt: t0.addingTimeInterval(200))
        XCTAssertEqual(departures.departed, [], "之后开始读的快照已经不含它")
    }

    // MARK: 过期

    func testSnapshotReadingsGoStaleAndLiveOnesNever() {
        let now = t0.addingTimeInterval(BluetoothBatteries.staleAfter + 1)
        let old = BluetoothBattery(id: "h", name: "WH-1000XM5", kind: .headphones, main: 40, readAt: t0)
        let fresh = BluetoothBattery(id: "f", name: "Buds", kind: .headphones, main: 40,
                                     readAt: now.addingTimeInterval(-60))
        let unreadable = BluetoothBattery(id: "u", name: "Mouse", kind: .mouse, readAt: t0)
        let marked = BluetoothBatteries.markStale([old, fresh, podsLive, unreadable], now: now)
        XCTAssertEqual(marked.map(\.stale), [true, false, false, false])
        XCTAssertEqual(marked.map(\.readState), [.stale, .fresh, .fresh, .unreadable])
    }

    func testTheProfilerIsAskedSoonerWhileItAloneKnowsADevice() {
        let headset = BluetoothBattery(id: "h", name: "WH-1000XM5", kind: .headphones, main: 40)
        XCTAssertEqual(BluetoothBatteries.profilerInterval(registry: [podsLive], profiler: [snapshotPods(at: t0)]),
                       BluetoothBatteries.profilerNormalInterval)
        XCTAssertEqual(BluetoothBatteries.profilerInterval(registry: [podsLive], profiler: [headset]),
                       BluetoothBatteries.profilerFastInterval)
        let silentPods = BluetoothBattery(id: podsLive.id, name: "AirPods Pro", kind: .airpodsPro,
                                          address: podsLive.address)
        XCTAssertEqual(BluetoothBatteries.profilerInterval(registry: [silentPods], profiler: [snapshotPods(at: t0)]),
                       BluetoothBatteries.profilerFastInterval, "注册表读不到、电量靠快照补的也用短间隔")
        XCTAssertLessThan(BluetoothBatteries.profilerFastInterval * 2, BluetoothBatteries.staleAfter,
                          "短间隔下漏读一轮还不算过期")
        XCTAssertLessThan(BluetoothBatteries.staleAfter, BluetoothBatteries.profilerDropAfter)
    }

    // MARK: 排序和取格

    private let mouse = BluetoothBattery(id: "m", name: "妙控鼠标", kind: .mouse, main: 80)
    private let keyboard = BluetoothBattery(id: "k", name: "妙控键盘", kind: .keyboard, main: 50)

    func testThePanelListsUsableLevelsFirst() {
        let unreadablePods = BluetoothBattery(id: "p", name: "AirPods", kind: .airpods)
        var staleMouse = BluetoothBattery(id: "m2", name: "MX Master", kind: .mouse, main: 30)
        staleMouse.stale = true
        let ordered = BluetoothBatteries.panelOrder([unreadablePods, staleMouse, keyboard, mouse])
        XCTAssertEqual(ordered.map(\.id), ["m", "k", "m2", "p"])
    }

    func testAStaleLowReadingDoesNotJumpTheQueue() {
        var staleLow = BluetoothBattery(id: "g", name: "Pad", kind: .mouse, main: 5)
        staleLow.stale = true
        XCTAssertEqual(BluetoothBatteries.tilePicks([staleLow, keyboard], limit: 1).map(\.id), ["k"])
        XCTAssertEqual(BluetoothBatteries.tilePicks([staleLow, keyboard], limit: 2).map(\.id), ["k", "g"])
        let unreadable = BluetoothBattery(id: "u", name: "Mouse", kind: .mouse)
        XCTAssertEqual(BluetoothBatteries.tilePicks([unreadable], limit: 2), [], "读不到电量的不占配件格")
    }

    func testTheBudsSlotPrefersAPairWithALevel() {
        let unreadablePods = BluetoothBattery(id: "u", name: "AirPods", kind: .airpods)
        XCTAssertEqual(BluetoothBatteries.budsSource([unreadablePods, podsLive])?.id, podsLive.id)
        XCTAssertEqual(BluetoothBatteries.budsSource([unreadablePods, mouse])?.id, "u",
                       "只有读不到的那副时仍读它，那一格写「电量不可获取」")
        XCTAssertNil(BluetoothBatteries.budsSource([mouse]))
        let unreadableKeyboard = BluetoothBattery(id: "uk", name: "Keys", kind: .keyboard)
        XCTAssertEqual(BluetoothBatteries.keyboardSource([unreadableKeyboard, keyboard])?.id, "k")
        XCTAssertEqual(BluetoothBatteries.keyboardSource([unreadableKeyboard])?.id, "uk")
    }

    func testTheFourthSlotTakesAUsableLevelBeforeAnUnreadableMouse() {
        let unreadableMouse = BluetoothBattery(id: "um", name: "Mouse", kind: .mouse)
        XCTAssertEqual(BluetoothBatteries.peripheralPick([unreadableMouse, keyboard], excluding: nil)?.id, "k")
        XCTAssertEqual(BluetoothBatteries.peripheralPick([keyboard, mouse], excluding: nil)?.id, "m",
                       "同样读得到时鼠标优先，和原来一样")
        XCTAssertEqual(BluetoothBatteries.peripheralPick([unreadableMouse], excluding: nil)?.id, "um")
        XCTAssertNil(BluetoothBatteries.peripheralPick([podsLive], excluding: nil), "AirPods 不进第四格")
        XCTAssertNil(BluetoothBatteries.peripheralPick([mouse], excluding: "m"))
    }

    // MARK: 文字

    func testWordsForAnUnreadableOrStaleBattery() {
        XCTAssertEqual(BatteryWords.absentWord(unreadable: true), "电量不可获取")
        XCTAssertEqual(BatteryWords.absentWord(unreadable: false), "未连接")
        XCTAssertEqual(BatteryWords.powerLine(level: 0, charging: false, onPower: false, present: false,
                                              unreadable: true), "电量不可获取")
        XCTAssertEqual(BatteryWords.powerLine(level: 0.5, charging: false, onPower: false, present: true,
                                              stale: true), "数据已过期")
        XCTAssertEqual(BatteryWords.accessoryCaption(present: false, unreadable: true, charging: false, parts: nil),
                       "电量不可获取")
        XCTAssertEqual(BatteryWords.accessoryCaption(present: false, unreadable: true, charging: false,
                                                     parts: "盒 40%"), "电量不可获取 · 盒 40%")
        XCTAssertEqual(BatteryWords.accessoryCaption(present: false, charging: false, parts: nil), "未连接")
        XCTAssertEqual(BatteryWords.accessoryCaption(present: true, stale: true, charging: false,
                                                     parts: "左 80% · 右 78%"), "数据已过期 · 左 80% · 右 78%")
        XCTAssertEqual(BatteryWords.accessoryCaption(present: true, charging: true, parts: nil), "正在充电")
        XCTAssertEqual(BatteryWords.accessoryCaption(present: true, charging: false, parts: nil), "使用电池")
    }

    func testHoverSaysUnreadableAndStale() {
        let unreadable = BatteryWords.hover(name: "妙控鼠标", level: 0, charging: false, onPower: false, present: false,
                                            unreadable: true, updated: nil, now: t0)
        XCTAssertEqual(unreadable, "妙控鼠标\n已连接 · 电量不可获取")
        XCTAssertFalse(unreadable.contains("%"), "读不到就不写百分比")
        let stale = BatteryWords.hover(name: "Buds", level: 0.4, charging: false, onPower: false, present: true,
                                       stale: true, updated: nil, now: t0)
        XCTAssertEqual(stale.components(separatedBy: "\n").last, "数据已过期")
    }
}
