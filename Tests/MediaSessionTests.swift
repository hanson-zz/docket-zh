import XCTest

final class MediaSessionTests: XCTestCase {
    func testEverySourcePreemptsExactlyTheOtherTwo() {
        for source in MediaSource.allCases {
            let others = MediaSessionRules.preempted(by: source)
            XCTAssertEqual(others.count, 2)
            XCTAssertFalse(others.contains(source))
            XCTAssertEqual(Set(others + [source]), Set(MediaSource.allCases))
        }
    }

    func testStaleStopAndDelayedEventsDoNotReleaseTheNewOwner() {
        var state = MediaSessionOwnership()
        state.begin(.radio)
        let old = state.generation
        state.begin(.podcast)
        let current = state.generation
        XCTAssertFalse(state.accepts(old))
        XCTAssertFalse(state.end(.radio))
        XCTAssertEqual(state.source, .podcast)
        XCTAssertTrue(state.accepts(current))
        XCTAssertTrue(state.end(.podcast))
        XCTAssertNil(state.source)
        XCTAssertFalse(state.accepts(current))
        state.begin(.podcast)
        XCTAssertFalse(state.accepts(current))
    }

    func testPauseAndToggleForAllSources() {
        for source in MediaSource.allCases {
            XCTAssertEqual(MediaSessionRules.action(.toggle, source: source, playing: true), .pause)
            XCTAssertEqual(MediaSessionRules.action(.toggle, source: source, playing: false), .play)
            XCTAssertEqual(MediaSessionRules.action(.stop, source: source, playing: false), .stop)
        }
    }

    func testRadioSwitchesStationsAndHasNoSeek() {
        XCTAssertEqual(MediaSessionRules.action(.next, source: .radio, playing: true), .station(1))
        XCTAssertEqual(MediaSessionRules.action(.previous, source: .radio, playing: false), .station(-1))
        XCTAssertNil(MediaSessionRules.action(.seek, source: .radio, playing: true, requestedPosition: 50))
    }

    func testPodcastUsesChaptersAndFallsBackToBoundedSkips() {
        let chapters = [PodcastChapter(start: 0, title: "开场"), PodcastChapter(start: 100, title: "正题")]
        XCTAssertEqual(MediaSessionRules.action(.next, source: .podcast, playing: true, position: 20,
                                               duration: 200, chapters: chapters), .position(100))
        XCTAssertEqual(MediaSessionRules.action(.previous, source: .podcast, playing: false, position: 100,
                                               duration: 200, chapters: chapters), .position(0))
        XCTAssertEqual(MediaSessionRules.action(.next, source: .podcast, playing: true, position: 195,
                                               duration: 200, chapters: chapters), .position(200))
        XCTAssertEqual(MediaSessionRules.action(.backward, source: .podcast, playing: true, position: 5,
                                               duration: 200), .position(0))
        XCTAssertEqual(MediaSessionRules.action(.forward, source: .podcast, playing: true, position: 10,
                                               duration: 200), .position(40))
        XCTAssertEqual(MediaSessionRules.action(.seek, source: .podcast, playing: false, duration: 200,
                                               requestedPosition: 500), .position(200))
        XCTAssertNil(MediaSessionRules.action(.seek, source: .podcast, playing: true, requestedPosition: .nan))
    }

    func testAmbientDoesNotAdvertiseTrackOrSeekCommands() {
        for command in [MediaCommand.next, .previous, .forward, .backward, .seek] {
            XCTAssertFalse(MediaSessionRules.supports(command, source: .ambient))
            XCTAssertNil(MediaSessionRules.action(command, source: .ambient, playing: true))
        }
    }
}
