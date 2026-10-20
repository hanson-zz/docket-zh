import Foundation

/// 相册卡片和面板共用的读法：哪些文件夹、读到哪些图片、照片图库里往年今天的
/// 照片、排除了哪些、按什么顺序、现在是哪张。规则在 Core 的 `PhotoRotation`。
///
/// 卡片和面板每次重画都新建一个，便宜：文件夹的图片由各自共用的 `FolderFeed`
/// 读好放着，这里只是拼起来。
@MainActor
struct PhotoAlbum {
    enum Item: Equatable {
        case file(ListedFile)
        case memory(PhotoMemories.Memory)

        var id: String {
            switch self {
            case .file(let file): file.url.path
            case .memory(let memory): PhotoRotation.memoryPrefix + memory.id
            }
        }

        var fileURL: URL? {
            if case .file(let file) = self { return file.url }
            return nil
        }
    }

    let config: WidgetConfig
    /// 宽幅卡片原来就会去要照片图库的权限，这里照旧。
    let wide: Bool

    init(config: WidgetConfig, wide: Bool = false) {
        self.config = config
        self.wide = wide
    }

    var activeFolders: [String] { PhotoRotation.activeFolders(config) }
    var feeds: [FolderFeed] { activeFolders.map { FolderFeed.shared(.pictures($0)) } }
    var interval: Double { PhotoRotation.interval(config) }
    var shuffle: Bool { config.bool(PhotoRotation.shuffleKey) }
    var memoriesFirst: Bool { config.bool(PhotoRotation.memoriesFirstKey, default: true) }
    var state: PhotoRotation.State { PhotoRotation.state(config) }
    var excluded: [String] { PhotoRotation.excluded(config) }

    /// 开始读文件夹；“那年今天优先”开着时读照片图库（宽幅卡片第一次出现时
    /// 照旧会请求一次权限，其余情况只在已经给了权限时读）。
    func start(now: Date = .now) {
        for feed in feeds { feed.start() }
        guard memoriesFirst else { return }
        if wide {
            PhotoMemories.shared.start(now: now)
        } else {
            PhotoMemories.shared.startIfAllowed(now: now)
        }
    }

    /// 所有勾上的文件夹里的图片，同一个文件只算一次。
    var files: [ListedFile] {
        var seen = Set<String>()
        var result: [ListedFile] = []
        for feed in feeds {
            for file in feed.files where seen.insert(file.url.path).inserted {
                result.append(file)
            }
        }
        return result
    }

    var memories: [PhotoMemories.Memory] {
        memoriesFirst ? PhotoMemories.shared.memories : []
    }

    /// 每个 id 对应的图片，排除了的也在（设置里恢复时要画）。
    var lookup: [String: Item] {
        var result: [String: Item] = [:]
        for memory in memories { result[PhotoRotation.memoryPrefix + memory.id] = .memory(memory) }
        for file in files { result[file.url.path] = .file(file) }
        return result
    }

    func order(excluding skip: [String]? = nil) -> [String] {
        PhotoRotation.order(memories: memories.map { PhotoRotation.memoryPrefix + $0.id },
                            files: files.map(\.url.path),
                            excluded: skip ?? excluded,
                            shuffle: shuffle, memoriesFirst: memoriesFirst)
    }

    /// 还没读完第一遍的文件夹（只要有一个读好了图片就先放）。
    var loading: Bool {
        feeds.contains { $0.loadedAt == nil } && files.isEmpty
    }

    /// 第一个读不了的文件夹的原因。
    var failure: (text: String, denied: Bool)? {
        guard files.isEmpty, let feed = feeds.first(where: { $0.error != nil }), let error = feed.error else { return nil }
        return (error, feed.accessDenied)
    }

    /// 文件夹显示的名字：空路径是“图片”。
    static func folderName(_ path: String) -> String {
        let url = FolderFeed.folder(for: .pictures(path))
        if path.trimmingCharacters(in: .whitespaces).isEmpty { return tr("图片") }
        return url.lastPathComponent
    }
}
