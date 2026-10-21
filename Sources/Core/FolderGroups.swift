import CoreGraphics
import Foundation

/// 小组件库「文件夹分组」：扩展栏上一个格子收好几个常用文件夹，点开是文件夹
/// 浏览小窗，顶部一排标签切换看哪一个。
///
/// 组本身就是 `DockGroup`（`kind` 为 `.folders`，`keepsEmpty` 为 true，空着也留着），
/// 里面每一项是 `.folder`。命名、去重沿用 `AppGroups`；这里管只收文件夹、移除、
/// 重排、记住上次看的那个、标签上的名字。
public enum FolderGroups {

    /// 在扩展栏末尾放一个空的文件夹分组，名字和所有分组一起避开重名
    /// （「文件夹分组」「文件夹分组 2」）。
    public static func addingEmptyGroup(named base: String, in items: [DockItem],
                                        id: UUID = UUID()) -> (items: [DockItem], id: UUID) {
        let name = AppGroups.uniqueName(base, existing: AppGroups.groupNames(in: items))
        let group = DockGroup(id: id, name: name, keepsEmpty: true, kind: .folders)
        return (items + [.group(group)], id)
    }

    /// 一个文件夹变成组里的一项（新 id、书签、系统图标）。
    public static func folderItem(for url: URL, id: UUID = UUID()) -> DockItem {
        .folder(id: id, ref: .capture(url), icon: FolderIcon())
    }

    /// 文件夹才收：目录且不是包（.app、.photoslibrary 这类在访达里是一个文件）。
    public static func accepts(isDirectory: Bool, isPackage: Bool) -> Bool {
        isDirectory && !isPackage
    }

    /// 读一下磁盘，看 `url` 是不是能收进文件夹分组的文件夹。
    public static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return accepts(isDirectory: values?.isDirectory ?? false, isPackage: values?.isPackage ?? false)
    }

    /// 能不能把 `item` 合进 `target`（拖到格子上、右键「添加到分组」）。
    /// 文件夹分组只收文件夹；应用分组和普通格子照旧，什么都能合。
    public static func canCombine(_ item: DockItem, into target: DockItem) -> Bool {
        guard let group = target.group, group.isFolderGroup else { return true }
        if case .folder = item { return true }
        return false
    }

    /// 往文件夹分组里加文件夹：不是文件夹的项跳过，同一路径的去重（见
    /// `AppGroups.adding`）。不是文件夹分组时原样返回。
    public static func adding(_ new: [DockItem], toGroup groupID: UUID,
                              in items: [DockItem]) -> [DockItem] {
        guard let group = items.first(where: { $0.id == groupID })?.group,
              group.isFolderGroup else { return items }
        let folders = new.filter { if case .folder = $0 { true } else { false } }
        guard !folders.isEmpty else { return items }
        var result = AppGroups.adding(folders, toGroup: groupID, in: items)
        // 原来是空组，就直接看第一个加进来的。
        if group.items.isEmpty, let slot = result.firstIndex(where: { $0.id == groupID }),
           var updated = result[slot].group, updated.selectedFolder == nil {
            updated.selectedFolder = updated.items.first?.id
            result[slot] = .group(updated)
        }
        return result
    }

    /// 从文件夹分组里移除一个文件夹（不放回扩展栏，文件夹本身不动）。组空了也留着。
    /// 移掉的正好是在看的那个时，改看它右边的（没有就左边的）。
    public static func removing(_ folderID: UUID, fromGroup groupID: UUID,
                                in items: [DockItem]) -> [DockItem] {
        guard let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group,
              let inner = group.items.firstIndex(where: { $0.id == folderID })
        else { return items }
        let wasSelected = selected(in: group)?.id == folderID
        group.items.remove(at: inner)
        if wasSelected {
            let next = group.items.indices.contains(inner) ? inner : group.items.count - 1
            group.selectedFolder = next >= 0 ? group.items[next].id : nil
        }
        var result = items
        result[slot] = .group(group)
        return result
    }

    /// 把组里的一个文件夹挪到 `index`（标签拖动、右键左移右移）。越界的位置夹到两端。
    public static func moving(_ folderID: UUID, to index: Int, inGroup groupID: UUID,
                              in items: [DockItem]) -> [DockItem] {
        guard let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group,
              let from = group.items.firstIndex(where: { $0.id == folderID })
        else { return items }
        let item = group.items.remove(at: from)
        group.items.insert(item, at: min(max(0, index), group.items.count))
        var result = items
        result[slot] = .group(group)
        return result
    }

    /// 往左（-1）或往右（+1）挪一格。
    public static func shifting(_ folderID: UUID, by step: Int, inGroup groupID: UUID,
                                in items: [DockItem]) -> [DockItem] {
        guard let group = items.first(where: { $0.id == groupID })?.group,
              let from = group.items.firstIndex(where: { $0.id == folderID }) else { return items }
        return moving(folderID, to: from + step, inGroup: groupID, in: items)
    }

    /// 记下现在看的是哪个文件夹。不在组里的 id 不记。
    public static func selecting(_ folderID: UUID, inGroup groupID: UUID,
                                 in items: [DockItem]) -> [DockItem] {
        guard let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group,
              group.items.contains(where: { $0.id == folderID }),
              group.selectedFolder != folderID
        else { return items }
        group.selectedFolder = folderID
        var result = items
        result[slot] = .group(group)
        return result
    }

    /// 打开时看哪个：上次看的还在就是它，否则第一个；空组没有。
    public static func selected(in group: DockGroup) -> DockItem? {
        if let id = group.selectedFolder, let item = group.items.first(where: { $0.id == id }) {
            return item
        }
        return group.items.first
    }

    /// 标签上的名字：文件夹名；有重名的在后面带上上一层的名字
    /// （「素材（工作）」「素材（个人）」），还重就带完整路径。
    /// - Parameter parenthesize: 把上一层名字包起来，中文「（工作）」，英文 " (Work)"。
    public static func tabTitles(for urls: [URL],
                                 parenthesize: (String) -> String = { "（\($0)）" }) -> [String] {
        let names = urls.map(displayName)
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        let first = urls.indices.map { index -> String in
            let name = names[index]
            guard counts[name, default: 0] > 1 else { return name }
            let parent = urls[index].deletingLastPathComponent().lastPathComponent
            return parent.isEmpty || parent == "/" ? name : name + parenthesize(parent)
        }
        var again: [String: Int] = [:]
        for title in first { again[title, default: 0] += 1 }
        return urls.indices.map { index in
            again[first[index], default: 0] > 1 ? urls[index].path(percentEncoded: false) : first[index]
        }
    }

    /// 文件夹显示的名字：最后一段，根目录写「/」。
    public static func displayName(_ url: URL) -> String {
        let name = url.standardizedFileURL.lastPathComponent
        return name.isEmpty ? "/" : name
    }

    /// 标签一排的高度（加在浏览小窗顶栏下面）。
    public static let tabRowHeight: CGFloat = 40
}
