import XCTest

/// 替代系统音量和亮度提示：认键、步进、拦不拦、按下松开配对、设置里的状态行。
final class IslandMediaKeysTests: XCTestCase {

    private func press(_ key: IslandMediaKey, down: Bool = true, repeating: Bool = false) -> IslandMediaKeyPress {
        IslandMediaKeyPress(key: key, isDown: down, isRepeat: repeating)
    }

    private var both: IslandSettings {
        var settings = IslandSettings()
        settings.volume = true
        settings.brightness = true
        settings.replaceSystemHUD = true
        return settings
    }

    // MARK: Settings

    func testSettingDefaultsOffAndOnlyAppliesToEnabledHUDs() throws {
        var settings = IslandSettings()
        XCTAssertFalse(settings.replaceSystemHUD)
        XCTAssertFalse(settings.wantsKeyTap)

        settings.replaceSystemHUD = true
        XCTAssertFalse(settings.wantsKeyTap, "no HUD on, nothing to take over")
        XCTAssertFalse(settings.anyEnabled, "the switch alone shows nothing")

        settings.volume = true
        XCTAssertTrue(settings.replacesVolume)
        XCTAssertFalse(settings.replacesBrightness)
        XCTAssertTrue(settings.wantsKeyTap)

        settings.volume = false
        settings.brightness = true
        XCTAssertFalse(settings.replacesVolume)
        XCTAssertTrue(settings.replacesBrightness)

        let old = try JSONDecoder().decode(IslandSettings.self, from: Data(#"{"volume":true}"#.utf8))
        XCTAssertFalse(old.replaceSystemHUD, "a state file from before the switch existed loads with it off")
        let round = try JSONDecoder().decode(IslandSettings.self, from: JSONEncoder().encode(both))
        XCTAssertTrue(round.replaceSystemHUD)
    }

    // MARK: Parsing

    func testParsesTheFiveKeysDownUpAndRepeat() {
        for key in IslandMediaKey.allCases {
            let down = IslandMediaKeyPress.parse(eventType: 14, subtype: 8,
                                                 data1: IslandMediaKeyPress.data1(key: key, isDown: true))
            XCTAssertEqual(down, press(key))
            let held = IslandMediaKeyPress.parse(eventType: 14, subtype: 8,
                                                 data1: IslandMediaKeyPress.data1(key: key, isDown: true, isRepeat: true))
            XCTAssertEqual(held, press(key, repeating: true))
            let up = IslandMediaKeyPress.parse(eventType: 14, subtype: 8,
                                               data1: IslandMediaKeyPress.data1(key: key, isDown: false))
            XCTAssertEqual(up, press(key, down: false))
        }
        // NX_KEYTYPE_SOUND_UP 按下：0x000A00 一类的原始值。
        XCTAssertEqual(IslandMediaKeyPress.parse(eventType: 14, subtype: 8, data1: 0x0000_0A00), press(.soundUp))
        XCTAssertEqual(IslandMediaKeyPress.parse(eventType: 14, subtype: 8, data1: 0x0007_0B00), press(.mute, down: false))
    }

    func testOtherEventsAndKeysAreNotOurs() {
        let soundUp = IslandMediaKeyPress.data1(key: .soundUp, isDown: true)
        XCTAssertNil(IslandMediaKeyPress.parse(eventType: 10, subtype: 8, data1: soundUp), "not NX_SYSDEFINED")
        XCTAssertNil(IslandMediaKeyPress.parse(eventType: 14, subtype: 7, data1: soundUp), "not the media key subtype")
        // 播放控制 16～20、键盘背光 21～23、弹出 14、大写锁定 4 等一律不认。
        for code in [4, 5, 6, 8, 10, 14, 16, 17, 18, 19, 20, 21, 22, 23] {
            let data1 = (code << 16) | (0x0A << 8)
            XCTAssertNil(IslandMediaKeyPress.parse(eventType: 14, subtype: 8, data1: data1), "key \(code)")
        }
        XCTAssertNil(IslandMediaKeyPress.parse(eventType: 14, subtype: 8, data1: 0x0000_0C00), "unknown state")
    }

    // MARK: Steps

    func testStepsSnapToSixteenthsAndClamp() {
        XCTAssertEqual(IslandStep.next(0.5, up: true), 9.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(IslandStep.next(0.5, up: false), 7.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(IslandStep.next(0.30, up: true), 5.0 / 16, accuracy: 1e-9, "off-grid goes to the next point up")
        XCTAssertEqual(IslandStep.next(0.30, up: false), 4.0 / 16, accuracy: 1e-9, "and down")
        XCTAssertEqual(IslandStep.next(1, up: true), 1)
        XCTAssertEqual(IslandStep.next(0, up: false), 0)
        XCTAssertEqual(IslandStep.next(15.0 / 16, up: true), 1, accuracy: 1e-9)
        XCTAssertEqual(IslandStep.next(1.0 / 16, up: false), 0, accuracy: 1e-9)
        XCTAssertEqual(IslandStep.next(.nan, up: true), 1.0 / 16, accuracy: 1e-9)
        // 浮点读回来差一点点也不跳两格。
        XCTAssertEqual(IslandStep.next(0.5 - 1e-8, up: true), 9.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(IslandStep.next(0.5 + 1e-8, up: false), 7.0 / 16, accuracy: 1e-9)
    }

    func testFineStepsAreSixtyFourths() {
        XCTAssertEqual(IslandStep.next(0.5, up: true, fine: true), 33.0 / 64, accuracy: 1e-9)
        XCTAssertEqual(IslandStep.next(0.5, up: false, fine: true), 31.0 / 64, accuracy: 1e-9)
        // 一路按到顶：普通 16 下，小步 64 下。
        var level = 0.0
        var presses = 0
        while level < 1 { level = IslandStep.next(level, up: true, fine: true); presses += 1 }
        XCTAssertEqual(presses, 64)
        level = 0; presses = 0
        while level < 1 { level = IslandStep.next(level, up: true); presses += 1 }
        XCTAssertEqual(presses, 16)
    }

    func testModifiers() {
        XCTAssertTrue(IslandMediaModifiers(option: true, shift: true).fine)
        XCTAssertFalse(IslandMediaModifiers(option: true, shift: true).opensSystemSettings)
        XCTAssertTrue(IslandMediaModifiers(option: true).opensSystemSettings)
        XCTAssertFalse(IslandMediaModifiers(shift: true).fine)
        XCTAssertFalse(IslandMediaModifiers().fine)
    }

    // MARK: Effects

    func testVolumeEffects() throws {
        let up = try XCTUnwrap(IslandKeyEffect.volume(press(.soundUp), level: 0.5, muted: true, fine: false))
        XCTAssertEqual(up.level, 9.0 / 16, accuracy: 1e-9)
        XCTAssertFalse(up.muted, "turning it up unmutes")

        let down = try XCTUnwrap(IslandKeyEffect.volume(press(.soundDown), level: 1.0 / 16, muted: false, fine: false))
        XCTAssertEqual(down.level, 0)
        XCTAssertTrue(down.muted, "down to nothing mutes")

        let mute = try XCTUnwrap(IslandKeyEffect.volume(press(.mute), level: 0.4, muted: false, fine: false))
        XCTAssertEqual(mute.level, 0.4)
        XCTAssertTrue(mute.muted)
        let unmute = try XCTUnwrap(IslandKeyEffect.volume(press(.mute), level: 0.4, muted: true, fine: false))
        XCTAssertFalse(unmute.muted)

        XCTAssertNil(IslandKeyEffect.volume(press(.mute, repeating: true), level: 0.4, muted: false, fine: false),
                     "holding mute does not flicker")
        let held = try XCTUnwrap(IslandKeyEffect.volume(press(.soundUp, repeating: true), level: 0.5, muted: false, fine: false))
        XCTAssertEqual(held.level, 9.0 / 16, accuracy: 1e-9, "holding volume up keeps stepping")

        XCTAssertNil(IslandKeyEffect.volume(press(.soundUp, down: false), level: 0.5, muted: false, fine: false))
        XCTAssertNil(IslandKeyEffect.volume(press(.brightnessUp), level: 0.5, muted: false, fine: false))
    }

    func testBrightnessEffects() {
        XCTAssertEqual(IslandKeyEffect.brightness(press(.brightnessUp), level: 0.5, fine: false) ?? -1, 9.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(IslandKeyEffect.brightness(press(.brightnessDown), level: 0.5, fine: true) ?? -1, 31.0 / 64, accuracy: 1e-9)
        XCTAssertEqual(IslandKeyEffect.brightness(press(.brightnessUp, repeating: true), level: 1, fine: false), 1)
        XCTAssertNil(IslandKeyEffect.brightness(press(.brightnessUp, down: false), level: 0.5, fine: false))
        XCTAssertNil(IslandKeyEffect.brightness(press(.soundUp), level: 0.5, fine: false))
    }

    // MARK: Routing

    func testHandlesOnlyWhatIsTurnedOnAndWritable() {
        let ready = IslandKeyContext()
        for key in IslandMediaKey.allCases {
            XCTAssertTrue(IslandKeyRoute.handles(press(key), settings: both, modifiers: .init(), context: ready), "\(key)")
            XCTAssertTrue(IslandKeyRoute.handles(press(key, repeating: true), settings: both, modifiers: .init(), context: ready))
            XCTAssertFalse(IslandKeyRoute.handles(press(key, down: false), settings: both, modifiers: .init(), context: ready),
                           "key-ups go through the ledger")
            XCTAssertTrue(IslandKeyRoute.handles(press(key), settings: both,
                                                 modifiers: .init(option: true, shift: true), context: ready))
            XCTAssertFalse(IslandKeyRoute.handles(press(key), settings: both,
                                                  modifiers: .init(option: true), context: ready),
                           "Option alone opens System Settings, the system's job")
            XCTAssertFalse(IslandKeyRoute.handles(press(key), settings: both, modifiers: .init(),
                                                  context: IslandKeyContext(keyboardLocked: true)),
                           "the clean-mode keyboard lock swallows it instead")
        }

        var off = both
        off.replaceSystemHUD = false
        for key in IslandMediaKey.allCases {
            XCTAssertFalse(IslandKeyRoute.handles(press(key), settings: off, modifiers: .init(), context: ready))
        }

        var volumeOnly = both
        volumeOnly.brightness = false
        XCTAssertTrue(IslandKeyRoute.handles(press(.soundUp), settings: volumeOnly, modifiers: .init(), context: ready))
        XCTAssertFalse(IslandKeyRoute.handles(press(.brightnessUp), settings: volumeOnly, modifiers: .init(), context: ready))

        var brightnessOnly = both
        brightnessOnly.volume = false
        XCTAssertFalse(IslandKeyRoute.handles(press(.mute), settings: brightnessOnly, modifiers: .init(), context: ready))
        XCTAssertTrue(IslandKeyRoute.handles(press(.brightnessDown), settings: brightnessOnly, modifiers: .init(), context: ready))
    }

    func testPassesThroughWhatCannotBeChanged() {
        let noVolume = IslandKeyContext(volumeWritable: false, muteWritable: true)
        XCTAssertFalse(IslandKeyRoute.handles(press(.soundUp), settings: both, modifiers: .init(), context: noVolume),
                       "an output without volume (HDMI) goes to the system")
        XCTAssertTrue(IslandKeyRoute.handles(press(.mute), settings: both, modifiers: .init(), context: noVolume))

        let noMute = IslandKeyContext(volumeWritable: true, muteWritable: false)
        XCTAssertFalse(IslandKeyRoute.handles(press(.mute), settings: both, modifiers: .init(), context: noMute))
        XCTAssertTrue(IslandKeyRoute.handles(press(.soundDown), settings: both, modifiers: .init(), context: noMute))

        let external = IslandKeyContext(brightnessWritable: false)
        XCTAssertFalse(IslandKeyRoute.handles(press(.brightnessUp), settings: both, modifiers: .init(), context: external),
                       "an external display, or a brightness that cannot be written, goes to the system")
        XCTAssertTrue(IslandKeyRoute.handles(press(.soundUp), settings: both, modifiers: .init(), context: external))
    }

    func testLedgerPairsUpsWithDowns() {
        var ledger = IslandKeyLedger()
        XCTAssertFalse(ledger.up(.soundUp), "an up with no down goes through")

        ledger.down(.soundUp, handled: true)
        ledger.down(.soundUp, handled: true)   // repeat
        XCTAssertTrue(ledger.up(.soundUp))
        XCTAssertFalse(ledger.up(.soundUp), "asked once, then cleared")

        ledger.down(.brightnessUp, handled: false)
        XCTAssertFalse(ledger.up(.brightnessUp), "a down the system got, its up goes there too")

        ledger.down(.mute, handled: true)
        ledger.down(.soundDown, handled: true)
        ledger.reset()
        XCTAssertFalse(ledger.up(.mute))
        XCTAssertFalse(ledger.up(.soundDown))
    }

    // MARK: Status

    func testStatusAndNote() {
        XCTAssertEqual(IslandTakeoverStatus.resolve(wanted: false, trusted: true, installed: true), .off)
        XCTAssertEqual(IslandTakeoverStatus.resolve(wanted: true, trusted: true, installed: true), .active)
        XCTAssertEqual(IslandTakeoverStatus.resolve(wanted: true, trusted: false, installed: false), .needsAccess)
        XCTAssertEqual(IslandTakeoverStatus.resolve(wanted: true, trusted: true, installed: false), .failed)

        XCTAssertNil(IslandTakeoverStatus.off.note(volume: true, brightness: true))
        for status in [IslandTakeoverStatus.active, .needsAccess, .failed] {
            for (volume, brightness) in [(true, true), (true, false), (false, true)] {
                let note = status.note(volume: volume, brightness: brightness)
                XCTAssertNotNil(note)
                XCTAssertFalse(note?.isEmpty ?? true)
            }
        }
        XCTAssertNotEqual(IslandTakeoverStatus.active.note(volume: true, brightness: false),
                          IslandTakeoverStatus.active.note(volume: false, brightness: true))
        XCTAssertTrue(IslandTakeoverStatus.needsAccess.needsGrant)
        XCTAssertFalse(IslandTakeoverStatus.failed.needsGrant)
        XCTAssertFalse(IslandTakeoverStatus.active.needsGrant)
    }
}
