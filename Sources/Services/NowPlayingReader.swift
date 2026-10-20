import AppKit
import Foundation

/// Reads the system's Now Playing for players with no AppleScript, such as
/// 网易云音乐 and QQ 音乐.
///
/// MediaRemote has been entitlement-gated since macOS 15.4 for ordinary
/// apps, but `osascript` is a platform binary that is still allowed to ask,
/// so the question is put through a short JavaScript for Automation script
/// rather than by loading the framework here. Every call is synchronous and
/// bounded; callers are already off the main thread.
enum NowPlayingReader {
    private static let script = """
    function run(argv) {
      ObjC.import('Foundation');
      const bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
      bundle.load;
      const R = $.NSClassFromString('MRNowPlayingRequest');
      if (!R || R.isNil()) return '';
      const item = R.localNowPlayingItem;
      if (!item || item.isNil()) return '';
      const info = item.nowPlayingInfo;
      if (!info || info.isNil()) return '';
      const value = (key) => { const v = info.valueForKey(key); return (!v || v.isNil()) ? null : v; };
      if (argv.length > 0 && argv[0] === 'art') {
        const art = value('kMRMediaRemoteNowPlayingInfoArtworkData');
        return art ? ObjC.unwrap(art.base64EncodedStringWithOptions(0)) : '';
      }
      const text = (key) => { const v = value(key); return v ? ObjC.unwrap(v) : null; };
      const path = R.localNowPlayingPlayerPath;
      const client = (path && !path.isNil()) ? path.client : null;
      const stamp = value('kMRMediaRemoteNowPlayingInfoTimestamp');
      return JSON.stringify({
        id: client ? ObjC.unwrap(client.bundleIdentifier) : null,
        parent: client ? ObjC.unwrap(client.parentApplicationBundleIdentifier) : null,
        title: text('kMRMediaRemoteNowPlayingInfoTitle'),
        artist: text('kMRMediaRemoteNowPlayingInfoArtist'),
        album: text('kMRMediaRemoteNowPlayingInfoAlbum'),
        duration: text('kMRMediaRemoteNowPlayingInfoDuration'),
        elapsed: text('kMRMediaRemoteNowPlayingInfoElapsedTime'),
        rate: text('kMRMediaRemoteNowPlayingInfoPlaybackRate'),
        stamp: stamp ? stamp.timeIntervalSince1970 : null,
        playing: R.localIsPlaying ? true : false
      });
    }
    """

    /// 系统「正在播放」一次读出来；网易云、QQ 音乐、小宇宙各自用 `track(from:source:)`
    /// 对是不是自己，一次轮询只跑一次 osascript。
    static func info() -> NowPlayingInfo? {
        guard let output = run([]) else { return nil }
        return NowPlayingInfo.decode(output)
    }

    static func track(from info: NowPlayingInfo, source: MusicSource) -> NowPlaying? {
        guard let track = info.track(for: source.bundleID, now: .now) else { return nil }
        return NowPlaying(title: track.title, artist: track.artist, album: track.album,
                          duration: track.duration, elapsed: track.elapsed,
                          isPlaying: track.isPlaying, artwork: nil, source: source)
    }

    static func artwork() -> Data? {
        guard let output = run(["art"]) else { return nil }
        return Data(base64Encoded: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `osascript -l JavaScript`, killed after `timeout` seconds.
    private static func run(_ arguments: [String], timeout: TimeInterval = 1.5) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let box = ProcessBox(process)
        let killer = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        // Read before waiting: artwork can be larger than the pipe's buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Lets the timeout's work item hold the process; it only ever terminates it.
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// The keyboard's play/pause, next and previous keys, posted as if pressed.
/// They go to whichever app owns Now Playing, which is the one just read.
/// Posting needs Accessibility; the first press asks for it.
enum MediaKeys {
    enum Key: Int {
        case playPause = 16, next = 17, previous = 18
    }

    static func press(_ key: Key) {
        DispatchQueue.main.async {
            guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
            for down in [true, false] {
                let state = down ? 0xA : 0xB
                let event = NSEvent.otherEvent(
                    with: .systemDefined, location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                    timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                    data1: (key.rawValue << 16) | (state << 8), data2: -1)
                event?.cgEvent?.post(tap: .cghidEventTap)
            }
        }
    }
}
