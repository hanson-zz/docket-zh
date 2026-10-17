import AppKit
import Observation

/// Notices when a newer release exists, and says so.
///
/// Docket is downloaded once and then never hears about a release again, so
/// somebody on the first version stays there until they happen to revisit the
/// repository.
///
/// It only ever *tells*. Installing an update over the running app needs a
/// stable signing identity, because an installer has to establish that the
/// replacement is the same app from the same author, and ad-hoc signing has no
/// stable identity: every build has a different cdhash. That is the same root
/// cause as granted permissions lapsing between releases. So this opens the
/// release page and lets the user do the drag, which is honest about what it
/// can promise.
@MainActor @Observable
public final class UpdateService {
    public static let shared = UpdateService()

    /// The newest release, once one has been seen that is newer than this
    /// build. Nil while up to date, which is most of the time.
    public private(set) var available: Release?
    public private(set) var lastChecked: Date?
    public private(set) var isChecking = false

    public struct Release: Hashable, Sendable {
        public let version: Version
        public let page: URL
        public let published: Date?
    }

    /// The running build, from the bundle rather than from anything stored:
    /// the number in project.yml is only a default for local builds, and CI
    /// stamps the real one from the tag.
    public var current: Version? {
        Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    /// 中文本地化分支：检查本分支自己的 Releases，而不是上游英文版的 Releases，
    /// 否则会提示用户“更新”到英文版。
    ///
    /// 仓库名在构建时写进 Info.plist（见 UpdateFeed），默认仍是
    /// hanson-zz/docket-zh；要换成单独的发布仓库，改 release.yml 用的仓库变量
    /// UPDATE_FEED_REPOSITORY 再打包即可，不用改这里。
    nonisolated static let releasesRepository = UpdateFeed.repository(
        from: Bundle.main.object(forInfoDictionaryKey: UpdateFeed.infoKey))

    private let endpoint = URL(string:
        "https://api.github.com/repos/\(UpdateService.releasesRepository)/releases/latest")!
    /// Saves bandwidth on a repeat check. Not quota: a 304 still counts
    /// against GitHub's 60 an hour, measured, whatever the docs suggest.
    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var timer: Task<Void, Never>?

    private init() {}

    // MARK: Schedule

    /// Daily, and once shortly after launch.
    ///
    /// Not *at* launch: starting up is when the machine is busiest and the
    /// user is least interested, and a release that appeared overnight keeps
    /// for another minute.
    public func start() {
        guard timer == nil else { return }
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(90))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(60 * 60 * 24))
            }
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: Checking

    public func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Identifies the app rather than looking like an anonymous scraper,
        // the same courtesy WeatherService already extends to MET Norway.
        request.setValue("Dockling/\(current?.description ?? "dev") (macOS; https://github.com/\(UpdateService.releasesRepository))",
                         forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return }

        lastChecked = .now
        if let tag = http.value(forHTTPHeaderField: "ETag") { etag = tag }

        // Nothing new since last time, so the cached answer still stands.
        if http.statusCode == 304 { return }
        // Rate limited, offline, or a repository that has moved. Staying quiet
        // is right: an update check failing is not the user's problem to see.
        guard http.statusCode == 200 else { return }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = payload["tag_name"] as? String,
              let newest = Version(tag),
              let link = payload["html_url"] as? String,
              let page = URL(string: link)
        else { return }

        // A prerelease is not something to nudge anyone toward.
        if payload["prerelease"] as? Bool == true { return }

        // Newer than what is running, and only then. Building from source
        // produces a version ahead of the latest release, and telling that
        // person to downgrade would be absurd.
        guard let current, newest > current else {
            available = nil
            return
        }

        let published = (payload["published_at"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        available = Release(version: newest, page: page, published: published)
    }

    public func openReleasePage() {
        guard let available else { return }
        NSWorkspace.shared.open(available.page)
    }
}
