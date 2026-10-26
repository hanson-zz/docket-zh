import Foundation

/// 钥匙串读一次的结果，以及「读过就记住、别再问」的判断。
///
/// 码头还是 ad-hoc 签名，每次更新签名都会变，登录钥匙串里旧项的访问控制不认新版本，
/// 读的时候 macOS 会弹「码头想要使用你储存在钥匙串的…」。所以每个钥匙串项每次运行
/// 只读一次，结果放在内存里；用户点了「拒绝」或读不出来，这次运行也不再去读，免得反复弹。
/// 钥匙串调用本身在 Services 里（ProLicenseService、AIChatClient、KeychainStore）。
public enum KeychainRead: Equatable, Sendable {
    case found(String)
    /// 钥匙串里没有这一项（errSecItemNotFound）。
    case missing
    /// 读失败：用户点了拒绝（errSecAuthFailed、errSecUserCanceled）、不允许交互
    /// （errSecInteractionNotAllowed）等。用户拒绝的这次运行不再重试；不允许交互
    /// 是暂时的（见 `isTransient`），下次用到时再读。
    case failed(Int32)

    /// errSecSuccess
    public static let statusSuccess: Int32 = 0
    /// errSecItemNotFound
    public static let statusItemNotFound: Int32 = -25300
    /// errSecInteractionNotAllowed：钥匙串锁着、又不能弹框（锁屏、登录时钥匙串还没解锁、
    /// 没有图形会话）。不是用户点了拒绝，系统根本没问，过一会儿再读通常就好了。
    public static let statusInteractionNotAllowed: Int32 = -25308

    /// 由 SecItemCopyMatching 的返回码和读出来的数据归类。成功但数据不是 UTF-8 文字时当失败。
    public static func classify(status: Int32, data: Data?) -> KeychainRead {
        switch status {
        case statusSuccess:
            guard let data, let text = String(data: data, encoding: .utf8) else { return .failed(status) }
            return .found(text)
        case statusItemNotFound:
            return .missing
        default:
            return .failed(status)
        }
    }

    public var value: String? {
        if case .found(let text) = self { return text }
        return nil
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// 暂时读不了（钥匙串锁着、不能弹框），不是用户拒绝：不记住，下次用到时再读，
    /// 不会多弹框（这种情况系统本来就不弹）。以前也记住，锁屏时自动重启的码头整次
    /// 运行都读不到授权，已购用户一直显示未激活、Pro 功能被锁，直到手动重启。
    public var isTransient: Bool {
        if case .failed(let status) = self { return status == Self.statusInteractionNotAllowed }
        return false
    }

    /// 钥匙串项是否存在（读失败时算存在，只是读不到）。
    public var exists: Bool {
        if case .missing = self { return false }
        return true
    }
}

/// 一组按名字存的秘密（AI 密钥、GitHub 令牌）的内存缓存：每个名字每次运行最多读一次钥匙串。
public struct KeychainReadCache: Equatable, Sendable {
    private var reads: [String: KeychainRead] = [:]

    public init() {}

    /// 读过（不论结果）就返回记住的结果；没读过时调 `load` 读一次并记住。
    /// 失败也记住，这次运行不再弹第二次；暂时读不了的（`isTransient`）不记，下次再读。
    public mutating func read(_ name: String, load: () -> KeychainRead) -> KeychainRead {
        if let known = reads[name] { return known }
        let result = load()
        if !result.isTransient { reads[name] = result }
        return result
    }

    public func cached(_ name: String) -> KeychainRead? { reads[name] }

    /// 写成功后记下新值；写失败时不动原来记住的结果。
    public mutating func wrote(_ value: String, for name: String, succeeded: Bool) {
        guard succeeded else { return }
        reads[name] = .found(value)
    }

    /// 删掉以后记成没有。
    public mutating func deleted(_ name: String) {
        reads[name] = .missing
    }

    /// 写之前要不要真的写：值没变（并且确实读到过）就不写，免得多一次钥匙串访问。
    public func needsWrite(_ value: String, for name: String) -> Bool {
        reads[name] != .found(value)
    }
}

// MARK: - 码头 Pro 授权

/// 授权的四样东西合成一个钥匙串项，内容是这段 JSON。
public struct ProLicenseRecord: Codable, Equatable, Sendable {
    public var version: Int
    public var licenseKey: String?
    public var instanceID: String?
    /// 1970 年起的秒数，和旧版单独存的写法一样。
    public var lastValidated: Double?
    public var trialStart: Double?

    public init(_ snapshot: ProLicenseSnapshot) {
        version = 1
        licenseKey = snapshot.licenseKey
        instanceID = snapshot.instanceID
        lastValidated = snapshot.lastValidated?.timeIntervalSince1970
        trialStart = snapshot.trialStart?.timeIntervalSince1970
    }

    public var snapshot: ProLicenseSnapshot {
        ProLicenseSnapshot(licenseKey: licenseKey.flatMap { $0.isEmpty ? nil : $0 },
                           instanceID: instanceID.flatMap { $0.isEmpty ? nil : $0 },
                           lastValidated: lastValidated.map(Date.init(timeIntervalSince1970:)),
                           trialStart: trialStart.map(Date.init(timeIntervalSince1970:)))
    }

    public static func encode(_ snapshot: ProLicenseSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ProLicenseRecord(snapshot)),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// 读不懂（不是 JSON、不是对象）返回 nil。
    public static func decode(_ text: String) -> ProLicenseSnapshot? {
        guard let record = try? JSONDecoder().decode(ProLicenseRecord.self, from: Data(text.utf8)) else { return nil }
        return record.snapshot
    }
}

/// 旧版分开存的四个钥匙串项（account 名就是 rawValue）。
public enum ProLicenseLegacyField: String, CaseIterable, Sendable {
    case licenseKey
    case instanceID
    case lastValidated
    case trialStart
}

/// 启动时读授权的结果：用什么、要不要写新项、要不要删旧项。
public struct ProLicenseLoad: Equatable, Sendable {
    public var snapshot: ProLicenseSnapshot
    /// 内存里的值是不是钥匙串里的完整真相。读失败（用户点了拒绝）时为 false：
    /// 不能据此开始试用，写的时候也不能把读不到的试用时间当成没开始过。
    public var trusted: Bool
    /// 要把 snapshot 写进新的合并项（从旧项迁移过来）。
    public var writeRecord: Bool
    /// 写成功后删掉旧的四个项。
    public var deleteLegacy: Bool
    /// 读失败全是暂时的（钥匙串锁着、不能弹框，见 `KeychainRead.isTransient`）：
    /// 这次结果不要记住，下次用到时再读一遍。有一项是用户点了拒绝就为 false，免得再弹。
    public var retryLater: Bool

    public init(snapshot: ProLicenseSnapshot, trusted: Bool, writeRecord: Bool, deleteLegacy: Bool,
                retryLater: Bool = false) {
        self.snapshot = snapshot
        self.trusted = trusted
        self.writeRecord = writeRecord
        self.deleteLegacy = deleteLegacy
        self.retryLater = retryLater
    }
}

/// 合并项的读取、旧项迁移和写入判断。
public enum ProLicenseStorePlan {
    /// 由合并项的读取结果决定怎么办。只有合并项不存在（或内容读不懂）时才调 `legacy`
    /// 去读旧的四项，每项最多读一次。
    public static func load(record: KeychainRead,
                            legacy: () -> [ProLicenseLegacyField: KeychainRead]) -> ProLicenseLoad {
        switch record {
        case .found(let text):
            if let snapshot = ProLicenseRecord.decode(text) {
                return ProLicenseLoad(snapshot: snapshot, trusted: true, writeRecord: false, deleteLegacy: false)
            }
            // 内容坏了：看看旧项还在不在，在就迁过来覆盖。
            return migrate(legacy())
        case .failed:
            // 用户拒绝或读不出：这次运行按读不到处理，不写、不删、不重试；
            // 只是钥匙串暂时锁着的，下次用到时再读。
            return ProLicenseLoad(snapshot: ProLicenseSnapshot(), trusted: false, writeRecord: false, deleteLegacy: false,
                                  retryLater: record.isTransient)
        case .missing:
            return migrate(legacy())
        }
    }

    static func migrate(_ reads: [ProLicenseLegacyField: KeychainRead]) -> ProLicenseLoad {
        func text(_ field: ProLicenseLegacyField) -> String? {
            guard let value = reads[field]?.value, !value.isEmpty else { return nil }
            return value
        }
        func date(_ field: ProLicenseLegacyField) -> Date? {
            text(field).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        }
        let snapshot = ProLicenseSnapshot(licenseKey: text(.licenseKey), instanceID: text(.instanceID),
                                          lastValidated: date(.lastValidated), trialStart: date(.trialStart))
        let anyFailed = reads.values.contains { $0.isFailed }
        let anyExists = reads.values.contains { $0.exists }
        if anyFailed {
            // 有旧项读不到：不写新项（写了下次就不再读旧项，读不到的那项就永远丢了），
            // 也不删旧项，下次启动再迁。只有暂时读不了、又一项都没读出来时（钥匙串整个锁着）
            // 才下次用到时再试：读出过的项可能是用户点「允许」放行的，重读会再弹。
            let retry = reads.values.allSatisfy { $0.isTransient || $0 == .missing }
            return ProLicenseLoad(snapshot: snapshot, trusted: false, writeRecord: false, deleteLegacy: false,
                                  retryLater: retry)
        }
        // 全新安装：什么都没有，什么都不用写。
        guard anyExists else {
            return ProLicenseLoad(snapshot: snapshot, trusted: true, writeRecord: false, deleteLegacy: false)
        }
        return ProLicenseLoad(snapshot: snapshot, trusted: true, writeRecord: true, deleteLegacy: true)
    }

    /// 要写进钥匙串的值。没读到完整真相时，试用开始时间不能写成「没开始过」，
    /// 否则用户点一次拒绝就能把试用期重置：写成很久以前，表示试用已用掉。
    public static func prepared(_ snapshot: ProLicenseSnapshot, trusted: Bool) -> ProLicenseSnapshot {
        guard !trusted, snapshot.trialStart == nil else { return snapshot }
        var safe = snapshot
        safe.trialStart = consumedTrialStart
        return safe
    }

    /// 「试用已经用掉」的占位时间。
    public static let consumedTrialStart = Date(timeIntervalSince1970: 0)

    /// 值真的变了才写。
    public static func needsWrite(current: ProLicenseSnapshot, next: ProLicenseSnapshot) -> Bool {
        current != next
    }

    /// 能不能开始试用：读不到完整真相时不让开始（可能早就开始过）。
    public static func canStartTrial(_ snapshot: ProLicenseSnapshot, trusted: Bool) -> Bool {
        trusted && ProLicenseLogic.canStartTrial(snapshot)
    }
}
