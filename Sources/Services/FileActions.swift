import AppKit
import UniformTypeIdentifiers

/// The handful of things every file widget does with a file.
@MainActor
enum FileActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// The file itself on the pasteboard, as Finder's Copy puts it there.
    static func copyFile(_ url: URL) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
    }

    /// The picture's pixels and the file both, so it pastes into a chat as an
    /// image and into Finder as a file. Decoded only now, because somebody
    /// asked for it.
    static func copyImage(_ url: URL) {
        let board = NSPasteboard.general
        board.clearContents()
        var objects: [NSPasteboardWriting] = [url as NSURL]
        if let image = NSImage(contentsOf: url) { objects.insert(image, at: 0) }
        board.writeObjects(objects)
    }

    /// What a row hands to a drag, so the file can be dropped anywhere a
    /// Finder file can.
    static func dragProvider(_ url: URL) -> NSItemProvider {
        NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
    }

    /// A folder chosen in the standard open panel.
    ///
    /// An accessory app is never frontmost, so the panel would open behind
    /// whatever is; the same brief promotion to a regular app the shelf uses
    /// for its own alerts brings it forward. Not sandboxed, so the URL is
    /// usable as it is and needs no bookmark.
    static func chooseFolder(title: String, startingAt start: URL?) -> URL? {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.message = title
        panel.prompt = tr("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// "12 KB", "3.4 MB": the byte counts Finder shows.
    static func size(_ bytes: Int64?) -> String? {
        guard let bytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
