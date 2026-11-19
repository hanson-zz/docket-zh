import Foundation
import Observation
import Security
import Synchronization

/// Claude 图标里的额度水位用的数据：读本机 Claude 命令行已登录账号的凭据，
/// 问 Anthropic 的用量接口 5 小时和每周额度用了多少。
///
/// 只读本地凭据，不让用户填 API key：先读登录钥匙串里 Claude 命令行存的 generic password
/// （`ClaudeCredentials.keychainService`），没有再退回 `~/.claude/.credentials.json`。
/// 令牌只发给 api.anthropic.com。过期了不自己刷新、不写回钥匙串或文件，水位当未知，
/// 等 Claude 命令行下次用时自己续期。没有凭据时静默不画水位。
///
/// 钥匙串：码头读别的程序存的项，macOS 第一次会弹框问要不要允许。每次运行读内容最多一次
/// （`KeychainReadCache`）；用户点了拒绝这次运行不再读，免得反复弹。只有钥匙串项的修改时间
/// 变了（Claude 命令行续期写了新令牌）才再读一次内容；查修改时间只问属性，不弹框。
///
/// 只在 Claude 图标在扩展栏、开关开着时由图标上的水位视图拉起轮询，5 分钟一次；
/// 失败按 `CodexBackoff` 退避，尊重 Retry-After；走 Codex 详情面板里填的代理。
@MainActor @Observable
final class ClaudeUsageService {
    static let shared = ClaudeUsageService()

    private(set) var report: CodexUsageReport?

    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var blockedUntil: Date?
    @ObservationIgnored private var loading = false

    /// 和 Codex 一样五分钟一次：窗口按每小时几个百分点变化，接口不是我们的，别猛敲。
    static let interval: TimeInterval = 300

    private init() {}

    /// 距上次尝试不到五分钟、或失败后还在退避时什么都不做。
    func refresh() {
        let now = Date.now
        if let blockedUntil, blockedUntil > now { return }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.interval { return }
        guard !loading else { return }
        lastAttempt = now
        loading = true
        let session = CodexService.session()
        Task {
            let token = await Task.detached(priority: .utility) { ClaudeCredentialStore.token(now: .now) }.value
            let outcome: Outcome
            if let token {
                outcome = await Self.fetch(token: token, session: session)
            } else {
                // 没登录或令牌过期：不算失败、不退避，下个五分钟再看一眼（只读一次文件或钥匙串缓存）。
                outcome = .unknown
            }
            loading = false
            apply(outcome)
        }
    }

    private enum Outcome {
        case ok(CodexUsageReport)
        /// 没有可用的凭据：清掉水位。
        case unknown
        case failed(retryAfter: TimeInterval?)
    }

    private func apply(_ outcome: Outcome) {
        switch outcome {
        case .ok(let fresh):
            failures = 0
            blockedUntil = nil
            report = fresh
        case .unknown:
            failures = 0
            blockedUntil = nil
            report = nil
        case .failed(let retryAfter):
            // 旧读数留着，过期（30 分钟）后水位自己变未知。
            failures += 1
            blockedUntil = Date.now.addingTimeInterval(CodexBackoff.delay(failures: failures, retryAfter: retryAfter))
        }
    }

    nonisolated private static func fetch(token: String, session: URLSession) async -> Outcome {
        guard let url = URL(string: ClaudeUsageParser.endpoint) else { return .failed(retryAfter: nil) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(ClaudeUsageParser.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed(retryAfter: nil) }
        switch http.statusCode {
        case 200..<300:
            guard let report = try? ClaudeUsageParser.report(from: data) else { return .failed(retryAfter: nil) }
            return .ok(report)
        case 401, 403:
            // 令牌被服务器拒了（多半是刚过期）：退避，免得每五分钟白敲一次；旧读数 30 分钟后自己过期。
            return .failed(retryAfter: nil)
        case 429:
            return .failed(retryAfter: CodexBackoff.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: .now))
        default:
            return .failed(retryAfter: nil)
        }
    }
}

/// 读 Claude 命令行凭据：钥匙串优先，文件兜底。
enum ClaudeCredentialStore {
    private static let cacheName = "claude-credentials"
    private struct State {
        var reads = KeychainReadCache()
        /// 上次读内容时钥匙串项的修改时间。
        var modified: Date?
    }
    private static let state = Mutex(State())

    /// 能用的访问令牌；没有、过期或读不到时是 nil。
    static func token(now: Date) -> String? {
        if let text = keychainText(), let token = try? ClaudeCredentials.accessToken(from: text, now: now) {
            return token
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? ClaudeCredentials.accessToken(from: data, now: now)
    }

    private static var fileURL: URL {
        let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? ""
        if !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
                .appendingPathComponent(".credentials.json")
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(ClaudeCredentials.fileRelativePath)
    }

    private static func keychainText() -> String? {
        let modified = itemModified()
        return state.withLock { s in
            // 读到过内容、而钥匙串项后来被改过（续期写了新令牌）：重读一次。拒绝过的不重读。
            if case .some(.found) = s.reads.cached(cacheName), let modified, modified != s.modified {
                s.reads = KeychainReadCache()
            }
            let read = s.reads.read(cacheName) {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: ClaudeCredentials.keychainService,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return KeychainRead.classify(status: status, data: result as? Data)
            }
            if case .found = read { s.modified = modified }
            return read.value
        }
    }

    /// 钥匙串项的修改时间：只问属性、不读内容，不弹授权框。没有这一项时是 nil。
    private static func itemModified() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ClaudeCredentials.keychainService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attrs = result as? [String: Any] else { return nil }
        return attrs[kSecAttrModificationDate as String] as? Date
    }
}
