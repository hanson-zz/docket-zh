import XCTest
@testable import Docket

/// 小熊猫六状态：图名解析和回退、各面板事件到状态、庆祝合并与冷却、减弱动态效果。
final class PandaStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 图名

    func testPreferredArtComesFirst() {
        for state in PandaState.allCases {
            XCTAssertEqual(PandaStateResolver.candidates(state).first, "panda-state-\(state.rawValue)")
            XCTAssertFalse(PandaStateResolver.fallbackNames(state).isEmpty, "\(state) 要有回退")
        }
        let all: Set<String> = Set(PandaState.allCases.map(PandaStateResolver.preferredName))
        XCTAssertEqual(all.count, 6)
    }

    func testFallbackWhenPreferredMissing() {
        let old: Set<String> = ["pet-panda-idle", "pet-panda-cheer", "pet-panda-rest", "pet-sprite-lookup-4",
                                "pet-sprite-front-wave-1", "notch-panda-peek"]
        let exists: (String) -> Bool = { old.contains($0) }
        XCTAssertEqual(PandaStateResolver.imageName(.idle, exists: exists), "pet-panda-idle")
        XCTAssertEqual(PandaStateResolver.imageName(.thinking, exists: exists), "pet-sprite-lookup-4")
        XCTAssertEqual(PandaStateResolver.imageName(.peek, exists: exists), "notch-panda-peek")
        XCTAssertEqual(PandaStateResolver.imageName(.alert, exists: exists), "pet-sprite-front-wave-1")
        XCTAssertEqual(PandaStateResolver.imageName(.done, exists: exists), "pet-panda-cheer")
        XCTAssertEqual(PandaStateResolver.imageName(.rest, exists: exists), "pet-panda-rest")
        XCTAssertNil(PandaStateResolver.imageName(.done, exists: { _ in false }))
    }

    func testNewArtWinsWhenPresent() {
        let exists: (String) -> Bool = { _ in true }
        XCTAssertEqual(PandaStateResolver.imageName(.alert, exists: exists), "panda-state-alert")
        XCTAssertEqual(PandaStateResolver.imageName(.extra(.drink), exists: exists), "pet-panda-drink")
    }

    func testExtraFallsBackToIdle() {
        let exists: (String) -> Bool = { $0 == "pet-panda-idle" }
        XCTAssertEqual(PandaStateResolver.imageName(.extra(.sip), exists: exists), "pet-panda-idle")
    }

    // MARK: 常态加表态

    func testPulseOverridesLowerBaseUntilExpired() {
        let pulse = PandaPulse(state: .done, started: t0, until: t0.addingTimeInterval(2))
        XCTAssertEqual(PandaStateResolver.resolve(base: .state(.idle), pulse: pulse, now: t0.addingTimeInterval(1)),
                       .state(.done))
        XCTAssertEqual(PandaStateResolver.resolve(base: .state(.idle), pulse: pulse, now: t0.addingTimeInterval(2)),
                       .state(.idle))
        // 正在思考不被庆祝打断。
        XCTAssertEqual(PandaStateResolver.resolve(base: .state(.thinking), pulse: pulse, now: t0.addingTimeInterval(1)),
                       .state(.thinking))
        XCTAssertEqual(PandaStateResolver.resolve(base: .state(.rest), pulse: nil, now: t0), .state(.rest))
    }

    func testPriorityOrder() {
        let order: [PandaState] = [.rest, .idle, .peek, .done, .thinking, .alert]
        XCTAssertEqual(order.map(\.priority), order.map(\.priority).sorted())
        XCTAssertEqual(Set(order.map(\.priority)).count, 6)
    }

    // MARK: 庆祝合并与冷却

    func testCelebrationMergesWithinCooldown() {
        var moment = PandaCelebration()
        let first = moment.register(.done, at: t0)
        let second = moment.register(.done, at: t0.addingTimeInterval(1))
        XCTAssertEqual(second.started, first.started, "3 秒内再勾一条不重播")
        XCTAssertEqual(second.until, t0.addingTimeInterval(1 + PandaMotion.doneHold))
        let third = moment.register(.done, at: t0.addingTimeInterval(3.5))
        XCTAssertEqual(third.started, t0.addingTimeInterval(3.5), "冷却过了重新庆祝")
    }

    func testCelebrationKeepsHigherState() {
        var moment = PandaCelebration()
        moment.register(.done, at: t0)
        let merged = moment.register(.peek, at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(merged.state, .done)
        moment.reset()
        XCTAssertNil(moment.pulse)
        let peek = moment.register(.peek, at: t0)
        XCTAssertEqual(peek.state, .peek)
        XCTAssertEqual(moment.register(.done, at: t0.addingTimeInterval(1)).state, .done)
    }

    func testExpiredPulseStartsFresh() {
        var moment = PandaCelebration()
        moment.register(.done, at: t0, hold: 1)
        let next = moment.register(.done, at: t0.addingTimeInterval(2))
        XCTAssertEqual(next.started, t0.addingTimeInterval(2))
    }

    // MARK: 动效

    func testMotionTimingsWithinSpec() {
        XCTAssertTrue((0.25...0.45).contains(PandaMotion.transition))
        XCTAssertTrue((0.6...1.2).contains(PandaMotion.oneShot))
        XCTAssertEqual(PandaMotion.blinkInterval, 10...20)
        XCTAssertEqual(PandaMotion.celebrationCooldown, 3)
    }

    func testReduceMotionIsStatic() {
        XCTAssertEqual(PandaMotion.transitionDuration(reduceMotion: true), 0)
        XCTAssertEqual(PandaMotion.transitionDuration(reduceMotion: false), PandaMotion.transition)
        XCTAssertFalse(PandaMotion.playsOneShot(.done, reduceMotion: true))
        XCTAssertTrue(PandaMotion.playsOneShot(.done, reduceMotion: false))
        XCTAssertTrue(PandaMotion.playsOneShot(.alert, reduceMotion: false))
        XCTAssertFalse(PandaMotion.playsOneShot(.idle, reduceMotion: false))
        XCTAssertFalse(PandaMotion.blinks(.idle, reduceMotion: true, hasBlinkFrame: true))
        XCTAssertFalse(PandaMotion.blinks(.idle, reduceMotion: false, hasBlinkFrame: false))
        XCTAssertFalse(PandaMotion.blinks(.thinking, reduceMotion: false, hasBlinkFrame: true))
        XCTAssertTrue(PandaMotion.blinks(.idle, reduceMotion: false, hasBlinkFrame: true))
        XCTAssertEqual(PandaMotion.blinkDelay(unit: 0), 10)
        XCTAssertEqual(PandaMotion.blinkDelay(unit: 1), 20)
        XCTAssertEqual(PandaMotion.blinkDelay(unit: 5), 20)
        XCTAssertEqual(PandaMotion.blinkDelay(unit: .nan), 10)
    }

    func testStageSizesAndBaseline() {
        XCTAssertEqual(PandaStage.allCases.map(\.side), PandaStage.allCases.map(\.side).sorted())
        XCTAssertEqual(PandaStage.baseline(.peek), 1)
        XCTAssertEqual(PandaStage.baseline(.idle), 0.987, accuracy: 0.0001)
    }

    // MARK: 天气

    func testWeather() {
        XCTAssertEqual(PandaStateResolver.weather(nil, alertStyle: false), .state(.idle))
        XCTAssertEqual(PandaStateResolver.weather(.clothing, alertStyle: false), .state(.idle), "晴天平常天待机")
        XCTAssertEqual(PandaStateResolver.weather(.rain, alertStyle: true), .scene(.rain), "雨雪提醒用雨雪图代替举爪")
        XCTAssertEqual(PandaStateResolver.weather(.rain, alertStyle: false), .scene(.rain))
        XCTAssertEqual(PandaStateResolver.weather(.wind, alertStyle: true), .state(.alert))
        XCTAssertEqual(PandaStateResolver.weather(.air, alertStyle: true), .state(.alert), "空气差提醒")
        XCTAssertEqual(PandaStateResolver.weather(.uv, alertStyle: true), .scene(.drink))
        XCTAssertEqual(PandaStateResolver.weather(.cooling, alertStyle: true), .state(.idle))
    }

    func testWeatherScenesFromRealData() {
        func input(_ t: Double?, feels: Double? = nil, symbol: String? = "cloud.fill", mm: Double? = nil) -> WeatherSceneInput {
            WeatherSceneInput(temperatureC: t, apparentC: feels, symbolName: symbol, precipitationMM: mm)
        }
        let sunny = input(22, symbol: "sun.max.fill")
        XCTAssertEqual(PandaStateResolver.weather(.clothing, alertStyle: false, conditions: sunny), .scene(.sunny))
        XCTAssertEqual(PandaStateResolver.weather(nil, alertStyle: false, conditions: sunny), .scene(.sunny))
        XCTAssertEqual(PandaStateResolver.weather(.clothing, alertStyle: false,
                                                  conditions: input(10, symbol: "cloud.rain.fill")), .scene(.rain))
        XCTAssertEqual(PandaStateResolver.weather(.clothing, alertStyle: false,
                                                  conditions: input(-2, symbol: "cloud.snow.fill")), .scene(.rain), "下雪也算雨雪")
        XCTAssertEqual(PandaStateResolver.weatherScene(input(12, mm: 0.4)), .rain, "这一小时已有降水")
        XCTAssertEqual(PandaStateResolver.weatherScene(input(8, feels: 5)), .cold, "体感 5℃ 算冷")
        XCTAssertNil(PandaStateResolver.weatherScene(input(8, feels: 5.5)))
        XCTAssertEqual(PandaStateResolver.weatherScene(input(4)), .cold, "没有体感时看气温")
        XCTAssertEqual(PandaStateResolver.weatherScene(input(30, symbol: "sun.max.fill")), .hot, "热优先于晴")
        XCTAssertEqual(PandaStateResolver.weatherScene(input(-3, feels: -6, symbol: "sun.max.fill")), .cold)
        XCTAssertNil(PandaStateResolver.weatherScene(input(20, symbol: "moon.stars.fill")), "夜里晴不算晴天图")
        XCTAssertNil(PandaStateResolver.weatherScene(input(20, symbol: "cloud.sun.fill")))
        XCTAssertNil(PandaStateResolver.weatherScene(input(nil, symbol: nil)), "没有数据保持待机")
        XCTAssertEqual(PandaStateResolver.weather(.clothing, alertStyle: false, conditions: nil), .state(.idle))
        // 风大、空气差告警照旧举爪，不被晴天图盖掉；不是告警时按天气。
        XCTAssertEqual(PandaStateResolver.weather(.wind, alertStyle: true, conditions: sunny), .state(.alert))
        XCTAssertEqual(PandaStateResolver.weather(.air, alertStyle: false, conditions: sunny), .scene(.sunny))
        XCTAssertEqual(PandaStateResolver.weather(.uv, alertStyle: false, conditions: sunny), .scene(.drink))
    }

    // MARK: 场景图

    func testSceneNamesAndCandidates() {
        XCTAssertEqual(PandaScene.allCases.count, 7)
        for scene in PandaScene.allCases {
            XCTAssertEqual(scene.imageName, "panda-scene-\(scene.rawValue)")
            XCTAssertEqual(PandaStateResolver.candidates(.scene(scene)),
                           ["panda-scene-\(scene.rawValue)"] + PandaStateResolver.candidates(.idle))
            XCTAssertEqual(PandaPose.scene(scene).state, .idle, "场景图按待机算")
            XCTAssertTrue(PandaStateResolver.isFormalArt(scene.imageName))
        }
        XCTAssertTrue(PandaStateResolver.isFormalArt("panda-state-idle"))
        XCTAssertFalse(PandaStateResolver.isFormalArt("pet-panda-drink"))
    }

    func testSceneFallsBackToIdleWhenMissing() {
        XCTAssertEqual(PandaStateResolver.imageName(.scene(.record), exists: { _ in true }), "panda-scene-record")
        XCTAssertEqual(PandaStateResolver.imageName(.scene(.record), exists: { $0.hasPrefix("panda-state-") }),
                       "panda-state-idle")
        XCTAssertEqual(PandaStateResolver.imageName(.scene(.write), exists: { $0 == "pet-panda-idle" }), "pet-panda-idle")
        XCTAssertNil(PandaStateResolver.imageName(.scene(.sunny), exists: { _ in false }))
    }

    func testSceneArtShipsInResources() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/PandaStates")
        guard FileManager.default.fileExists(atPath: dir.path) else { throw XCTSkip("没有源码目录") }
        for scene in PandaScene.allCases {
            for suffix in ["", "@2x"] {
                let path = dir.appendingPathComponent("\(scene.imageName)\(suffix).png").path
                XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
            }
        }
    }

    func testWritePulseShowsSceneAndKeepsCooldown() {
        var moment = PandaCelebration()
        let first = moment.register(.peek, scene: .write, at: t0)
        XCTAssertEqual(first.pose, .scene(.write))
        XCTAssertEqual(PandaStateResolver.resolve(base: .state(.idle), pulse: first, now: t0.addingTimeInterval(1)),
                       .scene(.write))
        XCTAssertEqual(PandaStateResolver.resolve(base: .state(.rest), pulse: first, now: t0.addingTimeInterval(1)),
                       .scene(.write))
        // 3 秒里再记一条：不重播，只往后延。
        let again = moment.register(.peek, scene: .write, at: t0.addingTimeInterval(1))
        XCTAssertEqual(again.started, t0)
        XCTAssertEqual(again.pose, .scene(.write))
        // 冷却里勾完一条：完成优先级更高，改成完成的图。
        let done = moment.register(.done, at: t0.addingTimeInterval(1.5))
        XCTAssertEqual(done.pose, .state(.done))
        XCTAssertEqual(done.started, t0)
        // 过了冷却重新开始一次。
        let later = moment.register(.peek, scene: .write, at: t0.addingTimeInterval(10))
        XCTAssertEqual(later.started, t0.addingTimeInterval(10))
        XCTAssertEqual(later.pose, .scene(.write))
    }

    // MARK: AI

    func testAIStates() {
        XCTAssertEqual(PandaStateResolver.ai(nil), .idle)
        XCTAssertEqual(PandaStateResolver.ai(.thinking), .thinking)
        XCTAssertEqual(PandaStateResolver.ai(.answering), .thinking)
        XCTAssertEqual(PandaStateResolver.ai(.done), .done)
        XCTAssertEqual(PandaStateResolver.ai(.failed("x")), .alert)
        // 网页、App 拿不到回答，不假装思考或完成。
        XCTAssertEqual(PandaStateResolver.ai(.thinking, mode: .web), .idle)
        XCTAssertEqual(PandaStateResolver.ai(.done, mode: .jump), .idle)
        XCTAssertEqual(PandaStateResolver.aiBase(nil), .idle)
        XCTAssertEqual(PandaStateResolver.aiBase(.answering), .thinking)
        XCTAssertEqual(PandaStateResolver.aiBase(.done), .idle)
    }

    func testAIPulseOnlyOnFinish() {
        XCTAssertEqual(PandaStateResolver.aiPulse(from: .answering, to: .done, at: t0)?.state, .done)
        XCTAssertEqual(PandaStateResolver.aiPulse(from: .thinking, to: .failed("x"), at: t0)?.state, .alert)
        XCTAssertNil(PandaStateResolver.aiPulse(from: nil, to: .done, at: t0), "打开面板时已是旧回答不庆祝")
        XCTAssertNil(PandaStateResolver.aiPulse(from: .done, to: .done, at: t0))
        XCTAssertNil(PandaStateResolver.aiPulse(from: .thinking, to: .answering, at: t0))
        let pulse = PandaStateResolver.aiPulse(from: .answering, to: .done, at: t0)
        XCTAssertEqual(pulse?.until, t0.addingTimeInterval(PandaMotion.doneHold))
    }

    // MARK: 待办

    func testTodo() {
        XCTAssertEqual(PandaStateResolver.todo(openCount: 0, todayCleared: false, totalCount: 0), .rest)
        XCTAssertEqual(PandaStateResolver.todo(openCount: 3, todayCleared: false, totalCount: 5), .idle)
        XCTAssertEqual(PandaStateResolver.todo(openCount: 2, todayCleared: true, totalCount: 5), .done)
        XCTAssertEqual(PandaStateResolver.todo(openCount: 0, todayCleared: false, totalCount: 4), .rest)
    }

    // MARK: 喝水

    func testWater() {
        XCTAssertEqual(PandaStateResolver.water(.stage(.done)), .state(.done))
        XCTAssertEqual(PandaStateResolver.water(.stage(.nearlyFull)), .state(.idle))
        XCTAssertEqual(PandaStateResolver.water(.dry(hours: 2)), .state(.alert))
        XCTAssertEqual(PandaStateResolver.water(.stage(.sipping)), .extra(.sip))
        XCTAssertEqual(PandaStateResolver.water(.gulp), .scene(.drink))
        XCTAssertEqual(PandaStateResolver.water(.parched), .extra(.parched))
        XCTAssertEqual(PandaStateResolver.water(.stage(.thirsty)), .extra(.thirsty))
    }

    func testWaterDryKeepsThirstyArtWithoutAlertArt() {
        let old: (String) -> Bool = { $0.hasPrefix("pet-panda") }
        XCTAssertEqual(PandaStateResolver.waterImageName(.dry(hours: 3), exists: old), "pet-panda-hungry")
        XCTAssertEqual(PandaStateResolver.waterImageName(.dry(hours: 3), exists: { $0 != "panda-scene-drink" }),
                       "panda-state-alert")
        XCTAssertEqual(PandaStateResolver.waterImageName(.stage(.done), exists: old), "pet-panda-cheer")
        XCTAssertEqual(PandaStateResolver.waterImageName(.gulp, exists: old), "pet-panda-drink", "缺场景图回退抱竹筒")
    }

    func testWaterDrinkScene() {
        let all: (String) -> Bool = { _ in true }
        XCTAssertEqual(PandaStateResolver.waterImageName(.gulp, exists: all), "panda-scene-drink", "点 + 喝一口")
        XCTAssertEqual(PandaStateResolver.waterImageName(.dry(hours: 2), exists: all), "panda-scene-drink", "提醒该喝水")
        XCTAssertEqual(PandaStateResolver.waterImageName(.stage(.sipping), exists: all), "pet-panda-sip")
        XCTAssertEqual(PandaStateResolver.waterImageName(.stage(.thirsty), exists: all), "pet-panda-hungry")
        XCTAssertEqual(PandaStateResolver.waterImageName(.parched, exists: all), "WaterPanda-skeleton")
    }

    // MARK: 专注

    func testFocusCompatibility() {
        XCTAssertEqual(PandaStateResolver.focus(.idle), .idle)
        XCTAssertNil(PandaStateResolver.focus(.focus))
        XCTAssertEqual(PandaStateResolver.focus(.`break`), .rest)
        XCTAssertEqual(PandaStateResolver.focus(.done), .done)
    }

    // MARK: 老图名迁移

    func testLegacyNamesMapToStates() {
        XCTAssertEqual(PandaStateResolver.legacyState("pet-panda-idle"), .idle)
        XCTAssertEqual(PandaStateResolver.legacyState("pet-panda-cheer"), .done)
        XCTAssertEqual(PandaStateResolver.legacyState("pet-panda-rest"), .rest)
        for name in ["pet-panda-melt", "pet-panda-hungry", "pet-panda-sick"] {
            XCTAssertEqual(PandaStateResolver.legacyState(name), .alert, name)
        }
        // 场景扩展动作和专属素材不换。
        for name in ["pet-panda-drink", "pet-panda-sip", "pet-panda-eat", "pet-panda-skeleton", "pet-panda-dusty",
                     "pet-cat-hungry", "pet-sprite-blink-1", "notch-panda-peek", "focus-mascot-panda-idle"] {
            XCTAssertNil(PandaStateResolver.legacyState(name), name)
        }
    }

    func testMigratedNameNeedsArt() {
        XCTAssertEqual(PandaStateResolver.migratedName("pet-panda-cheer", exists: { _ in true }), "panda-state-done")
        XCTAssertEqual(PandaStateResolver.migratedName("pet-panda-cheer", exists: { _ in false }), "pet-panda-cheer")
        XCTAssertEqual(PandaStateResolver.migratedName("pet-panda-eat", exists: { _ in true }), "pet-panda-eat")
        XCTAssertEqual(PandaStateResolver.migratedName("pet-panda-melt", exists: { _ in true }), "panda-state-alert")
    }

    func testCodexStates() {
        XCTAssertEqual(CodexCard.pandaState(.working), .thinking)
        XCTAssertEqual(CodexCard.pandaState(.waiting), .alert)
        XCTAssertEqual(CodexCard.pandaState(.done), .done)
        XCTAssertEqual(CodexCard.pandaState(.idle), .rest)
    }
}
