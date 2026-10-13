import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import EventKit
import Foundation

// The three things 灵动提示 listens to. Each one only reads; none of them
// intercepts a key or replaces the system's own volume and brightness OSD.

// MARK: - System volume

/// The default output's volume and mute, through Core Audio property
/// listeners rather than a poll, so the capsule moves with the key press.
///
/// Follows the default output: when it changes, the listeners move to the
/// new device and the next reading becomes the new baseline instead of a
/// change worth showing.
@MainActor
final class SystemVolumeWatcher {
    typealias Handler = @MainActor (_ level: Double, _ muted: Bool, _ deviceChanged: Bool) -> Void

    private var handler: Handler?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var watched: [AudioObjectPropertyAddress] = []

    var isRunning: Bool { handler != nil }

    func start(_ handler: @escaping Handler) {
        guard self.handler == nil else { return }
        self.handler = handler
        var address = CoreAudioReader.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block = Self.block { [weak self] in self?.deviceDidChange() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            deviceListener = block
        }
        attach(to: CoreAudioReader.defaultOutput())
        report(deviceChanged: true)
    }

    func stop() {
        detach()
        if let deviceListener {
            var address = CoreAudioReader.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        }
        deviceListener = nil
        handler = nil
    }

    /// The current reading, or nil for an output with no volume (HDMI, most
    /// digital outputs), which then never shows a capsule.
    func read() -> (level: Double, muted: Bool)? {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        let level = Self.float(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            ?? Self.float(device, kAudioDevicePropertyVolumeScalar)
        guard let level else { return nil }
        let muted = (Self.uint(device, kAudioDevicePropertyMute) ?? 0) != 0
        return (Double(level), muted)
    }

    private func deviceDidChange() {
        detach()
        attach(to: CoreAudioReader.defaultOutput())
        report(deviceChanged: true)
    }

    private func attach(to output: AudioObjectID?) {
        guard let output else { return }
        device = output
        let block = Self.block { [weak self] in self?.report(deviceChanged: false) }
        volumeListener = block
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                         kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var address = Self.outputAddress(selector)
            guard AudioObjectHasProperty(output, &address) else { continue }
            if AudioObjectAddPropertyListenerBlock(output, &address, .main, block) == noErr {
                watched.append(address)
            }
        }
    }

    private func detach() {
        if let volumeListener, device != AudioObjectID(kAudioObjectUnknown) {
            for var address in watched {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, volumeListener)
            }
        }
        watched = []
        volumeListener = nil
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func report(deviceChanged: Bool) {
        guard let handler, let reading = read() else { return }
        handler(reading.level, reading.muted, deviceChanged)
    }

    /// Made outside the main actor: a closure formed in a main-actor method
    /// is inferred main-actor isolated, and the HAL calls listeners from its
    /// own queue machinery. Delivered on `.main`, so asserting is honest.
    nonisolated private static func block(_ action: @escaping @MainActor () -> Void) -> AudioObjectPropertyListenerBlock {
        { @Sendable _, _ in
            MainActor.assumeIsolated { action() }
        }
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func float(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float32? {
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}

// MARK: - Display brightness

/// The built-in display's brightness.
///
/// macOS has no public API for it. DisplayServices, a private framework,
/// has a getter that the brightness keys' own path reads; it is opened with
/// dlopen and every use is optional, so on a Mac without it (or without a
/// built-in display) brightness is simply not offered.
enum DisplayBrightness {
    private typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    private static let getter: Getter? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: Getter.self)
    }()

    /// Whether there is a brightness to read on this Mac at all.
    static var isAvailable: Bool { read() != nil }

    static func read() -> Double? {
        guard let getter, let display = builtInDisplay() else { return nil }
        var value: Float = 0
        guard getter(display, &value) == 0, value.isFinite else { return nil }
        return Double(min(1, max(0, value)))
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}

// MARK: - The next meeting

/// The soonest timed event inside the countdown window, read from EventKit.
///
/// Its own store rather than the calendar tile's, which is private to that
/// view; a store costs nothing to make and prompts for nothing until access
/// is requested, which happens only when the countdown is switched on.
@MainActor
enum MeetingSource {
    private static let store = EKEventStore()
    private static var lastStatus = EKEventStore.authorizationStatus(for: .event)

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccessIfNeeded() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        ask(store)
    }

    nonisolated private static func ask(_ store: EKEventStore) {
        store.requestFullAccessToEvents { _, _ in }
    }

    static func next(now: Date, leadMinutes: Int) -> IslandCountdown.Candidate? {
        let status = EKEventStore.authorizationStatus(for: .event)
        // A store made before the grant answers as if it had none until reset.
        if status != lastStatus {
            store.reset()
            lastStatus = status
        }
        guard status == .fullAccess else { return nil }
        let start = now.addingTimeInterval(-60)
        let end = now.addingTimeInterval(Double(max(1, leadMinutes)) * 60 + 1)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).compactMap { event -> IslandCountdown.Candidate? in
            guard let begins = event.startDate else { return nil }
            return IslandCountdown.Candidate(title: event.title ?? "", start: begins, isAllDay: event.isAllDay)
        }
        return IslandCountdown.next(events, now: now, leadMinutes: leadMinutes)
    }
}
