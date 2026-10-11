import SwiftUI

/// Somewhere to put files down for a moment: drop them on the card, carry
/// them back out of its panel when you have found where they go.
///
/// Only references are held, as paths in the widget's own config, so nothing
/// is copied or moved and a file that has since gone away simply drops out
/// of the list. The key is deliberately not among the catalog defaults: it
/// is not a setting, and the Widgets tab would otherwise offer the paths as
/// a comma separated text field.
struct FileShelfTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var targeted = false

    private var files: [ListedFile] { context.isPreview ? [] : FileShelf.files(instance) }

    var body: some View {
        let column = context.position.isVertical
        let count = context.isPreview ? 3 : files.count
        return WidgetSurface {
            if column {
                VStack(spacing: 6) {
                    badge(size: 32)
                    Text(count == 0 ? "拖入" : "\(count) 个")
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 10) {
                    badge(size: 40)
                    TileReading(value: count == 0 ? "拖入文件" : "\(count) 个文件",
                                caption: "文件暂存", valueSize: 15)
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: WidgetStyle.corner, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(targeted ? 1 : 0)
                .animation(.snappy(duration: 0.15), value: targeted)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !context.isPreview else { return false }
            return FileShelf.add(urls, to: instance)
        } isTargeted: { targeted = $0 }
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            if let first = files.first {
                ZStack {
                    if files.count > 1 {
                        Image(nsImage: Thumbnails.shared.icon(for: files[1].url))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(size * 0.12)
                            .rotationEffect(.degrees(-10))
                            .offset(x: -3)
                    }
                    Image(nsImage: Thumbnails.shared.icon(for: first.url))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(size * 0.1)
                        .offset(x: files.count > 1 ? 2 : 0)
                }
            } else {
                Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(WidgetStyle.primary)
            }
        }
    }
}

/// The shelf's list, kept in the widget's config.
@MainActor
enum FileShelf {
    static let key = "files"
    static let limit = 50

    static func paths(_ instance: WidgetInstance) -> [String] {
        instance.config.strings(key)
    }

    /// The held files that still exist, in the order they were put down,
    /// newest first.
    static func files(_ instance: WidgetInstance) -> [ListedFile] {
        paths(instance).compactMap { path in
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey,
                                                           .isPackageKey, .fileSizeKey])
            guard values != nil else { return nil }
            return ListedFile(url: url,
                              date: values?.contentModificationDate ?? .distantPast,
                              isDirectory: values?.isDirectory == true && values?.isPackage != true,
                              size: values?.fileSize.map(Int64.init))
        }
    }

    @discardableResult
    static func add(_ urls: [URL], to instance: WidgetInstance) -> Bool {
        let incoming = urls.filter(\.isFileURL).map(\.path)
        guard !incoming.isEmpty else { return false }
        WidgetWriter.write(instance) { config in
            var list = config.strings(key)
            for path in incoming.reversed() {
                list = RecentList.inserting(path, into: list, limit: limit)
            }
            config.set(key, .list(list.map { .string($0) }))
        }
        return true
    }

    static func remove(_ url: URL, from instance: WidgetInstance) {
        WidgetWriter.write(instance) { config in
            let list = config.strings(key).filter { $0 != url.path }
            config.set(key, .list(list.map { .string($0) }))
        }
    }

    static func clear(_ instance: WidgetInstance) {
        WidgetWriter.write(instance) { $0.set(key, .list([])) }
    }
}
