import Foundation

/// 小组件库「应用分组」：新建空组、给组起不重名的名字、往组里加 App 时去重。
///
/// 拖图标合成分组的老路子（`ShelfItems.combining`）不变；这里只管从库里新建的组
/// 和组窗口里的「＋」、从访达拖进来的 App。
public enum AppGroups {

    /// 「分组」，被占用了就「分组 2」「分组 3」……和扩展栏配置的重名规则一样。
    /// - Parameter existing: 扩展栏上已有分组的名字。
    public static func uniqueName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// 扩展栏上（只看顶层）所有分组的名字。
    public static func groupNames(in items: [DockItem]) -> [String] {
        items.compactMap(\.group?.name)
    }

    /// 在扩展栏末尾放一个空组，名字自动避开重名，少于两个也不解散。
    /// - Returns: 新的列表和新组的 id（调用方要立刻打开它）。
    public static func addingEmptyGroup(named base: String, in items: [DockItem],
                                        id: UUID = UUID()) -> (items: [DockItem], id: UUID) {
        let name = uniqueName(base, existing: groupNames(in: items))
        let group = DockGroup(id: id, name: name, keepsEmpty: true)
        return (items + [.group(group)], id)
    }

    /// 判断「是不是同一个东西」用的键：App 看 bundle id（不分大小写），没有
    /// bundle id 时看路径；文件夹、文件看路径；链接看地址。小组件、间隔、分组不去重。
    public static func identity(_ item: DockItem) -> String? {
        switch item {
        case .app(_, let bundleID, let ref):
            let id = bundleID.trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? "path:" + path(ref.url) : "bundle:" + id.lowercased()
        case .folder(_, let ref, _), .file(_, let ref):
            return "path:" + path(ref.url)
        case .link(_, let url, _):
            return "link:" + url.absoluteString
        case .spacer, .widget, .group:
            return nil
        }
    }

    private static func path(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    /// 把一批东西加进组的末尾。组里已有的、这一批里重复的都跳过；间隔和分组
    /// 放不进组，也跳过。找不到这个组时原样返回。
    public static func adding(_ new: [DockItem], toGroup groupID: UUID,
                              in items: [DockItem]) -> [DockItem] {
        guard let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group else { return items }
        var seen = Set(group.items.compactMap(identity))
        var ids = Set(group.items.map(\.id))
        for item in new {
            switch item {
            case .spacer, .group: continue
            default: break
            }
            guard !ids.contains(item.id) else { continue }
            if let key = identity(item) {
                guard !seen.contains(key) else { continue }
                seen.insert(key)
            }
            ids.insert(item.id)
            group.items.append(item)
        }
        var result = items
        result[slot] = .group(group)
        return result
    }

    /// 只改名字，按 id 找组，不碰组里的东西（组窗口开着时手里的那份可能已经旧了）。
    /// 空名字不改。
    public static func renaming(_ groupID: UUID, to name: String,
                                in items: [DockItem]) -> [DockItem] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group else { return items }
        group.name = trimmed
        var result = items
        result[slot] = .group(group)
        return result
    }

    /// 选择列表里一个 App 已经在组里了没有（打勾、不能再选）。
    public static func contains(_ candidate: DockItem, in group: DockGroup) -> Bool {
        guard let key = identity(candidate) else { return false }
        return group.items.contains { identity($0) == key }
    }

    /// 选择列表的搜索：名字或 bundle id 里含有关键字（不分大小写），空关键字全要。
    public static func matches(_ query: String, name: String, bundleID: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return name.lowercased().contains(q) || bundleID.lowercased().contains(q)
    }

    /// 一个 .app 变成扩展栏上的 App 项（新 id，记下 bundle id 和书签）。
    public static func appItem(for url: URL) -> DockItem {
        .app(id: UUID(), bundleID: Bundle(url: url)?.bundleIdentifier ?? "", ref: .capture(url))
    }

    /// 只收 .app：从访达拖进组、在选择列表里选的都只要 App。
    public static func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    // MARK: 条目显示名

    /// 给组里一项起名字（只是显示名）。空名字或和原名一样就是恢复原名。
    /// 顺手清掉已经不在组里的条目留下的名字。找不到组或这一项时原样返回。
    /// - Parameter original: 这一项原来的名字，起的名字和它一样时不存。
    public static func renamingItem(_ itemID: UUID, inGroup groupID: UUID, to name: String?,
                                    original: String? = nil, in items: [DockItem]) -> [DockItem] {
        guard let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group,
              group.items.contains(where: { $0.id == itemID }) else { return items }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let present = Set(group.items.map(\.id.uuidString))
        var names = (group.itemNames ?? [:]).filter { present.contains($0.key) }
        if trimmed.isEmpty || trimmed == original?.trimmingCharacters(in: .whitespacesAndNewlines) {
            names[itemID.uuidString] = nil
        } else {
            names[itemID.uuidString] = trimmed
        }
        group.itemNames = names.isEmpty ? nil : names
        var result = items
        result[slot] = .group(group)
        return result
    }

    /// 分组窗口里显示还是隐藏名字。显示时存 nil，和旧配置一样。
    public static func settingShowsNames(_ shows: Bool, inGroup groupID: UUID,
                                         in items: [DockItem]) -> [DockItem] {
        guard let slot = items.firstIndex(where: { $0.id == groupID }),
              var group = items[slot].group else { return items }
        group.hidesNames = shows ? nil : true
        var result = items
        result[slot] = .group(group)
        return result
    }

    /// 组里每一项在分组窗口里显示的名字：自定义名优先，App 用短名（同组撞名时
    /// 保留能区分的部分），文件、文件夹、链接用原名。
    /// - Parameter original: 每一项的原名（App 的文件名、链接标题）。
    public static func displayNames(in group: DockGroup,
                                    original: (DockItem) -> String) -> [UUID: String] {
        var custom: [UUID: String] = [:]
        var apps: [(id: UUID, name: String)] = []
        var result: [UUID: String] = [:]
        for item in group.items {
            if let own = group.customName(for: item.id) {
                custom[item.id] = own
                apps.append((item.id, original(item)))
            } else if case .app = item {
                apps.append((item.id, original(item)))
            } else {
                result[item.id] = original(item)
            }
        }
        for (id, name) in AppShortNames.displayNames(apps, custom: custom) { result[id] = name }
        return result
    }
}
