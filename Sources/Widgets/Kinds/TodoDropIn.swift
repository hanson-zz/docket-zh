import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 拖到快速待办上的文字、链接和文件，每样记成一条待办。卡片和面板共用。
///
/// 和隔空投送卡片一样用 `DropDelegate`：要在拖进来时亮出虚线框，松手后再
/// 一样样读出来。文件和链接记下地址，点一下就能打开；文字整段是网址时也当
/// 链接记。
@MainActor
struct TodoDropDelegate: DropDelegate {
    var enabled: Bool
    var targeted: @MainActor (Bool) -> Void
    var receive: @MainActor ([TodoDrop]) -> Void

    static let types: [UTType] = [.fileURL, .url, .plainText]
    /// 一次拖进来很多文件时只记前面这些，免得清单被一下塞满。
    static let maxPerDrop = 20

    func validateDrop(info: DropInfo) -> Bool {
        enabled && info.hasItemsConforming(to: Self.types)
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
        let providers = info.itemProviders(for: Self.types)
        guard enabled, !providers.isEmpty else { return false }
        let receive = self.receive
        Task { @MainActor in
            var drops: [TodoDrop] = []
            for provider in providers.prefix(Self.maxPerDrop) {
                if let drop = await Self.load(provider) { drops.append(drop) }
            }
            if drops.isEmpty {
                NSSound.beep()
            } else {
                receive(drops)
            }
        }
        return true
    }

    /// 先认文件，再认链接，最后当文字读。
    private static func load(_ provider: NSItemProvider) async -> TodoDrop? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: .fileURL), url.isFileURL {
            return TodoDrop.url(url)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: .url), let drop = TodoDrop.url(url) {
            return drop
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            let text: String? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    let words = (object as? NSString).map { $0 as String }
                    continuation.resume(returning: words)
                }
            }
            return text.flatMap { TodoDrop.text($0) }
        }
        return nil
    }

    /// 文件和链接在拖放里都是一段 URL 的数据。
    private static func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                continuation.resume(returning: url)
            }
        }
    }
}

/// 拖着东西停在卡片或面板上时盖在上面的一句话。
struct TodoDropHint: View {
    var compact = false

    var body: some View {
        VStack(spacing: 2) {
            Text("松手记一条待办")
                .font(WidgetStyle.label(compact ? 11 : 13))
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !compact {
                Text("文字、链接、文件都行")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }
}

/// 打开一条待办记下的链接或文件。文件已经不在了就响一声。
@MainActor
enum TodoLinkOpener {
    static func open(_ item: TodoItem) {
        guard let url = item.url else { return }
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func symbol(_ item: TodoItem) -> String {
        item.url?.isFileURL == true ? "doc" : "link"
    }
}
