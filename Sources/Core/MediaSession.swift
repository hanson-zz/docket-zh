import Foundation

public enum MediaSource: CaseIterable, Hashable, Sendable {
    case radio, podcast, ambient
}

public enum MediaCommand: CaseIterable, Sendable {
    case play, pause, toggle, stop, next, previous, forward, backward, seek
}

public enum MediaAction: Equatable, Sendable {
    case play, pause, stop, station(Int), position(Double)
}

/// 系统命令和抢占是同一套规则，播放器只执行结果，避免每个播放源各自解释媒体键。
public enum MediaSessionRules {
    public static func preempted(by source: MediaSource) -> [MediaSource] {
        MediaSource.allCases.filter { $0 != source }
    }

    public static func supports(_ command: MediaCommand, source: MediaSource) -> Bool {
        switch command {
        case .play, .pause, .toggle, .stop: true
        case .next, .previous: source != .ambient
        case .forward, .backward, .seek: source == .podcast
        }
    }

    public static func action(_ command: MediaCommand, source: MediaSource, playing: Bool,
                              position: Double = 0, duration: Double = 0,
                              chapters: [PodcastChapter] = [], requestedPosition: Double? = nil) -> MediaAction? {
        guard supports(command, source: source) else { return nil }
        switch command {
        case .play: return .play
        case .pause: return .pause
        case .toggle: return playing ? .pause : .play
        case .stop: return .stop
        case .next, .previous:
            if source == .radio { return .station(command == .next ? 1 : -1) }
            let forward = command == .next
            let starts = chapters.map(\.start).filter { $0.isFinite && $0 >= 0 && (duration <= 0 || $0 < duration) }.sorted()
            let target = forward ? starts.first { $0 > position + 0.5 } : starts.last { $0 < position - 0.5 }
            return .position(PodcastPlayback.skip(target ?? position,
                                                  by: target == nil ? (forward ? 30 : -15) : 0,
                                                  duration: duration))
        case .forward: return .position(PodcastPlayback.skip(position, by: 30, duration: duration))
        case .backward: return .position(PodcastPlayback.skip(position, by: -15, duration: duration))
        case .seek:
            guard let requestedPosition, requestedPosition.isFinite else { return nil }
            return .position(PodcastPlayback.skip(requestedPosition, by: 0, duration: duration))
        }
    }
}

/// 会话代数阻止已经排队的旧媒体键或封面下载结果覆盖新播放源。
public struct MediaSessionOwnership: Sendable {
    public private(set) var source: MediaSource?
    public private(set) var generation = UUID()

    public init() {}

    public mutating func begin(_ source: MediaSource) {
        generation = UUID()
        self.source = source
    }

    @discardableResult
    public mutating func end(_ source: MediaSource) -> Bool {
        guard self.source == source else { return false }
        clear()
        return true
    }

    public mutating func clear() {
        generation = UUID()
        source = nil
    }

    public func accepts(_ generation: UUID) -> Bool {
        source != nil && self.generation == generation
    }
}
