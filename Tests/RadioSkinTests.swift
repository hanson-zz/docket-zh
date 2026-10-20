import Foundation
import XCTest

/// 收音机的复古皮肤：刻度上的 FM 位置、琴键、VU 表的假动画，以及经典免费、
/// 复古皮肤 Pro 的划分。
final class RadioSkinTests: XCTestCase {

    // MARK: 刻度上的频率

    func testFrequenciesSpreadEvenlyBetween88And108InFavouriteOrder() {
        XCTAssertEqual(RadioDial.frequencies(count: 5), [90.0, 94.0, 98.0, 102.0, 106.0])
        XCTAssertEqual(RadioDial.frequencies(count: 1), [98.0])
        XCTAssertEqual(RadioDial.frequencies(count: 2), [93.0, 103.0])
        XCTAssertEqual(RadioDial.frequencies(count: 0), [])
        XCTAssertEqual(RadioDial.frequency(0, count: 0), 98.0, "没有电台时指针停在正中")
    }

    func testFrequenciesStayInsideTheBandAndNeverRepeat() {
        for count in 1...RadioDial.maxStations {
            let all = RadioDial.frequencies(count: count)
            XCTAssertEqual(all.count, count)
            XCTAssertEqual(Set(all).count, count, "\(count) 个收藏")
            XCTAssertEqual(all, all.sorted(), "按收藏顺序从低到高")
            for mhz in all {
                XCTAssertGreaterThanOrEqual(mhz, RadioDial.lowMHz)
                XCTAssertLessThanOrEqual(mhz, RadioDial.highMHz)
                XCTAssertEqual(mhz, (mhz * 10).rounded() / 10, accuracy: 1e-9, "取到 0.1 MHz")
            }
        }
    }

    func testOutOfRangeIndexesAreClamped() {
        XCTAssertEqual(RadioDial.frequency(-3, count: 5), 90.0)
        XCTAssertEqual(RadioDial.frequency(99, count: 5), 106.0)
    }

    func testDialFractionAndNearestStation() {
        XCTAssertEqual(RadioDial.dialFraction(88), 0)
        XCTAssertEqual(RadioDial.dialFraction(108), 1)
        XCTAssertEqual(RadioDial.dialFraction(98), 0.5, accuracy: 1e-9)
        XCTAssertEqual(RadioDial.dialFraction(70), 0)
        XCTAssertEqual(RadioDial.dialFraction(120), 1)
        // 五台在 90、94、98、102、106：点哪儿就换到最近的那台。
        XCTAssertEqual(RadioDial.nearestStation(toFraction: 0, count: 5), 0)
        XCTAssertEqual(RadioDial.nearestStation(toFraction: 0.5, count: 5), 2)
        XCTAssertEqual(RadioDial.nearestStation(toFraction: 0.68, count: 5), 3)
        XCTAssertEqual(RadioDial.nearestStation(toFraction: 1.4, count: 5), 4)
        XCTAssertEqual(RadioDial.nearestStation(toFraction: 0.3, count: 0), 0)
        for count in 1...12 {
            for index in 0..<count {
                let f = RadioDial.dialFraction(RadioDial.frequency(index, count: count))
                XCTAssertEqual(RadioDial.nearestStation(toFraction: f, count: count), index)
            }
        }
    }

    func testFrequencyTexts() {
        XCTAssertEqual(RadioDial.frequencyText(98), "98.0")
        XCTAssertEqual(RadioDial.frequencyText(101.7), "101.7")
        XCTAssertEqual(RadioDial.fmText(2, count: 5), "FM 98.0")
        XCTAssertEqual(RadioDial.segmentText(98), " 98.0", "段码屏固定四位，前面补一位暗的")
        XCTAssertEqual(RadioDial.segmentText(101.7), "101.7")
        XCTAssertEqual(RadioDial.segmentText(88.2).count, 5)
        XCTAssertEqual(RadioDial.channelOfTotal(2, count: 5), "频道 03 / 05")
    }

    // MARK: 琴键

    func testPresetKeysMapToTheFirstFiveFavourites() {
        XCTAssertEqual(RadioDial.presetKeys, 5)
        XCTAssertEqual((0..<5).map { RadioDial.presetStation(key: $0, count: 8) }, [0, 1, 2, 3, 4])
        XCTAssertEqual((0..<5).map { RadioDial.presetStation(key: $0, count: 3) }, [0, 1, 2, nil, nil])
        XCTAssertNil(RadioDial.presetStation(key: 5, count: 8))
        XCTAssertNil(RadioDial.presetStation(key: -1, count: 8))
        XCTAssertEqual(RadioDial.pressedKey(index: 2, count: 8), 2)
        XCTAssertNil(RadioDial.pressedKey(index: 6, count: 8), "第 6 个起没有键按下")
        XCTAssertNil(RadioDial.pressedKey(index: 0, count: 0))
        XCTAssertEqual(RadioDial.presetLabel(index: 2, count: 5), "P3")
        XCTAssertEqual(RadioDial.presetLabel(index: 11, count: 20), "CH 12")
    }

    // MARK: VU 表

    func testFakeMeterStaysOnTheScaleAndMoves() {
        var seen = Set<Int>()
        for step in 0..<400 {
            let time = Double(step) * 0.05
            for channel in 0..<2 {
                let level = RadioVU.level(time: time, channel: channel)
                XCTAssertGreaterThanOrEqual(level, 0.08)
                XCTAssertLessThanOrEqual(level, 0.95)
                seen.insert(Int(level * 20))
            }
        }
        XCTAssertGreaterThan(seen.count, 6, "表针会起伏")
        XCTAssertNotEqual(RadioVU.level(time: 3, channel: 0), RadioVU.level(time: 3, channel: 1), "左右声道错开")
        XCTAssertEqual(RadioVU.angle(0), -46)
        XCTAssertEqual(RadioVU.angle(1), 46)
        XCTAssertEqual(RadioVU.angle(2), 46)
        XCTAssertEqual(RadioVU.still.count, 2)
    }

    // MARK: 皮肤和 Pro

    func testSkinIsStoredUnderSkinAndOldCardsAreClassic() {
        XCTAssertEqual(RadioSkin.key, "skin")
        XCTAssertEqual(RadioSkin.allCases.map(\.rawValue),
                       ["classic", "wood", "transistor", "deck", "smoke", "led", "porcelain", "pixel", "ruler"])
        XCTAssertEqual(RadioSkin.stored(WidgetConfig()), .classic, "旧卡片没存 skin 时是经典")
        XCTAssertEqual(RadioSkin.stored(WidgetConfig([RadioSkin.key: .string("deck")])), .deck)
        XCTAssertEqual(RadioSkin.stored(WidgetConfig([RadioSkin.key: .string("bogus")])), .classic)
        XCTAssertFalse(RadioSkin.classic.isPro)
        XCTAssertTrue([RadioSkin.wood, .transistor, .deck].allSatisfy(\.isPro))
        XCTAssertTrue([RadioSkin.smoke, .led, .porcelain, .pixel, .ruler].allSatisfy(\.isPro), "五款新外观全是 Pro")
        XCTAssertEqual(RadioSkin.proCount, 8)
    }

    func testRadioIsFreeAndOnlyTheRetroSkinsArePro() {
        XCTAssertFalse(ProFeatures.isProKind(.radio))
        XCTAssertTrue(ProLicenseGate.canAdd(.radio, overrides: [:], unlocked: false))
        for skin in RadioSkin.allCases {
            let overrides: [String: WidgetConfig.Value] = [RadioSkin.key: .string(skin.rawValue)]
            XCTAssertEqual(ProFeatures.isProStyle(.radio, overrides), skin.isPro, "\(skin)")
            XCTAssertEqual(ProFeatures.isPro(.radio, overrides: overrides), skin.isPro, "\(skin)")
            XCTAssertEqual(ProLicenseGate.canChoose(.radio, overrides, unlocked: false), !skin.isPro, "\(skin)")
            XCTAssertTrue(ProLicenseGate.canChoose(.radio, overrides, unlocked: true), "\(skin)")
            XCTAssertEqual(ProLicenseGate.canAdd(.radio, overrides: overrides, unlocked: false), !skin.isPro)
            XCTAssertEqual(ProFeatures.isProChoice(kind: .radio, key: RadioSkin.key, value: skin.rawValue), skin.isPro)
            // 同一个键放在别的小组件上不算 Pro。
            XCTAssertFalse(ProFeatures.isProStyle(.clock, overrides))
            XCTAssertFalse(ProFeatures.isProStyle(overrides))
        }
    }

    func testLockedRetroSkinsDrawClassicWithoutALockAndKeepTheConfig() {
        for skin in RadioSkin.allCases {
            let config = WidgetConfig([RadioSkin.key: .string(skin.rawValue)])
            XCTAssertEqual(ProLicenseGate.radioSkin(config: config, unlocked: false), .classic, "\(skin)")
            XCTAssertEqual(ProLicenseGate.radioSkin(config: config, unlocked: true), skin, "\(skin)")
            let placed = WidgetInstance(kind: .radio, config: config)
            XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false), "\(skin) 不盖锁")
            XCTAssertEqual(ProFeatures.isPro(placed), skin.isPro, "\(skin) 的 Pro 标识")
            XCTAssertEqual(RadioSkin.stored(placed.config), skin, "配置不改写")
        }
        let old = WidgetInstance(kind: .radio, config: WidgetConfig())
        XCTAssertEqual(ProLicenseGate.radioSkin(config: old.config, unlocked: false), .classic)
        XCTAssertFalse(ProFeatures.isPro(old))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(old, unlocked: false))
    }

    func testCatalogOffersClassicFirstAndAsTheDefault() {
        guard let entry = WidgetCatalog.entry(.radio) else { return XCTFail("收音机不在目录里") }
        XCTAssertEqual(entry.variants.map(\.title), ["经典", "木壳电子管", "晶体管便携", "数码卡座",
                                                     "烟晶", "灯阵", "瓷白圆盘", "掌机像素", "墨白直尺"])
        XCTAssertEqual(entry.defaults[RadioSkin.key], .string("classic"))
        XCTAssertEqual(WidgetCatalog.make(.radio)?.config[RadioSkin.key], .string("classic"))
        XCTAssertFalse(WidgetCatalog.applies(RadioSkin.key, to: WidgetConfig(), kind: .radio),
                       "皮肤在样式里选，设置里不单列")
        let deck = WidgetConfig([RadioSkin.key: .string("deck")])
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: deck, kind: .radio), "数码卡座")
        XCTAssertEqual(WidgetCatalog.naturalSize(WidgetInstance(kind: .radio, config: deck)),
                       CGSize(width: 212, height: 62), "九种皮肤卡片一样大")
        XCTAssertTrue(ProUnlockStyle.allCases.contains(.radioSkins))
    }
}
