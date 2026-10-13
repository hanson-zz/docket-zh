import AppKit
import Observation
import SwiftUI

/// 灵动提示: a capsule at the top centre of the main screen, just under the
/// notch, that shows the volume or brightness for a moment after either
/// changes, and counts down to the next meeting.
///
/// A borderless, non-activating panel at status-bar level that ignores the
/// mouse entirely, so it can never take a click or focus from the app
/// underneath. It only reads levels; the system's own OSD still appears as
/// it always has, because no key is intercepted.
@MainActor
final class IslandController {
    static let shared = IslandController()

    private var settings = IslandSettings()
    private let model = IslandModel()
    private var panel: NSPanel?

    private let volume = SystemVolumeWatcher()
    private var lastVolume: Double?
    private var lastMuted: Bool?

    private var brightnessTimer: Timer?
    private var lastBrightness: Double?

    private var meetingTimer: Timer?

    private var flashGeneration = 0
    private var hideGeneration = 0
    private var screenObserver: NSObjectProtocol?

    private init() {}

    func apply(_ next: IslandSettings) {
        settings = next

        if next.volume {
            volume.start { [weak self] level, muted, deviceChanged in
                self?.volumeChanged(level: level, muted: muted, deviceChanged: deviceChanged)
            }
        } else if volume.isRunning {
            volume.stop()
            lastVolume = nil
            lastMuted = nil
        }

        if next.brightness, DisplayBrightness.isAvailable {
            startBrightness()
        } else {
            brightnessTimer?.invalidate()
            brightnessTimer = nil
            lastBrightness = nil
        }

        if next.meeting {
            MeetingSource.requestAccessIfNeeded()
            startMeeting()
        } else {
            meetingTimer?.invalidate()
            meetingTimer = nil
            model.meeting = nil
        }

        if !next.anyEnabled {
            model.flash = nil
            model.meeting = nil
        }
        sync()
    }

    // MARK: Sources

    private func volumeChanged(level: Double, muted: Bool, deviceChanged: Bool) {
        defer {
            lastVolume = level
            lastMuted = muted
        }
        // A new output reports its own level; that is not the user turning
        // anything, so it only sets the baseline.
        guard !deviceChanged else { return }
        let moved = IslandLevel.changed(from: lastVolume, to: level)
        let toggled = lastMuted.map { $0 != muted } ?? false
        guard moved || toggled else { return }
        flash(.volume(level: level, muted: muted))
    }

    private func startBrightness() {
        guard brightnessTimer == nil else { return }
        lastBrightness = DisplayBrightness.read()
        // Polled: there is no notification for a brightness change. Five
        // reads a second is fast enough to follow a held key and costs one
        // cheap call into WindowServer each.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readBrightness() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        brightnessTimer = timer
    }

    private func readBrightness() {
        guard let level = DisplayBrightness.read() else { return }
        defer { lastBrightness = level }
        guard IslandLevel.changed(from: lastBrightness, to: level, threshold: 0.01) else { return }
        flash(.brightness(level: level))
    }

    private func startMeeting() {
        refreshMeeting()
        guard meetingTimer == nil else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMeeting() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        meetingTimer = timer
    }

    private func refreshMeeting() {
        guard settings.meeting else { return }
        let next = MeetingSource.next(now: .now, leadMinutes: settings.leadMinutes)
        let content = next.map { IslandContent.meeting(title: $0.title, start: $0.start) }
        if content != model.meeting {
            model.meeting = content
            sync()
        }
    }

    // MARK: Showing

    private func flash(_ content: IslandContent) {
        flashGeneration += 1
        let generation = flashGeneration
        model.flash = content
        sync()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(IslandContent.flashDuration))
            guard let self, self.flashGeneration == generation else { return }
            self.model.flash = nil
            self.sync()
        }
    }

    /// Puts the panel up when there is something to show, and takes it down
    /// once the capsule has finished animating away.
    private func sync() {
        if model.content != nil {
            hideGeneration += 1
            let panel = panel ?? makePanel()
            place(panel)
            panel.orderFrontRegardless()
        } else if let panel {
            hideGeneration += 1
            let generation = hideGeneration
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, self.hideGeneration == generation, self.model.content == nil else { return }
                panel.orderOut(nil)
            }
        }
    }

    private static let panelSize = CGSize(width: 440, height: 96)

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: IslandView(model: model))
        host.frame = CGRect(origin: .zero, size: Self.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.place(panel)
            }
        }
        return panel
    }

    /// Top centre of the screen with the menu bar, under the notch when
    /// there is one and under the menu bar when there is not.
    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let notch = screen.safeAreaInsets.top
        let top = notch > 0 ? frame.maxY - notch - 4 : screen.visibleFrame.maxY - 6
        let origin = CGPoint(x: frame.midX - Self.panelSize.width / 2, y: top - Self.panelSize.height)
        panel.setFrame(CGRect(origin: origin, size: Self.panelSize), display: false)
    }
}

/// What the capsule is showing, observed by the SwiftUI view.
@MainActor @Observable
final class IslandModel {
    var flash: IslandContent?
    var meeting: IslandContent?

    var content: IslandContent? { IslandContent.resolve(flash: flash, meeting: meeting) }
}

// MARK: - The capsule

struct IslandView: View {
    var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            if let content = model.content {
                IslandCapsule(content: content)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.55, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.7, anchor: .top).combined(with: .opacity)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: model.content)
    }
}

private struct IslandCapsule: View {
    var content: IslandContent

    var body: some View {
        HStack(spacing: 10) {
            switch content {
            case .volume(let level, let muted):
                levelRow(symbol: IslandLevel.volumeSymbol(level, muted: muted),
                         level: muted ? 0 : level,
                         label: muted ? "静音" : "\(IslandLevel.percent(level))%",
                         name: "音量")
            case .brightness(let level):
                levelRow(symbol: IslandLevel.brightnessSymbol(level), level: level,
                         label: "\(IslandLevel.percent(level))%", name: "亮度")
            case .meeting(let title, let start):
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                        Text(IslandCountdown.line(title: title, secondsUntil: start.timeIntervalSince(tick.date)))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .contentTransition(.numericText())
                    }
                }
                .frame(maxWidth: 360)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background {
            Capsule(style: .continuous)
                .fill(.black)
                .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    private func levelRow(symbol: String, level: Double, label: String, name: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            SegmentBar(lit: IslandLevel.lit(level))
                .frame(width: 128, height: 6)
            Text(label)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .accessibilityLabel(name)
        .accessibilityValue(label)
    }
}

private struct SegmentBar: View {
    var lit: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<IslandLevel.segments, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index < lit ? Color.white : Color.white.opacity(0.18))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: lit)
    }
}
