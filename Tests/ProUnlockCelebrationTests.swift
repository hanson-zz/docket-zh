import XCTest

/// 码头 Pro 解锁庆祝动画的纯逻辑：时间线分段、音效调度、功能标签和“+N”、首次激活标记，
/// 以及中英文标题、标签在 560 宽卡片里放不放得下。
final class ProUnlockCelebrationTests: XCTestCase {

    // MARK: 时间线

    func testPhasesFollowTheStoryboard() {
        let expected: [(Double, ProUnlockPhase)] = [
            (-1, .entrance), (0, .entrance), (0.39, .entrance),
            (0.4, .bow), (0.99, .bow),
            (1.0, .unlock), (1.59, .unlock),
            (1.6, .reveal), (2.39, .reveal),
            (2.4, .settle), (2.99, .settle),
            (3.0, .idle), (30, .idle),
        ]
        for (t, phase) in expected {
            XCTAssertEqual(ProUnlockTimeline.phase(at: t), phase, "t = \(t)")
        }
        XCTAssertEqual(ProUnlockPhase.allCases.map(\.start), [0, 0.4, 1.0, 1.6, 2.4, 3.0])
        XCTAssertEqual(ProUnlockTimeline.duration, ProUnlockPhase.idle.start)
    }

    func testBeatsLandInTheirPhase() {
        typealias T = ProUnlockTimeline
        XCTAssertEqual(T.phase(at: T.crownDropAt), .bow)
        XCTAssertEqual(T.phase(at: T.crownLandAt), .bow)
        XCTAssertEqual(T.phase(at: T.confettiAt), .bow)
        XCTAssertEqual(T.phase(at: T.leftFireworkAt), .unlock)
        XCTAssertEqual(T.phase(at: T.rightFireworkAt), .unlock)
        XCTAssertLessThan(T.leftFireworkAt, T.rightFireworkAt)
        XCTAssertEqual(T.phase(at: T.titleAt), .reveal)
        XCTAssertEqual(T.phase(at: T.shimmerAt), .reveal)
        for index in 0..<6 {
            XCTAssertEqual(T.phase(at: T.chipTime(index)), .reveal, "第 \(index) 个标签")
        }
        XCTAssertEqual(T.phase(at: T.waveAt), .settle)
        XCTAssertEqual(T.phase(at: T.successAt), .settle)
    }

    func testPoseSwapsToCrownThenWave() {
        XCTAssertEqual(ProUnlockTimeline.pose(at: 0), .bow)
        XCTAssertEqual(ProUnlockTimeline.pose(at: 0.89), .bow)
        XCTAssertEqual(ProUnlockTimeline.pose(at: 0.9), .crown)
        XCTAssertEqual(ProUnlockTimeline.pose(at: 2.39), .crown)
        XCTAssertEqual(ProUnlockTimeline.pose(at: 2.4), .wave)
        XCTAssertEqual(ProUnlockTimeline.pose(at: 99), .wave)
    }

    func testFireworksFadeToAfterglow() {
        XCTAssertEqual(ProUnlockTimeline.fireworkLevel(at: 1.0), 1)
        XCTAssertEqual(ProUnlockTimeline.fireworkLevel(at: 2.4), 1)
        XCTAssertEqual(ProUnlockTimeline.fireworkLevel(at: 2.7), 0.65, accuracy: 1e-9)
        XCTAssertEqual(ProUnlockTimeline.fireworkLevel(at: 3.0), ProUnlockTimeline.fireworkAfterglow, accuracy: 1e-9)
        XCTAssertEqual(ProUnlockTimeline.fireworkLevel(at: 10), ProUnlockTimeline.fireworkAfterglow, accuracy: 1e-9)
        XCTAssertEqual(ProUnlockTimeline.progress(5, from: 1, length: 0), 1)
        XCTAssertEqual(ProUnlockTimeline.progress(0.5, from: 1, length: 0), 0)
    }

    // MARK: 音效

    func testFullScheduleMatchesTheBrief() {
        let cues = ProUnlockSoundSchedule.full(chipCount: 6)
        XCTAssertEqual(cues.count, 4 + 6 + 1)
        XCTAssertEqual(cues.map(\.time), cues.map(\.time).sorted())
        XCTAssertEqual(cues.first, ProUnlockSoundCue(time: 0, sound: .whoosh))
        XCTAssertEqual(cues.last?.sound, .success)
        XCTAssertEqual(cues.last?.time ?? 0, 2.4, accuracy: 1e-9)

        let pop = cues.first { $0.sound == .pop }
        XCTAssertEqual(pop?.time ?? 0, 0.9, accuracy: 1e-9)

        let fireworks = cues.filter { $0.sound == .firework }
        XCTAssertEqual(fireworks.map(\.time), [1.0, 1.3])
        XCTAssertLessThan(fireworks[0].pan, 0, "第一发在左")
        XCTAssertGreaterThan(fireworks[1].pan, 0, "第二发在右")

        let dings = cues.filter { if case .ding = $0.sound { true } else { false } }
        XCTAssertEqual(dings.map(\.sound), (0..<6).map { ProUnlockSound.ding($0) }, "音高逐个升高")
        XCTAssertEqual(dings.map(\.time), (0..<6).map(ProUnlockTimeline.chipTime))
        XCTAssertTrue(dings.allSatisfy { $0.pan == 0 })
    }

    func testReducedMotionAndSwitchOff() {
        XCTAssertEqual(ProUnlockSoundSchedule.cues(soundOn: true, reduceMotion: true, chipCount: 6),
                       [ProUnlockSoundCue(time: 0, sound: .success)])
        XCTAssertEqual(ProUnlockSoundSchedule.cues(soundOn: true, reduceMotion: false, chipCount: 6),
                       ProUnlockSoundSchedule.full(chipCount: 6))
        XCTAssertTrue(ProUnlockSoundSchedule.cues(soundOn: false, reduceMotion: false, chipCount: 6).isEmpty)
        XCTAssertTrue(ProUnlockSoundSchedule.cues(soundOn: false, reduceMotion: true, chipCount: 6).isEmpty)
        XCTAssertEqual(ProUnlockSoundSchedule.full(chipCount: 0).count, 5)
        XCTAssertEqual(ProUnlockSoundSchedule.pandaTap.map(\.sound), [.pop, .firework])
    }

    func testSoundFilesAreDistinctAndClamped() {
        let names = ProUnlockSound.all.map(\.fileName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names.count, 3 + ProUnlockSound.dingCount + 1)
        XCTAssertEqual(ProUnlockSound.ding(-3).fileName, "unlock-ding-0")
        XCTAssertEqual(ProUnlockSound.ding(42).fileName, "unlock-ding-5")
    }

    // MARK: 功能标签和 +N

    func testOverflowIsCountedFromTheProList() {
        let all = ProUnlockHighlights.allItems
        let expected = ProFeatures.proKinds.count + ProFeatures.proTools.count
            + ProFeatures.Setting.allCases.count + ProUnlockStyle.allCases.count
        XCTAssertEqual(all.count, expected)
        XCTAssertEqual(Set(all).count, all.count, "清单里没有重复")
        XCTAssertEqual(ProUnlockHighlights.featured.count, 5)
        XCTAssertEqual(Set(ProUnlockHighlights.featured).count, 5)
        for item in ProUnlockHighlights.featured {
            XCTAssertTrue(all.contains(item), "\(item) 不在 Pro 清单里")
        }
        XCTAssertEqual(ProUnlockHighlights.overflowCount(), expected - 5)
        // 今天的清单：17 种小组件、5 个工具、2 个设置、11 类外观样式，减去 5 个。
        XCTAssertEqual(ProUnlockHighlights.overflowCount(), 30)
        XCTAssertEqual(ProUnlockHighlights.overflowCount(total: 3, shown: 5), 0)
        XCTAssertEqual(ProUnlockHighlights.overflowCount(total: 7, shown: -1), 7)
    }

    func testChipsAreFivePlusN() {
        let chips = ProUnlockHighlights.chips
        XCTAssertEqual(chips.count, 6)
        XCTAssertEqual(chips.last?.title, "+\(ProUnlockHighlights.overflowCount())")
        XCTAssertNil(chips.last?.symbol)
        XCTAssertEqual(chips.last?.tint, .gray)
        XCTAssertEqual(Set(chips.prefix(5).map(\.tint)).count, 5, "五个功能五种颜色")
        XCTAssertEqual(chips.prefix(5).map(\.title), ["液态外观", "刘海 AI 对话", "充电上限", "电子宠物", "截图识字"])
        for chip in chips.prefix(5) {
            XCTAssertNotNil(chip.symbol)
            let length = chip.title.filter { $0 != " " }.count
            XCTAssertTrue((4...6).contains(length), "\(chip.title) 不是 4 到 6 个字")
        }
    }

    // MARK: 首次激活

    func testAutoPlaysOnlyOnTheFirstActivation() {
        XCTAssertTrue(ProUnlockFirstRun.shouldAutoPlay(activationSucceeded: true, alreadyShown: false))
        XCTAssertFalse(ProUnlockFirstRun.shouldAutoPlay(activationSucceeded: true, alreadyShown: true),
                       "解绑后再激活不再自动弹")
        XCTAssertFalse(ProUnlockFirstRun.shouldAutoPlay(activationSucceeded: false, alreadyShown: false))
        XCTAssertFalse(ProUnlockFirstRun.shouldAutoPlay(activationSucceeded: false, alreadyShown: true))
    }

    func testLaunchMarksMacsActivatedBeforeTheFeature() {
        XCTAssertTrue(ProUnlockFirstRun.shouldMarkOnLaunch(isActivated: true, alreadyShown: false))
        XCTAssertFalse(ProUnlockFirstRun.shouldMarkOnLaunch(isActivated: true, alreadyShown: true))
        XCTAssertFalse(ProUnlockFirstRun.shouldMarkOnLaunch(isActivated: false, alreadyShown: false),
                       "试用或免费时不标记，之后第一次激活照常播放")
    }

    func testFirstRunMarkerRoundTripsThroughDefaults() throws {
        let suite = "ProUnlockCelebrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(defaults.bool(forKey: ProUnlockFirstRun.shownKey))
        XCTAssertTrue(ProUnlockFirstRun.soundEnabled(defaults.object(forKey: ProUnlockFirstRun.soundKey)), "音效默认开")
        defaults.set(true, forKey: ProUnlockFirstRun.shownKey)
        defaults.set(false, forKey: ProUnlockFirstRun.soundKey)
        XCTAssertFalse(ProUnlockFirstRun.shouldAutoPlay(activationSucceeded: true,
                                                         alreadyShown: defaults.bool(forKey: ProUnlockFirstRun.shownKey)))
        XCTAssertFalse(ProUnlockFirstRun.soundEnabled(defaults.object(forKey: ProUnlockFirstRun.soundKey)))
        XCTAssertNotEqual(ProUnlockFirstRun.shownKey, ProUnlockFirstRun.soundKey)
    }

    // MARK: 中英文放得下

    func testCardGeometry() {
        XCTAssertEqual(ProUnlockLayout.cardWidth, 560)
        XCTAssertEqual(ProUnlockLayout.cardHeight, 760)
        XCTAssertEqual(ProUnlockLayout.cornerRadius, 28)
        XCTAssertEqual(ProUnlockLayout.contentWidth, 512)
        XCTAssertEqual(ProUnlockLayout.chipWidth * 3 + ProUnlockLayout.chipSpacing * 2, ProUnlockLayout.contentWidth, accuracy: 1e-9)
        XCTAssertGreaterThan(ProUnlockLayout.chipTextWidth, 100)
    }

    func testChineseCopyFits() {
        for chip in ProUnlockHighlights.chips {
            XCTAssertTrue(fitsChip(chip.title), "标签放不下：\(chip.title)")
        }
        XCTAssertTrue(ProUnlockLayout.fits("解锁成功，谢谢你！", fontSize: ProUnlockLayout.titleFontSize,
                                           width: ProUnlockLayout.titleTextWidth))
        XCTAssertTrue(ProUnlockLayout.fits("恭喜码头 Pro 已激活，一次购买，永久使用",
                                           fontSize: ProUnlockLayout.subtitleFontSize, width: ProUnlockLayout.contentWidth))
    }

    func testEnglishCopyFitsAndStaysShort() throws {
        let english = try englishStrings()
        for item in ProUnlockHighlights.featured {
            let key = ProUnlockHighlights.title(item)
            let value = try XCTUnwrap(english[key], "\(key) 没有英文")
            let words = value.split(separator: " ").count
            XCTAssertTrue((1...3).contains(words), "\(value) 不是 1 到 3 个词")
            XCTAssertTrue(fitsChip(value), "英文标签放不下：\(value)")
        }
        let title = try XCTUnwrap(english["解锁成功，谢谢你！"])
        XCTAssertEqual(title, "Unlocked, thank you!")
        XCTAssertTrue(ProUnlockLayout.fits(title, fontSize: ProUnlockLayout.titleFontSize,
                                           width: ProUnlockLayout.titleTextWidth))
        let subtitle = try XCTUnwrap(english["恭喜码头 Pro 已激活，一次购买，永久使用"])
        XCTAssertTrue(ProUnlockLayout.fits(subtitle, fontSize: ProUnlockLayout.subtitleFontSize,
                                           width: ProUnlockLayout.contentWidth))
        let button = try XCTUnwrap(english["开启 Pro 之旅 ›"])
        XCTAssertTrue(ProUnlockLayout.fits(button, fontSize: 19, width: ProUnlockLayout.contentWidth - 40))
        for key in ["解锁动画音效", "重看解锁动画", "关于 Pro"] {
            XCTAssertNotNil(english[key], "\(key) 没有英文")
        }
    }

    func testWidthEstimateIsMonotonic() {
        XCTAssertEqual(ProUnlockLayout.estimatedWidth("", fontSize: 14), 0)
        XCTAssertEqual(ProUnlockLayout.estimatedWidth("码", fontSize: 10), 10)
        XCTAssertGreaterThan(ProUnlockLayout.estimatedWidth("WWW", fontSize: 14), ProUnlockLayout.estimatedWidth("iii", fontSize: 14))
        XCTAssertGreaterThan(ProUnlockLayout.estimatedWidth("Text from Screen", fontSize: 13),
                             ProUnlockLayout.estimatedWidth("Text", fontSize: 13))
    }

    // MARK: 资源

    func testBundledArtAndSoundsExist() throws {
        let folder = repoRoot().appendingPathComponent("Resources/Unlock")
        for pose in [ProUnlockPose.bow, .crown, .wave] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(pose.rawValue + ".png").path), pose.rawValue)
        }
        for name in ["unlock-crown", "unlock-gift", "unlock-ticket"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".png").path), name)
        }
        for sound in ProUnlockSound.all {
            let url = folder.appendingPathComponent(sound.fileName + ".wav")
            let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, sound.fileName)
            XCTAssertLessThan(size, 60 * 1024, "\(sound.fileName) 超过 60 KB")
        }
    }

    // MARK: 工具

    private func fitsChip(_ text: String) -> Bool {
        let font = text.hasPrefix("+") ? 15 : ProUnlockLayout.chipFontSize
        return ProUnlockLayout.fits(text, fontSize: font, width: ProUnlockLayout.chipTextWidth)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 从 Localizable.xcstrings 读出全部英文译文（测试包里没有这张表，tr 只给中文）。
    private func englishStrings() throws -> [String: String] {
        let url = repoRoot().appendingPathComponent("Resources/Localization/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        var result: [String: String] = [:]
        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let en = localizations["en"] as? [String: Any],
                  let unit = en["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String else { continue }
            result[key] = value
        }
        return result
    }
}
