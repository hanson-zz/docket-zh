import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 只收文件的拖放，拖进来时数出几个文件给卡片写“3 个文件”。
///
/// 文件暂存和废纸篓原来用 `dropDestination(for: URL.self)`，它只告诉卡片
/// 有没有东西停在上面，数不出个数；这里和隔空投送卡片一样用 `DropDelegate`，
/// 松手后再一个个读出文件地址交给 `receive`。拖来的不是文件时不接。
@MainActor
struct FileDropDelegate: DropDelegate {
    static let types: [UTType] = [.fileURL]

    var enabled: Bool
    /// 有没有文件停在卡片上、几个。
    var update: @MainActor (Bool, Int) -> Void
    var receive: @MainActor ([URL]) -> Void

    private func count(_ info: DropInfo) -> Int {
        info.itemProviders(for: Self.types).count
    }

    func dropEntered(info: DropInfo) {
        guard enabled else { return }
        let files = count(info)
        update(files > 0, files)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard enabled else { return DropProposal(operation: .forbidden) }
        let files = count(info)
        update(files > 0, files)
        return DropProposal(operation: files > 0 ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        update(false, 0)
    }

    func validateDrop(info: DropInfo) -> Bool {
        enabled && info.hasItemsConforming(to: Self.types)
    }

    func performDrop(info: DropInfo) -> Bool {
        update(false, 0)
        let providers = info.itemProviders(for: Self.types)
        guard enabled, !providers.isEmpty else { return false }
        let receive = self.receive
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.load(provider) { urls.append(url) }
            }
            if !urls.isEmpty { receive(urls) }
        }
        return true
    }

    /// 文件地址在拖放里是一段 file URL 的数据。
    @MainActor
    static func load(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }
}
