import XCTest

/// 专注时把收音机当背景音乐：选台的编码、该不该播、淡入淡出曲线、按台记住的音量，
/// 以及环境音合成器的整体淡入淡出。
final class FocusRadioTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func station(_ id: String, _ url: String = "", name: String = "台") -> RadioStation {
        RadioStation(id: id, name: name, url: url.isEmpty ? "https://example.com/\(id).mp3" : url)
    }

    private func running(_ ambient: String, phase: TimerPhase = .focus, quiet: Bool = true) -> TimerState {
        var state = TimerState()
        state.ambient = ambient
        state.phase = phase
        state.quietOnBreak = quiet
        state.deadline = t0.addingTimeInterval(600)
        state.duration = 1500
        return state
    }

    // MARK: 淡入淡出曲线

    func testCurveRunsFromZeroToOneSmoothly() {
        XCTAssertEqual(AudioFade.curve(0), 0)
        XCTAssertEqual(AudioFade.curve(1), 1)
        XCTAssertEqual(AudioFade.curve(0.5), 0.5, accuracy: 1e-6)
        var last = -1.0
        for step in 0...100 {
            let value = AudioFade.curve(Double(step) / 100)
            XCTAssertGreaterThanOrEqual(value, last)
            last = value
        }
        // 两头平缓：开头 5% 的时间只走了不到 1%。
        XCTAssertLessThan(AudioFade.curve(0.05), 0.01)
        XCTAssertEqual(AudioFade.curve(-3), 0)
        XCTAssertEqual(AudioFade.curve(.nan), 0)
    }

    func testFullFadeInTakesOnePointFiveSeconds() {
        let fade = AudioFade(from: 0, to: 1, start: t0, full: AudioFade.fadeIn)
        XCTAssertEqual(fade.duration, 1.5, accuracy: 1e-6)
        XCTAssertEqual(fade.value(at: t0), 0)
        XCTAssertEqual(fade.value(at: t0.addingTimeInterval(0.75)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(fade.value(at: t0.addingTimeInterval(1.5)), 1)
        XCTAssertTrue(fade.isDone(at: t0.addingTimeInterval(1.6)))
        XCTAssertFalse(fade.isDone(at: t0.addingTimeInterval(1.4)))
    }

    func testFadeOutTakesPointEightSeconds() {
        let fade = AudioFade(from: 1, to: 0, start: t0, full: AudioFade.fadeOut)
        XCTAssertEqual(fade.duration, 0.8, accuracy: 1e-6)
        XCTAssertEqual(fade.value(at: t0.addingTimeInterval(0.8)), 0)
        XCTAssertEqual(fade.value(at: t0.addingTimeInterval(10)), 0)
    }

    /// 淡出到一半又点播放：从那一半往回升，只用剩下的时间，绝不先掉到 0。
    func testResumingMidFadeOutRisesFromWhereItWas() {
        let out = AudioFade(from: 1, to: 0, start: t0, full: AudioFade.fadeOut)
        let halfway = out.value(at: t0.addingTimeInterval(0.4))
        XCTAssertEqual(halfway, 0.5, accuracy: 1e-6)
        let back = AudioFade(from: halfway, to: 1, start: t0.addingTimeInterval(0.4), full: AudioFade.fadeIn)
        XCTAssertEqual(back.duration, 0.75, accuracy: 1e-6)
        XCTAssertEqual(back.value(at: back.start), halfway, accuracy: 1e-6)
        for step in 0...20 {
            let value = back.value(at: back.start.addingTimeInterval(Double(step) * 0.05))
            XCTAssertGreaterThanOrEqual(value, halfway - 1e-6)
        }
        XCTAssertEqual(back.value(at: back.start.addingTimeInterval(0.75)), 1)
    }

    func testFadeToWhereItAlreadyIsIsInstant() {
        let fade = AudioFade(from: 1, to: 1, start: t0, full: AudioFade.fadeIn)
        XCTAssertEqual(fade.duration, 0)
        XCTAssertTrue(fade.isDone(at: t0))
        XCTAssertEqual(fade.value(at: t0), 1)
        let clamped = AudioFade(from: 3, to: -2, start: t0, full: 1)
        XCTAssertEqual(clamped.from, 1)
        XCTAssertEqual(clamped.to, 0)
    }

    // MARK: 按台记住音量

    func testUnknownStationUsesThePanelVolume() {
        XCTAssertEqual(RadioVolumeMemory.volume(for: "a", in: [:], fallback: 60), 60)
        XCTAssertEqual(RadioVolumeMemory.volume(for: "a", in: [:], fallback: 140), 100)
        XCTAssertEqual(RadioVolumeMemory.volume(for: "a", in: ["a": 35], fallback: 60), 35)
    }

    func testRememberingIsPerStationAndClamped() {
        var memory = RadioVolumeMemory.remembering(35.4, for: "loud", in: [:])
        memory = RadioVolumeMemory.remembering(80, for: "quiet", in: memory)
        memory = RadioVolumeMemory.remembering(150, for: "huge", in: memory)
        XCTAssertEqual(memory, ["loud": 35, "quiet": 80, "huge": 100])
        // 切回原来那台还是它自己的音量。
        XCTAssertEqual(RadioVolumeMemory.volume(for: "loud", in: memory, fallback: 60), 35)
        XCTAssertEqual(RadioVolumeMemory.remembering(50, for: "  ", in: memory), memory)
        XCTAssertEqual(RadioVolumeMemory.remembering(.nan, for: "x", in: memory), memory)
    }

    func testMemoryStaysBelowTheLimitAndKeepsTheNewest() {
        var memory: [String: Int] = [:]
        for index in 0..<(RadioVolumeMemory.limit + 5) {
            memory = RadioVolumeMemory.remembering(40, for: String(format: "s%04d", index), in: memory)
        }
        memory = RadioVolumeMemory.remembering(12, for: "a-new", in: memory)
        XCTAssertEqual(memory.count, RadioVolumeMemory.limit)
        XCTAssertEqual(memory["a-new"], 12)
    }

    func testDecodingDropsNonNumbers() {
        let raw: [String: Any] = ["a": 30, "b": 55.6, "c": "loud", "d": 300]
        XCTAssertEqual(RadioVolumeMemory.decode(raw), ["a": 30, "b": 56, "d": 100])
        XCTAssertEqual(RadioVolumeMemory.decode(nil), [:])
    }

    // MARK: 选台

    func testChoiceKeepsAmbientSoundsAsBefore() {
        XCTAssertEqual(FocusRadio.choice(""), .none)
        XCTAssertEqual(FocusRadio.choice(AmbientSound.rain.rawValue), .ambient(.rain))
        XCTAssertEqual(FocusRadio.choice("radio:"), .none)
        let fm = station("fm1", name: "音乐之声")
        let raw = FocusRadio.raw(for: fm)
        XCTAssertTrue(raw.hasPrefix(FocusRadio.prefix))
        XCTAssertEqual(FocusRadio.choice(raw), .radio(fm))
        // 环境音的读法不受影响：电台不是一种环境音。
        var state = TimerState()
        state.ambient = raw
        XCTAssertNil(FocusAmbient.sound(state))
    }

    func testStationFollowsTheFavouriteWithTheSameID() {
        let stored = station("fm1", name: "旧名字")
        var renamed = stored
        renamed.name = "新名字"
        renamed.backups = ["https://example.com/backup.mp3"]
        let raw = FocusRadio.raw(for: stored)
        XCTAssertEqual(FocusRadio.station(raw, favourites: [station("x"), renamed])?.name, "新名字")
        // 收藏里删掉了也还知道放哪个。
        XCTAssertEqual(FocusRadio.station(raw, favourites: [station("x")]), stored)
        XCTAssertNil(FocusRadio.station(AmbientSound.rain.rawValue, favourites: [stored]))
    }

    func testFavouritesMergeAllRadioWidgetsWithoutDuplicates() {
        var a = WidgetConfig()
        RadioDial.store([station("1"), station("2")], in: &a)
        var b = WidgetConfig()
        RadioDial.store([station("2"), station("3", "https://example.com/1.mp3"), station("4")], in: &b)
        XCTAssertEqual(FocusRadio.favourites([a, b]).map(\.id), ["1", "2", "4"])
        XCTAssertEqual(FocusRadio.favourites([]), [])
        var emptied = WidgetConfig()
        RadioDial.store([], in: &emptied)
        XCTAssertEqual(FocusRadio.favourites([emptied]), [])
        // 从没改过收藏的小组件显示自带的台，也算收藏。
        XCTAssertEqual(FocusRadio.favourites([WidgetConfig()]), RadioDial.presets)
    }

    func testNextCyclesFavouritesThenBackToAmbient() {
        let list = [station("1"), station("2")]
        let first = FocusRadio.raw(for: list[0])
        XCTAssertEqual(FocusRadio.next(after: first, favourites: list), FocusRadio.raw(for: list[1]))
        XCTAssertEqual(FocusRadio.next(after: FocusRadio.raw(for: list[1]), favourites: list),
                       AmbientSound.allCases[0].rawValue)
        XCTAssertEqual(FocusRadio.next(after: AmbientSound.rain.rawValue, favourites: list),
                       FocusAmbient.next(after: AmbientSound.rain.rawValue).rawValue)
        XCTAssertTrue(FocusRadio.isChosen(list[0], raw: first))
        XCTAssertFalse(FocusRadio.isChosen(list[1], raw: first))
    }

    // MARK: 该不该播

    func testWantedFollowsTheFocusRules() {
        let fm = station("fm1")
        let raw = FocusRadio.raw(for: fm)
        XCTAssertEqual(FocusRadio.wanted(running(raw), now: t0), fm)
        // 环境音不归电台管。
        XCTAssertNil(FocusRadio.wanted(running(AmbientSound.rain.rawValue), now: t0))
        // 休息时开着“休息时声音停下”不放，关着照放。
        XCTAssertNil(FocusRadio.wanted(running(raw, phase: .rest), now: t0))
        XCTAssertEqual(FocusRadio.wanted(running(raw, phase: .long, quiet: false), now: t0), fm)
        // 暂停、重置、到点都不放。
        var paused = running(raw)
        paused.paused = 300
        paused.deadline = nil
        XCTAssertNil(FocusRadio.wanted(paused, now: t0))
        var reset = running(raw)
        reset.deadline = nil
        XCTAssertNil(FocusRadio.wanted(reset, now: t0))
        XCTAssertNil(FocusRadio.wanted(running(raw), now: t0.addingTimeInterval(601)))
    }

    func testStartsWhenIdleAndStopsWhenFocusStops() {
        var rule = FocusPlayback()
        XCTAssertEqual(rule.step(wanted: "fm1", playing: nil), .start("fm1"))
        XCTAssertEqual(rule.step(wanted: "fm1", playing: "fm1"), .none)
        XCTAssertEqual(rule.step(wanted: nil, playing: "fm1"), .stop)
        XCTAssertNil(rule.started)
        // 下一轮重新来。
        XCTAssertEqual(rule.step(wanted: "fm1", playing: nil), .start("fm1"))
    }

    func testDoesNotGrabTheRadioWhileTheUserPlaysAnotherStation() {
        var rule = FocusPlayback()
        XCTAssertEqual(rule.step(wanted: "fm1", playing: "news"), .none)
        XCTAssertTrue(rule.yielded)
        // 用户停了也不放回来，这一轮让给用户。
        XCTAssertEqual(rule.step(wanted: "fm1", playing: nil), .none)
        // 专注停下时用户的台不碰。
        XCTAssertEqual(rule.step(wanted: nil, playing: "news"), .none)
        XCTAssertFalse(rule.yielded)
    }

    func testManualStopDuringFocusIsRespectedForTheRound() {
        var rule = FocusPlayback()
        _ = rule.step(wanted: "fm1", playing: nil)
        XCTAssertEqual(rule.step(wanted: "fm1", playing: nil), .none)
        XCTAssertTrue(rule.yielded)
        XCTAssertEqual(rule.step(wanted: "fm1", playing: nil), .none)
        // 用户换了别的台也一样。
        var other = FocusPlayback()
        _ = other.step(wanted: "fm1", playing: nil)
        XCTAssertEqual(other.step(wanted: "fm1", playing: "news"), .none)
        XCTAssertEqual(other.step(wanted: nil, playing: "news"), .none)
    }

    func testChoosingAnotherStationMidFocusSwitches() {
        var rule = FocusPlayback()
        _ = rule.step(wanted: "fm1", playing: nil)
        XCTAssertEqual(rule.step(wanted: "fm2", playing: "fm1"), .switchTo("fm2"))
        XCTAssertEqual(rule.step(wanted: "fm2", playing: "fm2"), .none)
    }

    func testFailedStartIsNotRetriedEverySecond() {
        var rule = FocusPlayback()
        _ = rule.step(wanted: "fm1", playing: nil)
        rule.failed()
        XCTAssertEqual(rule.step(wanted: "fm1", playing: nil), .none)
        XCTAssertEqual(rule.step(wanted: nil, playing: nil), .none)
        XCTAssertEqual(rule.step(wanted: "fm1", playing: nil), .start("fm1"))
    }

    // MARK: 环境音合成器的淡入淡出

    private func peak(_ synth: inout AmbientSynth, seconds: Double) -> Float {
        var peak: Float = 0
        for _ in 0..<Int(seconds * synth.sampleRate) { peak = max(peak, abs(synth.next())) }
        return peak
    }

    func testSynthFadesInFromSilence() {
        var synth = AmbientSynth(sampleRate: 8_000, seed: 5)
        synth.setVolume(0.8)
        synth.setSounds([.white])
        synth.setFade(0)
        synth.fade(to: 1, over: AudioFade.fadeIn)
        let start = peak(&synth, seconds: 0.05)
        _ = peak(&synth, seconds: 1.5)
        let settled = peak(&synth, seconds: 0.2)
        XCTAssertLessThan(start, settled * 0.1)
        XCTAssertEqual(synth.fadeProgress, 1)
    }

    func testSynthFadesOutAndCanComeBackMidway() {
        var synth = AmbientSynth(sampleRate: 8_000, seed: 9)
        synth.setVolume(0.8)
        synth.setSounds([.pink])
        _ = peak(&synth, seconds: 0.5)
        synth.fade(to: 0, over: AudioFade.fadeOut)
        _ = peak(&synth, seconds: 0.4)
        let midway = synth.fadeProgress
        XCTAssertEqual(midway, 0.5, accuracy: 0.01)
        synth.fade(to: 1, over: AudioFade.fadeIn)
        _ = peak(&synth, seconds: 0.1)
        XCTAssertGreaterThan(synth.fadeProgress, midway)
        _ = peak(&synth, seconds: 1)
        XCTAssertEqual(synth.fadeProgress, 1)
        synth.fade(to: 0, over: AudioFade.fadeOut)
        _ = peak(&synth, seconds: 0.9)
        XCTAssertEqual(synth.fadeProgress, 0)
        XCTAssertEqual(peak(&synth, seconds: 0.1), 0)
    }
}
