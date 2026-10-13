import Foundation

// The pure half of reading Codex's limits through its own app-server.
//
// `codex app-server` is the interface the Codex IDE extension and desktop app
// use. It speaks JSON-RPC over stdio, one JSON object per line, without the
// "jsonrpc": "2.0" field. A client sends `initialize` (with `clientInfo`),
// then the `initialized` notification, then any request; here only
// `account/rateLimits/read`. Shapes taken from the protocol crate in
// github.com/openai/codex:
//   codex-rs/app-server-protocol/src/rpc.rs            (message envelope)
//   codex-rs/app-server-protocol/src/protocol/v1.rs    (InitializeParams, ClientInfo)
//   codex-rs/app-server-protocol/src/protocol/common.rs (method names)
//   codex-rs/app-server-protocol/src/protocol/v2/account.rs (GetAccountRateLimitsResponse)
//
// Nothing here starts a process; CodexService does that. Everything here runs
// in tests.

/// Where a reading came from, so the panel can say.
public enum CodexUsageSource: String, Codable, Equatable, Sendable {
    /// `codex app-server`, `account/rateLimits/read`.
    case appServer
    /// chatgpt.com/backend-api/wham with the sign-in in auth.json.
    case web

    public var title: String {
        switch self {
        case .appServer: "官方接口"
        case .web: "备用接口"
        }
    }
}

public enum CodexAppServer {
    public static let initializeID = 1
    public static let rateLimitsID = 2

    /// One message the server wrote.
    public enum Message: Equatable, Sendable {
        /// A reply to one of our requests; `result` re-encoded as JSON.
        case response(id: Int, result: Data)
        case error(id: Int, code: Int?, message: String)
        /// A notification or a request from the server; ignored here.
        case other
    }

    public enum Failure: Error, Equatable, Sendable {
        case noBinary
        case launchFailed
        case timedOut
        case exited
        case rpc(String)
        case unreadable
    }

    // MARK: Building

    /// `{"id":1,"method":"initialize","params":{"clientInfo":{...}}}` plus a newline.
    public static func initializeRequest(version: String, id: Int = initializeID) -> Data {
        line([
            "id": id,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "docket", "title": "码头", "version": version],
            ],
        ])
    }

    /// The notification that completes the handshake. It has no params.
    public static func initializedNotification() -> Data {
        line(["method": "initialized"])
    }

    /// `account/rateLimits/read` without params, as the protocol's own test
    /// sends it, so older servers that predate its optional params accept it.
    public static func rateLimitsRequest(id: Int = rateLimitsID) -> Data {
        line(["id": id, "method": "account/rateLimits/read"])
    }

    private static func line(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }

    // MARK: Parsing

    /// Reads one line of the server's stdout. A line that is not JSON (a log
    /// line, say) is `.other`, never a failure.
    public static func parse(line: Data) -> Message {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return .other }
        // A request from the server carries both a method and an id; it is
        // not a reply to us.
        if root["method"] != nil { return .other }
        guard let id = CodexUsageParser.number(root["id"]).map({ Int($0) }) else { return .other }
        if let error = root["error"] as? [String: Any] {
            return .error(id: id, code: CodexUsageParser.number(error["code"]).map { Int($0) },
                          message: (error["message"] as? String) ?? "未知错误")
        }
        if let result = root["result"],
           let data = try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]) {
            return .response(id: id, result: data)
        }
        return .other
    }

    /// Splits a growing stdout buffer into complete lines, leaving any
    /// unfinished tail in the buffer.
    public static func takeLines(_ buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer = Data(buffer[buffer.index(after: newline)...])
        }
        return lines
    }

    /// Maps a `GetAccountRateLimitsResponse` into the widget's report.
    ///
    /// `rateLimits` is the single-bucket view (the `codex` limit);
    /// `rateLimitsByLimitId` holds the others, such as a Spark model's.
    /// Window lengths arrive in minutes and resets in Unix seconds.
    public static func report(fromResult data: Data, now: Date = .now,
                              includeExtras: Bool = true) throws -> CodexUsageReport {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.unreadable
        }
        let main = root["rateLimits"] as? [String: Any]
        var windows: [CodexLimitWindow] = []
        for (id, key) in [("primary", "primary"), ("secondary", "secondary")] {
            if let w = main?[key] as? [String: Any], let item = window(id: id, group: nil, w, fallback: id) {
                windows.append(item)
            }
        }
        if includeExtras, let buckets = root["rateLimitsByLimitId"] as? [String: Any] {
            let mainID = (main?["limitId"] as? String) ?? "codex"
            for key in buckets.keys.sorted() where key != mainID && key != "codex" {
                guard let bucket = buckets[key] as? [String: Any] else { continue }
                let name = (bucket["limitName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
                let group = name.range(of: "spark", options: .caseInsensitive) != nil ? "Spark" : name
                for (suffix, wkey) in [("", "primary"), ("-secondary", "secondary")] {
                    let id = "\(key)\(suffix)"
                    guard !windows.contains(where: { $0.id == id }),
                          let w = bucket[wkey] as? [String: Any],
                          let item = window(id: id, group: group, w, fallback: wkey) else { continue }
                    windows.append(item)
                }
            }
        }
        // A seat with no rolling windows and only a spend cap.
        if windows.isEmpty, let cap = main?["individualLimit"] as? [String: Any],
           let remaining = CodexUsageParser.number(cap["remainingPercent"]) {
            windows.append(CodexLimitWindow(id: "credits", label: "额度上限", usedFraction: 1 - remaining / 100,
                                            resetsAt: CodexUsageParser.number(cap["resetsAt"]).map { Date(timeIntervalSince1970: $0) }))
        }
        guard !windows.isEmpty else { throw CodexUsageError.nothingMetered }
        let plan = (main?["planType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let resets = ((root["rateLimitResetCredits"] as? [String: Any])?["availableCount"]).flatMap { CodexUsageParser.number($0) }.map { Int($0) }
        return CodexUsageReport(windows: windows, plan: plan, resetCredits: resets,
                                fetchedAt: now, source: .appServer)
    }

    private static func window(id: String, group: String?, _ w: [String: Any], fallback: String) -> CodexLimitWindow? {
        guard let percent = CodexUsageParser.number(w["usedPercent"]) else { return nil }
        let seconds = CodexUsageParser.number(w["windowDurationMins"]).map { $0 * 60 }
        let resets = CodexUsageParser.number(w["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return CodexLimitWindow(id: id, group: group,
                                label: CodexUsageParser.label(windowSeconds: seconds ?? 0, fallback: fallback),
                                usedFraction: percent / 100, resetsAt: resets, duration: seconds)
    }

    // MARK: Finding the binary

    /// Places a `codex` executable is looked for, in order: the user's own
    /// override, every folder on the login shell's PATH, the usual package
    /// manager folders, then the copy bundled in the desktop app (which moved
    /// from Codex.app to ChatGPT.app).
    public static func candidatePaths(home: String, shellPath: String?, override: String? = nil) -> [String] {
        var paths: [String] = []
        if let override, !override.isEmpty { paths.append((override as NSString).expandingTildeInPath) }
        for dir in (shellPath ?? "").split(separator: ":") where !dir.isEmpty {
            paths.append("\(dir)/codex")
        }
        paths += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.volta/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
        ]
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// The PATH handed to the child. An npm install of codex is a script run
    /// by `env node`, and an app opened from Finder has a PATH without node,
    /// so the login shell's PATH, the binary's own folder and Homebrew's are
    /// all added.
    public static func childPath(binary: String, shellPath: String?, inherited: String?) -> String {
        var dirs: [String] = [(binary as NSString).deletingLastPathComponent]
        for source in [shellPath, inherited] {
            dirs += (source ?? "").split(separator: ":").map(String.init)
        }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    /// Proxy variables for the child, from the proxy typed in the panel, so
    /// the app-server reaches chatgpt.com the same way the fallback does.
    public static func proxyEnvironment(_ proxy: CodexProxy?) -> [String: String] {
        guard let proxy else { return [:] }
        let url = proxy.kind == .socks ? "socks5h://\(proxy.host):\(proxy.port)" : "http://\(proxy.host):\(proxy.port)"
        var env = ["ALL_PROXY": url, "all_proxy": url]
        if proxy.kind == .http {
            for key in ["HTTPS_PROXY", "HTTP_PROXY", "https_proxy", "http_proxy"] { env[key] = url }
        }
        return env
    }
}
