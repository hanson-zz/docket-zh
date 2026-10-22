import Foundation

// MARK: - AI 助手：API 的设置流程

/// 设置 ▸ AI 里「网页 / API / 跳转」三选一中 API 那一段的纯逻辑。
///
/// 以前 API 段要先展开、填好密钥才点得动，用户以为 API 没做。现在 API 段
/// 总能点：已经齐了就直接改用 API；还差东西时把选择先记下（存成 `.api`，
/// `AIOpenModes.mode` 在没齐时自动退回网页），展开这一行并把焦点放到缺的
/// 那一格，旁边写「填入密钥后生效」。密钥存好后发一个最小请求校验，通过
/// 就切到 API；密钥删掉时回到网页。
public enum AIAPISetup {
    /// 展开区里的三格。
    public enum Field: String, Hashable, Sendable, CaseIterable {
        case key, baseURL, model
    }

    /// API 现在能不能用；不能用时差的是哪一格。
    public enum Readiness: Equatable, Sendable {
        case ready
        case missing(Field)
        /// 地址填了但不是 https（本机调试的 http://localhost 例外）。
        case badURL
    }

    /// 先看密钥（用户点 API 最先要填的就是它），再看地址，最后看模型。
    public static func readiness(serviceID: String, override: AIEndpoint?, hasKey: Bool) -> Readiness {
        if !hasKey { return .missing(.key) }
        let fallback = AIEndpoints.defaults[serviceID] ?? AIEndpoint()
        let typedBase = trimmed(override?.baseURL)
        let base = typedBase.isEmpty ? fallback.baseURL : typedBase
        if base.isEmpty { return .missing(.baseURL) }
        if AIEndpoints.chatURL(base: base) == nil { return .badURL }
        let typedModel = trimmed(override?.model)
        let model = typedModel.isEmpty ? fallback.model : typedModel
        if model.isEmpty { return .missing(.model) }
        return .ready
    }

    /// 点 API 段的结果。
    public enum Tap: Equatable, Sendable {
        /// 都齐了，直接改用 API。
        case select
        /// 记下选择，展开这一行，焦点放到这一格。
        case expand(focus: Field)
    }

    public static func tapAPI(_ readiness: Readiness) -> Tap {
        switch readiness {
        case .ready: .select
        case .missing(let field): .expand(focus: field)
        case .badURL: .expand(focus: .baseURL)
        }
    }

    /// 选了 API 但还没生效时，API 段旁边那句话。生效了为 nil。
    public static func pendingHint(_ readiness: Readiness, serviceID: String) -> String? {
        switch readiness {
        case .ready: nil
        case .missing(.key): tr("填入密钥后生效")
        case .missing(.baseURL): tr("填入接口地址后生效")
        case .missing(.model): AIEndpoints.requiresModel(serviceID) ? tr("填入接入点 ID 后生效") : tr("填入模型名后生效")
        case .badURL: tr("接口地址要以 https:// 开头")
        }
    }

    // MARK: 分段的样子

    /// 三选一里每一段画成什么样。
    public enum Segment: Equatable, Sendable {
        /// 正在用的方式：实心高亮。
        case current
        /// 选了 API 但还差东西：描边，旁边写「填入密钥后生效」。
        case pending
        /// 能点。
        case normal
        /// 点不了（只有没有网址的服务的「网页」）。
        case unavailable
    }

    /// - Parameters:
    ///   - saved: 存下的选择（没存过时是默认方式）。
    ///   - effective: 实际在用的方式（`AIOpenModes.mode`）。
    ///   - hasWeb: 这个服务有没有网址。
    public static func segment(_ mode: AIOpenMode, saved: AIOpenMode, effective: AIOpenMode, hasWeb: Bool) -> Segment {
        if mode == effective { return .current }
        if mode == .api, saved == .api { return .pending }
        if mode == .web, !hasWeb { return .unavailable }
        return .normal
    }

    // MARK: 密钥

    public enum KeyInput: Equatable, Sendable {
        case ok(String)
        case empty
        /// 去掉首尾空白和开头的 "Bearer " 之后中间还有空白：多半是粘了两段。
        case hasSpaces

        public var message: String? {
            switch self {
            case .ok: nil
            case .empty: tr("先粘贴密钥。")
            case .hasSpaces: tr("密钥中间有空格或换行，可能粘贴了多余的内容。")
            }
        }
    }

    /// 用户粘贴的密钥：去掉首尾空白、开头的 "Bearer "（从文档里连着复制过来的）。
    public static func normalizedKey(_ text: String) -> KeyInput {
        var key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.lowercased().hasPrefix("bearer ") {
            key = String(key.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if key.isEmpty { return .empty }
        if key.contains(where: \.isWhitespace) { return .hasSpaces }
        return .ok(key)
    }

    // MARK: 获取密钥

    /// 各服务官方控制台里创建 API 密钥的页面，2026 年 10 月对照各家文档核对：
    ///
    /// - DeepSeek：api-docs.deepseek.com「首次调用 API」里的 API key 链接
    /// - Kimi：platform.kimi.com/docs/api/overview「API Key 可在控制台创建」
    /// - 通义：help.aliyun.com/zh/model-studio/get-api-key 里的百炼 API Key 页面
    /// - 智谱：docs.bigmodel.cn「快速开始」里的 API Keys 链接
    /// - 豆包：火山方舟控制台 API Key 管理
    /// - ChatGPT：OpenAI 平台的 API keys 页面
    /// - Gemini：Google AI Studio 的 API keys 页面（ai.google.dev「Using Gemini API keys」）
    /// - Perplexity：docs.perplexity.ai 指向的 API 控制台
    /// - Grok：docs.x.ai 指向的 xAI 控制台
    /// - 元宝：API 由腾讯混元提供，cloud.tencent.com/document/product/1729/111008 的控制台入口
    /// - 文心：API 由百度千帆提供，cloud.baidu.com 千帆文档里的 API Key 列表
    ///
    /// 自定义服务没有链接。
    public static let keyPages: [String: String] = [
        "deepseek": "https://platform.deepseek.com/api_keys",
        "kimi": "https://platform.kimi.com/console/api-keys",
        "tongyi": "https://bailian.console.aliyun.com/cn-beijing/model/settings/api-key",
        "zhipu": "https://bigmodel.cn/usercenter/proj-mgmt/apikeys",
        "doubao": "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey",
        "chatgpt": "https://platform.openai.com/api-keys",
        "gemini": "https://aistudio.google.com/apikey",
        "perplexity": "https://console.perplexity.ai/",
        "grok": "https://console.x.ai/",
        "yuanbao": "https://console.cloud.tencent.com/hunyuan/start",
        "wenxin": "https://console.bce.baidu.com/iam/#/iam/apikey/list",
    ]

    public static func keyPage(_ serviceID: String) -> URL? {
        keyPages[serviceID].flatMap(URL.init(string:))
    }

    /// 展开区底部的一行说明：API 实际由谁提供、模型名要填什么。
    public static func providerNote(_ serviceID: String) -> String? {
        switch serviceID {
        case "doubao": tr("豆包的 API 在火山方舟：先在控制台创建推理接入点，把接入点 ID（ep- 开头）填进「模型」。")
        case "yuanbao": tr("元宝的 API 由腾讯混元提供，模型名见混元文档。")
        case "wenxin": tr("文心的 API 由百度千帆提供，模型名见千帆文档。")
        case "gemini": tr("Gemini 用谷歌的 OpenAI 兼容接口，模型名见 Gemini API 文档。")
        default: nil
        }
    }

    // MARK: 测试连接

    /// 测试连接的结论。
    public enum Verdict: Equatable, Sendable {
        /// 服务接受了密钥和模型。
        case ok
        /// 服务明确拒绝：密钥、地址、模型或账户有问题。附提示。
        case rejected(String)
        /// 没能确认（断网、超时、服务出错）。附提示。
        case unverified(String)

        public var message: String {
            switch self {
            case .ok: tr("连接成功。")
            case .rejected(let text), .unverified(let text): text
            }
        }
    }

    /// 测试请求的结果换成结论。只要服务回了 2xx 就算通过，不等回答内容；
    /// 429 说明密钥有效、只是太频繁，也算通过。
    public static func verdict(status: Int) -> Verdict {
        switch status {
        case 200 ..< 300, 429: .ok
        case 500 ... 599: .unverified(AIChatFailure.http(status: status, message: nil).message)
        default: .rejected(AIChatFailure.http(status: status, message: nil).message)
        }
    }

    public static func verdict(failure: AIChatFailure) -> Verdict {
        switch failure {
        case .http(let status, let message):
            switch verdict(status: status) {
            case .ok: return .ok
            case .unverified: return .unverified(failure.message)
            case .rejected: return .rejected(AIChatFailure.http(status: status, message: message).message)
            }
        case .missingKey, .missingEndpoint, .badURL, .stream:
            return .rejected(failure.message)
        case .timeout, .offline, .cannotConnect, .secureConnection, .emptyReply, .other:
            return .unverified(failure.message)
        }
    }

    /// 校验之后存成哪种方式。`intent` 是用户想要的方式：存密钥时是 API，
    /// 点「测试连接」时是现在存的方式（nil 为默认）。通过就照用户的意思；
    /// 服务明确拒绝时不留一个注定出错的 API，回到默认（网页）；没能确认时
    /// 照用户的意思，发送时会再报错。
    public static func modeAfterCheck(_ verdict: Verdict, intent: AIOpenMode?) -> AIOpenMode? {
        switch verdict {
        case .ok, .unverified: intent
        case .rejected: intent == .api ? nil : intent
        }
    }

    /// 校验之后的一句话。
    public static func checkNote(_ verdict: Verdict, mode: AIOpenMode?) -> String {
        switch verdict {
        case .ok: return mode == .api ? tr("连接成功，已改用 API。") : tr("连接成功。")
        case .rejected(let text): return tr("没通过：\(text)")
        case .unverified(let text):
            return mode == .api ? tr("暂时没能确认：\(text) 已先改用 API，发送时会再试。") : tr("暂时没能确认：\(text)")
        }
    }

    /// 删掉密钥后的方式：选的是 API 就回到默认（网页），其余不变。
    public static func modeAfterKeyDeleted(_ saved: AIOpenMode?) -> AIOpenMode? {
        saved == .api ? nil : saved
    }

    // MARK: 设置页的说明

    /// 三种方式各一行的短说明，放在表格最上面，不放在会被裁切的表尾。
    public static func modeNote(_ mode: AIOpenMode) -> String {
        switch mode {
        case .web: tr("在面板里打开官网，用你自己的账号，登录一次会记住。")
        case .api: tr("填密钥直接对话，回答流式显示；密钥只存在钥匙串。")
        case .jump: tr("打开 Mac App，没装就用浏览器。")
        }
    }

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
