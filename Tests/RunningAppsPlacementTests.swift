import Foundation
import XCTest

/// 正在运行的应用放在扩展栏哪里：五档选择、旧开关的迁移和一行的拼接顺序。
final class RunningAppsPlacementTests: XCTestCase {
    private typealias T = ShelfRowToken

    // 两个小组件、两个固定 App、三个正在运行的 App。
    private let mixed = [true, true, false, false]

    private func row(_ pinned: [Bool], running: Int = 2, trash: Bool = false,
                     _ placement: RunningAppsPlacement) -> [T] {
        ShelfRow.tokens(pinnedIsWidget: pinned, runningCount: running,
                        showsTrash: trash, placement: placement)
    }

    // MARK: 设置

    func testDefaultIsAfterAppsWhichIsTheOldBehaviour() {
        XCTAssertEqual(RunningAppsPlacement.defaultValue, .afterApps)
        XCTAssertEqual(CustomDockSettings().runningApps, .afterApps)
    }

    func testLegacySwitchMigrates() throws {
        let off = Data(#"{"showRunningApps": false}"#.utf8)
        let on = Data(#"{"showRunningApps": true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: off).runningApps, .hidden)
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: on).runningApps, .afterApps)
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: Data("{}".utf8)).runningApps,
                       .afterApps)
    }

    func testNewKeyWinsOverTheLegacyOne() throws {
        let both = Data(#"{"showRunningApps": false, "runningApps": "start"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: both).runningApps, .start)
    }

    func testUnknownValueFallsBackToTheDefault() throws {
        let odd = Data(#"{"runningApps": "sideways"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: odd).runningApps, .afterApps)
    }

    func testEveryPlacementSurvivesARestart() throws {
        for placement in RunningAppsPlacement.allCases {
            var settings = CustomDockSettings()
            settings.runningApps = placement
            let data = try JSONEncoder().encode(settings)
            XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: data).runningApps,
                           placement)
        }
    }

    func testLabelsSayTopAndBottomOnAVerticalShelf() {
        XCTAssertNotEqual(RunningAppsPlacement.start.label(vertical: true),
                          RunningAppsPlacement.start.label(vertical: false))
        XCTAssertNotEqual(RunningAppsPlacement.end.label(vertical: true),
                          RunningAppsPlacement.end.label(vertical: false))
        XCTAssertEqual(RunningAppsPlacement.beforeApps.label(vertical: true),
                       RunningAppsPlacement.beforeApps.label(vertical: false))
        for placement in RunningAppsPlacement.allCases {
            XCTAssertFalse(placement.label(vertical: false).isEmpty)
        }
    }

    // MARK: 插入位置

    func testInsertionIndex() {
        func at(_ pinned: [Bool], _ placement: RunningAppsPlacement) -> Int? {
            ShelfRow.runningInsertionIndex(pinnedIsWidget: pinned, placement: placement)
        }
        XCTAssertNil(at(mixed, .hidden))
        XCTAssertEqual(at(mixed, .start), 0)
        XCTAssertEqual(at(mixed, .beforeApps), 2)
        XCTAssertEqual(at(mixed, .afterApps), 4)
        XCTAssertEqual(at(mixed, .end), 4)

        // 小组件排在固定 App 后面时，应用后和最右边才分得开。
        let appsFirst = [false, false, true]
        XCTAssertEqual(at(appsFirst, .beforeApps), 3)
        XCTAssertEqual(at(appsFirst, .afterApps), 2)
        XCTAssertEqual(at(appsFirst, .end), 3)

        // 没有固定 App：应用前和应用后都在小组件之后。
        XCTAssertEqual(at([true, true], .beforeApps), 2)
        XCTAssertEqual(at([true, true], .afterApps), 2)
        // 没有小组件：应用前在最开头。
        XCTAssertEqual(at([false, false], .beforeApps), 0)
        // 空扩展栏：哪一档都是 0。
        for placement in RunningAppsPlacement.allCases where placement != .hidden {
            XCTAssertEqual(at([], placement), 0)
        }
    }

    // MARK: 一整行

    func testAfterAppsMatchesTheOldRow() {
        XCTAssertEqual(row(mixed, trash: true, .afterApps),
                       [.pinned(0), .pinned(1), .grip, .pinned(2), .pinned(3),
                        .separator, .running(0), .running(1),
                        .separator, .trash])
    }

    func testFarLeftLeadsTheRow() {
        XCTAssertEqual(row(mixed, trash: true, .start),
                       [.running(0), .running(1), .separator,
                        .pinned(0), .pinned(1), .grip, .pinned(2), .pinned(3),
                        .separator, .trash])
    }

    func testBeforeAppsSitsAfterTheWidgets() {
        XCTAssertEqual(row(mixed, .beforeApps),
                       [.pinned(0), .pinned(1), .grip,
                        .separator, .running(0), .running(1), .separator,
                        .pinned(2), .pinned(3)])
    }

    func testFarRightStaysBeforeTheTrash() {
        let appsFirst = [false, true]
        XCTAssertEqual(row(appsFirst, trash: true, .end),
                       [.pinned(0), .pinned(1), .grip,
                        .separator, .running(0), .running(1),
                        .separator, .trash])
        XCTAssertEqual(row(appsFirst, trash: true, .afterApps),
                       [.pinned(0), .separator, .running(0), .running(1), .separator,
                        .pinned(1), .grip, .separator, .trash])
    }

    func testHiddenAndNoneRunningLeaveNoSeparator() {
        let plain: [T] = [.pinned(0), .pinned(1), .grip, .pinned(2), .pinned(3)]
        XCTAssertEqual(row(mixed, .hidden), plain)
        for placement in RunningAppsPlacement.allCases {
            XCTAssertEqual(row(mixed, running: 0, placement), plain, "\(placement)")
        }
    }

    func testNothingButRunningApps() {
        XCTAssertEqual(row([], .start), [.running(0), .running(1)])
        XCTAssertEqual(row([], trash: true, .end), [.running(0), .running(1), .separator, .trash])
    }

    func testEveryPlacementKeepsEveryEntryOnceAndTheTrashLast() {
        let shapes: [[Bool]] = [[], [true], [false], mixed, [false, true, false, true]]
        for pinned in shapes {
            for placement in RunningAppsPlacement.allCases {
                let tokens = row(pinned, running: 3, trash: true, placement)
                let pinnedSeen = tokens.compactMap { if case .pinned(let i) = $0 { i } else { nil } }
                let runningSeen = tokens.compactMap { if case .running(let i) = $0 { i } else { nil } }
                XCTAssertEqual(pinnedSeen, Array(pinned.indices), "\(pinned) \(placement)")
                XCTAssertEqual(runningSeen, placement == .hidden ? [] : [0, 1, 2], "\(pinned) \(placement)")
                XCTAssertEqual(tokens.last, .trash)
                // 没有两条相邻的分隔线，也不会以分隔线开头。
                XCTAssertNotEqual(tokens.first, .separator)
                for (a, b) in zip(tokens, tokens.dropFirst()) {
                    XCTAssertFalse(a == .separator && b == .separator, "\(pinned) \(placement)")
                }
                XCTAssertLessThanOrEqual(tokens.filter { $0 == .grip }.count, 1)
            }
        }
    }
}
