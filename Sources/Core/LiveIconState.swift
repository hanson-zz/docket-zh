import Foundation

/// A normalized status shared by live icon data providers and renderers.
public enum LiveIconState: Equatable, Sendable {
    case idle
    case running(progress: Double?)
    case completed
    case attention

    /// Progress is never allowed to produce an invalid ring or layout.
    public var normalizedProgress: Double? {
        guard case let .running(progress?) = self, progress.isFinite else { return nil }
        return min(1, max(0, progress))
    }

    public var isActive: Bool {
        if case .running = self { return true }
        return false
    }
}

/// A display policy separate from data collection and animation implementation.
public struct LiveIconPolicy: Equatable, Sendable {
    public var enabled: Bool
    public var reduceMotion: Bool
    public var lowPowerMode: Bool

    public init(enabled: Bool = true, reduceMotion: Bool = false, lowPowerMode: Bool = false) {
        self.enabled = enabled
        self.reduceMotion = reduceMotion
        self.lowPowerMode = lowPowerMode
    }

    public func presentation(for state: LiveIconState) -> LiveIconPresentation {
        guard enabled else { return .staticIcon }
        switch state {
        case .idle:
            return .staticIcon
        case .running:
            return reduceMotion || lowPowerMode ? .staticProgress : .animatedProgress
        case .completed:
            return .completionMark
        case .attention:
            return .attentionMark
        }
    }
}

/// The view decides how each presentation looks, without changing the data model.
public enum LiveIconPresentation: Equatable, Sendable {
    case staticIcon
    case staticProgress
    case animatedProgress
    case completionMark
    case attentionMark
}
