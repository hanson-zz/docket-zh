import Foundation
import XCTest

final class WidgetSoundTests: XCTestCase {
    private func widget() -> DockItem {
        .widget(WidgetCatalog.make(.clock)!)
    }

    private func app() -> DockItem {
        .app(id: UUID(), bundleID: "com.apple.Safari",
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/Safari.app")))
    }

    // MARK: Decision

    func testAddingAWidgetIsAnAdd() {
        let before = [app()]
        XCTAssertEqual(WidgetSoundDecision.event(before: before, after: before + [widget()]), .added)
    }

    func testRemovingAWidgetIsARemove() {
        let w = widget()
        let a = app()
        XCTAssertEqual(WidgetSoundDecision.event(before: [a, w], after: [a]), .removed)
    }

    func testAppsAndReorderingAreSilent() {
        let a = app(), w = widget()
        XCTAssertNil(WidgetSoundDecision.event(before: [a], after: [a, app()]))
        XCTAssertNil(WidgetSoundDecision.event(before: [a, w], after: [w, a]))
        XCTAssertNil(WidgetSoundDecision.event(before: [a, w], after: [w]))
    }

    func testGroupingAWidgetIsSilentButRemovingItsGroupIsNot() {
        let a = app(), w = widget()
        let group = DockItem.group(DockGroup(id: UUID(), name: "组", tint: .blue, items: [a, w]))
        XCTAssertNil(WidgetSoundDecision.event(before: [a, w], after: [group]))
        XCTAssertEqual(WidgetSoundDecision.widgetCount([group, widget()]), 2)
        XCTAssertEqual(WidgetSoundDecision.event(before: [group], after: []), .removed)
    }

    func testSwitchVolumeAndSystemSettingAllGate() {
        var settings = WidgetSoundSettings()
        XCTAssertTrue(WidgetSoundDecision.shouldPlay(settings, systemUISoundsEnabled: true))
        XCTAssertFalse(WidgetSoundDecision.shouldPlay(settings, systemUISoundsEnabled: false))
        settings.volume = 0
        XCTAssertFalse(WidgetSoundDecision.shouldPlay(settings, systemUISoundsEnabled: true))
        settings.volume = 0.5
        settings.enabled = false
        XCTAssertFalse(WidgetSoundDecision.shouldPlay(settings, systemUISoundsEnabled: true))
    }

    func testSystemUISoundsDefaultReading() {
        XCTAssertTrue(WidgetSoundDecision.systemUISoundsEnabled(nil))
        XCTAssertTrue(WidgetSoundDecision.systemUISoundsEnabled(1))
        XCTAssertFalse(WidgetSoundDecision.systemUISoundsEnabled(0))
        XCTAssertFalse(WidgetSoundDecision.systemUISoundsEnabled(false))
        XCTAssertFalse(WidgetSoundDecision.systemUISoundsEnabled(NSNumber(value: 0)))
    }

    // MARK: Gate

    func testGateCollapsesOneGestureButNotSeparateClicks() {
        var gate = WidgetSoundGate(interval: 0.12)
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(gate.allow(.added, at: t))
        XCTAssertFalse(gate.allow(.added, at: t.addingTimeInterval(0.05)))
        XCTAssertTrue(gate.allow(.removed, at: t.addingTimeInterval(0.05)))
        XCTAssertTrue(gate.allow(.added, at: t.addingTimeInterval(0.3)))
    }

    // MARK: Settings

    func testSettingsDefaultsAndLenientDecoding() throws {
        let empty = try JSONDecoder().decode(WidgetSoundSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.enabled)
        XCTAssertEqual(empty.style, .dockling)
        XCTAssertEqual(empty.volume, WidgetSoundSettings.defaultVolume)

        let odd = try JSONDecoder().decode(WidgetSoundSettings.self,
                                           from: Data(#"{"enabled":false,"style":"later","volume":3}"#.utf8))
        XCTAssertFalse(odd.enabled)
        XCTAssertEqual(odd.style, .dockling)
        XCTAssertEqual(odd.gain, 1)

        let state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.widgetSounds.enabled)
    }

    func testSettingsRoundTrip() throws {
        var settings = WidgetSoundSettings()
        settings.style = .system
        settings.volume = 0.3
        settings.enabled = false
        let back = try JSONDecoder().decode(WidgetSoundSettings.self,
                                            from: JSONEncoder().encode(settings))
        XCTAssertEqual(back, settings)
    }

    // MARK: Synth

    func testSynthesisedSoundsAreShortAudibleAndClean() {
        for event in WidgetSoundEvent.allCases {
            let samples = WidgetSoundSynth.render(event)
            let seconds = Double(samples.count) / WidgetSoundSynth.sampleRate
            XCTAssertGreaterThan(seconds, 0.05, "\(event)")
            XCTAssertLessThan(seconds, 0.5, "\(event)")
            let peak = samples.map { abs($0) }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.1, "\(event)")
            XCTAssertLessThanOrEqual(peak, 0.95, "\(event)")
            XCTAssertTrue(samples.allSatisfy(\.isFinite), "\(event)")
            XCTAssertLessThan(abs(samples.last ?? 1), 0.001, "\(event) ends in a click")
        }
    }

    func testWavHeader() {
        let samples = WidgetSoundSynth.render(.added)
        let data = WidgetSoundSynth.wav(samples)
        XCTAssertEqual(data.count, 44 + samples.count * 2)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
    }

    func testSystemCandidatesPreferTheDocksPoof() {
        XCTAssertTrue(WidgetSystemSounds.candidates(for: .removed).first?.hasSuffix("poof item off dock.aif") == true)
        XCTAssertFalse(WidgetSystemSounds.fallbackNames(for: .added).isEmpty)
    }
}
