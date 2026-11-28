import Darwin
import Foundation
import Network

/// Native Messaging hosts can reach this socket inside the current macOS user's temporary directory.
@MainActor
final class TimeInsightsChromiumBridge: TimeInsightsBrowserBridge {
    struct Report: Decodable {
        let browser: String
        let sender: UUID
        let status: String
        let lease: UUID?
        let observed: Double?
        let domain: String?
    }

    private struct Presence {
        var status: BrowserBridgeState
        var lastSeen: Date
    }

    private struct Reading {
        let sender: UUID
        let seen: Date
        let tab: BrowserTabSample?
    }

    static let expiry: TimeInterval = 2.5
    private var listener: NWListener?
    private var presence: [String: Presence] = [:]
    private var reading: Reading?
    private var eligibleBrowser: String?
    private var lease = UUID()
    var onRequest: ((Report) -> UUID?)?

    var state: BrowserBridgeState {
        guard let eligibleBrowser else { return .notConnected }
        return state(for: eligibleBrowser, now: .now)
    }

    func state(for bundleID: String, now: Date) -> BrowserBridgeState {
        guard let presence = presence[bundleID] else { return .notConnected }
        return now.timeIntervalSince(presence.lastSeen) > Self.expiry ? .offline : presence.status
    }

    func currentTab(for bundleID: String) -> BrowserTabSample? {
        guard bundleID == eligibleBrowser, let reading,
              Date.now.timeIntervalSince(reading.seen) <= Self.expiry else { return nil }
        return reading.tab
    }

    func boundary(for bundleID: String, now: Date) -> Date {
        guard bundleID == eligibleBrowser, let reading else { return now }
        return now.timeIntervalSince(reading.seen) > Self.expiry
            ? reading.seen.addingTimeInterval(Self.expiry) : reading.seen
    }

    func authorize(_ bundleID: String?) {
        guard bundleID != eligibleBrowser else { return }
        eligibleBrowser = bundleID
        lease = UUID()
        reading = nil
    }

    func ingest(_ report: Report, now: Date, settings: TimeInsightsSettings, unlocked: Bool) -> UUID? {
        guard TimeInsightsBrowserSamplePolicy.chromiumBrowsers.contains(report.browser) else { return nil }

        switch report.status {
        case "ready":
            presence[report.browser] = Presence(status: .connected, lastSeen: now)
            return eligibleBrowser == report.browser ? lease : nil
        case "permission":
            presence[report.browser] = Presence(status: .permissionRequired, lastSeen: now)
            if reading?.sender == report.sender { reading = nil }
        case "tab", "unfocused":
            guard eligibleBrowser == report.browser, report.lease == lease,
                  let observed = report.observed, observed.isFinite else { return nil }
            let captured = Date(timeIntervalSince1970: observed / 1000)
            guard captured <= now, now.timeIntervalSince(captured) <= Self.expiry,
                  captured >= (reading?.seen ?? .distantPast) else { return nil }
            if report.status == "unfocused", reading?.sender != report.sender { return nil }
            let tab = (report.status == "tab" ? report.domain : nil).flatMap {
                TimeInsightsBrowserSamplePolicy.acceptDomain(
                    $0, browserBundleID: report.browser, foregroundBundleID: eligibleBrowser,
                    capturedAt: captured, now: now, settings: settings, unlocked: unlocked
                )
            }
            reading = Reading(sender: report.sender, seen: captured, tab: tab)
        default:
            break
        }
        return nil
    }

    func start() {
        guard listener == nil else { return }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com.docket-zh.time-insights")
        let socket = directory.appendingPathComponent("host.sock")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))?.isDirectory == true,
                  (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { return }
        }
        if FileManager.default.fileExists(atPath: socket.path) {
            try? FileManager.default.removeItem(at: socket)
        }
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .unix(path: socket.path)
        guard let server = try? NWListener(using: parameters) else { return }
        server.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                connection.start(queue: .main)
                self.receive(connection, prefix: Data())
            }
        }
        server.start(queue: .main)
        listener = server
    }

    private func receive(_ connection: NWConnection, prefix: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] chunk, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, let chunk, error == nil, prefix.count + chunk.count <= 2048 else {
                    connection.cancel()
                    return
                }
                let data = prefix + chunk
                if let newline = data.firstIndex(of: 10) {
                    let report = try? JSONDecoder().decode(Report.self, from: data.prefix(upTo: newline))
                    let grant = report.flatMap { self.onRequest?($0) }
                    let response = (grant?.uuidString ?? "-") + "\n"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                } else if complete {
                    connection.cancel()
                } else {
                    self.receive(connection, prefix: data)
                }
            }
        }
    }
}
