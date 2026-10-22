import Foundation

// MARK: - AI 助手：找本机的 Mac App

/// 「App」打开方式要找的 Mac App：先看用户在设置里亲手选的，再按 bundle id
/// 找，最后在「应用程序」文件夹里按 App 名找。这里只放纯逻辑（候选 id、
/// 名字怎么比），真正问系统的在 `AIServiceOpener`。
public enum AIAppMatch {
    /// 内置服务的候选 bundle id，按可信程度排序。2026 年 10 月核对：
    ///
    /// - 豆包 `com.bot.pc.doubao`：Homebrew 官方 cask `doubao` 的卸载清单
    ///   （~/Library/Preferences/com.bot.pc.doubao.plist），官网下载的 Doubao.app；
    ///   `com.bot.neotix.doubao`：Mac App Store 版（MacUpdater 的应用页）；
    ///   `com.volcengine.doubao`：旧版本里写的，留作候选。
    /// - Kimi `com.moonshot.kimichat`：Homebrew cask `kimi` 的卸载清单。
    /// - 通义 / 千问 `com.alibaba.tongyi`：千问 Mac 版（Qianwen.app）的 bundle id。
    /// - 元宝 `com.tencent.yuanbao`：Homebrew cask `yuanbao` 的卸载清单（元宝.app）。
    /// - ChatGPT `com.openai.chat`：安装包的 codesign 结果。
    /// - Gemini `com.google.GeminiMacOS`：Homebrew cask `google-gemini` 读的 plist 键。
    /// - Perplexity `ai.perplexity.mac`：第三方工具的应用清单。
    ///
    /// DeepSeek 官网的客户端只有手机版（桌面端是写代码的 DeepSeek Harness，不是
    /// 对话 App）；文心（文小言）、智谱清言、Grok 没找到可信的 bundle id，只按名字找。
    public static let bundleIDs: [String: [String]] = [
        "doubao": ["com.bot.pc.doubao", "com.bot.neotix.doubao", "com.volcengine.doubao"],
        "kimi": ["com.moonshot.kimichat"],
        "tongyi": ["com.alibaba.tongyi"],
        "yuanbao": ["com.tencent.yuanbao"],
        "chatgpt": ["com.openai.chat"],
        "gemini": ["com.google.GeminiMacOS"],
        "perplexity": ["ai.perplexity.mac"],
    ]

    /// 按名字找时认的 App 名（不带 .app），比较时不分大小写、不看空格和标点。
    public static let appNames: [String: [String]] = [
        "doubao": ["豆包", "Doubao"],
        "deepseek": ["DeepSeek"],
        "kimi": ["Kimi", "Kimi 智能助手"],
        "tongyi": ["千问", "Qianwen", "通义", "Tongyi", "通义千问", "Qwen"],
        "yuanbao": ["元宝", "腾讯元宝", "Yuanbao"],
        "wenxin": ["文小言", "文心", "文心一言", "Wenxiaoyan", "ERNIE"],
        "zhipu": ["智谱清言", "ChatGLM", "智谱"],
        "chatgpt": ["ChatGPT"],
        "gemini": ["Gemini", "Google Gemini"],
        "perplexity": ["Perplexity"],
        "grok": ["Grok"],
    ]

    /// 名字后面可以多出来的词：「Kimi AI」「Gemini Desktop」「豆包助手」都算。
    /// 别的词不算，免得「Doubao Browser」「Grok Bot」「DeepSeek Harness」这类
    /// 同名不同用的 App 被当成对话 App。
    static let genericSuffixes = ["ai", "app", "desktop", "mac", "formac", "beta", "助手", "智能助手", "桌面版", "电脑版"]

    /// 候选 bundle id：服务自己带的（自定义服务选 App 时记下的）在前，再是内置表。
    public static func bundleIDs(for service: AIService) -> [String] {
        var ids: [String] = []
        if let own = service.appBundleID, !own.isEmpty { ids.append(own) }
        for id in bundleIDs[service.id] ?? [] where !ids.contains(id) { ids.append(id) }
        return ids
    }

    /// 认的名字：内置表里的，加上服务自己的名字（自定义服务就靠它）。
    public static func names(for service: AIService) -> [String] {
        var names = appNames[service.id] ?? []
        if !names.contains(service.title) { names.append(service.title) }
        return names
    }

    /// 比较用的样子：去掉 .app、小写、去掉空格和标点。
    public static func normalized(_ name: String) -> String {
        var text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasSuffix(".app") { text.removeLast(4) }
        return String(text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }.map(Character.init))
    }

    /// 匹配得多好：完全同名最好，名字加一个通用后缀次之，不匹配为 nil。
    public enum Quality: Int, Comparable, Sendable {
        case suffix = 1, exact = 2
        public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    public static func quality(of fileName: String, names: [String]) -> Quality? {
        let candidate = normalized(fileName)
        guard !candidate.isEmpty else { return nil }
        var best: Quality?
        for name in names {
            let key = normalized(name)
            guard !key.isEmpty else { continue }
            if candidate == key { return .exact }
            if candidate.hasPrefix(key), genericSuffixes.contains(String(candidate.dropFirst(key.count))) {
                best = .suffix
            }
        }
        return best
    }

    /// 在一串 App 文件名（「Doubao.app」）里挑最像这个服务的那个；同样好时
    /// 取先出现的（调用方按 /Applications、~/Applications 的顺序给）。
    public static func bestMatch(for service: AIService, among fileNames: [String]) -> String? {
        let names = names(for: service)
        var best: (name: String, quality: Quality)?
        for file in fileNames where file.lowercased().hasSuffix(".app") {
            guard let quality = quality(of: file, names: names) else { continue }
            if best == nil || quality > best!.quality { best = (file, quality) }
            if quality == .exact { break }
        }
        return best?.name
    }

    // MARK: 设置里的说明

    /// 「App」方式实际会打开什么。
    public enum Target: Equatable, Sendable {
        /// 用户在设置里选的 App。
        case chosen(name: String)
        /// 自动找到的 App。
        case found(name: String)
        /// 没找到 App，用浏览器打开网页。
        case web
        /// 没有 App 也没有网址。
        case nothing
    }

    /// 设置展开区里那行字。
    public static func describe(_ target: Target) -> String {
        switch target {
        case .chosen(let name): tr("会打开你选的 \(name)")
        case .found(let name): tr("会打开 \(name)")
        case .web: tr("没找到 Mac App，会用浏览器打开网页")
        case .nothing: tr("没找到 Mac App，也没有网址")
        }
    }

    /// 「Doubao.app」「/Applications/元宝.app」 -> 「Doubao」「元宝」。
    public static func displayName(_ fileNameOrPath: String) -> String {
        var name = (fileNameOrPath as NSString).lastPathComponent
        if name.lowercased().hasSuffix(".app") { name.removeLast(4) }
        return name
    }
}

// MARK: - 「App」方式下带着问题怎么交出去

extension AIAsk {
    /// 「App」方式：装了 App 时复制问题再打开 App（App 不接带问题的网址），
    /// 没装才按服务支持的网址在浏览器里带上问题。
    public static func plan(_ text: String, service: AIService, appInstalled: Bool) -> Plan {
        guard let question = question(text) else { return .blocked }
        if appInstalled { return .copyThenOpen(question) }
        return plan(text, service: service)
    }
}
