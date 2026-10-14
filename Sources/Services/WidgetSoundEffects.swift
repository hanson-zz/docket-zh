import AppKit
import Foundation

/// The one place a widget being added to or removed from the shelf makes a
/// sound.
///
/// Callers hand over the shelf's list before and after a user's edit and this
/// decides whether that edit added or removed a widget. Launch, layout
/// switching, migrations and every other programmatic rewrite of the list
/// never come through here, so they stay silent by construction.
@MainActor
final class WidgetSoundEffects {
    static let shared = WidgetSoundEffects()

    private var gate = WidgetSoundGate()
    /// Built once per style and event; a WAV this short is a few kilobytes.
    private var cache: [String: NSSound] = [:]

    private init() {}

    /// A user edit changed the shelf from `before` to `after`.
    func shelfChanged(from before: [DockItem], to after: [DockItem], settings: WidgetSoundSettings) {
        guard let event = WidgetSoundDecision.event(before: before, after: after) else { return }
        play(event, settings: settings)
    }

    func play(_ event: WidgetSoundEvent, settings: WidgetSoundSettings) {
        guard WidgetSoundDecision.shouldPlay(settings, systemUISoundsEnabled: Self.systemUISoundsEnabled),
              gate.allow(event, at: .now)
        else { return }
        start(event, settings: settings)
    }

    /// 试听: the add sound, then the remove one. Ignores the switch, so the
    /// sounds can be heard before deciding to turn them on.
    func preview(settings: WidgetSoundSettings) {
        start(.added, settings: settings)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.start(.removed, settings: settings)
        }
    }

    /// The system's "播放用户界面音效" switch in 声音 settings.
    static var systemUISoundsEnabled: Bool {
        WidgetSoundDecision.systemUISoundsEnabled(
            UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled"))
    }

    private func start(_ event: WidgetSoundEvent, settings: WidgetSoundSettings) {
        guard let sound = sound(event, style: settings.style) else { return }
        if sound.isPlaying { sound.stop() }
        sound.volume = settings.gain
        sound.play()
    }

    private func sound(_ event: WidgetSoundEvent, style: WidgetSoundStyle) -> NSSound? {
        let key = "\(style.rawValue).\(event.rawValue)"
        if let cached = cache[key] { return cached }
        let made: NSSound?
        switch style {
        case .dockling:
            made = NSSound(data: WidgetSoundSynth.wav(WidgetSoundSynth.render(event)))
        case .system:
            made = Self.systemSound(event)
                ?? NSSound(data: WidgetSoundSynth.wav(WidgetSoundSynth.render(event)))
        }
        if let made { cache[key] = made }
        return made
    }

    /// The Dock's own file when this Mac has one, else a named system alert.
    private static func systemSound(_ event: WidgetSoundEvent) -> NSSound? {
        for path in WidgetSystemSounds.candidates(for: event)
        where FileManager.default.fileExists(atPath: path) {
            if let sound = NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true) {
                return sound
            }
        }
        for name in WidgetSystemSounds.fallbackNames(for: event) {
            // `NSSound(named:)` hands back a shared instance; a copy keeps our
            // volume off whatever else in the process plays that alert.
            if let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound {
                return sound
            }
        }
        return nil
    }
}
