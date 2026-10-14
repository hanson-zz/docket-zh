import Foundation
import XCTest

/// The GitHub widget's list of projects and its "new since last seen" logic.
/// The network half lives in GitHubService, which the test target does not
/// compile; everything it decides with is here.
final class GitHubWatchTests: XCTestCase {

    private func date(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    // MARK: Addresses

    func testSlugsFromEveryKindOfAddress() {
        XCTAssertEqual(GitHubWatch.slug(from: "hanson-zz/docket-zh"), "hanson-zz/docket-zh")
        XCTAssertEqual(GitHubWatch.slug(from: "  https://github.com/apple/swift  "), "apple/swift")
        XCTAssertEqual(GitHubWatch.slug(from: "https://github.com/apple/swift/issues/123"), "apple/swift")
        XCTAssertEqual(GitHubWatch.slug(from: "https://github.com/apple/swift/pull/9?w=1"), "apple/swift")
        XCTAssertEqual(GitHubWatch.slug(from: "https://github.com/apple/swift/pulls"), "apple/swift")
        XCTAssertEqual(GitHubWatch.slug(from: "https://github.com/a/b/releases/tag/v1.0"), "a/b")
        XCTAssertEqual(GitHubWatch.slug(from: "https://www.github.com/a/b.git"), "a/b")
        XCTAssertEqual(GitHubWatch.slug(from: "github.com/a/b#readme"), "a/b")
        XCTAssertEqual(GitHubWatch.slug(from: "git@github.com:o/r.git"), "o/r")
        XCTAssertEqual(GitHubWatch.slug(from: "https://api.github.com/repos/o/r"), "o/r")
        XCTAssertEqual(GitHubWatch.slug(from: "a/socket.io"), "a/socket.io", "repository names may have dots")
    }

    func testAnythingElseIsRefused() {
        XCTAssertNil(GitHubWatch.slug(from: "https://gitlab.com/a/b"))
        XCTAssertNil(GitHubWatch.slug(from: "example.com/a/b"))
        XCTAssertNil(GitHubWatch.slug(from: "https://github.com/onlyowner"))
        XCTAssertNil(GitHubWatch.slug(from: "中文/仓库"))
        XCTAssertNil(GitHubWatch.slug(from: ""))
    }

    // MARK: The list

    func testTheOldRepoIsMovedIntoTheList() {
        let old = WidgetConfig(["repo": .string("https://github.com/apple/swift")])
        XCTAssertEqual(GitHubWatch.repos(old), ["apple/swift"], "read before the move too")
        let moved = GitHubWatch.migratingRepo(old)
        XCTAssertEqual(moved.strings("repos"), ["apple/swift"])
        XCTAssertNil(moved["repo"])
        XCTAssertEqual(GitHubWatch.repos(moved), ["apple/swift"])
    }

    func testAMigrationNeverOverwritesAList() {
        let both = WidgetConfig(["repo": .string("x/y"), "repos": .list([.string("a/b"), .string("c/d")])])
        let moved = GitHubWatch.migratingRepo(both)
        XCTAssertEqual(moved.strings("repos"), ["a/b", "c/d"])
        XCTAssertNil(moved["repo"])
        let untouched = WidgetConfig(["notify": .bool(true)])
        XCTAssertEqual(GitHubWatch.migratingRepo(untouched), untouched)
    }

    func testAnUnreadableOldRepoBecomesTheDefault() {
        let moved = GitHubWatch.migratingRepo(WidgetConfig(["repo": .string("nonsense")]))
        XCTAssertEqual(moved.strings("repos"), [GitHubWatch.defaultRepo])
    }

    func testASavedGitHubWidgetIsMigratedOnDecode() throws {
        // Saved by a build that knew only `repo`.
        let saved = WidgetInstance(kind: .github, config: WidgetConfig(["repo": .string("apple/swift")]))
        let json = try JSONEncoder().encode(saved)
        let widget = try JSONDecoder().decode(WidgetInstance.self, from: json)
        XCTAssertEqual(widget.config.strings("repos"), ["apple/swift"])
        XCTAssertNil(widget.config["repo"])
    }

    func testTheCatalogStartsWithTheDefaultRepo() throws {
        let widget = try XCTUnwrap(WidgetCatalog.make(.github))
        XCTAssertEqual(GitHubWatch.repos(widget.config), [GitHubWatch.defaultRepo])
        XCTAssertFalse(GitHubWatch.notifies(widget.config), "notifications are opt-in")
        XCTAssertEqual(GitHubWatch.interval(widget.config), 30)
    }

    func testTheListIsCleanedDedupedAndCapped() {
        let many = (1...12).map { "o/r\($0)" }
        let config = WidgetConfig(["repos": .list((["A/B", "a/b", "junk"] + many).map { .string($0) })])
        let repos = GitHubWatch.repos(config)
        XCTAssertEqual(repos.count, GitHubWatch.maxRepos)
        XCTAssertEqual(repos.first, "A/B")
        XCTAssertFalse(repos.contains("a/b"), "GitHub ignores case, so this is the same project")
        XCTAssertEqual(GitHubWatch.repos(WidgetConfig(["repos": .list([])])), [GitHubWatch.defaultRepo])
    }

    func testAddingChecksFormatRepeatsAndTheLimit() {
        XCTAssertEqual(try GitHubWatch.adding("https://github.com/c/d/issues", to: ["a/b"]).get(), ["a/b", "c/d"])
        XCTAssertEqual(GitHubWatch.adding("not a repo", to: []), .failure(.invalid))
        XCTAssertEqual(GitHubWatch.adding("A/b", to: ["a/B"]), .failure(.duplicate))
        let full = (1...8).map { "o/r\($0)" }
        XCTAssertEqual(GitHubWatch.adding("x/y", to: full), .failure(.full))
        XCTAssertEqual(GitHubWatch.AddError.full.message, "最多关注 8 个项目")
    }

    func testRemovingAndMoving() {
        XCTAssertEqual(GitHubWatch.removing("A/B", from: ["a/b", "c/d"]), ["c/d"])
        XCTAssertEqual(GitHubWatch.removing("a/b", from: ["a/b"]), ["a/b"], "the last one stays")
        XCTAssertEqual(GitHubWatch.moving("c/d", by: -1, in: ["a/b", "c/d", "e/f"]), ["c/d", "a/b", "e/f"])
        XCTAssertEqual(GitHubWatch.moving("a/b", by: -1, in: ["a/b", "c/d"]), ["a/b", "c/d"])
        XCTAssertEqual(GitHubWatch.moving("a/b", by: 1, in: ["a/b", "c/d"]), ["c/d", "a/b"])
        XCTAssertEqual(GitHubWatch.moving("x/y", by: 1, in: ["a/b"]), ["a/b"])
    }

    func testIntervalAndItsUnauthenticatedStretch() {
        XCTAssertEqual(GitHubWatch.interval(WidgetConfig(["interval": .string("15")])), 15)
        XCTAssertEqual(GitHubWatch.interval(WidgetConfig(["interval": .string("7")])), 30)
        XCTAssertEqual(GitHubWatch.effectiveInterval(minutes: 15, repoCount: 8, authenticated: true), 15)
        XCTAssertEqual(GitHubWatch.effectiveInterval(minutes: 30, repoCount: 1, authenticated: false), 30)
        // Eight projects at three requests each, under 45 an hour.
        XCTAssertEqual(GitHubWatch.effectiveInterval(minutes: 15, repoCount: 8, authenticated: false), 32)
        XCTAssertEqual(GitHubWatch.effectiveInterval(minutes: 60, repoCount: 8, authenticated: false), 60)
    }

    func testThePlanJoinsEveryGitHubWidget() {
        let a = WidgetInstance(kind: .github, config: WidgetConfig([
            "repos": .list([.string("a/b"), .string("c/d")]), "interval": .string("60")]))
        let b = WidgetInstance(kind: .github, config: WidgetConfig([
            "repos": .list([.string("C/D"), .string("e/f")]), "interval": .string("15"),
            "notify": .bool(true)]))
        let other = WidgetInstance(kind: .clock, config: WidgetConfig())
        let plan = GitHubWatch.plan([a, other, b])
        XCTAssertEqual(plan.repos, ["a/b", "c/d", "e/f"])
        XCTAssertEqual(plan.interval, 15)
        XCTAssertEqual(plan.notifyKeys, ["c/d", "e/f"])
        XCTAssertTrue(GitHubWatch.plan([other]).isEmpty)
    }

    func testTileTitleAndBadge() {
        XCTAssertEqual(GitHubWatch.tileTitle(["hanson-zz/docket-zh"]), "docket-zh")
        XCTAssertEqual(GitHubWatch.tileTitle(["a/b", "c/d", "e/f"]), "3 个项目")
        XCTAssertNil(GitHubWatch.badgeText(0))
        XCTAssertEqual(GitHubWatch.badgeText(7), "7")
        XCTAssertEqual(GitHubWatch.badgeText(120), "99+")
    }

    // MARK: Parsing

    private let issuesJSON = Data("""
    [
      {"id":101,"number":7,"title":"新功能：多仓库","user":{"login":"lin"},
       "created_at":"2026-10-14T03:00:00Z","html_url":"https://github.com/o/r/pull/7",
       "labels":[],"pull_request":{"url":"https://api.github.com/repos/o/r/pulls/7"}},
      {"id":100,"number":6,"title":"崩溃","user":{"login":"wang"},
       "created_at":"2026-10-13T03:00:00Z","html_url":"https://github.com/o/r/issues/6",
       "labels":[{"name":"bug"},{"name":"高优先级"}]},
      {"id":99,"number":5,"title":"旧议题","user":{"login":"zhao"},
       "created_at":"2026-09-01T00:00:00Z","html_url":"https://github.com/o/r/issues/5","labels":[]}
    ]
    """.utf8)

    private let commentsJSON = Data("""
    [
      {"id":555,"user":{"login":"chen"},"created_at":"2026-10-14T04:00:00Z",
       "html_url":"https://github.com/o/r/issues/6#issuecomment-555",
       "issue_url":"https://api.github.com/repos/o/r/issues/6","body":"我也遇到了"},
      {"id":554,"user":{"login":"li"},"created_at":"2026-10-12T04:00:00Z",
       "html_url":"https://github.com/o/r/issues/2#issuecomment-554",
       "issue_url":"https://api.github.com/repos/o/r/issues/2","body":"第一行\\n第二行"}
    ]
    """.utf8)

    private let releasesJSON = Data("""
    [
      {"id":3,"tag_name":"v0.7.0","name":"草稿","draft":true,"published_at":null,"assets":[]},
      {"id":2,"tag_name":"v0.6.0","name":"码头 0.6.0","draft":false,
       "published_at":"2026-10-10T08:00:00Z","html_url":"https://github.com/o/r/releases/tag/v0.6.0",
       "assets":[{"name":"Dockling-0.6.0.dmg","download_count":300},
                 {"name":"Dockling-0.6.0.zip","download_count":42}]},
      {"id":1,"tag_name":"v0.5.0","draft":false,"published_at":"2026-09-01T08:00:00Z",
       "assets":[{"name":"Dockling-0.5.0.dmg","download_count":1000}]}
    ]
    """.utf8)

    func testIssuesAndPullsAreToldApart() throws {
        let items = try XCTUnwrap(GitHubFeed.parseIssues(issuesJSON))
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].kind, .pull)
        XCTAssertEqual(items[0].number, 7)
        XCTAssertEqual(items[0].author, "lin")
        XCTAssertEqual(items[1].kind, .issue)
        XCTAssertEqual(items[1].labels, ["bug", "高优先级"])
        XCTAssertEqual(items[1].url?.absoluteString, "https://github.com/o/r/issues/6")
        XCTAssertNotEqual(items[0].id, items[1].id)
        XCTAssertNil(GitHubFeed.parseIssues(Data(#"{"message":"Not Found"}"#.utf8)))
    }

    func testCommentsBorrowTheirIssueTitle() throws {
        let comments = try XCTUnwrap(GitHubFeed.parseComments(commentsJSON, titles: [6: "崩溃"]))
        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].kind, .comment)
        XCTAssertEqual(comments[0].number, 6)
        XCTAssertEqual(comments[0].title, "#6 崩溃")
        XCTAssertEqual(comments[1].title, "#2 第一行", "unknown issue: the comment's first line")
        XCTAssertEqual(comments[0].id, "comment-555")
    }

    func testReleasesSumTheirDownloadsAndSkipDrafts() throws {
        let releases = try XCTUnwrap(GitHubFeed.parseReleases(releasesJSON))
        XCTAssertEqual(releases.map(\.tag), ["v0.6.0", "v0.5.0"])
        XCTAssertEqual(releases[0].downloads, 342)
        XCTAssertEqual(releases[0].assets.map(\.downloads), [300, 42])
        XCTAssertEqual(releases[0].publishedAt, date("2026-10-10T08:00:00Z"))
        XCTAssertEqual(releases[1].name, "v0.5.0", "a release without a name is called by its tag")
        XCTAssertEqual(GitHubFeed.totalDownloads(releases), 1342)
    }

    // MARK: What is new

    func testFeedbackSinceLastSeen() throws {
        let issues = try XCTUnwrap(GitHubFeed.parseIssues(issuesJSON))
        let comments = try XCTUnwrap(GitHubFeed.parseComments(commentsJSON))
        let releases = try XCTUnwrap(GitHubFeed.parseReleases(releasesJSON))
        let stats = GitHubStats(fullName: "o/r", stars: 130, forks: 10, watchers: 3, openIssuesAndPulls: 4)
        let seen = GitHubSeen(at: date("2026-10-12T12:00:00Z"), stars: 120, forks: 10, downloads: 1300)
        let items = GitHubFeed.merged([issues, comments])
        XCTAssertEqual(items.first?.id, "comment-555", "newest first")
        let feedback = GitHubFeed.feedback(items: items, stats: stats, releases: releases, seen: seen)
        XCTAssertEqual(feedback, GitHubFeedback(issues: 1, pulls: 1, comments: 1, stars: 10, forks: 0, downloads: 42))
        XCTAssertEqual(feedback.total, 55)
        XCTAssertEqual(feedback.written, 3)
        XCTAssertEqual(feedback.summary, "1 个议题 · 1 个拉取请求 · 1 条评论 · 10 个星标 · 42 次下载")
        XCTAssertTrue(GitHubFeed.isUnread(items[0], seen: seen))
        XCTAssertFalse(GitHubFeed.isUnread(items.last!, seen: seen))
    }

    func testNothingIsNewWithoutABaselineOrWhenCountersFall() {
        let stats = GitHubStats(fullName: "o/r", stars: 5, forks: 1, watchers: 0, openIssuesAndPulls: 0)
        XCTAssertEqual(GitHubFeed.feedback(items: [], stats: stats, releases: [], seen: nil).total, 0)
        let seen = GitHubSeen(at: .distantPast, stars: 9, forks: 3, downloads: 500)
        XCTAssertEqual(GitHubFeed.feedback(items: [], stats: stats, releases: [], seen: seen).total, 0)
        let unknownDownloads = GitHubSeen(at: .distantPast, stars: 5, forks: 1, downloads: nil)
        let release = GitHubRelease(id: 1, tag: "v1", name: "v1", publishedAt: nil, url: nil,
                                    assets: [.init(name: "a.dmg", downloads: 80)])
        XCTAssertEqual(GitHubFeed.feedback(items: [], stats: stats, releases: [release],
                                           seen: unknownDownloads).downloads, 0,
                       "downloads before the first reading are not new")
    }

    func testMarkingReadTakesTheCurrentCounters() {
        let now = date("2026-10-14T06:00:00Z")
        let stats = GitHubStats(fullName: "o/r", stars: 42, forks: 4, watchers: 1, openIssuesAndPulls: 0)
        let release = GitHubRelease(id: 1, tag: "v1", name: "v1", publishedAt: nil, url: nil,
                                    assets: [.init(name: "a.dmg", downloads: 80), .init(name: "b.zip", downloads: 20)])
        let seen = GitHubFeed.seen(at: now, stats: stats, releases: [release])
        XCTAssertEqual(seen, GitHubSeen(at: now, stars: 42, forks: 4, downloads: 100))
        let previous = GitHubSeen(at: .distantPast, stars: 1, forks: 2, downloads: 3)
        XCTAssertEqual(GitHubFeed.seen(at: now, stats: nil, releases: nil, previous: previous),
                       GitHubSeen(at: now, stars: 1, forks: 2, downloads: 3))
    }

    func testOnlyItemsPastTheWatermarkAreNotified() throws {
        let issues = try XCTUnwrap(GitHubFeed.parseIssues(issuesJSON))
        let seen = GitHubSeen(at: date("2026-10-01T00:00:00Z"))
        let fresh = GitHubFeed.toNotify(issues, after: date("2026-10-13T12:00:00Z"), seen: seen)
        XCTAssertEqual(fresh.map(\.number), [7])
        XCTAssertTrue(GitHubFeed.toNotify(issues, after: date("2026-10-13T12:00:00Z"),
                                          seen: GitHubSeen(at: date("2026-10-14T05:00:00Z"))).isEmpty,
                      "already marked read")
    }

    func testNotificationWording() throws {
        let issues = try XCTUnwrap(GitHubFeed.parseIssues(issuesJSON))
        let one = try XCTUnwrap(GitHubFeed.notificationText(repo: "o/r", items: [issues[1]]))
        XCTAssertEqual(one.title, "o/r · 新议题")
        XCTAssertEqual(one.body, "wang：崩溃")
        let many = try XCTUnwrap(GitHubFeed.notificationText(repo: "o/r", items: Array(issues.prefix(2))))
        XCTAssertEqual(many.title, "o/r 有 2 条新反馈")
        XCTAssertEqual(many.body, "新增 1 个议题、1 个拉取请求。最新：新功能：多仓库")
        XCTAssertNil(GitHubFeed.notificationText(repo: "o/r", items: []))
    }

    func testRelativeTimeInChinese() {
        let now = date("2026-10-14T12:00:00Z")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(-20), now: now), "刚刚")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(20), now: now), "刚刚")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(-5 * 60), now: now), "5 分钟前")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(-3 * 3600), now: now), "3 小时前")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(-30 * 3600), now: now), "昨天")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(-4 * 86_400), now: now), "4 天前")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(-65 * 86_400), now: now), "2 个月前")
        XCTAssertEqual(GitHubFeed.relativeText(now.addingTimeInterval(-400 * 86_400), now: now), "1 年前")
    }

    // MARK: Rate limits

    func testRateLimitRetryTimes() {
        let now = date("2026-10-14T12:00:00Z")
        XCTAssertEqual(GitHubRateLimit.retryAt(status: 403, headers: ["Retry-After": "120"], now: now),
                       now.addingTimeInterval(120))
        let reset = now.addingTimeInterval(900)
        XCTAssertEqual(GitHubRateLimit.retryAt(status: 403, headers: [
            "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(Int(reset.timeIntervalSince1970))"], now: now),
            reset)
        XCTAssertEqual(GitHubRateLimit.retryAt(status: 429, headers: [:], now: now), now.addingTimeInterval(60))
        XCTAssertNil(GitHubRateLimit.retryAt(status: 403, headers: ["X-RateLimit-Remaining": "12"], now: now),
                     "a refusal that is not about the rate")
        XCTAssertNil(GitHubRateLimit.retryAt(status: 404, headers: ["Retry-After": "5"], now: now))
    }

    func testRateLimitWording() {
        let now = date("2026-10-14T12:00:00Z")
        XCTAssertEqual(GitHubRateLimit.waitText(until: now.addingTimeInterval(14 * 60 + 5), now: now),
                       "请求太频繁，15 分钟后重试")
        XCTAssertEqual(GitHubRateLimit.waitText(until: now.addingTimeInterval(3), now: now),
                       "请求太频繁，1 分钟后重试")
    }

    // MARK: Display condition

    func testShownWhenThereIsNewFeedback() {
        var widget = WidgetInstance(kind: .github, config: WidgetConfig([
            "repos": .list([.string("a/b"), .string("C/D")])]))
        widget.config.set(WidgetVisibility.modeKey, .string("conditional"))
        XCTAssertTrue(WidgetVisibility.supportsCondition(.github))
        XCTAssertEqual(WidgetVisibility.conditionTitle(.github, config: widget.config), "有新反馈时显示")
        XCTAssertTrue(WidgetVisibility.isVisible(widget, WidgetConditions()), "unknown stays visible")
        XCTAssertTrue(WidgetVisibility.isVisible(widget, WidgetConditions(githubFeedback: ["x/y": 0])),
                      "none of its own read yet")
        XCTAssertFalse(WidgetVisibility.isVisible(widget, WidgetConditions(githubFeedback: ["a/b": 0, "c/d": 0])))
        XCTAssertTrue(WidgetVisibility.isVisible(widget, WidgetConditions(githubFeedback: ["a/b": 0, "c/d": 2])))
    }
}
