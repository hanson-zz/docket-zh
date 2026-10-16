import Foundation

// MARK: - AI 助手：服务

/// AI 助手小组件里的一块字牌：一个 AI 服务的入口。
///
/// 卡片上只画单色玻璃字牌（首字或短缩写），不用任何官方图标。点字牌打开
/// 这个服务的 Mac App（装了的话），否则打开网页；提问面板按 `askTemplate`
/// 决定能不能把问题带进网址，不能的就复制问题再打开，由用户自己粘贴。
public struct AIService: Codable, Equatable, Sendable, Identifiable {
    public enum Region: String, Codable, Sendable, CaseIterable {
        case domestic, overseas

        public var title: String {
            switch self {
            case .domestic: "国内"
            case .overseas: "国外"
            }
        }
    }

    /// 内置服务是固定 id；自定义的以 `custom-` 开头。
    public var id: String
    public var title: String
    /// 字牌上的字：中文取一个字，英文取一两个字母。
    public var initial: String
    public var region: Region
    /// 网页入口，`https://…`。自定义服务只选了 App 时为空字符串。
    public var home: String
    /// Mac App 的 bundle id，装了就优先打开它。
    public var appBundleID: String?
    /// 自定义服务用 NSOpenPanel 选的 App 路径。
    public var appPath: String?
    /// 只在服务正式支持把问题带进网址时才有：`%s` 是问题的位置。
    public var askTemplate: String?

    public init(id: String, title: String, initial: String, region: Region, home: String,
                appBundleID: String? = nil, appPath: String? = nil, askTemplate: String? = nil) {
        self.id = id
        self.title = title
        self.initial = initial
        self.region = region
        self.home = home
        self.appBundleID = appBundleID
        self.appPath = appPath
        self.askTemplate = askTemplate
    }

    public var isCustom: Bool { id.hasPrefix(AIServices.customPrefix) }

    /// 网页入口；不是 http(s) 时为 nil。
    public var homeURL: URL? { AIServices.webURL(home) }

    /// 能不能把问题直接带进网址（只看是否有核实过的模板）。
    public var supportsAsk: Bool { askTemplate != nil }

    /// 带着问题的网址。空白问题、没有模板、或者拼出来的网址太长时为 nil，
    /// 这时面板改为复制问题再打开。
    public func askURL(for question: String) -> URL? {
        guard let template = askTemplate else { return nil }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        let filled = template.replacingOccurrences(of: "%s", with: encoded)
        guard filled.count <= AIServices.maxAskURLLength else { return nil }
        return URL(string: filled)
    }
}

// MARK: - AI 助手：目录和配置

/// AI 助手的纯逻辑：内置服务、卡片上显示哪些、默认是谁、自定义服务的校验，
/// 以及卡片尺寸。全部存在小组件自己的设置里（和搜索站一样），读的时候容错，
/// 设置坏了或是旧数据都回到默认，不会崩。
public enum AIServices {
    public static let customPrefix = "custom-"

    /// 设置里的键。都不在目录默认值里：它们在卡片和面板里改，不进设置页。
    public static let servicesKey = "services"
    public static let customKey = "customServices"
    public static let defaultKey = "defaultService"
    /// 自定义服务的 JSON 读不出来时，第一次改动前把原文留在这里，便于找回。
    public static let brokenCustomKey = "customServicesBroken"

    public static let wideLayout = "wide"
    public static let squareLayout = "square"

    /// 卡片上最多几块字牌，再多卡片就太长了。
    public static let maxCount = 12
    /// 自定义服务最多几个。
    public static let maxCustom = 12
    /// 名字最多几个字。
    public static let maxTitleLength = 12
    /// 带问题的网址超过这个长度就不拼了，改为复制。
    public static let maxAskURLLength = 4_000

    /// 内置服务。网址都在 2026 年 10 月用网页搜索核对过：
    ///
    /// - 豆包 https://www.doubao.com/chat/ （官网的对话页）
    /// - DeepSeek https://chat.deepseek.com/ （deepseek.com 首页“开始对话”指向这里）
    /// - Kimi https://www.kimi.com/ （旧域 kimi.moonshot.cn 整域跳转到这里）
    /// - 通义 https://www.qianwen.com/ （通义 App 已改名“千问”，tongyi.com 跳到这里）
    /// - 元宝 https://yuanbao.tencent.com/
    /// - 文心 https://wenxin.baidu.com/ （原 yiyan.baidu.com 会跳到这里）
    /// - 智谱清言 https://chatglm.cn/
    /// - ChatGPT https://chatgpt.com/
    /// - Gemini https://gemini.google.com/app
    /// - Perplexity https://www.perplexity.ai/
    /// - Grok https://grok.com/
    ///
    /// 提问模板只给两家：
    ///
    /// - ChatGPT：`https://chatgpt.com/?q=%s`。OpenAI 帮助中心“Searching the web
    ///   with ChatGPT”（help.openai.com/en/articles/9237897）写明官方的 ChatGPT
    ///   search 扩展能从浏览器地址栏直接开始对话，用的就是 `?q=`；OpenAI 开发者
    ///   社区里官方确认这个参数“已经按需求实现”。问题会填进输入框。
    /// - Perplexity：`https://www.perplexity.ai/search?q=%s`。Perplexity 官方的
    ///   “Perplexity - AI Search”浏览器扩展和 Firefox 144 内置的 Perplexity 搜索
    ///   都按这个格式把搜索词交给它，打开即开始搜索。
    ///
    /// 其余都没有模板：Grok 的 `?q=` 只有第三方实测、没有官方文档，而且打开就
    /// 直接发送，不给用户看一眼；Gemini 不支持；国内几家没有找到官方说明。
    ///
    /// Mac App 的 bundle id 只填有据可查的：ChatGPT 是 com.openai.chat（安装包
    /// codesign 结果），Perplexity 是 ai.perplexity.mac、豆包是
    /// com.volcengine.doubao（第三方工具的应用清单）。没装或 id 不对时照常打开网页。
    public static let builtIn: [AIService] = [
        AIService(id: "doubao", title: "豆包", initial: "豆", region: .domestic,
                  home: "https://www.doubao.com/chat/", appBundleID: "com.volcengine.doubao"),
        AIService(id: "deepseek", title: "DeepSeek", initial: "D", region: .domestic,
                  home: "https://chat.deepseek.com/"),
        AIService(id: "kimi", title: "Kimi", initial: "K", region: .domestic,
                  home: "https://www.kimi.com/"),
        AIService(id: "tongyi", title: "通义", initial: "通", region: .domestic,
                  home: "https://www.qianwen.com/"),
        AIService(id: "yuanbao", title: "元宝", initial: "元", region: .domestic,
                  home: "https://yuanbao.tencent.com/"),
        AIService(id: "wenxin", title: "文心", initial: "文", region: .domestic,
                  home: "https://wenxin.baidu.com/"),
        AIService(id: "zhipu", title: "智谱清言", initial: "智", region: .domestic,
                  home: "https://chatglm.cn/"),
        AIService(id: "chatgpt", title: "ChatGPT", initial: "G", region: .overseas,
                  home: "https://chatgpt.com/", appBundleID: "com.openai.chat",
                  askTemplate: "https://chatgpt.com/?q=%s"),
        AIService(id: "gemini", title: "Gemini", initial: "Gm", region: .overseas,
                  home: "https://gemini.google.com/app"),
        AIService(id: "perplexity", title: "Perplexity", initial: "P", region: .overseas,
                  home: "https://www.perplexity.ai/", appBundleID: "ai.perplexity.mac",
                  askTemplate: "https://www.perplexity.ai/search?q=%s"),
        AIService(id: "grok", title: "Grok", initial: "Gr", region: .overseas,
                  home: "https://grok.com/"),
    ]

    /// 新放上的 AI 助手默认显示的三块。
    public static let defaultIDs = ["deepseek", "kimi", "doubao"]
    public static let defaultServiceID = "deepseek"

    public static func builtIn(_ id: String) -> AIService? { builtIn.first { $0.id == id } }

    public static var defaults: [AIService] { defaultIDs.compactMap(builtIn) }

    // MARK: 读

    /// 按保存的 id 顺序取服务：内置的按 id 找，自定义的在 `custom` 里找；
    /// 找不到的跳过，重复的去掉，最多 `maxCount` 个。
    public static func resolve(ids: [String], custom: [AIService]) -> [AIService] {
        var seen = Set<String>()
        let services = ids.compactMap { id -> AIService? in
            guard seen.insert(id).inserted else { return nil }
            return builtIn(id) ?? custom.first { $0.id == id }
        }
        return Array(services.prefix(maxCount))
    }

    /// 卡片上显示的服务，按顺序。
    ///
    /// 从没设置过、类型不对、或者一个都认不出来（坏数据、旧版本的 id）时用
    /// 默认三块；用户亲手把它们都隐藏了（保存的是空列表）时就是空的，卡片
    /// 显示“添加”。
    public static func enabled(in config: WidgetConfig) -> [AIService] {
        guard case .list(let items)? = config[servicesKey] else { return defaults }
        if items.isEmpty { return [] }
        let ids = items.compactMap { item -> String? in
            if case .string(let id) = item { return id }
            return nil
        }
        let resolved = resolve(ids: ids, custom: custom(in: config))
        return resolved.isEmpty ? defaults : resolved
    }

    /// 用户加的自定义服务（不论是否显示在卡片上）。
    public static func custom(in config: WidgetConfig) -> [AIService] {
        decode(config.string(customKey))
    }

    /// 全部可选的服务：内置的加自定义的。
    public static func all(in config: WidgetConfig) -> [AIService] {
        builtIn + custom(in: config)
    }

    /// 默认服务（蓝点）：保存的那个还显示在卡片上就是它；否则 DeepSeek 在
    /// 卡片上就用 DeepSeek，再否则用第一块。一块都没有时为 nil。
    public static func defaultService(in config: WidgetConfig, enabled: [AIService]? = nil) -> AIService? {
        let shown = enabled ?? self.enabled(in: config)
        let saved = config.string(defaultKey)
        return shown.first { $0.id == saved }
            ?? shown.first { $0.id == defaultServiceID }
            ?? shown.first
    }

    public static func isEnabled(_ id: String, in config: WidgetConfig) -> Bool {
        enabled(in: config).contains { $0.id == id }
    }

    // MARK: 改

    /// 显示或隐藏一块字牌。已满 `maxCount` 时不再加。
    public static func toggle(_ id: String, in config: inout WidgetConfig) {
        if isEnabled(id, in: config) { hide(id, in: &config) } else { show(id, in: &config) }
    }

    /// 显示一块字牌（加在末尾）。认不出的 id 或已满时不变。
    public static func show(_ id: String, in config: inout WidgetConfig) {
        var ids = enabled(in: config).map(\.id)
        guard !ids.contains(id), ids.count < maxCount,
              builtIn(id) != nil || custom(in: config).contains(where: { $0.id == id }) else { return }
        ids.append(id)
        write(ids, in: &config)
    }

    /// 从卡片上拿掉（不删除）。它是默认服务时，默认移到剩下的第一块。
    public static func hide(_ id: String, in config: inout WidgetConfig) {
        let before = enabled(in: config)
        let wasDefault = defaultService(in: config, enabled: before)?.id == id
        let ids = before.map(\.id).filter { $0 != id }
        write(ids, in: &config)
        if wasDefault {
            if let next = ids.first { config.set(defaultKey, .string(next)) }
            else { config.set(defaultKey, nil) }
        }
    }

    public static func setDefault(_ id: String, in config: inout WidgetConfig) {
        guard isEnabled(id, in: config) else { return }
        // 先把当前顺序写下来，免得一个从没保存过的卡片换默认时丢了顺序。
        write(enabled(in: config).map(\.id), in: &config)
        config.set(defaultKey, .string(id))
    }

    /// 左移（-1）或右移（+1）。到头了不动。
    public static func move(_ id: String, by offset: Int, in config: inout WidgetConfig) {
        var ids = enabled(in: config).map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + offset
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        write(ids, in: &config)
    }

    public static func canMove(_ id: String, by offset: Int, in config: WidgetConfig) -> Bool {
        let ids = enabled(in: config).map(\.id)
        guard let index = ids.firstIndex(of: id) else { return false }
        return ids.indices.contains(index + offset)
    }

    /// 加一个自定义服务，并显示在卡片上。
    @discardableResult
    public static func addCustom(_ service: AIService, in config: inout WidgetConfig) -> CustomError? {
        guard service.isCustom else { return .invalidAddress }
        var custom = self.custom(in: config)
        guard custom.count < maxCustom else { return .tooMany }
        if let duplicate = duplicateError(service, among: builtIn + custom) { return duplicate }
        preserveBrokenCustom(in: &config)
        custom.append(service)
        config.set(customKey, .string(encode(custom)))
        var ids = enabled(in: config).map(\.id)
        if ids.count < maxCount { ids.append(service.id) }
        write(ids, in: &config)
        return nil
    }

    /// 删除一个自定义服务（内置的只能隐藏）。
    public static func removeCustom(_ id: String, in config: inout WidgetConfig) {
        guard id.hasPrefix(customPrefix) else { return }
        hide(id, in: &config)
        preserveBrokenCustom(in: &config)
        let custom = self.custom(in: config).filter { $0.id != id }
        config.set(customKey, .string(encode(custom)))
    }

    private static func write(_ ids: [String], in config: inout WidgetConfig) {
        config.set(servicesKey, .list(ids.map { .string($0) }))
    }

    /// 自定义服务的原文读不出来时，覆盖之前先留一份。
    private static func preserveBrokenCustom(in config: inout WidgetConfig) {
        let raw = config.string(customKey)
        guard !raw.isEmpty, (try? JSONDecoder().decode([AIService].self, from: Data(raw.utf8))) == nil,
              config.string(brokenCustomKey).isEmpty else { return }
        config.set(brokenCustomKey, .string(raw))
    }

    // MARK: 自定义服务

    public enum CustomError: Error, Equatable, Sendable {
        case emptyName, invalidAddress, missingTarget, duplicateName, duplicateAddress, tooMany

        public var message: String {
            switch self {
            case .emptyName: "请填写名字。"
            case .invalidAddress: "网址要以 http:// 或 https:// 开头（不写协议会补 https）。"
            case .missingTarget: "填一个网址，或者选一个 App。"
            case .duplicateName: "已经有同名的服务了。"
            case .duplicateAddress: "这个地址已经添加过了。"
            case .tooMany: "自定义服务最多 \(AIServices.maxCustom) 个。"
            }
        }
    }

    /// 用户填的自定义服务：名字必填，网址和 App 至少一个。网址没写协议补
    /// https，写了别的协议、带空格或没有域名都不收。重复的名字或地址不收。
    public static func custom(title: String, address: String, appPath: String? = nil,
                              appBundleID: String? = nil, id: String,
                              existing: [AIService] = builtIn) -> Result<AIService, CustomError> {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.emptyName) }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = appPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasApp = !(app ?? "").isEmpty
        var home = ""
        if !trimmed.isEmpty {
            guard let normalized = normalizedAddress(trimmed) else { return .failure(.invalidAddress) }
            home = normalized
        } else if !hasApp {
            return .failure(.missingTarget)
        }
        let short = String(name.prefix(maxTitleLength))
        let service = AIService(id: customPrefix + id, title: short, initial: initial(for: short),
                                region: .domestic, home: home,
                                appBundleID: appBundleID?.isEmpty == false ? appBundleID : nil,
                                appPath: hasApp ? app : nil)
        if let duplicate = duplicateError(service, among: existing) { return .failure(duplicate) }
        return .success(service)
    }

    /// `metaso.cn` -> `https://metaso.cn`；不合格时为 nil。
    public static func normalizedAddress(_ text: String) -> String? {
        var address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !address.contains(where: \.isWhitespace) else { return nil }
        let lower = address.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            guard !lower.contains("://") else { return nil }
            address = "https://" + address
        }
        return webURL(address) == nil ? nil : address
    }

    /// 只收 http(s)，而且要有像样的域名（带点，或 localhost）。
    public static func webURL(_ text: String) -> URL? {
        guard !text.isEmpty, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty,
              host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    /// 字牌上的字：中文取第一个字；英文取首字母大写。
    public static func initial(for title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    private static func duplicateError(_ service: AIService, among others: [AIService]) -> CustomError? {
        let name = service.title.lowercased()
        if others.contains(where: { $0.id != service.id && $0.title.lowercased() == name }) { return .duplicateName }
        if let key = addressKey(service.home),
           others.contains(where: { $0.id != service.id && addressKey($0.home) == key }) {
            return .duplicateAddress
        }
        if let path = service.appPath,
           others.contains(where: { $0.id != service.id && $0.appPath == path }) {
            return .duplicateAddress
        }
        return nil
    }

    /// 比较地址时不看协议、大小写、开头的 www. 和末尾的斜杠。
    static func addressKey(_ home: String) -> String? {
        guard let url = webURL(home), var host = url.host()?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path().lowercased()
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    // MARK: 存

    public static func encode(_ services: [AIService]) -> String {
        guard let data = try? JSONEncoder().encode(services) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 读不出来就当没有；只留自定义的、能打开点什么的。
    public static func decode(_ text: String) -> [AIService] {
        guard !text.isEmpty,
              let services = try? JSONDecoder().decode([AIService].self, from: Data(text.utf8)) else { return [] }
        var seen = Set<String>()
        return services.filter {
            $0.isCustom && seen.insert($0.id).inserted
                && ($0.homeURL != nil || !($0.appPath ?? "").isEmpty)
        }
    }

    // MARK: 卡片尺寸

    /// 方块样式最多画几块字牌（剩下的在面板里选）。
    public static let squareVisible = 3
    /// 侧边栏一列最多画几块。
    public static let columnVisible = 8

    public static func isSquare(_ config: WidgetConfig) -> Bool {
        config.string("layout", default: wideLayout) == squareLayout
    }

    /// 卡片上实际画几块字牌。
    public static func visibleCount(_ count: Int, square: Bool, vertical: Bool) -> Int {
        let total = max(0, min(count, maxCount))
        if square { return min(total, squareVisible) }
        return vertical ? min(total, columnVisible) : total
    }

    /// 底部货架上的宽度：左右各 10 的内边距，小熊猫 38，分隔线和两边的
    /// 间距 13，每块字牌 24 加 5 的间距，末尾的“＋”24。一块都没有时是
    /// “添加”按钮（52）。方块样式是小熊猫加 2x2 的格子。
    public static func tileWidth(count: Int, square: Bool) -> Double {
        if square { return 108 }
        let shown = visibleCount(count, square: false, vertical: false)
        if shown == 0 { return 20 + 38 + 13 + 52 }
        return Double(20 + 38 + 13 + shown * 29 + 24)
    }

    /// 侧边栏一列的高度：小熊猫在上，字牌两个一行，最后是“＋”。
    public static func columnHeight(count: Int, square: Bool) -> Double {
        let shown = visibleCount(count, square: square, vertical: true)
        let cells = shown + 1
        let rows = (cells + 1) / 2
        return max(76, Double(10 + 34 + 6 + rows * 29 - 5 + 10))
    }
}

// MARK: - AI 助手：提问

/// 提问面板的纯逻辑：回车怎么算、问题怎么交出去、按钮和提示怎么写。
public enum AIAsk {
    /// 一次按下回车该做什么。
    public enum ReturnAction: Equatable, Sendable {
        /// 交给输入法或文本框自己处理（中文输入法正在选字时）。
        case passThrough
        case newline
        case submit
    }

    /// 输入法有未确认的字（marked text）时，回车是确认选字，绝不提交；
    /// Shift 或 Option 加回车换行；单按回车提交。
    public static func returnAction(shift: Bool, option: Bool = false, hasMarkedText: Bool) -> ReturnAction {
        if hasMarkedText { return .passThrough }
        if shift || option { return .newline }
        return .submit
    }

    /// 去掉首尾空白后的问题；空白时为 nil，面板不提交。
    public static func question(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 交出去的方式。
    public enum Plan: Equatable, Sendable {
        /// 空白，什么都不做。
        case blocked
        /// 服务正式支持：带着问题打开这个网址。
        case openWithQuestion(URL)
        /// 不支持：把问题复制到剪贴板，再打开服务。
        case copyThenOpen(String)
    }

    public static func plan(_ text: String, service: AIService) -> Plan {
        guard let question = question(text) else { return .blocked }
        if let url = service.askURL(for: question) { return .openWithQuestion(url) }
        return .copyThenOpen(question)
    }

    /// 主按钮上的字。
    public static func buttonTitle(for service: AIService?) -> String {
        service?.supportsAsk == true ? "打开并提问" : "复制问题并打开"
    }

    /// 做完之后面板上的一句话。只说做了什么，不假装已经发送或已经回答。
    public static func hint(after plan: Plan, service: AIService) -> String? {
        switch plan {
        case .blocked: "先写下要问的问题。"
        case .openWithQuestion: "已在浏览器打开 \(service.title)，问题已带过去，回答在那边看。"
        case .copyThenOpen: "已复制，到 \(service.title) 里粘贴即可。"
        }
    }
}
