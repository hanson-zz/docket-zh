import XCTest

final class TimeInsightsWebsiteConnectionTests: XCTestCase {
    private func resolve(bridge: BrowserBridgeState = .connected, status: TimeInsightsStatus = .recording,
                         enabled: Bool = true, placed: Bool = true, excluded: Bool = false,
                         foreground: Bool = true, hasWebsite: Bool = true) -> TimeInsightsWebsiteConnection {
        .resolve(bridge: bridge, status: status, enabled: enabled, placed: placed, excluded: excluded,
                 foreground: foreground, hasWebsite: hasWebsite)
    }

    func testConnectedExtensionIsNotEnoughToClaimWebsiteRecording() {
        XCTAssertEqual(resolve(hasWebsite: false), .applicationOnly)
        XCTAssertEqual(resolve(foreground: false), .waitingForeground)
        XCTAssertEqual(resolve(status: .ownApp), .waitingForeground)
        XCTAssertEqual(resolve(status: .starting), .waitingForeground)
        XCTAssertEqual(resolve(status: .excluded, foreground: false), .waitingForeground)
        XCTAssertEqual(resolve(), .recording)
    }

    func testConsentAndPlacementOverrideAConnectedExtensionAndStaleWebsite() {
        XCTAssertEqual(resolve(enabled: false), .disabled)
        XCTAssertEqual(resolve(placed: false), .notPlaced)
        XCTAssertEqual(resolve(excluded: true), .blocked(.excluded))
    }

    func testPausedSleepIdleAndStorageFailureNeverClaimActiveRecording() {
        for status: TimeInsightsStatus in [.paused, .away, .idle, .storageError] {
            XCTAssertEqual(resolve(status: status), .blocked(status))
            XCTAssertEqual(resolve(bridge: .offline, status: status), .blocked(status))
        }
    }

    func testMissingPermissionOrDisconnectedBridgeOverridesStaleRecordedWebsite() {
        for bridge: BrowserBridgeState in [.permissionRequired, .notConnected, .offline] {
            XCTAssertEqual(resolve(bridge: bridge), .disconnected(bridge))
            XCTAssertEqual(resolve(bridge: bridge, foreground: false), .disconnected(bridge))
        }
    }

    func testPrivateOrUnavailablePageFallsBackToApplicationOnlyAndRecovers() {
        XCTAssertEqual(resolve(), .recording)
        XCTAssertEqual(resolve(hasWebsite: false), .applicationOnly)
        XCTAssertEqual(resolve(bridge: .offline, hasWebsite: false), .disconnected(.offline))
        XCTAssertEqual(resolve(hasWebsite: false), .applicationOnly)
        XCTAssertEqual(resolve(), .recording)
    }
}
