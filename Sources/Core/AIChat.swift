import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - AI 助手：打开方式

/// 每个服务在刘海对话里怎么用：网页（用自己的账号）、API（填密钥），
/// 或者跳转（打开 Mac App 或浏览器，就是 P0 的做法）。
public enum AIOpenMode: String, Codable, Sendable, CaseIterable {
    case web, api, jump

    public var title: String {
        switch self {
        case .web: "网页"
        case .api: "API"
        case .jump: "跳转"
        }
    }
}

/// 一个服务的对话接口：OpenAI 兼容的 base URL 和模型名。
public struct AIEndpoint: Codable, Hashable, Sendable {
    public var baseURL: String
    public var model: String

    public init(baseURL: String = "", model: String = "") {
        self.baseURL = baseURL
        self.model = model
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
    }
}

// MARK: - 刘海对话的设置

/// 刘海对话的设置，存在状态文件里（密钥不在这里，在钥匙串）。
///
/// 逐个字段宽松读取：旧的状态文件没有这一项时就是默认值，以后多了新键
/// 也照常读取。打开方式里认不出来的值跳过，回到那个服务的默认方式。
public struct AINotchSettings: Codable, Hashable, Sendable {
    /// 在刘海显示 AI 助手。默认开。
    public var enabled: Bool = true
    /// 只在主屏（带菜单栏的那块）显示。默认关，每块屏幕都有入口。
    public var mainScreenOnly: Bool = false
    /// 展开对话的全局快捷键。默认不设，由用户在设置里录制。
    public var hotKey: KeyCombo?
    /// 每个服务的打开方式，按服务 id。没有的用 `AIOpenModes.defaultMode`。
    public var modes: [String: AIOpenMode] = [:]
    /// 用户改过的接口地址和模型名，按服务 id。空字符串表示用默认值。
    public var endpoints: [String: AIEndpoint] = [:]
    /// 上次在刘海里用的服务。
    public var lastServiceID: String?
    /// 用户自己存的常用提示词，按显示顺序。见 `AIPrompts`。
    public var prompts: [AIPrompt] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, mainScreenOnly, hotKey, modes, endpoints, lastServiceID, prompts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        mainScreenOnly = (try? c.decodeIfPresent(Bool.self, forKey: .mainScreenOnly)) ?? false
        hotKey = try? c.decodeIfPresent(KeyCombo.self, forKey: .hotKey)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .modes)) ?? [:]
        modes = raw.compactMapValues(AIOpenMode.init(rawValue:))
        endpoints = (try? c.decodeIfPresent([String: AIEndpoint].self, forKey: .endpoints)) ?? [:]
        lastServiceID = try? c.decodeIfPresent(String.self, forKey: .lastServiceID)
        prompts = AIPrompts.sanitized((try? c.decodeIfPresent([AIPrompt].self, forKey: .prompts)) ?? [])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(mainScreenOnly, forKey: .mainScreenOnly)
        try c.encodeIfPresent(hotKey, forKey: .hotKey)
        try c.encode(modes.mapValues(\.rawValue), forKey: .modes)
        try c.encode(endpoints, forKey: .endpoints)
        try c.encodeIfPresent(lastServiceID, forKey: .lastServiceID)
        try c.encode(prompts, forKey: .prompts)
    }

    /// 只有带 Control、Option 或 Command 的组合才注册，Shift 单独不算。
    public var usableHotKey: KeyCombo? {
        guard let hotKey, hotKey.hasRequiredModifier else { return nil }
        return hotKey
    }
}

// MARK: - 接口的默认值

/// 内置服务的默认接口地址和模型名，以及怎么拼出 /chat/completions。
///
/// 地址都是各家文档里写的 OpenAI 兼容地址。豆包（火山方舟）的模型名要填
/// 用户自己创建的接入点 ID，所以没有默认模型。没写在这里的服务（元宝、
/// 文心、Gemini、Perplexity、Grok 和自定义服务）由用户自己填地址和模型。
public enum AIEndpoints {
    public static let defaults: [String: AIEndpoint] = [
        "deepseek": AIEndpoint(baseURL: "https://api.deepseek.com", model: "deepseek-chat"),
        "kimi": AIEndpoint(baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k"),
        "tongyi": AIEndpoint(baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus"),
        "zhipu": AIEndpoint(baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash"),
        "doubao": AIEndpoint(baseURL: "https://ark.cn-beijing.volces.com/api/v3", model: ""),
        "chatgpt": AIEndpoint(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
    ]

    /// 豆包的模型名是接入点 ID，只能用户填。
    public static func requiresModel(_ serviceID: String) -> Bool { serviceID == "doubao" }

    /// 用户改过的优先，空的字段用默认值。地址和模型都有才算能用。
    public static func resolved(_ serviceID: String, override: AIEndpoint?) -> AIEndpoint? {
        let fallback = defaults[serviceID] ?? AIEndpoint()
        let base = trimmed(override?.baseURL).isEmpty ? fallback.baseURL : trimmed(override?.baseURL)
        let model = trimmed(override?.model).isEmpty ? fallback.model : trimmed(override?.model)
        guard !base.isEmpty, !model.isEmpty, chatURL(base: base) != nil else { return nil }
        return AIEndpoint(baseURL: base, model: model)
    }

    /// `https://api.deepseek.com` -> `https://api.deepseek.com/chat/completions`。
    /// 末尾的斜杠去掉；已经写到 /chat/completions 的照用。只收 https，
    /// 本机调试的 http://localhost 和 127.0.0.1 例外。
    public static func chatURL(base: String) -> URL? {
        var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              let host = url.host(), !host.isEmpty,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.user == nil else { return nil }
        let local = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && local) else { return nil }
        guard host.contains(".") || local else { return nil }
        if text.lowercased().hasSuffix("/chat/completions") { return url }
        return URL(string: text + "/chat/completions")
    }

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 打开方式的取舍

public enum AIOpenModes {
    /// 内置的十一家默认都是网页；自定义服务默认跳转（P0 的做法）。
    public static func defaultMode(_ service: AIService) -> AIOpenMode {
        if service.isCustom { return .jump }
        return service.homeURL == nil ? .jump : .web
    }

    /// 实际用哪种。选了 API 但没填密钥（或者地址、模型不全）时退回网页，
    /// 没有网页地址的再退回跳转；网页没有地址时也退回跳转。
    public static func mode(for service: AIService, settings: AINotchSettings, hasKey: Bool) -> AIOpenMode {
        let saved = settings.modes[service.id] ?? defaultMode(service)
        switch saved {
        case .api:
            if hasKey, AIEndpoints.resolved(service.id, override: settings.endpoints[service.id]) != nil {
                return .api
            }
            return service.homeURL == nil ? .jump : .web
        case .web:
            return service.homeURL == nil ? .jump : .web
        case .jump:
            return .jump
        }
    }

    /// 设置表里哪几个能选：网页要有网址，API 要有密钥和完整的接口。跳转总能选。
    public static func available(for service: AIService, settings: AINotchSettings, hasKey: Bool) -> Set<AIOpenMode> {
        var modes: Set<AIOpenMode> = [.jump]
        if service.homeURL != nil { modes.insert(.web) }
        if hasKey, AIEndpoints.resolved(service.id, override: settings.endpoints[service.id]) != nil {
            modes.insert(.api)
        }
        return modes
    }

    /// 面板顶部的一行字：“API · deepseek-chat”“网页 · 你的账号”“跳转 · 打开 App 或浏览器”。
    public static func label(_ mode: AIOpenMode, model: String? = nil) -> String {
        switch mode {
        case .api:
            let name = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "API" : "API · \(name)"
        case .web: return "网页 · 你的账号"
        case .jump: return "跳转 · 打开 App 或浏览器"
        }
    }
}

// MARK: - 对话

public struct AIChatMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public enum Status: Equatable, Sendable, Codable {
        case done
        case streaming
        /// 用户点了停止，已经流出来的字留着。
        case stopped
        /// 出错了，附中文提示。
        case failed(String)
    }

    public var id: UUID
    public var role: Role
    public var text: String
    public var status: Status

    public init(id: UUID = UUID(), role: Role, text: String, status: Status = .done) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
    }

    public var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }
}

/// 发给接口的上下文。
public enum AIChatContext {
    /// 最多带几条（用户和回答各算一条）。
    public static let limit = 20

    /// 去掉出错的、空白的回答，只留最近 `limit` 条，开头的回答也去掉，
    /// 让第一条总是用户的问题。
    public static func history(_ messages: [AIChatMessage], limit: Int = limit) -> [AIChatMessage] {
        let usable = messages.filter { message in
            if message.role == .assistant {
                return !message.isFailed && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var recent = Array(usable.suffix(max(0, limit)))
        while let first = recent.first, first.role == .assistant { recent.removeFirst() }
        return recent
    }
}

// MARK: - 请求

public enum AIChatRequest {
    public static let timeout: TimeInterval = 60

    struct Body: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
        }
        var model: String
        var messages: [Message]
        var stream: Bool
    }

    /// `{"model": …, "messages": [{"role": "user", "content": …}], "stream": true}`。
    public static func body(model: String, history: [AIChatMessage], stream: Bool = true) -> Data {
        let body = Body(model: model,
                        messages: history.map { .init(role: $0.role.rawValue, content: $0.text) },
                        stream: stream)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(body)) ?? Data("{}".utf8)
    }

    /// 整个请求。密钥只放在 Authorization 头里，不进日志也不进网址。
    public static func urlRequest(endpoint: AIEndpoint, key: String, history: [AIChatMessage]) -> URLRequest? {
        guard let url = AIEndpoints.chatURL(base: endpoint.baseURL) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key.trimmingCharacters(in: .whitespacesAndNewlines))",
                         forHTTPHeaderField: "Authorization")
        request.httpBody = body(model: endpoint.model, history: history)
        return request
    }
}

// MARK: - 流式回答（SSE）

public enum AISSEEvent: Equatable, Sendable {
    /// 新流出来的一段字。
    case delta(String)
    /// `data: [DONE]`。
    case done
    /// 流里夹着的错误对象。
    case failure(String)
}

/// 一行一行喂进来的 SSE 解析器。
///
/// 每个 `data:` 行一般就是一整段 JSON，直接解析；拆成几行的 JSON 先攒着，
/// 到空行再拼起来解析。`:` 开头的注释行（保活）和 `event:`、`id:` 行忽略。
/// 回车换行和只有换行都认。`feed(chunk:)` 可以喂任意切开的字节块。
public struct AISSEParser: Sendable {
    private var pending: [String] = []
    private var buffer = ""

    public init() {}

    /// 喂一段任意切开的文字，返回其中完整的行解析出的事件。
    public mutating func feed(chunk: String) -> [AISSEEvent] {
        // 按 Unicode 标量找换行：回车换行在 String 里是一个字符，按字符找
        // "\n" 会找不到。
        buffer.unicodeScalars.append(contentsOf: chunk.unicodeScalars)
        var events: [AISSEEvent] = []
        while let newline = buffer.unicodeScalars.firstIndex(of: "\n") {
            let line = String(String.UnicodeScalarView(buffer.unicodeScalars[..<newline]))
            buffer.unicodeScalars.removeSubrange(...newline)
            events += feed(line: line)
        }
        return events
    }

    /// 喂一整行（不带换行符）。
    public mutating func feed(line raw: String) -> [AISSEEvent] {
        var line = raw
        while line.unicodeScalars.last == "\r" { line.unicodeScalars.removeLast() }
        if line.isEmpty { return flush() }
        if line.hasPrefix(":") { return [] }
        guard line.hasPrefix("data:") else { return [] }
        var payload = String(line.dropFirst(5))
        if payload.hasPrefix(" ") { payload.removeFirst() }
        if pending.isEmpty {
            if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" { return [.done] }
            if let events = Self.parse(payload) { return events }
        }
        pending.append(payload)
        if let events = Self.parse(pending.joined(separator: "\n")) {
            pending.removeAll()
            return events
        }
        return []
    }

    /// 流结束时把剩下的交出来。
    public mutating func finish() -> [AISSEEvent] {
        var events: [AISSEEvent] = []
        if !buffer.isEmpty {
            let line = buffer
            buffer = ""
            events += feed(line: line)
        }
        return events + flush()
    }

    private mutating func flush() -> [AISSEEvent] {
        guard !pending.isEmpty else { return [] }
        let joined = pending.joined(separator: "\n")
        pending.removeAll()
        if joined.trimmingCharacters(in: .whitespaces) == "[DONE]" { return [.done] }
        return Self.parse(joined) ?? []
    }

    /// 一段 JSON：`choices[0].delta.content`，或者 `error.message`。读不出
    /// JSON 时为 nil（可能还没收全）。没有内容的（比如只带 role 的第一段、
    /// 只有 finish_reason 的最后一段）返回空数组。
    static func parse(_ payload: String) -> [AISSEEvent]? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = AIChatFailure.errorMessage(in: object) { return [.failure(message)] }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return [] }
        if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String, !content.isEmpty {
            return [.delta(content)]
        }
        // 不支持流式、把整段回答一次给出来的接口。
        if let message = first["message"] as? [String: Any], let content = message["content"] as? String,
           !content.isEmpty {
            return [.delta(content)]
        }
        return []
    }

    /// 不是 SSE、直接回了一整段 JSON 时，从里面取回答。
    public static func completeReply(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]], let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String, !content.isEmpty else { return nil }
        return content
    }
}

// MARK: - 出错

/// 对话出错的种类和给用户看的中文提示。
public enum AIChatFailure: Error, Equatable, Sendable {
    case http(status: Int, message: String?)
    case timeout
    case offline
    case cannotConnect
    case secureConnection
    case missingKey
    case missingEndpoint
    case badURL
    case emptyReply
    case stream(String)
    case other(String)

    public var message: String {
        switch self {
        case .http(let status, let server):
            let detail = Self.short(server).map { "：\($0)" } ?? ""
            switch status {
            case 401: return "密钥不对或已失效（401），请到设置里重新填写。"
            case 402: return "账户余额不足（402），充值后再试。"
            case 403: return "没有权限使用这个模型（403），检查密钥的权限或账户状态\(detail)。"
            case 404: return "接口地址或模型名不对（404），检查设置里的地址和模型。"
            case 408: return "等了太久没有回应（408），稍后重试。"
            case 429: return "请求太频繁或额度用完了（429），稍等一会儿再试。"
            case 400, 422: return "请求被拒绝（\(status)）\(detail)。"
            case 500...599: return "服务暂时出错（\(status)），稍后重试。"
            default: return "请求失败（\(status)）\(detail)。"
            }
        case .timeout: return "等了 60 秒没有回应，已停止。可以点“重试”。"
        case .offline: return "没有连上网络，检查网络后重试。"
        case .cannotConnect: return "连不上服务器，检查接口地址或网络。"
        case .secureConnection: return "安全连接失败，检查接口地址或网络代理。"
        case .missingKey: return "还没有填这个服务的密钥，到“设置 ▸ 通用 ▸ AI 助手”里填写。"
        case .missingEndpoint: return "接口地址或模型名没填全（豆包要填接入点 ID 作为模型名）。"
        case .badURL: return "接口地址不对，要以 https:// 开头。"
        case .emptyReply: return "服务没有返回内容，可以点“重试”。"
        case .stream(let text): return "服务返回了错误：\(Self.short(text) ?? "未知错误")"
        case .other(let text): return "出错了：\(Self.short(text) ?? "未知错误")"
        }
    }

    /// URLError 的代码换成种类。取消（用户停止）为 nil。
    public static func network(code: Int) -> AIChatFailure? {
        switch code {
        case URLError.Code.cancelled.rawValue: return nil
        case URLError.Code.timedOut.rawValue: return .timeout
        case URLError.Code.notConnectedToInternet.rawValue, URLError.Code.networkConnectionLost.rawValue,
             URLError.Code.dataNotAllowed.rawValue, URLError.Code.internationalRoamingOff.rawValue:
            return .offline
        case URLError.Code.cannotFindHost.rawValue, URLError.Code.cannotConnectToHost.rawValue,
             URLError.Code.dnsLookupFailed.rawValue:
            return .cannotConnect
        case URLError.Code.secureConnectionFailed.rawValue, URLError.Code.serverCertificateUntrusted.rawValue,
             URLError.Code.serverCertificateHasBadDate.rawValue, URLError.Code.serverCertificateHasUnknownRoot.rawValue,
             URLError.Code.serverCertificateNotYetValid.rawValue, URLError.Code.clientCertificateRejected.rawValue,
             URLError.Code.appTransportSecurityRequiresSecureConnection.rawValue:
            return .secureConnection
        case URLError.Code.badURL.rawValue, URLError.Code.unsupportedURL.rawValue: return .badURL
        default: return .other("网络错误 \(code)")
        }
    }

    /// 出错的 HTTP 回应：状态码加上服务端说的原因（如果读得出）。
    public static func http(status: Int, body: Data) -> AIChatFailure {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let message = object.flatMap(errorMessage(in:))
        return .http(status: status, message: message)
    }

    /// `{"error": {"message": …}}`、`{"error": "…"}` 或 `{"message": …}`。
    static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String,
           !message.isEmpty { return message }
        if let error = object["error"] as? String, !error.isEmpty { return error }
        if object["choices"] == nil, let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }

    /// 服务端的原话最多留 160 个字，免得把整页错误塞进面板。
    static func short(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.count > 160 ? String(text.prefix(160)) + "…" : text
    }
}

// MARK: - 回答的排版

/// 把回答切成普通段落和代码块。代码块等宽显示，段落交给
/// `AttributedString(markdown:)` 的 inlineOnlyPreservingWhitespace 处理
/// 粗体、斜体、行内代码和链接，换行原样保留。回答还在流的时候，没收尾的
/// ``` 也当代码块。
public enum AIMarkdown {
    public enum Block: Equatable, Sendable {
        case text(String)
        case code(language: String, body: String)
    }

    public static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String] = []
        var language = ""
        var inCode = false

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(joined.trimmingCharacters(in: .newlines)))
            }
            paragraph.removeAll()
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: language, body: code.joined(separator: "\n")))
                    code.removeAll()
                    language = ""
                    inCode = false
                } else {
                    flushParagraph()
                    language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                continue
            }
            if inCode { code.append(line) } else { paragraph.append(line) }
        }
        if inCode {
            blocks.append(.code(language: language, body: code.joined(separator: "\n")))
        } else {
            flushParagraph()
        }
        return blocks
    }
}

// MARK: - 网页模式

public enum AIWeb {
    /// Safari 的桌面 UA。有的服务看到 WKWebView 默认的 UA（没有 Version/
    /// Safari 字样）会提示“浏览器不受支持”。
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    public static let googleWarning =
        "谷歌不允许在内嵌网页登录，请改用邮箱或 Apple 登录，或用浏览器打开。"

    /// 是不是谷歌账号的登录页（accounts.google.com 下的任何页面）。
    public static func isGoogleSignIn(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "accounts.google.com" || host.hasSuffix(".accounts.google.com")
    }

    public enum NewWindowTarget: Equatable, Sendable { case sameView, browser, ignore }

    /// 网页要开新窗口（target=_blank 或 window.open）时：同一家网站和常见
    /// 的登录页在当前视图里打开，别的网站交给浏览器；不是 http(s) 的不管。
    public static func newWindowTarget(_ url: URL?, home: URL?) -> NewWindowTarget {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased() else { return .ignore }
        if let homeHost = home?.host()?.lowercased(), siteKey(host) == siteKey(homeHost) { return .sameView }
        let login = ["accounts.", "auth.", "login.", "signin.", "sso.", "passport.", "appleid.apple.com"]
        if login.contains(where: { host.hasPrefix($0) || host == $0 }) { return .sameView }
        return .browser
    }

    /// 粗略的“同一家网站”：取域名最后两段（.com.cn 这种取三段）。
    static func siteKey(_ host: String) -> String {
        let parts = host.split(separator: ".")
        guard parts.count > 2 else { return host }
        let secondLevel = ["com", "net", "org", "gov", "edu", "co"]
        let take = secondLevel.contains(String(parts[parts.count - 2])) && parts.last!.count == 2 ? 3 : 2
        return parts.suffix(take).joined(separator: ".")
    }

    /// 网页底部的一行小字：“网页内容由 chatgpt.com 提供”。
    public static func credit(_ home: URL?) -> String? {
        guard var host = home?.host()?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return "网页内容由 \(host) 提供"
    }
}

// MARK: - 快捷键

public enum AIHotKeyAdvice {
    /// 常见的冲突。录到这些组合时在设置里提醒一句，不拒收。
    public static func warning(for combo: KeyCombo?) -> String? {
        guard let combo, combo.keyCode == 49 else { return nil }
        let m = combo.modifiers
        typealias M = KeyCombo.Modifier
        if m == M.option { return "Option+空格 是 ChatGPT 桌面版的默认快捷键，建议换一个，免得两边抢。" }
        if m == M.command { return "Command+空格 是聚焦搜索，建议换一个。" }
        if m == M.control || m == M.control | M.shift { return "Control+空格 常用来切换输入法，建议换一个。" }
        if m == M.command | M.option { return "Command+Option+空格 是访达搜索，建议换一个。" }
        return nil
    }
}

// MARK: - 钥匙串

public enum AIKeyNaming {
    /// 钥匙串里的 service：bundle id 加服务 id，比如 `com.docket-zh.app.ai.deepseek`。
    public static func service(bundleID: String, serviceID: String) -> String {
        "\(bundleID).ai.\(serviceID)"
    }

    public static let account = "api-key"
}
