import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 拖到卡片上的一样东西：一段文字、一个网页链接或一个文件。
enum DroppedThing: Equatable, Sendable {
    case text(String)
    case link(URL)
    case file(URL)

    /// 当成文字用时的样子：链接写网址，文件写路径。
    var plainText: String {
        switch self {
        case .text(let words): words
        case .link(let url): url.absoluteString
        case .file(let url): url.path
        }
    }
}

/// AI 任意门、书签、便签共用的拖入：拖进来时亮出虚线框（`dropTargetOutline`），
/// 松手后一样样读出来交给卡片。和快速待办的 `TodoDropDelegate` 同一个读法：
/// 先认文件，再认链接，最后当文字读。
@MainActor
struct ContentDropDelegate: DropDelegate {
    var types: [UTType]
    var enabled: Bool
    var targeted: @MainActor (Bool) -> Void
    var receive: @MainActor ([DroppedThing]) -> Void

    /// 一次拖进来很多样时只读前面这些。
    static let maxPerDrop = 20

    func validateDrop(info: DropInfo) -> Bool {
        enabled && info.hasItemsConforming(to: types)
    }

    func dropEntered(info: DropInfo) {
        guard enabled else { return }
        targeted(true)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: enabled ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        targeted(false)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted(false)
        let providers = info.itemProviders(for: types)
        guard enabled, !providers.isEmpty else { return false }
        let receive = self.receive
        let wantsFiles = types.contains(.fileURL)
        Task { @MainActor in
            var things: [DroppedThing] = []
            for provider in providers.prefix(Self.maxPerDrop) {
                if let thing = await Self.load(provider, files: wantsFiles) { things.append(thing) }
            }
            if things.isEmpty {
                NSSound.beep()
            } else {
                receive(things)
            }
        }
        return true
    }

    private static func load(_ provider: NSItemProvider, files: Bool) async -> DroppedThing? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: .fileURL), url.isFileURL {
            return files ? .file(url) : .text(url.path)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: .url) {
            return url.isFileURL ? (files ? .file(url) : .text(url.path)) : .link(url)
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            let text: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    let words = (object as? NSString).map { $0 as String }
                    continuation.resume(returning: words)
                }
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(text) }
        }
        return nil
    }

    private static func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - 三张卡拿到东西之后

/// 拖到 AI 任意门：打开提问面板并把文字带进输入框。
@MainActor
enum AIDropRouter {
    static func ask(_ things: [DroppedThing], instance: WidgetInstance) {
        var texts: [String] = []
        var files: [AIDrop.File] = []
        for thing in things {
            switch thing {
            case .text, .link: texts.append(thing.plainText)
            case .file(let url): files.append(file(url))
            }
        }
        guard let prompt = AIDrop.compose(texts: texts, files: files) else {
            NSSound.beep()
            return
        }
        // 刘海对话（网页或 API 模式，码头 Pro）：同一份草稿。网页模式没有输入框，
        // 放进剪贴板，在网页的对话框里粘贴。
        if AINotchController.shared.openFromShelf(instance) {
            let center = AIChatCenter.shared
            if let service = center.current, center.mode(for: service) == .web {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
                center.notice = tr("拖进来的内容已复制，在对话框里粘贴即可。")
            } else {
                center.draft = AIClipboard.insert(prompt, into: center.draft)
            }
            return
        }
        // 跳转模式：原来的迷你提问面板，草稿按卡片存。
        let state = AIPanelState.shared
        state.setDraft(AIClipboard.insert(prompt, into: state.draft(instance.id)), for: instance.id)
        state.requestPanel(instance.id, mode: .ask)
    }

    /// 文本文件读出内容，别的只给路径。
    private static func file(_ url: URL) -> AIDrop.File {
        let name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey])
        var contents: String?
        if values?.isDirectory != true,
           let type = values?.contentType, type.conforms(to: .text),
           let size = values?.fileSize, size <= AIDrop.maxFileBytes,
           let data = try? Data(contentsOf: url) {
            contents = String(data: data, encoding: .utf8)
        }
        return AIDrop.File(name: name, path: url.path, contents: contents)
    }
}

/// 拖到书签：每个链接加一条，重复的和放满了的响一声。
@MainActor
enum BookmarkDrop {
    static func add(_ things: [DroppedThing], to instance: WidgetInstance) {
        let current = WidgetWriter.current(instance.id) ?? instance
        var entries = current.config.strings("links")
        var added = false
        for thing in things {
            let url: URL?
            switch thing {
            case .link(let link): url = Bookmark.dropped(link.absoluteString)
            case .text(let words): url = Bookmark.dropped(words)
            case .file(let file): url = file
            }
            guard let url, let next = Bookmark.adding(url, to: entries) else { continue }
            entries = next
            added = true
        }
        guard added else {
            NSSound.beep()
            return
        }
        WidgetWriter.write(current) { config in
            config.set("links", .list(entries.map { .string($0) }))
        }
    }
}

/// 拖到便签：在最上面那张末尾追加一行（几样东西各占一行）。
@MainActor
enum StickyDrop {
    static func append(_ things: [DroppedThing], to instance: WidgetInstance) {
        let lines = things.map(\.plainText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            NSSound.beep()
            return
        }
        StickyLog.change(instance) { $0.appendingLine(lines.joined(separator: "\n")) }
    }
}
