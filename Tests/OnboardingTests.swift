import XCTest

/// 新手引导：什么时候弹、选择到小组件的映射、权限去重、清单进度。
final class OnboardingTests: XCTestCase {
    private var catalog: Set<String> { Set(WidgetCatalog.shippable.map(\.kind.rawValue)) }

    func testShowsOnlyOnFreshInstall() {
        XCTAssertTrue(Onboarding.shouldShow(seen: false, hasSavedSetup: false))
        XCTAssertFalse(Onboarding.shouldShow(seen: true, hasSavedSetup: false))
        // 老用户升级：已经有布局，不弹。
        XCTAssertFalse(Onboarding.shouldShow(seen: false, hasSavedSetup: true))
        XCTAssertFalse(Onboarding.shouldShow(seen: true, hasSavedSetup: true))
    }

    func testEveryPickedKindExistsInCatalog() {
        let kinds = Onboarding.kinds(for: OnboardingUse.allCases, available: catalog)
        XCTAssertFalse(kinds.isEmpty)
        for kind in kinds {
            XCTAssertNotNil(WidgetKind(rawValue: kind), kind)
            XCTAssertTrue(catalog.contains(kind), kind)
        }
    }

    func testEveryUseHasAtLeastTwoRealCandidates() {
        for use in OnboardingUse.allCases {
            let kinds = Onboarding.kinds(for: [use], available: catalog)
            XCTAssertGreaterThanOrEqual(kinds.count, 2, use.rawValue)
            XCTAssertLessThanOrEqual(kinds.count, Onboarding.maxPerUse, use.rawValue)
        }
    }

    func testUnknownCandidatesAreSkipped() {
        // 目录里没有的种类（这里故意不给“小熊猫的竹篮”）不会被选中。
        let kinds = Onboarding.kinds(for: [OnboardingUse.health], available: ["water", "posture"])
        XCTAssertEqual(kinds, ["water", "posture"])
        XCTAssertEqual(Onboarding.kinds(for: [OnboardingUse.health], available: []), [])
    }

    func testHealthAddsHabitsNowThatTheyAreFree() {
        // 习惯打卡 2026-10-19 起免费 3 个，健康用途又会加上它。
        XCTAssertEqual(Onboarding.kinds(for: [OnboardingUse.health], available: ["water", "posture", "habit"]),
                       ["water", "posture", "habit"])
        XCTAssertFalse(Onboarding.isPro("habit"))
        XCTAssertFalse(Onboarding.isPro("progress"))
    }

    func testNoDuplicatesAndStableOrder() {
        let a = Onboarding.kinds(for: [OnboardingUse.fun, .system, .fun, .productivity], available: catalog)
        let b = Onboarding.kinds(for: [OnboardingUse.productivity, .system, .fun], available: catalog)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, Set(a).count)
        XCTAssertEqual(Array(a.prefix(3)), ["todo", "calendar", "timer"])
    }

    func testExistingKindsAreNotAddedAgain() {
        let kinds = Onboarding.kinds(for: [OnboardingUse.system], available: catalog,
                                     existing: ["battery", "system"])
        XCTAssertFalse(kinds.contains("battery"))
        XCTAssertFalse(kinds.contains("system"))
        // 空出的名额由后面的候选补上。
        XCTAssertEqual(kinds, ["network", "gauges"])
    }

    func testNoProWidgetsAreAdded() {
        // 引导只加免费小组件，竹篮、播客、电子宠物、GitHub、Codex 用量等 Pro 小组件都不加。
        let kinds = Onboarding.kinds(for: OnboardingUse.allCases, available: catalog)
        for kind in kinds {
            XCTAssertFalse(ProFeatures.isProKind(WidgetKind(rawValue: kind)!), kind)
        }
        for use in OnboardingUse.allCases {
            for kind in use.candidates {
                XCTAssertFalse(Onboarding.isPro(kind), kind)
            }
        }
        // 就算候选里混进 Pro 的，也会被跳过。
        XCTAssertEqual(Onboarding.kinds(for: [OnboardingUse.developer],
                                        available: ["github", "ai-usage", "clipboard", "color-picker"]),
                       ["clipboard", "color-picker"])
        XCTAssertTrue(Onboarding.isPro("perfect-day"))
        XCTAssertFalse(Onboarding.isPro("water"))
    }

    func testDeveloperUseStillAddsFreeWidgets() {
        XCTAssertEqual(Onboarding.kinds(for: [OnboardingUse.developer], available: catalog),
                       ["clipboard", "color-picker"])
    }

    func testOnboardingWidgetsUseFreeLooks() {
        // 电池新建默认液态（Pro），引导里改回经典；其他小组件的默认外观本来就免费。
        let kinds = Onboarding.kinds(for: OnboardingUse.allCases, available: catalog)
        XCTAssertTrue(kinds.contains("battery"))
        for kind in kinds {
            var widget = WidgetCatalog.make(WidgetKind(rawValue: kind)!)!
            for (key, value) in Onboarding.freeLookOverrides(widget.config.values) { widget.config.set(key, value) }
            XCTAssertFalse(ProFeatures.isPro(widget), kind)
        }
        XCTAssertEqual(Onboarding.freeLookOverrides([BatteryLook.key: .string("liquid")]),
                       [BatteryLook.key: .string("classic")])
        XCTAssertEqual(Onboarding.freeLookOverrides([BatteryLook.key: .string("classic")]), [:])
        XCTAssertEqual(Onboarding.freeLookOverrides([:]), [:])
    }

    func testNothingSelectedAddsNothing() {
        XCTAssertEqual(Onboarding.kinds(for: [OnboardingUse](), available: catalog), [])
    }

    func testCapPerUse() {
        let kinds = Onboarding.kinds(for: [OnboardingUse.productivity], available: catalog)
        XCTAssertEqual(kinds.count, Onboarding.maxPerUse)
    }

    func testPermissionsAreOnlyThoseNeededAndDeduplicated() {
        XCTAssertEqual(Onboarding.permissions(for: ["calendar", "week", "battery", "music"]),
                       ["日历", "自动化（音乐 App）"])
        XCTAssertEqual(Onboarding.permissions(for: ["battery", "network"]), [])
        let table = ["a": "甲", "b": "甲", "c": "乙"]
        XCTAssertEqual(Onboarding.permissions(for: ["c", "a", "b"], table: table), ["乙", "甲"])
    }

    func testChecklistTicksInOrder() {
        XCTAssertEqual(Onboarding.checkedItems(progress: 0), 0)
        XCTAssertEqual(Onboarding.checkedItems(progress: 0.2), 0)
        XCTAssertEqual(Onboarding.checkedItems(progress: 0.4), 1)
        XCTAssertEqual(Onboarding.checkedItems(progress: 0.7), 2)
        XCTAssertEqual(Onboarding.checkedItems(progress: 0.99), 2)
        XCTAssertEqual(Onboarding.checkedItems(progress: 1), 3)
        XCTAssertEqual(Onboarding.checkedItems(progress: 5), 3)
        XCTAssertEqual(Onboarding.checkedItems(progress: -1), 0)
    }

    func testSteps() {
        XCTAssertEqual(OnboardingStep.allCases.count, 6)
        XCTAssertEqual(OnboardingStep.welcome.filledSegments, 1)
        XCTAssertEqual(OnboardingStep.done.filledSegments, 6)
        XCTAssertFalse(OnboardingStep.welcome.canGoBack)
        XCTAssertTrue(OnboardingStep.position.canGoBack)
        XCTAssertTrue(OnboardingStep.permissions.canGoBack)
        XCTAssertFalse(OnboardingStep.building.canGoBack)
        XCTAssertFalse(OnboardingStep.done.canGoBack)
        XCTAssertNil(OnboardingStep.done.next)
    }

    func testEveryCandidateHasASymbol() {
        for use in OnboardingUse.allCases {
            for kind in use.candidates {
                XCTAssertNotEqual(Onboarding.symbol(for: kind), "square.grid.2x2.fill", kind)
            }
        }
    }

    // MARK: 靠岸动画

    func testWidgetsDockOneAfterAnother() {
        let count = 4
        XCTAssertEqual(Onboarding.dockingFraction(index: 0, count: count, progress: 0), 0)
        XCTAssertEqual(Onboarding.dockedCount(count: count, progress: 0), 0)
        // 第一个先出发，后面的还在画面外。
        XCTAssertGreaterThan(Onboarding.dockingFraction(index: 0, count: count, progress: 0.2), 0)
        XCTAssertEqual(Onboarding.dockingFraction(index: 3, count: count, progress: 0.2), 0)
        // 进度走满时全部靠岸，在那之前最后一个还没停好。
        XCTAssertLessThan(Onboarding.dockingFraction(index: 3, count: count, progress: 0.99), 1)
        XCTAssertEqual(Onboarding.dockedCount(count: count, progress: 1), count)
        XCTAssertEqual(Onboarding.dockedCount(count: count, progress: 1.5), count, "progress is clamped")
    }

    func testDockingIsMonotonicAndOrdered() {
        let count = 6
        var previous = Array(repeating: 0.0, count: count)
        for step in 0...100 {
            let progress = Double(step) / 100
            let now = (0..<count).map { Onboarding.dockingFraction(index: $0, count: count, progress: progress) }
            for index in 0..<count {
                XCTAssertGreaterThanOrEqual(now[index], previous[index], "never sails backwards")
                if index > 0 { XCTAssertLessThanOrEqual(now[index], now[index - 1], "queued in order") }
            }
            XCTAssertEqual(Onboarding.dockedCount(count: count, progress: progress), now.filter { $0 >= 1 }.count)
            previous = now
        }
    }

    func testDockingEdgeCases() {
        XCTAssertEqual(Onboarding.dockingFraction(index: 0, count: 1, progress: 0.45), 1, "a lone widget takes the whole span")
        XCTAssertEqual(Onboarding.dockingFraction(index: 0, count: 0, progress: 0.5), 0)
        XCTAssertEqual(Onboarding.dockingFraction(index: 5, count: 3, progress: 0.5), 0)
        XCTAssertEqual(Onboarding.dockingFraction(index: -1, count: 3, progress: 0.5), 0)
        XCTAssertEqual(Onboarding.dockedCount(count: 0, progress: 1), 0)
        XCTAssertEqual(Onboarding.symbol(for: "perfect-day"), "leaf.fill")
    }
}
