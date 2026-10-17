import Foundation

/// 码头 Pro 的收费授权：配置、状态机、响应解析和中文文案。
///
/// 做法照搬兄弟应用拾掇：Creem 一次买断，许可证密钥在 Creem 激活、校验、解绑，
/// 中间经一个 Cloudflare Worker（仓库里的 server/license-relay）转发，App 里
/// 不放 Creem 的密钥；另有赠送用的兑换码 DKG-XXXX-XXXX-XXXX，由同一个 Worker
/// 存在 KV 里。7 天试用要用户自己点“开始试用”才开始。
///
/// 这里只有纯逻辑，方便测试；钥匙串和网络在 Services/ProLicenseService.swift。
public enum ProLicenseConfig {
    /// Creem 里码头 Pro 的产品 ID。中转服务和 App 都只认它，拾掇的码解锁不了码头。
    public static let productID = "prod_XYf9P2X55fvYZQOLhs3Lr"

    /// 购买页（Creem 结账链接）。
    public static let buyURL = URL(string: "https://www.creem.io/payment/prod_XYf9P2X55fvYZQOLhs3Lr")!

    /// 授权中转服务的地址，后面接 activate、validate、deactivate。
    /// 部署 Worker 后如果地址不同，只改这一处。
    public static let apiBase = "https://dockling-license.tudou-123.workers.dev/v1/licenses/"

    /// 免费试用天数。
    public static let trialDays = 7
    /// 离线时，距离上次成功校验多少天内仍然算已激活。
    public static let offlineGraceDays = 30
    /// 最多每 24 小时联网校验一次。
    public static let revalidateInterval: TimeInterval = 86_400

    /// 原价和早鸟价，只用于显示。
    public static let price = "$9.90"
    public static let earlyBirdPrice = "$6.90"

    /// 码头兑换码的前缀；拾掇的是 SDG。
    public static let giftPrefix = "DKG"
    /// 兄弟应用拾掇的兑换码前缀，用来给出更明白的提示。
    public static let siblingGiftPrefix = "SDG"
}

// MARK: - 状态

/// 码头 Pro 的四种状态。
public enum ProLicenseState: Equatable, Sendable {
    /// 没开始试用，也没激活。
    case free
    /// 试用中，还剩几天（1 到 7）。
    case trial(daysLeft: Int)
    /// 已用许可证或兑换码激活。
    case pro
    /// 试用已结束，没有激活。
    case expiredTrial

    /// 试用中或已激活，Pro 功能可以用。
    public var isUnlocked: Bool {
        switch self {
        case .trial, .pro: true
        case .free, .expiredTrial: false
        }
    }

    /// 设置和付费墙里显示的一句话。
    public var statusText: String {
        switch self {
        case .free: tr("免费版")
        case .trial(let days): tr("Pro 试用中，还剩 \(days) 天")
        case .pro: tr("码头 Pro 已激活")
        case .expiredTrial: tr("试用已结束")
        }
    }
}

/// 钥匙串里存的四样东西，读出来交给 `ProLicenseLogic` 计算状态。
public struct ProLicenseSnapshot: Equatable, Sendable {
    public var licenseKey: String?
    public var instanceID: String?
    public var lastValidated: Date?
    public var trialStart: Date?

    public init(licenseKey: String? = nil, instanceID: String? = nil,
                lastValidated: Date? = nil, trialStart: Date? = nil) {
        self.licenseKey = licenseKey
        self.instanceID = instanceID
        self.lastValidated = lastValidated
        self.trialStart = trialStart
    }

    /// 这台 Mac 用许可证或兑换码激活过（还没解绑）。
    public var isActivated: Bool {
        guard let licenseKey, !licenseKey.isEmpty, let instanceID, !instanceID.isEmpty else { return false }
        return true
    }
}

/// 状态机和时间计算。
public enum ProLicenseLogic {
    private static let day: TimeInterval = 86_400

    /// 由钥匙串里的信息算出现在的状态，不联网。
    ///
    /// 已激活且在离线宽限期内是 Pro；宽限期过了就看试用（多半已结束），
    /// 等下一次联网校验成功再回到 Pro。
    public static func state(_ snapshot: ProLicenseSnapshot, now: Date) -> ProLicenseState {
        if snapshot.isActivated, let last = snapshot.lastValidated, withinGrace(lastValidated: last, now: now) {
            return .pro
        }
        guard let start = snapshot.trialStart else { return .free }
        let left = trialDaysLeft(trialStart: start, now: now)
        return left > 0 ? .trial(daysLeft: left) : .expiredTrial
    }

    /// 试用还剩几天，0 表示已结束。开始当天算 7 天，满 24 小时减一天。
    /// 系统时间被往回拨（开始时间在将来）时不会多给，最多 7 天。
    public static func trialDaysLeft(trialStart: Date, now: Date) -> Int {
        let used = max(0, Int(now.timeIntervalSince(trialStart) / day))
        return min(ProLicenseConfig.trialDays, max(0, ProLicenseConfig.trialDays - used))
    }

    /// 试用结束的时刻。
    public static func trialEndDate(trialStart: Date) -> Date {
        trialStart.addingTimeInterval(TimeInterval(ProLicenseConfig.trialDays) * day)
    }

    /// 距离上次成功校验还在离线宽限期内。上次校验的时间在将来（时钟被拨过）
    /// 也算在内，等下次联网再纠正。
    public static func withinGrace(lastValidated: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastValidated) < TimeInterval(ProLicenseConfig.offlineGraceDays) * day
    }

    /// 该不该联网重新校验：激活了，且距离上次成功校验超过 24 小时（或从没校验过）。
    public static func needsRevalidation(_ snapshot: ProLicenseSnapshot, now: Date) -> Bool {
        guard snapshot.isActivated else { return false }
        guard let last = snapshot.lastValidated else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= ProLicenseConfig.revalidateInterval || elapsed < 0
    }

    /// 能不能开始试用：没开始过，也没激活。试用开始过就不会再重置。
    public static func canStartTrial(_ snapshot: ProLicenseSnapshot) -> Bool {
        snapshot.trialStart == nil && !snapshot.isActivated
    }

    /// 激活的结果。
    public enum Activation: Equatable, Sendable {
        case success(instanceID: String)
        /// 码是有效的，但不属于码头 Pro（比如拾掇的）。要把刚占的名额还回去。
        case wrongProduct(instanceID: String)
        case failure(message: String)
    }

    public static func activation(_ response: ProLicenseResponse) -> Activation {
        guard response.activated == true, let instance = response.instanceID, !instance.isEmpty else {
            return .failure(message: ProLicenseText.message(error: response.error, status: response.status))
        }
        guard response.matchesProduct else { return .wrongProduct(instanceID: instance) }
        guard response.isUsableStatus else {
            return .failure(message: ProLicenseText.message(error: response.error, status: response.status))
        }
        return .success(instanceID: instance)
    }

    /// 重新校验的结果。
    public enum Revalidation: Equatable, Sendable {
        /// 没联网或服务器出错：保持现状，宽限期内仍是 Pro。
        case keep
        /// 校验通过，记下这次的时间。
        case confirmed
        /// 服务器明确说不能用了（停用、过期、在别处被解绑、不是码头的码），清掉激活。
        case revoked(message: String)
    }

    /// `response` 为 nil 表示网络或服务器出错。
    public static func revalidation(_ response: ProLicenseResponse?) -> Revalidation {
        guard let response else { return .keep }
        if response.valid == true, response.matchesProduct, response.isUsableStatus { return .confirmed }
        if response.valid == true, !response.matchesProduct {
            return .revoked(message: ProLicenseText.wrongProduct)
        }
        if response.valid != nil || response.status != nil {
            return .revoked(message: ProLicenseText.message(error: response.error, status: response.status))
        }
        return .keep
    }

    /// 解绑算成功：服务器说已解绑，或这台 Mac 本来就不在了。
    public static func deactivationSucceeded(_ response: ProLicenseResponse) -> Bool {
        if response.deactivated == true { return true }
        return (response.error ?? "").lowercased().contains("not found")
    }
}

// MARK: - 响应

/// 中转服务返回的内容里关心的几项（格式见 server/license-relay/worker.js）。
public struct ProLicenseResponse: Equatable, Sendable {
    public var activated: Bool?
    public var valid: Bool?
    public var deactivated: Bool?
    public var error: String?
    public var instanceID: String?
    public var status: String?
    public var productID: String?

    public init(activated: Bool? = nil, valid: Bool? = nil, deactivated: Bool? = nil,
                error: String? = nil, instanceID: String? = nil,
                status: String? = nil, productID: String? = nil) {
        self.activated = activated
        self.valid = valid
        self.deactivated = deactivated
        self.error = error
        self.instanceID = instanceID
        self.status = status
        self.productID = productID
    }

    /// 只认码头 Pro 的产品 ID；没有产品 ID 也不认。
    public var matchesProduct: Bool { productID == ProLicenseConfig.productID }

    /// 许可证状态可用。没有状态时不拦（由 activated / valid 决定）。
    public var isUsableStatus: Bool {
        guard let status else { return true }
        return status == "active" || status == "inactive"
    }

    /// 解析中转服务的 JSON 正文。不是 JSON 对象时返回 nil。
    /// 授权码无效时服务返回 4xx，但正文仍是 JSON，所以不看状态码。
    public static func parse(_ data: Data) -> ProLicenseResponse? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(object)
    }

    public static func parse(_ object: [String: Any]) -> ProLicenseResponse {
        var r = ProLicenseResponse()
        r.activated = object["activated"] as? Bool
        r.valid = object["valid"] as? Bool
        r.deactivated = object["deactivated"] as? Bool
        r.error = object["error"] as? String
        if let instance = object["instance"] as? [String: Any] {
            r.instanceID = instance["id"] as? String
        }
        if let key = object["license_key"] as? [String: Any] {
            r.status = key["status"] as? String
        }
        if let meta = object["meta"] as? [String: Any] {
            r.productID = meta["product_id"] as? String
        }
        return r
    }
}

// MARK: - 输入

/// 用户在输入框里填的东西：许可证密钥或兑换码。
public enum ProLicenseInput: Equatable, Sendable {
    case empty
    /// 格式正确的码头兑换码，已规整成 DKG-XXXX-XXXX-XXXX。
    case gift(String)
    /// 以 DKG 开头但格式不对（少了位、有容易看错的字符）。
    case malformedGift
    /// 拾掇的兑换码，码头不认。
    case siblingGift
    /// 其余当作 Creem 许可证密钥，原样（去掉首尾空白）交给服务器。
    case licenseKey(String)

    /// 兑换码用的字符：去掉了 0 O 1 I 这些容易看错的。
    public static let giftAlphabet = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    public static func classify(_ raw: String) -> ProLicenseInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let upper = trimmed.uppercased()
        if upper.hasPrefix(ProLicenseConfig.siblingGiftPrefix + "-") { return .siblingGift }
        guard upper.hasPrefix(ProLicenseConfig.giftPrefix) else { return .licenseKey(trimmed) }
        if let code = normalizedGift(upper) { return .gift(code) }
        return .malformedGift
    }

    /// 把 “dkg xxxx xxxx xxxx”、“DKGXXXXXXXXXXXX” 这类写法规整成
    /// DKG-XXXX-XXXX-XXXX；格式不对返回 nil。
    public static func normalizedGift(_ raw: String) -> String? {
        let compact = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard compact.hasPrefix(ProLicenseConfig.giftPrefix) else { return nil }
        let body = compact.dropFirst(ProLicenseConfig.giftPrefix.count)
        guard body.count == 12, body.allSatisfy({ giftAlphabet.contains($0) }) else { return nil }
        let chars = Array(body)
        let groups = stride(from: 0, to: 12, by: 4).map { String(chars[$0..<$0 + 4]) }
        return ([ProLicenseConfig.giftPrefix] + groups).joined(separator: "-")
    }

    /// 已经是标准格式的码头兑换码。
    public static func isGiftCode(_ text: String) -> Bool {
        normalizedGift(text) == text
    }
}

// MARK: - 文案

public enum ProLicenseText {
    public static let emptyInput = tr("请输入许可证密钥或兑换码。")
    public static let malformedGift = tr("兑换码格式不对，应为 DKG-XXXX-XXXX-XXXX，请检查是否完整复制。")
    public static let siblingGift = tr("这是拾掇的兑换码，不能用于码头。码头的兑换码以 DKG 开头。")
    public static let wrongProduct = tr("这个许可证不属于码头 Pro。拾掇等其他应用的许可证不能用于码头。")
    public static let network = tr("无法连接授权服务器，请检查网络后再试。")

    /// 输入框占位文字。
    public static let inputPlaceholder = tr("许可证密钥或兑换码（DKG-XXXX-XXXX-XXXX）")

    /// 价格一句话，付费墙和设置里用。
    public static var priceLine: String {
        tr("一次买断 \(ProLicenseConfig.price)，早鸟价 \(ProLicenseConfig.earlyBirdPrice)")
    }

    /// 许可证只显示前 4 位和后 4 位；兑换码只显示最后一组。
    public static func mask(_ key: String) -> String {
        if ProLicenseInput.isGiftCode(key) {
            return "\(ProLicenseConfig.giftPrefix)-••••-••••-" + String(key.suffix(4))
        }
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return String(key.prefix(4)) + "••••••••" + String(key.suffix(4))
    }

    /// 输入检查不通过时的提示；可以提交时返回 nil。
    public static func inputProblem(_ input: ProLicenseInput) -> String? {
        switch input {
        case .empty: emptyInput
        case .malformedGift: malformedGift
        case .siblingGift: siblingGift
        case .gift, .licenseKey: nil
        }
    }

    /// 把中转服务的英文错误翻成中文。
    public static func message(error: String?, status: String?) -> String {
        let text = (error ?? "").lowercased()
        if text.contains("activation limit") {
            return tr("这个许可证的激活次数已用完。请先在旧 Mac 的 设置 ▸ 码头 Pro 里“解绑本机”，再来激活。")
        }
        if text.contains("not found") || text.contains("invalid") {
            return tr("许可证密钥或兑换码不正确，请检查是否完整复制。")
        }
        if text.contains("disabled") || status == "disabled" {
            return tr("这个许可证已被停用。")
        }
        if text.contains("expired") || status == "expired" {
            return tr("这个许可证已过期。")
        }
        if text.contains("too many") {
            return tr("请求太频繁，请稍后再试。")
        }
        if text.contains("misconfigured") || text.contains("upstream") || text.contains("not configured") {
            return tr("授权服务器暂时不可用，请稍后再试。")
        }
        if let error, !error.isEmpty {
            return tr("授权失败：\(error)")
        }
        return tr("授权失败，请稍后再试。")
    }
}
