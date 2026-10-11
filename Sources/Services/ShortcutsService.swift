import Foundation
import Observation

/// Runs `/usr/bin/shortcuts`, which is how a shortcut is listed and fired
/// without any consent of our own.
///
/// The tool ships with macOS 26 and offers `run`, `list`, `view` and `sign`,
/// and listing costs no TCC prompt. What a *shortcut* then does may well need
/// consent, but that is the shortcut's own business with the system, not
/// something this app can grant or inherit.
///
/// This is the first place in the app that reads a child process's output.
/// `DockStrut` runs `killall` and discards everything, which works only
/// because killall has nothing worth hearing. The two things that costs us,
/// the pipe deadlock and the orphan a timeout leaves behind, are handled in
/// `Tool` below rather than discovered later.
@MainActor @Observable
final class ShortcutsService {
    static let shared = ShortcutsService()

    /// Names as the tool last reported them.
    private(set) var names: [String] = []

    /// `nil` until a load has finished, which is what separates "not asked
    /// yet" from "asked, and there are none". A panel says something
    /// different for each and would be guessing without this.
    private(set) var loadedAt: Date?

    /// Set when listing failed outright, as opposed to succeeding with
    /// nothing to report.
    private(set) var loadError: String?

    /// The shortcut currently running, so a tile can offer to stop it rather
    /// than appear to have frozen.
    private(set) var running: String?

    private(set) var lastRun: Outcome?

    @ObservationIgnored private var loading = false
    @ObservationIgnored private let child = ProcessBox()

    private init() {}

    enum Outcome: Equatable, Sendable {
        case ok(String)
        case failed(String, String)
        case cancelled(String)
    }

    /// Re-reads the shortcut list. Cheap enough to call whenever a panel
    /// opens: the tool answered in 15ms on the machine this was written on.
    func load() async {
        guard !loading else { return }
        loading = true
        let result = await Tool.offMain { Tool.capture(["list"], seconds: 5) }
        loading = false
        loadedAt = .now
        guard result.status == 0 else {
            loadError = Tool.message(result) ?? "“快捷指令”命令行工具没有响应。"
            return
        }
        loadError = nil
        names = ShortcutList.parse(result.out)
    }

    /// Fires a shortcut.
    ///
    /// Deliberately not routed through `withTimeout` or `PollGate`. Those
    /// exist to stop a *poll* stacking up behind a hung script; this is a
    /// thing a person just clicked, and making it wait out a poll interval
    /// would make the shelf feel broken. It gets a long ceiling instead,
    /// because a shortcut that takes a minute is doing its job.
    func run(_ name: String) {
        guard !name.isEmpty, running == nil else { return }
        running = name
        lastRun = nil
        let box = child
        Task {
            let result = await Tool.offMain { Tool.capture(["run", name], seconds: 300, box: box) }
            running = nil
            if result.signalled {
                lastRun = .cancelled(name)
            } else if result.status == 0 {
                lastRun = .ok(name)
            } else {
                // The tool puts its reason on stderr and nowhere else, and a
                // renamed shortcut is the common case: "Couldn't find
                // shortcut". Showing it is what makes that recoverable
                // instead of a tile that quietly stopped working.
                lastRun = .failed(name, Tool.message(result) ?? "快捷指令未能完成。")
            }
        }
    }

    /// Stops the running shortcut. The tool exits on the signal and `run`
    /// reports it as cancelled rather than as a failure.
    func stop() { child.terminate() }
}

/// Everything that touches the process, kept out of the main actor so the
/// blocking parts cannot be called from it by accident. Same shape as
/// `MusicService`'s `Bridge`.
private enum Tool {
    static let path = "/usr/bin/shortcuts"

    static let queue = DispatchQueue(label: "com.namanparashar.plinth.shortcuts")

    static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    struct Result: Sendable {
        var status: Int32
        var signalled: Bool
        var out: String
        var err: String
    }

    /// The first line of stderr, which is where the tool puts its reason.
    static func message(_ result: Result) -> String? {
        let line = result.err
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        // "Error: The operation couldn't be completed. Couldn't find
        // shortcut" reads better in a panel without the prefix.
        return line.hasPrefix("Error: ") ? String(line.dropFirst(7)) : line
    }

    static func capture(_ arguments: [String], seconds: Double,
                        box: ProcessBox? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // Arguments go to the child as argv, so a shortcut named with a
        // quote or a semicolon is passed through intact. There is no shell
        // here and there must never be one.
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return Result(status: -1, signalled: false, out: "",
                          err: "无法启动 \(path)：\(error.localizedDescription)")
        }
        box?.hold(process)

        // `withTimeout` is the app's usual guard and it is the wrong tool
        // here: it abandons its work rather than cancelling it, and work
        // abandoned by this function is a live child still holding a pipe
        // open. Terminating the process is the only thing that ends it.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: watchdog)

        // Both pipes drained at once, each on its own thread. Reading one to
        // the end while the other fills its buffer is the standard pipe
        // deadlock: the child blocks writing to the pipe nobody is reading,
        // so the pipe being read never reaches its end and the wait below
        // never returns.
        let stdout = DataBox(), stderr = DataBox()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            stdout.value = out.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global().async(group: group) {
            stderr.value = err.fileHandleForReading.readDataToEndOfFile()
        }
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()
        box?.hold(nil)

        return Result(status: process.terminationStatus,
                      signalled: process.terminationReason == .uncaughtSignal,
                      out: String(decoding: stdout.value, as: UTF8.self),
                      err: String(decoding: stderr.value, as: UTF8.self))
    }
}

/// Carries a running child across threads so a stop can reach it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func hold(_ process: Process?) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
    }

    func terminate() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { process.terminate() }
    }
}

/// One pipe's bytes, written by exactly one reader and read only after the
/// group it belongs to has finished, which is what makes the unchecked
/// conformance true rather than merely convenient.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}
