import XCTest

/// 系统通知被关时，发通知的开关旁提示「系统通知已关闭 · 去开启」。
final class NotificationAccessTests: XCTestCase {
    func testAuthorizationStatusMapping() {
        XCTAssertEqual(NotificationAccess(authorizationStatus: 0), .unknown, "还没问过不提示")
        XCTAssertEqual(NotificationAccess(authorizationStatus: 1), .denied)
        XCTAssertEqual(NotificationAccess(authorizationStatus: 2), .allowed)
        XCTAssertEqual(NotificationAccess(authorizationStatus: 3), .allowed, "临时授权也能发")
        XCTAssertEqual(NotificationAccess(authorizationStatus: 4), .allowed)
        XCTAssertEqual(NotificationAccess(authorizationStatus: 99), .unknown)
    }

    func testWarnsOnlyWhenDeniedAndSwitchOn() {
        XCTAssertTrue(NotificationAccess.denied.warns(switchOn: true))
        XCTAssertFalse(NotificationAccess.denied.warns(switchOn: false), "开关本来就关着不提示")
        XCTAssertFalse(NotificationAccess.allowed.warns(switchOn: true))
        XCTAssertFalse(NotificationAccess.unknown.warns(switchOn: true))
    }

    func testSettingsURLOpensThisAppsNotificationPage() {
        XCTAssertEqual(NotificationAccess.settingsURL(bundleID: "com.docket-zh.app")?.absoluteString,
                       "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.docket-zh.app")
        XCTAssertEqual(NotificationAccess.settingsURL(bundleID: nil)?.absoluteString,
                       "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    func testNotificationSwitchesCoverTheWidgetsThatPostNotifications() {
        XCTAssertTrue(NotificationAccess.isNotificationSwitch(kind: WidgetKind.posture.rawValue, key: "notify"))
        XCTAssertTrue(NotificationAccess.isNotificationSwitch(kind: WidgetKind.podcast.rawValue, key: "notify"))
        XCTAssertTrue(NotificationAccess.isNotificationSwitch(kind: WidgetKind.github.rawValue, key: "notify"))
        XCTAssertTrue(NotificationAccess.isNotificationSwitch(kind: WidgetKind.aiUsage.rawValue, key: "notify"))
        XCTAssertTrue(NotificationAccess.isNotificationSwitch(kind: WidgetKind.aiUsage.rawValue, key: "notifyDone"))
        XCTAssertTrue(NotificationAccess.isNotificationSwitch(kind: WidgetKind.lunar.rawValue, key: "workAlert"))
        XCTAssertFalse(NotificationAccess.isNotificationSwitch(kind: WidgetKind.lunar.rawValue, key: "showTerm"))
        XCTAssertFalse(NotificationAccess.isNotificationSwitch(kind: WidgetKind.clock.rawValue, key: "notify"))
        // 每个列出的键都是这种小组件真有的布尔开关。
        for (kind, keys) in NotificationAccess.switches {
            guard let widgetKind = WidgetKind(rawValue: kind) else { return XCTFail("没有 \(kind) 这种小组件") }
            let defaults = WidgetCatalog.entry(widgetKind)?.defaults
            for key in keys {
                guard case .bool = defaults?.values[key] else {
                    XCTFail("\(kind).\(key) 不是默认配置里的布尔开关")
                    continue
                }
            }
        }
    }

    func testBareScreenshotToolCannotQueryNotificationCenter() {
        XCTAssertTrue(NotificationAccess.canReadSettings(bundleURL: URL(fileURLWithPath: "/Applications/Dockling.app")))
        XCTAssertFalse(NotificationAccess.canReadSettings(bundleURL: URL(fileURLWithPath: "/tmp/build/Release/")))
        XCTAssertFalse(NotificationAccess.canReadSettings(bundleURL: URL(fileURLWithPath: "/tmp/build/Release/Shots")))
    }

    func testWaterStockAndBatteryRules() {
        XCTAssertTrue(NotificationAccess.waterUsesNotifications(every: 60, popupShows: false))
        XCTAssertFalse(NotificationAccess.waterUsesNotifications(every: 60, popupShows: true), "弹卡片时不走通知")
        XCTAssertFalse(NotificationAccess.waterUsesNotifications(every: 0, popupShows: false), "提醒关闭")
        XCTAssertTrue(NotificationAccess.stockUsesNotifications(alertCount: 1))
        XCTAssertFalse(NotificationAccess.stockUsesNotifications(alertCount: 0))
        XCTAssertTrue(NotificationAccess.batteryUsesNotifications(levels: 1, extras: [false]))
        XCTAssertTrue(NotificationAccess.batteryUsesNotifications(levels: 0, extras: [false, true]))
        XCTAssertFalse(NotificationAccess.batteryUsesNotifications(levels: 0, extras: [false, false, false]))
    }
}
