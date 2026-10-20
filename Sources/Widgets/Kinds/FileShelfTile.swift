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
    /// 拖进来的有几个文件，写在拖入提示的第二行。
    @State private var dragged = 0
    @Environment(\.colorScheme) private var scheme

    private var files: [ListedFile] { context.isPreview ? [] : FileShelf.files(instance) }

    var body: some View {
        let column = context.position.isVertical
        let count = context.isPreview ? 3 : files.count
        return WidgetSurface {
            Group {
                if column {
                    VStack(spacing: WidgetStyle.columnSpacing) {
                        badge(size: WidgetStyle.badgeColumn)
                        Text(count == 0 ? PandaEmpty.fileShelf.line(compact: true) : tr("\(count) 个"))
                            .font(WidgetStyle.label(11))
                            .foregroundStyle(WidgetStyle.primary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: WidgetStyle.rowSpacing) {
                        badge(size: WidgetStyle.badge)
                        TileReading(value: count == 0 ? PandaEmpty.fileShelf.line() : tr("\(count) 个文件"),
                                    caption: tr("文件暂存"), valueSize: 15)
                        Spacer(minLength: 0)
                    }
                }
            }
            .dropHidden(targeted)
        }
        // 拖入：青色虚线框，“暂存在这里 / 3 个文件”。原文件不动，只记位置。
        .dropTargetOutline(targeted, prompt: .fileShelf(files: dragged), compact: column)
        .onDrop(of: FileDropDelegate.types, delegate: FileDropDelegate(
            enabled: !context.isPreview,
            update: { inside, count in
                targeted = inside
                dragged = count
            },
            receive: { urls in _ = FileShelf.add(urls, to: instance) }))
        // 自动移出：现在看一次，再睡到下一个条目到期（最多一小时）再看。
        .task(id: sweepKey) {
            guard !context.isPreview else { return }
            while !Task.isCancelled {
                FileShelf.sweep(instance)
                let config = (WidgetWriter.current(instance.id) ?? instance).config
                let next = FileShelfList.nextExpiry(FileShelfList.read(config),
                                                    expiry: FileShelfList.expiry(config))
                let wait = min(3600, max(60, (next ?? .distantFuture).timeIntervalSinceNow + 1))
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// 清单或自动移出设置一变，重新安排检查。
    private var sweepKey: String {
        FileShelfList.expiry(instance.config).rawValue + "|" + FileShelfList.paths(instance.config).joined(separator: "\n")
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
            } else if targeted || context.isPreview {
                // 库里的缩略图写着“3 个文件”，配托盘而不是空状态的小熊猫。
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: size * CGFloat(DockMetrics.badgeGlyphRatio), weight: .medium))
                    .foregroundStyle(WidgetStyle.primary)
            } else {
                // 空着：小熊猫等着接文件。
                PandaEmptyBadge(empty: .fileShelf, size: size, fallback: "tray.and.arrow.down")
            }
        }
    }
}

/// The shelf's list, kept in the widget's config (paths and when each was
/// put down, see `FileShelfList`).
///
/// Nothing here ever deletes, moves or copies a file: removing, clearing,
/// auto-expiry and "clear the missing ones" only edit the list.
@MainActor
enum FileShelf {
    /// One held path: the file as it is now, or nil when it has gone away
    /// (moved, renamed, deleted, or on a disk that is not mounted).
    struct Entry: Identifiable {
        var item: FileShelfList.Item
        var file: ListedFile?

        var id: String { item.path }
        var url: URL { URL(fileURLWithPath: item.path) }
        var name: String { url.lastPathComponent }
        var missing: Bool { file == nil }
    }

    static func entries(_ instance: WidgetInstance) -> [Entry] {
        FileShelfList.read(instance.config).map { item in
            Entry(item: item, file: listed(URL(fileURLWithPath: item.path)))
        }
    }

    /// The held files that still exist, in the order they were put down,
    /// newest first.
    static func files(_ instance: WidgetInstance) -> [ListedFile] {
        entries(instance).compactMap(\.file)
    }

    private static func listed(_ url: URL) -> ListedFile? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey,
                                                             .isPackageKey, .fileSizeKey]) else { return nil }
        return ListedFile(url: url,
                          date: values.contentModificationDate ?? .distantPast,
                          isDirectory: values.isDirectory == true && values.isPackage != true,
                          size: values.fileSize.map(Int64.init))
    }

    /// Edits the list on the copy saved right now, so a write made after an
    /// await (compressing, the move menu) never puts back a stale list.
    private static func edit(_ instance: WidgetInstance,
                             _ change: ([FileShelfList.Item]) -> [FileShelfList.Item]) {
        let current = WidgetWriter.current(instance.id) ?? instance
        WidgetWriter.write(current) { config in
            FileShelfList.write(change(FileShelfList.read(config)), into: &config)
        }
    }

    @discardableResult
    static func add(_ urls: [URL], to instance: WidgetInstance) -> Bool {
        let incoming = urls.filter(\.isFileURL).map(\.path)
        guard !incoming.isEmpty else { return false }
        edit(instance) { FileShelfList.adding(incoming, to: $0, now: Date()) }
        return true
    }

    static func remove(_ url: URL, from instance: WidgetInstance) {
        remove([url.path], from: instance)
    }

    static func remove(_ paths: [String], from instance: WidgetInstance) {
        let drop = Set(paths)
        guard !drop.isEmpty else { return }
        edit(instance) { FileShelfList.removing(drop, from: $0) }
    }

    /// After "Move to…": the shelf follows the files to where they went,
    /// keeping their place in the list and when they were put down.
    static func relocate(_ moves: [(from: String, to: String)], in instance: WidgetInstance) {
        guard !moves.isEmpty else { return }
        let map = Dictionary(moves.map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        edit(instance) { items in
            var seen = Set<String>()
            return items.compactMap { item in
                var item = item
                if let moved = map[item.path] { item.path = moved }
                return seen.insert(item.path).inserted ? item : nil
            }
        }
    }

    static func clear(_ instance: WidgetInstance) {
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) { FileShelfList.write([], into: &$0) }
    }

    static func setExpiry(_ expiry: FileShelfList.Expiry, for instance: WidgetInstance) {
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) {
            $0.set(FileShelfList.expireKey, .string(expiry.rawValue))
        }
        sweep(instance)
    }

    /// Takes whatever has expired off the list. Writes only when something
    /// changed, so calling it from a view's task never loops.
    static func sweep(_ instance: WidgetInstance, now: Date = Date()) {
        let current = WidgetWriter.current(instance.id) ?? instance
        let result = FileShelfList.sweep(FileShelfList.read(current.config),
                                         expiry: FileShelfList.expiry(current.config), now: now)
        guard result.changed else { return }
        WidgetWriter.write(current) { FileShelfList.write(result.kept, into: &$0) }
    }
}
