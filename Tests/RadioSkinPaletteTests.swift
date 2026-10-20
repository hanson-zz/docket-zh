import Foundation
import XCTest

/// 收音机五款新外观（烟晶、灯阵、瓷白圆盘、掌机像素、墨白直尺）的两版配色、
/// 深浅切换和 Pro 划分。
final class RadioSkinPaletteTests: XCTestCase {

    private let modern: [RadioSkin] = [.smoke, .led, .porcelain, .pixel, .ruler]

    func testOnlyTheFiveNewLooksHavePalettes() {
        XCTAssertEqual(RadioSkinPalette.skins, modern)
        for skin in RadioSkin.allCases {
            for tone in RadioSkinTone.allCases {
                XCTAssertEqual(RadioSkinPalette.palette(skin, tone: tone) != nil, modern.contains(skin),
                               "\(skin) \(tone)")
            }
            XCTAssertEqual(skin.isModern, modern.contains(skin), "\(skin)")
            XCTAssertFalse(skin.isModern && skin.isRetro, "\(skin) 不会同时算复古和新外观")
        }
        XCTAssertEqual(RadioSkin.allCases.filter(\.isRetro), [.wood, .transistor, .deck])
    }

    func testToneFollowsWhetherTheContentIsDark() {
        XCTAssertEqual(RadioSkinTone(darkContent: true), .dark)
        XCTAssertEqual(RadioSkinTone(darkContent: false), .light)
        for skin in modern {
            XCTAssertFalse(RadioSkinPalette.palette(skin, tone: .dark)!.isLight, "\(skin) 暗色版底色是深的")
            XCTAssertTrue(RadioSkinPalette.palette(skin, tone: .light)!.isLight, "\(skin) 浅色版底色是浅的")
        }
    }

    func testEveryVersionReadsAtLeast4_5To1() {
        for skin in modern {
            for tone in RadioSkinTone.allCases {
                let p = RadioSkinPalette.palette(skin, tone: tone)!
                XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(p.text, p.background), 4.5, "\(skin) \(tone) 正文")
                XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(p.secondaryText, p.background), 4.5,
                                            "\(skin) \(tone) 次要字")
                XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(p.accentText, p.background), 4.5,
                                            "\(skin) \(tone) 强调小字")
                XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(p.ink, p.accent), 4.5,
                                            "\(skin) \(tone) 实心键上的图标")
                XCTAssertGreaterThanOrEqual(p.minimumContrast, 4.5, "\(skin) \(tone)")
            }
        }
    }

    func testIconsOnSolidKeysAreAlwaysDark() {
        for skin in modern {
            for tone in RadioSkinTone.allCases {
                let p = RadioSkinPalette.palette(skin, tone: tone)!
                XCTAssertFalse(p.ink.isLight, "\(skin) \(tone) 实心按钮深色字")
            }
        }
    }

    func testValuesMatchTheDesignScript() {
        let smoke = RadioSkinPalette.palette(.smoke, tone: .dark)!
        XCTAssertEqual(smoke.background.hex, "#1B1A1F")
        XCTAssertEqual(smoke.accent.hex, "#F4C27A")
        XCTAssertEqual(RadioSkinPalette.palette(.led, tone: .light)!.accentText.hex, "#8A6200")
        XCTAssertEqual(RadioSkinPalette.palette(.porcelain, tone: .light)!.accent.hex, "#F07A4A")
        XCTAssertEqual(RadioSkinPalette.palette(.pixel, tone: .dark)!.rowStyle, .square)
        XCTAssertEqual(RadioSkinPalette.palette(.ruler, tone: .light)!.rowStyle, .line)
        XCTAssertEqual(RadioSkinPalette.palette(.ruler, tone: .light)!.accent.hex, "#E4E4E0",
                       "墨白直尺浅色主钮是浅灰实心")
        XCTAssertEqual(RadioSkinPalette.palette(.smoke, tone: .light)!.rowStyle, .round)
    }

    func testMixBlendsTowardsTheTopColour() {
        let black = ColorCode(red: 0, green: 0, blue: 0)
        let white = ColorCode(red: 1, green: 1, blue: 1)
        XCTAssertEqual(RadioSkinPalette.mix(white, over: black, opacity: 0), black)
        XCTAssertEqual(RadioSkinPalette.mix(white, over: black, opacity: 1), white)
        XCTAssertEqual(RadioSkinPalette.mix(white, over: black, opacity: 0.5).red, 0.5, accuracy: 0.001)
        XCTAssertEqual(RadioSkinPalette.mix(white, over: black, opacity: 2), white, "超出范围夹到 1")
    }

    func testNewLooksArePaidStylesThatFallBackToClassicWhenLocked() {
        for skin in modern {
            let overrides: [String: WidgetConfig.Value] = [RadioSkin.key: .string(skin.rawValue)]
            XCTAssertTrue(ProFeatures.isProStyle(.radio, overrides), "\(skin)")
            XCTAssertFalse(ProLicenseGate.canChoose(.radio, overrides, unlocked: false), "\(skin)")
            let config = WidgetConfig(overrides)
            XCTAssertEqual(ProLicenseGate.radioSkin(config: config, unlocked: false), .classic, "\(skin)")
            XCTAssertEqual(ProLicenseGate.radioSkin(config: config, unlocked: true), skin, "\(skin)")
            let placed = WidgetInstance(kind: .radio, config: config)
            XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false), "\(skin) 不盖锁")
            XCTAssertEqual(RadioSkin.stored(placed.config), skin, "配置不改写")
        }
    }
}
