import Foundation
import XCTest

final class AppVolumeTests: XCTestCase {
    func testUnityIsUntouchedAndNeedsNoTap() {
        XCTAssertEqual(AppVolume.gain(percent: 100, muted: false), 1, accuracy: 0.0001)
        XCTAssertFalse(AppVolume.needsTap(AppVolumeSetting()))
        XCTAssertTrue(AppVolumeSetting().isDefault)
    }

    func testMuteAndChangesNeedATap() {
        XCTAssertTrue(AppVolume.needsTap(AppVolumeSetting(percent: 100, muted: true)))
        XCTAssertTrue(AppVolume.needsTap(AppVolumeSetting(percent: 60)))
        XCTAssertTrue(AppVolume.needsTap(AppVolumeSetting(percent: 150)))
        XCTAssertEqual(AppVolume.gain(percent: 80, muted: true), 0)
    }

    func testGainIsSquareLawAndClamped() {
        XCTAssertEqual(AppVolume.gain(percent: 50, muted: false), 0.25, accuracy: 0.0001)
        XCTAssertEqual(AppVolume.gain(percent: 150, muted: false), 2.25, accuracy: 0.0001)
        XCTAssertEqual(AppVolume.gain(percent: 400, muted: false), 2.25, accuracy: 0.0001)
        XCTAssertEqual(AppVolume.gain(percent: -10, muted: false), 0)
        XCTAssertEqual(AppVolume.gain(percent: .nan, muted: false), 1, accuracy: 0.0001)
        // Monotonic, so the slider never turns down while moving up.
        var previous: Float = -1
        for step in stride(from: 0.0, through: 150, by: 5) {
            let gain = AppVolume.gain(percent: step, muted: false)
            XCTAssertGreaterThan(gain, previous)
            previous = gain
        }
    }

    func testSnapsBackToUnity() {
        XCTAssertEqual(AppVolume.snapped(98), 100)
        XCTAssertEqual(AppVolume.snapped(103), 100)
        XCTAssertEqual(AppVolume.snapped(96), 96)
        XCTAssertEqual(AppVolume.snapped(200), 150)
    }

    func testTextAndSymbols() {
        XCTAssertEqual(AppVolume.percentText(62.4), "62%")
        XCTAssertEqual(AppVolume.symbol(percent: 0, muted: false), "speaker.slash.fill")
        XCTAssertEqual(AppVolume.symbol(percent: 80, muted: true), "speaker.slash.fill")
        XCTAssertEqual(AppVolume.symbol(percent: 20, muted: false), "speaker.wave.1.fill")
        XCTAssertEqual(AppVolume.symbol(percent: 120, muted: false), "speaker.wave.3.fill")
        XCTAssertEqual(AppVolumeText.value(playing: 0), "没有声音")
        XCTAssertEqual(AppVolumeText.value(playing: 2), "2 个应用")
        XCTAssertEqual(AppVolumeText.caption(names: ["音乐", "Safari"], permissionNeeded: false), "音乐、Safari")
        XCTAssertEqual(AppVolumeText.caption(names: ["音乐", "Safari", "微信"], permissionNeeded: false),
                       "音乐、Safari 等 3 个")
        XCTAssertEqual(AppVolumeText.caption(names: ["音乐"], permissionNeeded: true), "需要录音权限")
    }

    func testSettingsRoundTripDropsUntouchedApps() {
        let all: [String: AppVolumeSetting] = [
            "com.apple.Music": AppVolumeSetting(percent: 40),
            "com.apple.Safari": AppVolumeSetting(),
            "com.tencent.xinWeChat": AppVolumeSetting(percent: 100, muted: true),
        ]
        let read = AppVolumeSetting.decode(AppVolumeSetting.encode(all))
        XCTAssertEqual(Set(read.keys), ["com.apple.Music", "com.tencent.xinWeChat"])
        XCTAssertEqual(read["com.apple.Music"]?.percent, 40)
        XCTAssertEqual(read["com.tencent.xinWeChat"]?.muted, true)
    }

    func testSettingsDecodeLeniently() {
        let json = #"{"a":{"percent":300},"b":{"muted":true},"c":{}}"#.data(using: .utf8)
        let read = AppVolumeSetting.decode(json)
        XCTAssertEqual(read["a"]?.percent, 150)
        XCTAssertEqual(read["b"], AppVolumeSetting(percent: 100, muted: true))
        XCTAssertEqual(read["c"], AppVolumeSetting())
        XCTAssertEqual(AppVolumeSetting.decode(nil), [:])
        XCTAssertEqual(AppVolumeSetting.decode(Data("nope".utf8)), [:])
    }
}

final class AudioAppListTests: XCTestCase {
    private let apps = ["com.google.Chrome", "com.apple.Music", "com.apple.Safari", "com.google.Chrome.beta"]

    func testHelpersBelongToTheirApp() {
        XCTAssertEqual(AudioAppList.owner(of: "com.google.Chrome.helper.Renderer", apps: apps), "com.google.Chrome")
        XCTAssertEqual(AudioAppList.owner(of: "com.google.Chrome.beta.helper", apps: apps), "com.google.Chrome.beta")
        XCTAssertEqual(AudioAppList.owner(of: "com.apple.Music", apps: apps), "com.apple.Music")
        // A shared prefix that is not at a dot is a different app.
        XCTAssertEqual(AudioAppList.owner(of: "com.apple.MusicHelper", apps: apps), "com.apple.MusicHelper")
        XCTAssertEqual(AudioAppList.owner(of: "com.apple.WebKit.GPU", apps: apps), "com.apple.WebKit.GPU")
    }

    func testGroupsOnlyPlayingProcessesByOwner() {
        let processes = [
            AudioProcessInfo(objectID: 10, pid: 1, bundleID: "com.google.Chrome.helper", isRunningOutput: true),
            AudioProcessInfo(objectID: 11, pid: 2, bundleID: "com.google.Chrome.helper.Renderer", isRunningOutput: true),
            AudioProcessInfo(objectID: 12, pid: 3, bundleID: "com.apple.Music", isRunningOutput: false),
            AudioProcessInfo(objectID: 13, pid: 4, bundleID: "com.apple.WebKit.GPU", isRunningOutput: true),
            AudioProcessInfo(objectID: 14, pid: 5, bundleID: "", isRunningOutput: true),
            AudioProcessInfo(objectID: 15, pid: 6, bundleID: "com.docket-zh.app", isRunningOutput: true),
        ]
        let groups = AudioAppList.groups(processes, apps: apps, owners: [13: "com.apple.Safari"],
                                         excluding: ["com.docket-zh.app"])
        XCTAssertEqual(groups, [
            AudioAppGroup(bundleID: "com.apple.Safari", objectIDs: [13]),
            AudioAppGroup(bundleID: "com.google.Chrome", objectIDs: [11, 10]),
        ])
        XCTAssertEqual(groups.last?.objectIDs, [10, 11])
    }

    func testDiff() {
        let old = [AudioAppGroup(bundleID: "a", objectIDs: [1]), AudioAppGroup(bundleID: "b", objectIDs: [2])]
        let new = [AudioAppGroup(bundleID: "b", objectIDs: [2, 3]), AudioAppGroup(bundleID: "c", objectIDs: [4])]
        let diff = AudioAppList.diff(old: old, new: new)
        XCTAssertEqual(diff.added, ["c"])
        XCTAssertEqual(diff.removed, ["a"])
        XCTAssertEqual(diff.changed, ["b"])
        XCTAssertTrue(AudioAppList.diff(old: old, new: old).isEmpty)
    }

    func testTapPlan() {
        let playing = [AudioAppGroup(bundleID: "music", objectIDs: [1]),
                       AudioAppGroup(bundleID: "chrome", objectIDs: [2, 3]),
                       AudioAppGroup(bundleID: "safari", objectIDs: [4])]
        let settings: [String: AppVolumeSetting] = [
            "music": AppVolumeSetting(percent: 50),
            "chrome": AppVolumeSetting(percent: 100, muted: true),
            "safari": AppVolumeSetting(),
        ]
        // Nothing tapped yet: the two changed apps get taps, Safari does not.
        var plan = AppTapPlan.plan(playing: playing, settings: settings, tapped: [:])
        XCTAssertEqual(plan.build.map(\.bundleID), ["chrome", "music"])
        XCTAssertEqual(plan.remove, [])

        // Up to date: nothing to do.
        plan = AppTapPlan.plan(playing: playing, settings: settings, tapped: ["music": [1], "chrome": [3, 2]])
        XCTAssertEqual(plan, AppTapPlan.Plan(build: [], remove: []))

        // Chrome gained a helper, Music stopped, and a stale tap lingers.
        let later = [AudioAppGroup(bundleID: "chrome", objectIDs: [2, 3, 5])]
        plan = AppTapPlan.plan(playing: later, settings: settings,
                               tapped: ["music": [1], "chrome": [2, 3], "gone": [9]])
        XCTAssertEqual(plan.remove, ["chrome", "gone", "music"])
        XCTAssertEqual(plan.build, [AudioAppGroup(bundleID: "chrome", objectIDs: [2, 3, 5])])

        // Back to 100 percent removes the tap.
        plan = AppTapPlan.plan(playing: playing, settings: [:], tapped: ["music": [1]])
        XCTAssertEqual(plan, AppTapPlan.Plan(build: [], remove: ["music"]))
    }
}

final class SampleGainTests: XCTestCase {
    func testApplyClipsAndScrubsNonFinite() {
        XCTAssertEqual(SampleGain.apply(0.5, gain: 0.5), 0.25)
        XCTAssertEqual(SampleGain.apply(0.8, gain: 2.25), 1)
        XCTAssertEqual(SampleGain.apply(-0.8, gain: 2.25), -1)
        XCTAssertEqual(SampleGain.apply(.nan, gain: 1), 0)
    }

    func testSourceChannelMapping() {
        XCTAssertEqual(SampleGain.sourceChannel(for: 0, inputChannels: 2), 0)
        XCTAssertEqual(SampleGain.sourceChannel(for: 1, inputChannels: 2), 1)
        XCTAssertEqual(SampleGain.sourceChannel(for: 3, inputChannels: 2), 1)
        XCTAssertEqual(SampleGain.sourceChannel(for: 1, inputChannels: 1), 0)
        XCTAssertNil(SampleGain.sourceChannel(for: 0, inputChannels: 0))
    }

    func testInterleavedToPlanarCopy() {
        // Interleaved stereo in: L R L R L R.
        let input: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        var right = [Float](repeating: 9, count: 3)
        input.withUnsafeBufferPointer { source in
            right.withUnsafeMutableBufferPointer { destination in
                SampleGain.copy(from: source.baseAddress! + 1, sourceStride: 2,
                                to: destination.baseAddress!, destinationStride: 1, frames: 3, gain: 2)
            }
        }
        XCTAssertEqual(right[0], 0.4, accuracy: 0.0001)
        XCTAssertEqual(right[1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(right[2], 1, accuracy: 0.0001)
    }

    func testSilenceOnlyTouchesItsStride() {
        var buffer: [Float] = [1, 1, 1, 1]
        buffer.withUnsafeMutableBufferPointer { pointer in
            SampleGain.silence(pointer.baseAddress!, stride: 2, frames: 2)
        }
        XCTAssertEqual(buffer, [0, 1, 0, 1])
    }
}

final class IslandTests: XCTestCase {
    func testSettingsDefaultOffAndDecodeLeniently() throws {
        let fresh = IslandSettings()
        XCTAssertFalse(fresh.anyEnabled)
        XCTAssertEqual(fresh.leadMinutes, 5)

        let decoded = try JSONDecoder().decode(IslandSettings.self, from: Data(#"{"volume":true,"meetingMinutes":7}"#.utf8))
        XCTAssertTrue(decoded.volume)
        XCTAssertFalse(decoded.brightness)
        XCTAssertTrue(decoded.anyEnabled)
        XCTAssertEqual(decoded.leadMinutes, 5, "a choice no picker offers falls back")

        var state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(state.island, IslandSettings())
        state.island.meeting = true
        state.island.meetingMinutes = 10
        let again = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(again.island.leadMinutes, 10)
        XCTAssertTrue(again.island.meeting)
    }

    func testLevelQuantization() {
        XCTAssertEqual(IslandLevel.lit(0), 0)
        XCTAssertEqual(IslandLevel.lit(0.001), 1, "anything audible lights a segment")
        XCTAssertEqual(IslandLevel.lit(0.5), 8)
        XCTAssertEqual(IslandLevel.lit(1), 16)
        XCTAssertEqual(IslandLevel.lit(1.4), 16)
        XCTAssertEqual(IslandLevel.lit(-1), 0)
        XCTAssertEqual(IslandLevel.lit(.nan), 0)
        XCTAssertEqual(IslandLevel.percent(0.625), 63)
    }

    func testChangeThreshold() {
        XCTAssertFalse(IslandLevel.changed(from: nil, to: 0.5), "the first reading is a baseline")
        XCTAssertFalse(IslandLevel.changed(from: 0.5, to: 0.501))
        XCTAssertTrue(IslandLevel.changed(from: 0.5, to: 0.5625))
    }

    func testSymbols() {
        XCTAssertEqual(IslandLevel.volumeSymbol(0.8, muted: true), "speaker.slash.fill")
        XCTAssertEqual(IslandLevel.volumeSymbol(0.2, muted: false), "speaker.wave.1.fill")
        XCTAssertEqual(IslandLevel.volumeSymbol(0.9, muted: false), "speaker.wave.3.fill")
        XCTAssertEqual(IslandLevel.brightnessSymbol(0.2), "sun.min.fill")
        XCTAssertEqual(IslandLevel.brightnessSymbol(0.8), "sun.max.fill")
    }

    func testCountdownText() {
        XCTAssertEqual(IslandCountdown.text(secondsUntil: 300), "5 分钟后")
        XCTAssertEqual(IslandCountdown.text(secondsUntil: 250), "5 分钟后", "rounded up")
        XCTAssertEqual(IslandCountdown.text(secondsUntil: 61), "2 分钟后")
        XCTAssertEqual(IslandCountdown.text(secondsUntil: 60), "1 分钟后")
        XCTAssertEqual(IslandCountdown.text(secondsUntil: 30), "不到 1 分钟后")
        XCTAssertEqual(IslandCountdown.text(secondsUntil: 0), "现在")
        XCTAssertEqual(IslandCountdown.text(secondsUntil: -20), "现在")
        XCTAssertEqual(IslandCountdown.line(title: " 周会 ", secondsUntil: 180), "3 分钟后：周会")
        XCTAssertEqual(IslandCountdown.line(title: "", secondsUntil: 180), "3 分钟后：新日程")
    }

    func testCountdownPicksTheSoonestTimedEventInTheWindow() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let events = [
            IslandCountdown.Candidate(title: "全天", start: now.addingTimeInterval(60), isAllDay: true),
            IslandCountdown.Candidate(title: "太远", start: now.addingTimeInterval(20 * 60), isAllDay: false),
            IslandCountdown.Candidate(title: "评审", start: now.addingTimeInterval(4 * 60), isAllDay: false),
            IslandCountdown.Candidate(title: "站会", start: now.addingTimeInterval(2 * 60), isAllDay: false),
            IslandCountdown.Candidate(title: "早就开始", start: now.addingTimeInterval(-5 * 60), isAllDay: false),
        ]
        XCTAssertEqual(IslandCountdown.next(events, now: now, leadMinutes: 5)?.title, "站会")
        XCTAssertNil(IslandCountdown.next(events, now: now, leadMinutes: 1))
        XCTAssertTrue(IslandCountdown.inWindow(start: now.addingTimeInterval(-30), now: now, leadMinutes: 5),
                      "stays up for the minute it starts")
        XCTAssertFalse(IslandCountdown.inWindow(start: now.addingTimeInterval(301), now: now, leadMinutes: 5))
    }

    func testFlashOutranksTheMeeting() {
        let meeting = IslandContent.meeting(title: "周会", start: .distantFuture)
        let flash = IslandContent.volume(level: 0.5, muted: false)
        XCTAssertEqual(IslandContent.resolve(flash: flash, meeting: meeting), flash)
        XCTAssertEqual(IslandContent.resolve(flash: nil, meeting: meeting), meeting)
        XCTAssertNil(IslandContent.resolve(flash: nil, meeting: nil))
    }
}
