import Darwin
import Foundation

/// Asks a short-lived `codex app-server` for the account's rate limits.
///
/// Starts the process, sends `initialize`, `initialized` and
/// `account/rateLimits/read` over its stdin, reads the replies from its
/// stdout, and stops it. The whole exchange has a deadline; past it the
/// process is terminated and the caller falls back to the web endpoint.
/// Codex itself signs in and talks to the backend; Docket sees only the
/// answer. The message shapes live in CodexAppServer (Core).
enum CodexAppServerClient {
    static let timeout: TimeInterval = 8

    /// Runs the exchange off the main thread. Answers within the deadline
    /// plus a margin even if a read is stuck (a grandchild holding a pipe
    /// open, say): the stuck thread is left behind, the widget is not.
    static func read(includeExtras: Bool, proxy: CodexProxy?) async -> Result<CodexUsageReport, CodexAppServer.Failure> {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout + 4) {
                once.resume(.failure(.timedOut))
            }
            DispatchQueue.global(qos: .utility).async {
                do {
                    once.resume(.success(try exchange(includeExtras: includeExtras, proxy: proxy)))
                } catch let failure as CodexAppServer.Failure {
                    once.resume(.failure(failure))
                } catch {
                    once.resume(.failure(.unreadable))
                }
            }
        }
    }

    /// Resumes a continuation the first time only.
    private final class Once: @unchecked Sendable {
        typealias Value = Result<CodexUsageReport, CodexAppServer.Failure>
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Never>?

        init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }

        func resume(_ value: Value) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }

    /// Terminates the process once the deadline passes, and remembers that
    /// it did, so an empty read can be told apart from a crash.
    private final class Watchdog: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process
        private var fired = false

        init(_ process: Process) { self.process = process }

        func fire() {
            lock.lock()
            defer { lock.unlock() }
            guard process.isRunning else { return }
            fired = true
            process.terminate()
        }

        var didFire: Bool {
            lock.lock()
            defer { lock.unlock() }
            return fired
        }
    }

    private static func exchange(includeExtras: Bool, proxy: CodexProxy?) throws -> CodexUsageReport {
        // A write to a pipe whose reader has exited would otherwise kill the
        // whole app with SIGPIPE; ignored, it becomes a thrown error.
        signal(SIGPIPE, SIG_IGN)

        let shellPath = LoginShell.path()
        guard let binary = locate(shellPath: shellPath) else { throw CodexAppServer.Failure.noBinary }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = CodexAppServer.childPath(binary: binary, shellPath: shellPath, inherited: env["PATH"])
        env.merge(CodexAppServer.proxyEnvironment(proxy)) { _, new in new }
        process.environment = env
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CodexAppServer.Failure.launchFailed
        }

        let watchdog = Watchdog(process)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { watchdog.fire() }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        let writer = input.fileHandleForWriting
        let reader = output.fileHandleForReading
        do {
            try writer.write(contentsOf: CodexAppServer.initializeRequest(version: version))
        } catch {
            throw CodexAppServer.Failure.exited
        }

        var buffer = Data()
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty {
                throw watchdog.didFire ? CodexAppServer.Failure.timedOut : CodexAppServer.Failure.exited
            }
            buffer.append(chunk)
            for line in CodexAppServer.takeLines(&buffer) {
                switch CodexAppServer.parse(line: line) {
                case .response(let id, _) where id == CodexAppServer.initializeID:
                    do {
                        try writer.write(contentsOf: CodexAppServer.initializedNotification())
                        try writer.write(contentsOf: CodexAppServer.rateLimitsRequest())
                    } catch {
                        throw CodexAppServer.Failure.exited
                    }
                case .response(let id, let result) where id == CodexAppServer.rateLimitsID:
                    do {
                        return try CodexAppServer.report(fromResult: result, includeExtras: includeExtras)
                    } catch {
                        throw CodexAppServer.Failure.unreadable
                    }
                case .error(_, _, let message):
                    throw CodexAppServer.Failure.rpc(message)
                default:
                    continue
                }
            }
        }
    }

    private static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    private static func locate(shellPath: String?) -> String? {
        let fm = FileManager.default
        let candidates = CodexAppServer.candidatePaths(
            home: NSHomeDirectory(), shellPath: shellPath,
            override: ProcessInfo.processInfo.environment["CODEX_BIN"])
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }
}

/// The PATH a Terminal window would have. An app opened from Finder gets only
/// the system folders, which leaves out Homebrew, npm and nvm. Read once per
/// launch, with a short deadline so a slow shell profile can not stall it.
enum LoginShell {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String??

    static func path() -> String? {
        lock.lock()
        if let cached {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let value = read()
        lock.lock()
        cached = .some(value)
        lock.unlock()
        return value
    }

    private static func read() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Markers around the value, because profiles like to print greetings.
        process.arguments = ["-ilc", "printf '__DOCKET_PATH__%s__DOCKET_PATH__' \"$PATH\""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let box = ProcessBox(process)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { box.stop() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.components(separatedBy: "__DOCKET_PATH__")
        guard parts.count >= 3 else { return nil }
        let path = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func stop() { if process.isRunning { process.terminate() } }
    }
}
