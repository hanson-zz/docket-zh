import Foundation
import Security

/// OpenAI 兼容的 /chat/completions 流式请求。
///
/// 回答一段一段交出来（`AsyncThrowingStream`），出错时抛 `AIChatFailure`。
/// 停止生成就是取消读这个流的任务，底下的网络请求跟着取消。请求和回答
/// 都不写日志；密钥只在 Authorization 头里。
enum AIChatClient {
    /// 60 秒没有任何回应就算超时（`timeoutIntervalForRequest` 是两次收到
    /// 数据之间的最长等待）。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = AIChatRequest.timeout
        configuration.timeoutIntervalForResource = 10 * 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func stream(_ request: URLRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? 200
                    guard (200 ..< 300).contains(status) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 16_384 { break }
                        }
                        throw AIChatFailure.http(status: status, body: body)
                    }
                    let type = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                    var gotText = false
                    if type.contains("application/json") {
                        // 不支持流式的接口一次回整段 JSON。
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        guard let reply = AISSEParser.completeReply(body) else {
                            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                            if let message = object.flatMap(AIChatFailure.errorMessage(in:)) {
                                throw AIChatFailure.stream(message)
                            }
                            throw AIChatFailure.emptyReply
                        }
                        continuation.yield(reply)
                        continuation.finish()
                        return
                    }
                    var parser = AISSEParser()
                    var line = Data()
                    func handle(_ events: [AISSEEvent]) throws -> Bool {
                        for event in events {
                            switch event {
                            case .delta(let text):
                                gotText = true
                                continuation.yield(text)
                            case .done:
                                return true
                            case .failure(let message):
                                throw AIChatFailure.stream(message)
                            }
                        }
                        return false
                    }
                    var finished = false
                    for try await byte in bytes {
                        if byte == 0x0A {
                            let text = String(decoding: line, as: UTF8.self)
                            line.removeAll(keepingCapacity: true)
                            if try handle(parser.feed(line: text)) { finished = true; break }
                        } else {
                            line.append(byte)
                        }
                    }
                    if !finished {
                        if !line.isEmpty { _ = try handle(parser.feed(line: String(decoding: line, as: UTF8.self))) }
                        _ = try handle(parser.finish())
                    }
                    if !gotText { throw AIChatFailure.emptyReply }
                    continuation.finish()
                } catch let failure as AIChatFailure {
                    continuation.finish(throwing: failure)
                } catch let error as URLError {
                    if let failure = AIChatFailure.network(code: error.code.rawValue) {
                        continuation.finish(throwing: failure)
                    } else {
                        continuation.finish(throwing: CancellationError())
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    let ns = error as NSError
                    if ns.domain == NSURLErrorDomain, let failure = AIChatFailure.network(code: ns.code) {
                        continuation.finish(throwing: failure)
                    } else if ns.domain == NSURLErrorDomain {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish(throwing: AIChatFailure.other(ns.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension AIChatClient {
    /// 测试连接：发一个最小的流式请求（问题只有「hi」），一拿到回应的状态码
    /// 就断开，不等回答，所以几乎不花额度。2xx 和 429 算通过（见 `AIAPISetup.verdict`）。
    static func check(endpoint: AIEndpoint, key: String) async -> AIAPISetup.Verdict {
        let ping = [AIChatMessage(role: .user, text: "hi")]
        guard var request = AIChatRequest.urlRequest(endpoint: endpoint, key: key, history: ping) else {
            return AIAPISetup.verdict(failure: .badURL)
        }
        request.timeoutInterval = 20
        do {
            let (bytes, response) = try await checkSession.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if (200 ..< 300).contains(status) {
                bytes.task.cancel()
                return .ok
            }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 16_384 { break }
            }
            return AIAPISetup.verdict(failure: AIChatFailure.http(status: status, body: body))
        } catch let error as URLError {
            return AIAPISetup.verdict(failure: AIChatFailure.network(code: error.code.rawValue) ?? .timeout)
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, let failure = AIChatFailure.network(code: ns.code) {
                return AIAPISetup.verdict(failure: failure)
            }
            return AIAPISetup.verdict(failure: .other(ns.localizedDescription))
        }
    }

    private static let checkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}

/// 每个服务的 API 密钥，存在登录钥匙串里（kSecClassGenericPassword），
/// service 是 bundle id 加服务 id。绝不写进 UserDefaults、状态文件或日志。
///
/// “有没有密钥”只读属性不读内容，不会触发钥匙串的授权弹窗；真正发请求
/// 时才读内容。内容每个服务每次运行最多读一次，之后用内存里的（码头是 ad-hoc
/// 签名，每次更新后读旧项都会弹授权框）；用户点了拒绝也记住，这次运行不再读，
/// 重新保存密钥会覆盖。
@MainActor
enum AIKeyStore {
    private static var known: [String: Bool] = [:]
    private static var values = KeychainReadCache()

    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.docket-zh.app" }

    private static func query(_ serviceID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AIKeyNaming.service(bundleID: bundleID, serviceID: serviceID),
            kSecAttrAccount as String: AIKeyNaming.account,
        ]
    }

    static func hasKey(_ serviceID: String) -> Bool {
        if let read = values.cached(serviceID) { return read.exists }
        if let cached = known[serviceID] { return cached }
        var lookup = query(serviceID)
        lookup[kSecReturnAttributes as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let found = SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess
        known[serviceID] = found
        return found
    }

    static func read(_ serviceID: String) -> String? {
        let read = values.read(serviceID) {
            var lookup = query(serviceID)
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &result)
            return KeychainRead.classify(status: status, data: result as? Data)
        }
        guard let key = read.value?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func write(_ key: String, for serviceID: String) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        // 和这次运行读到的一样就不再碰钥匙串。
        guard values.needsWrite(value, for: serviceID) else { return true }
        let data = Data(value.utf8)
        let match = query(serviceID)
        var status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel as String] = tr("码头 AI 助手密钥（\(serviceID)）")
            status = SecItemAdd(add as CFDictionary, nil)
        }
        values.wrote(value, for: serviceID, succeeded: status == errSecSuccess)
        known[serviceID] = nil
        changed()
        return status == errSecSuccess
    }

    static func delete(_ serviceID: String) {
        SecItemDelete(query(serviceID) as CFDictionary)
        values.deleted(serviceID)
        known[serviceID] = nil
        changed()
    }

    /// 告诉对话面板和设置表重新看一眼。
    private static func changed() {
        AIChatCenter.shared.keysChanged()
    }
}
