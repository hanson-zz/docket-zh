import AppKit
import Observation

/// 搜索站的图标，从网站自己那里读：先要 `apple-touch-icon.png`（大多是
/// 180 像素，清楚），没有再要 `favicon.ico`。读到的存进缓存目录，下次
/// 启动直接用；读不到的这次运行不再问，面板上画首字。
@MainActor @Observable
final class SiteIconCache {
    static let shared = SiteIconCache()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var asked = Set<String>()

    private init() {}

    /// 图标或 nil（还在读，或读不到）。第一次问某个网站时开始读。
    func icon(for home: URL?) -> NSImage? {
        guard let home, let host = home.host() else { return nil }
        if let image = images[host] { return image }
        guard asked.insert(host).inserted else { return nil }
        // 不在画面更新途中改状态：读缓存和联网都放到下一轮。
        Task { await load(home, host: host) }
        return nil
    }

    private func load(_ home: URL, host: String) async {
        if let url = Self.file(host), let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            images[host] = image
            return
        }
        await fetch(home, host: host)
    }

    private func fetch(_ home: URL, host: String) async {
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            guard let url = URL(string: home.absoluteString + path) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                             forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count > 64, data.count < 2_000_000,
                  let image = NSImage(data: data), image.size.width >= 16 else { continue }
            images[host] = image
            if let file = Self.file(host) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return
        }
    }

    private static func file(_ host: String) -> URL? {
        let safe = host.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        guard !safe.isEmpty else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.docket-zh.app", isDirectory: true)
            .appendingPathComponent("site-icons", isDirectory: true)
            .appendingPathComponent(safe + ".img")
    }
}
