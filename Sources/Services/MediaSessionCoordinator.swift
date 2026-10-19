import AppKit
import Foundation
@preconcurrency import MediaPlayer

/// 系统只有一个正在播放的会话。先暂停旧源再接管，旧源的延迟回调不能覆盖新源。
@MainActor
final class MediaSessionCoordinator {
    static let shared = MediaSessionCoordinator()
    private var ownership = MediaSessionOwnership()
    private var handlers: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var controls: (@MainActor (MediaCommand, Double?) -> Void)?
    private init() {}

    func begin(_ source: MediaSource, controls: @escaping @MainActor (MediaCommand, Double?) -> Void) {
        for other in MediaSessionRules.preempted(by: source) {
            switch other {
            case .radio: RadioPlayer.shared.pause()
            case .podcast: PodcastPlayer.shared.pause()
            case .ambient: AmbientPlayer.shared.pause(immediate: true)
            }
        }
        clear()
        ownership.begin(source)
        self.controls = controls
        let token = ownership.generation
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MediaCommand, MPRemoteCommand)] = [
            (.play, center.playCommand), (.pause, center.pauseCommand),
            (.toggle, center.togglePlayPauseCommand), (.stop, center.stopCommand),
            (.next, center.nextTrackCommand), (.previous, center.previousTrackCommand),
            (.forward, center.skipForwardCommand), (.backward, center.skipBackwardCommand),
            (.seek, center.changePlaybackPositionCommand),
        ]
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.preferredIntervals = [15]
        for (kind, command) in commands {
            command.isEnabled = MediaSessionRules.supports(kind, source: source)
            guard command.isEnabled else { continue }
            let handler = Self.handler { [weak self] position in
                Task { @MainActor in
                    guard let self, self.ownership.accepts(token) else { return }
                    self.controls?(kind, position)
                }
            }
            handlers.append((command, command.addTarget(handler: handler)))
        }
    }

    /// 回调可能来自系统线程，不能继承主 actor 的运行时断言。
    private nonisolated static func handler(_ perform: @escaping @Sendable (Double?) -> Void)
        -> @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { event in
            perform((event as? MPChangePlaybackPositionCommandEvent)?.positionTime)
            return .success
        }
    }

    func update(_ source: MediaSource, title: String, subtitle: String, playing: Bool,
                duration: Double? = nil, position: Double? = nil, imageURL: URL? = nil) {
        guard ownership.source == source else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: title,
                                   MPMediaItemPropertyArtist: subtitle,
                                   MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
                                   MPNowPlayingInfoPropertyIsLiveStream: source == .radio]
        if let duration, duration.isFinite, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let position, position.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, position) }
        if imageURL != artworkURL {
            artworkTask?.cancel()
            artworkURL = imageURL
            artwork = nil
            if let imageURL { loadArtwork(imageURL) }
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
    }

    func end(_ source: MediaSource) {
        guard ownership.source == source else { return }
        clear()
    }

    private func clear() {
        ownership.clear()
        controls = nil
        for (command, handler) in handlers {
            command.removeTarget(handler)
            command.isEnabled = false
        }
        handlers = []
        artworkTask?.cancel()
        artworkTask = nil
        artworkURL = nil
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func loadArtwork(_ url: URL) {
        let token = ownership.generation
        artworkTask = Task { [weak self] in
            let request = URLRequest(url: url, timeoutInterval: 12)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !Task.isCancelled, data.count <= 8_000_000,
                  let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
                  let self, self.ownership.accepts(token), self.artworkURL == url else { return }
            let box = MediaArtworkImage(image)
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in box.image }
            self.artwork = art
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = art
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}

/// 系统可在后台请求封面，创建后不再修改图片。
private final class MediaArtworkImage: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image }
}
