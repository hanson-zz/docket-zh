import XCTest

final class AmbientMixTests: XCTestCase {
    // MARK: 各自音量

    func testLevelsParseAndEncode() {
        let levels = AmbientLevels.parse(["rain:75", "fire：30", "nope:20", "wind:abc", "waves:150", "rain:60"])
        XCTAssertEqual(levels, [.rain: 60, .fire: 30, .waves: 100], "later wins, clamped, junk dropped")
        XCTAssertEqual(AmbientLevels.encode([.fire: 30, .rain: 60, .wind: AmbientLevels.defaultLevel]),
                       ["rain:60", "fire:30"], "catalog order, default not written")
        XCTAssertEqual(AmbientLevels.level(.brown, in: levels), AmbientLevels.defaultLevel)
    }

    func testDefaultLevelSoundsLikeBefore() {
        XCTAssertEqual(AmbientLevels.gain(AmbientLevels.defaultLevel), 1)
        XCTAssertEqual(AmbientLevels.gain(0), 0)
        XCTAssertEqual(AmbientLevels.gain(100), 1.25)
        XCTAssertEqual(AmbientLevels.gain(400), 1.25)
    }

    /// 没存 levels 的老卡片和改版前出一样的声音。
    func testSynthWithoutLevelsMatchesOldOutput() {
        var old = AmbientSynth(sampleRate: 22_050, seed: 7)
        var new = AmbientSynth(sampleRate: 22_050, seed: 7)
        old.setVolume(0.6)
        new.setVolume(0.6)
        old.setSounds([.rain, .fire])
        new.setSounds([.rain, .fire], levels: [.rain: AmbientLevels.defaultLevel])
        for _ in 0..<5_000 { XCTAssertEqual(old.next(), new.next()) }
    }

    /// 一种声音拉到 0：和只放另一种一样安静的那一路不出声。
    func testLevelZeroSilencesThatSound() {
        var synth = AmbientSynth(sampleRate: 22_050, seed: 3)
        synth.setVolume(1)
        synth.setSounds([.white], levels: [.white: 0])
        var peak: Float = 0
        for _ in 0..<22_050 { peak = max(peak, abs(synth.next())) }
        XCTAssertLessThan(peak, 0.001)
    }

    // MARK: 组合

    func testMixParseAndText() {
        let mix = AmbientMix.parse("雨夜篝火=rain:75,fire:30")
        XCTAssertEqual(mix?.name, "雨夜篝火")
        XCTAssertEqual(mix?.sounds, [.rain, .fire])
        XCTAssertEqual(mix?.levels[.fire], 30)
        XCTAssertEqual(mix?.text, "雨夜篝火=rain:75,fire:30")
        XCTAssertNil(AmbientMix.parse("=rain:75"), "no name")
        XCTAssertNil(AmbientMix.parse("空的=nope:3"), "no known sound")
        XCTAssertNil(AmbientMix.parse("没有等号"))
        let ordered = AmbientMix.parse("夜=fire:30,rain:75,fire:40")
        XCTAssertEqual(ordered?.sounds, [.fire, .rain], "saved order kept, repeats folded")
        XCTAssertEqual(ordered?.levels[.fire], 40)
        XCTAssertEqual(ordered?.text, "夜=fire:40,rain:75")
    }

    func testSavingAddsReplacesAndStopsAtSix() {
        var raw: [String] = []
        for index in 1...6 {
            guard case .saved(let list) = AmbientMixes.saving(name: "组合\(index)", sounds: [.rain],
                                                              levels: [:], in: raw) else {
                return XCTFail("could not save \(index)")
            }
            raw = list
        }
        XCTAssertEqual(AmbientMixes.all(raw).count, AmbientMixes.limit)
        XCTAssertEqual(AmbientMixes.saving(name: "第七个", sounds: [.rain], levels: [:], in: raw), .full)
        // 满了还能覆盖同名的。
        guard case .saved(let replaced) = AmbientMixes.saving(name: "组合2", sounds: [.wind, .fire],
                                                              levels: [.wind: 20], in: raw) else {
            return XCTFail("overwrite refused")
        }
        let second = AmbientMixes.all(replaced)[1]
        XCTAssertEqual(second.name, "组合2")
        XCTAssertEqual(second.levels, [.wind: 20, .fire: AmbientLevels.defaultLevel])
        XCTAssertEqual(AmbientMixes.saving(name: "  ", sounds: [.rain], levels: [:], in: raw), .emptyName)
        XCTAssertEqual(AmbientMixes.saving(name: "x", sounds: [], levels: [:], in: []), .noSounds)
    }

    func testNamesAreCleaned() {
        XCTAssertEqual(AmbientMixes.cleanName("  雨=夜\n篝火  "), "雨 夜 篝火")
        XCTAssertEqual(AmbientMixes.cleanName("一二三四五六七八九十十一").count, AmbientMixes.nameLimit)
    }

    func testRemoveRenameAndDuplicates() {
        let raw = ["海边=waves:80", "海边=rain:10", "专注=brown:50", "坏的"]
        XCTAssertEqual(AmbientMixes.all(raw).map(\.name), ["海边", "专注"], "first of a name wins")
        XCTAssertEqual(AmbientMixes.removing("海边", in: raw), ["专注=brown:50"])
        XCTAssertEqual(AmbientMixes.removing("专注", in: AmbientMixes.removing("海边", in: raw)), [],
                       "removing the last one leaves an empty list")
        XCTAssertEqual(AmbientMixes.renaming("专注", to: "专注棕噪", in: raw), ["海边=waves:80", "专注棕噪=brown:50"])
        XCTAssertNil(AmbientMixes.renaming("专注", to: "海边", in: raw), "clash")
        XCTAssertNil(AmbientMixes.renaming("专注", to: " ", in: raw), "empty")
        XCTAssertNil(AmbientMixes.renaming("没有", to: "新", in: raw))
    }

    func testMatchingAndApplying() {
        let mixes = AmbientMixes.all(["雨夜篝火=rain:75,fire:30", "雨=rain:80"])
        XCTAssertEqual(AmbientMixes.matching(sounds: [.rain, .fire], levels: [.rain: 75, .fire: 30], in: mixes)?.name,
                       "雨夜篝火")
        XCTAssertNil(AmbientMixes.matching(sounds: [.rain, .fire], levels: [.rain: 70, .fire: 30], in: mixes))
        XCTAssertEqual(AmbientMixes.matching(sounds: [.rain], levels: [:], in: mixes)?.name, "雨",
                       "an unset level is the default")
        XCTAssertNil(AmbientMixes.matching(sounds: [], levels: [:], in: mixes))

        XCTAssertEqual(AmbientMixes.matching(sounds: [.fire, .rain], levels: [.rain: 75, .fire: 30], in: mixes)?.name,
                       "雨夜篝火", "order does not matter for matching")
        let applied = AmbientMixes.applying(mixes[0], levels: [.wind: 10, .rain: 20])
        XCTAssertEqual(applied.sounds, [.rain, .fire])
        XCTAssertEqual(applied.levels, [.wind: 10, .rain: 75, .fire: 30], "wind keeps its level for next time")
    }

    func testSuggestedNameSkipsUsed() {
        let mixes = AmbientMixes.all(["组合 2=rain:80"])
        XCTAssertEqual(AmbientMixes.suggestedName(existing: mixes), "组合 3")
        XCTAssertEqual(AmbientMixes.suggestedName(existing: []), "组合 1")
    }

    // MARK: 定时

    func testCustomTimer() {
        XCTAssertEqual(AmbientCustomTimer.clamp(2), 5)
        XCTAssertEqual(AmbientCustomTimer.clamp(47), 45)
        XCTAssertEqual(AmbientCustomTimer.clamp(10_000), 480)
        XCTAssertTrue(AmbientCustomTimer.isCustom(45))
        XCTAssertFalse(AmbientCustomTimer.isCustom(30))
        XCTAssertFalse(AmbientCustomTimer.isCustom(0))
    }
}
