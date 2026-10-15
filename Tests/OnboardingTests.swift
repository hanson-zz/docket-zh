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
        // 目录里没有的种类（比如还没上线的“完美一天”）不会被选中。
        let kinds = Onboarding.kinds(for: [OnboardingUse.health], available: ["water", "posture"])
        XCTAssertEqual(kinds, ["water", "posture"])
        XCTAssertEqual(Onboarding.kinds(for: [OnboardingUse.health], available: []), [])
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
}
