import Foundation

// 码头 Pro 解锁成功庆祝动画的纯逻辑：时间线分段、音效调度、功能标签和“+N”、
// 首次激活标记、文字宽度估算。界面在 MenuBar/ProUnlockCelebrationView.swift，
// 声音在 Services/ProUnlockSoundPlayer.swift，这里不依赖 AppKit 和 SwiftUI，测试直接测。

// MARK: - 时间线

/// 动画的五段，约 3 秒后停在最终画面（熊猫继续小幅挥手，按钮呼吸发光）。
public enum ProUnlockPhase: Int, CaseIterable, Comparable, Sendable {
    /// 0 到 0.4 秒：背景变暗模糊，卡片从 0.85 弹入，熊猫从下方跳起。
    case entrance
    /// 0.4 到 1.0 秒：熊猫鞠躬、耳朵轻摆，彩纸彩带落下，皇冠落到头上。
    case bow
    /// 1.0 到 1.6 秒：PRO 徽章和金色光环旋转，左右烟花依次爆发。
    case unlock
    /// 1.6 到 2.4 秒：标题和功能标签依次出现，星光扫过皇冠和票券。
    case reveal
    /// 2.4 到 3.0 秒：烟花渐弱，换挥手图，按钮开始呼吸发光。
    case settle
    /// 3.0 秒之后：停在最终画面。
    case idle

    public static func < (lhs: ProUnlockPhase, rhs: ProUnlockPhase) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 这一段开始的时刻（秒）。
    public var start: Double {
        switch self {
        case .entrance: 0
        case .bow: 0.4
        case .unlock: 1.0
        case .reveal: 1.6
        case .settle: 2.4
        case .idle: 3.0
        }
    }
}

public enum ProUnlockTimeline {
    /// 动画总长：之后停在最终画面。
    public static let duration: Double = 3.0
    /// 皇冠开始下落、落稳（换成戴皇冠的图）的时刻。
    public static let crownDropAt: Double = 0.55
    public static let crownLandAt: Double = 0.9
    /// 彩纸、彩带开始落下。
    public static let confettiAt: Double = 0.45
    /// 左右两发烟花。
    public static let leftFireworkAt: Double = 1.0
    public static let rightFireworkAt: Double = 1.3
    /// PRO 徽章和金色光环。
    public static let badgeAt: Double = 1.0
    /// 标题、副标题。
    public static let titleAt: Double = 1.6
    public static let subtitleAt: Double = 1.72
    /// 第一个标签出现的时刻和之后的间隔。六个标签在 1.85 到 2.35 秒之间出完。
    public static let firstChipAt: Double = 1.85
    public static let chipStagger: Double = 0.1
    /// 星光扫过皇冠和票券。
    public static let shimmerAt: Double = 2.0
    /// 换挥手图、成功音、按钮开始呼吸。
    public static let waveAt: Double = 2.4
    public static let successAt: Double = 2.4
    public static let buttonAt: Double = 2.4
    /// 烟花开始渐弱到完全消失。
    public static let fireworkFadeFrom: Double = 2.4
    public static let fireworkFadeTo: Double = 3.0

    /// 某一时刻在哪一段。负数按第一段算。
    public static func phase(at t: Double) -> ProUnlockPhase {
        ProUnlockPhase.allCases.last { t >= $0.start } ?? .entrance
    }

    /// 第 index 个标签（0 起，含最后的“+N”）出现的时刻。
    public static func chipTime(_ index: Int) -> Double {
        firstChipAt + Double(max(0, index)) * chipStagger
    }

    /// t 在 [start, start + length] 里走到哪了（0 到 1）。
    public static func progress(_ t: Double, from start: Double, length: Double) -> Double {
        guard length > 0 else { return t >= start ? 1 : 0 }
        return min(1, max(0, (t - start) / length))
    }

    /// 烟花渐弱后留下的余光亮度。
    public static let fireworkAfterglow: Double = 0.3

    /// 烟花的整体亮度：2.4 秒前为 1，到 3.0 秒渐弱到余光 0.3，之后保持。
    public static func fireworkLevel(at t: Double) -> Double {
        1 - (1 - fireworkAfterglow) * progress(t, from: fireworkFadeFrom, length: fireworkFadeTo - fireworkFadeFrom)
    }

    /// 某一时刻熊猫该显示哪张图。
    public static func pose(at t: Double) -> ProUnlockPose {
        if t >= waveAt { return .wave }
        if t >= crownLandAt { return .crown }
        return .bow
    }
}

/// 熊猫的三张图。
public enum ProUnlockPose: String, Sendable {
    /// 双手合拢鞠躬，没戴皇冠。
    case bow = "unlock-panda-bow"
    /// 戴着皇冠鞠躬。
    case crown = "unlock-panda-crown"
    /// 戴着皇冠挥手。
    case wave = "unlock-panda-wave"
}

// MARK: - 音效

/// 音效文件，都在 Resources/Unlock，由 scripts/make-unlock-sounds.py 合成。
public enum ProUnlockSound: Hashable, Sendable {
    case whoosh
    case pop
    case firework
    /// 标签出现时的轻“叮”，序号越大音高越高（0 到 5）。
    case ding(Int)
    case success

    public static let dingCount = 6

    /// 不带扩展名的文件名（.wav）。
    public var fileName: String {
        switch self {
        case .whoosh: "unlock-whoosh"
        case .pop: "unlock-pop"
        case .firework: "unlock-firework"
        case .ding(let index): "unlock-ding-\(min(max(index, 0), Self.dingCount - 1))"
        case .success: "unlock-success"
        }
    }

    /// 全部要预加载的文件。
    public static var all: [ProUnlockSound] {
        let dings = (0..<dingCount).map { ProUnlockSound.ding($0) }
        return [ProUnlockSound.whoosh, .pop, .firework] + dings + [.success]
    }
}

/// 一次要响的声音：什么时候、哪个文件、左右声像（-1 左，1 右）。
public struct ProUnlockSoundCue: Equatable, Sendable {
    public var time: Double
    public var sound: ProUnlockSound
    public var pan: Float

    public init(time: Double, sound: ProUnlockSound, pan: Float = 0) {
        self.time = time
        self.sound = sound
        self.pan = pan
    }
}

public enum ProUnlockSoundSchedule {
    /// 烟花的左右声像。
    public static let fireworkPan: Float = 0.7

    /// 完整动画：登场“嗖”，皇冠“啵”，左右两发烟花，每个标签一声“叮”，最后成功音。
    public static func full(chipCount: Int) -> [ProUnlockSoundCue] {
        var cues = [
            ProUnlockSoundCue(time: 0, sound: .whoosh),
            ProUnlockSoundCue(time: ProUnlockTimeline.crownLandAt, sound: .pop),
            ProUnlockSoundCue(time: ProUnlockTimeline.leftFireworkAt, sound: .firework, pan: -fireworkPan),
            ProUnlockSoundCue(time: ProUnlockTimeline.rightFireworkAt, sound: .firework, pan: fireworkPan),
        ]
        for index in 0..<max(0, chipCount) {
            cues.append(ProUnlockSoundCue(time: ProUnlockTimeline.chipTime(index), sound: .ding(index)))
        }
        cues.append(ProUnlockSoundCue(time: ProUnlockTimeline.successAt, sound: .success))
        return cues.sorted { $0.time < $1.time }
    }

    /// “减少动态效果”时只显示最终画面，只响成功音。
    public static let reducedMotion = [ProUnlockSoundCue(time: 0, sound: .success)]

    /// 点熊猫：再鞠一躬，“啵”一声，接着一声噼啪（不分左右）。
    public static let pandaTap = [
        ProUnlockSoundCue(time: 0, sound: .pop),
        ProUnlockSoundCue(time: 0.12, sound: .firework),
    ]

    /// 按设置和“减少动态效果”挑出这次该响的声音。关掉音效时什么都不响。
    public static func cues(soundOn: Bool, reduceMotion: Bool, chipCount: Int) -> [ProUnlockSoundCue] {
        guard soundOn else { return [] }
        return reduceMotion ? reducedMotion : full(chipCount: chipCount)
    }
}

// MARK: - 功能标签

/// 码头 Pro 里一项可以单独说出来的功能。全部清单由 `ProFeatures` 算出来，
/// 加了 Pro 小组件、Pro 工具或 Pro 设置，“+N”会自己跟着变。
public enum ProUnlockItem: Hashable, Sendable {
    case kind(WidgetKind)
    case tool(QuickToggle)
    case setting(ProFeatures.Setting)
    case style(ProUnlockStyle)
}

/// 不属于某一种小组件、也不是工具或设置的 Pro 外观和样式（和付费墙“Pro 包含”里列的一致）。
public enum ProUnlockStyle: String, CaseIterable, Sendable {
    /// 所有小组件的液态外观。
    case liquid
    /// 时钟的霓虹、实景、液晶表盘和翻页大号卡片。
    case clockFaces
    /// 喝水的企鹅、水獭、章鱼角色。
    case characters
    /// 数字、点状、细线 Wi-Fi 和像素电池等电池外观。
    case wifiBatteryLooks
    /// 小组件自定义颜色和渐变背景。
    case customTint
    /// 便签更多纸色。
    case noteColors
    /// 天气多城市。
    case weatherCities
    /// 电池的电池格。
    case batteryGauge
    /// 时间进度四格。
    case progressQuad
    /// 习惯打卡第 4 个起和近七天报告。
    case moreHabits
    /// 收音机的三款复古皮肤（木壳电子管、晶体管便携、数码卡座）。
    case radioSkins
}

/// 卡片上的胶囊标签：最有卖点的 5 个功能，第 6 个是“+N”。
public enum ProUnlockHighlights {
    /// 标签的颜色（界面里换成具体的色值）。
    public enum Tint: String, CaseIterable, Sendable {
        case orange, blue, purple, green, pink, gray
    }

    public struct Chip: Equatable, Sendable {
        public var title: String
        /// SF Symbols 名字；“+N”没有图标。
        public var symbol: String?
        public var tint: Tint
    }

    /// 选出来放在卡片上的 5 个功能，按顺序。
    public static let featured: [ProUnlockItem] = [
        .style(.liquid),
        .setting(.aiNotch),
        .setting(.chargeLimit),
        .kind(.pet),
        .tool(.textCapture),
    ]

    /// 码头 Pro 的全部功能：整种 Pro 的小组件、Pro 工具、Pro 设置、Pro 外观样式。
    public static var allItems: [ProUnlockItem] {
        let kinds = WidgetKind.allCases.filter { ProFeatures.proKinds.contains($0) }.map(ProUnlockItem.kind)
        let tools = QuickToggle.allCases.filter { ProFeatures.proTools.contains($0) }.map(ProUnlockItem.tool)
        let settings = ProFeatures.Setting.allCases.map(ProUnlockItem.setting)
        let styles = ProUnlockStyle.allCases.map(ProUnlockItem.style)
        return kinds + tools + settings + styles
    }

    /// “+N”的 N：全部功能里没放上卡片的个数。
    public static func overflowCount(total: Int = allItems.count, shown: Int = featured.count) -> Int {
        max(0, total - max(0, shown))
    }

    /// 标签的短名（中文 4 到 6 个字，英文 1 到 3 个词）。
    public static func title(_ item: ProUnlockItem) -> String {
        switch item {
        case .style(.liquid): tr("液态外观")
        case .setting(.aiNotch): tr("刘海 AI 对话")
        case .setting(.chargeLimit): tr("充电上限")
        case .kind(.pet): tr("电子宠物")
        case .tool(.textCapture): tr("截图识字")
        case .kind(let kind): WidgetCatalog.entry(kind)?.name ?? kind.rawValue
        case .tool(let tool): tool.title
        case .setting(let setting): setting.rawValue
        case .style(let style): style.rawValue
        }
    }

    static func symbol(_ item: ProUnlockItem) -> String {
        switch item {
        case .style(.liquid): "drop.fill"
        case .setting(.aiNotch): "sparkles"
        case .setting(.chargeLimit): "battery.75percent"
        case .kind(.pet): "pawprint.fill"
        case .tool(.textCapture): "text.viewfinder"
        default: "star.fill"
        }
    }

    /// 卡片上的 6 个标签：5 个功能加“+N”（N 为 0 时只有 5 个）。
    public static var chips: [Chip] {
        var result = featured.enumerated().map { index, item in
            Chip(title: title(item), symbol: symbol(item), tint: Tint.allCases[index % 5])
        }
        let more = overflowCount()
        if more > 0 { result.append(Chip(title: "+\(more)", symbol: nil, tint: .gray)) }
        return result
    }
}

// MARK: - 首次激活

/// 只在第一次激活成功时自动播放：标记存在 UserDefaults，重启、重新校验、
/// 解绑后再激活都不再自动弹，只能在设置里“重看解锁动画”。
public enum ProUnlockFirstRun {
    /// 已经自动播放过（或这台 Mac 在有这个动画之前就已激活）。
    public static let shownKey = "pro.unlockCelebration.shown"
    /// 设置里的“解锁动画音效”，默认开。
    public static let soundKey = "pro.unlockCelebration.sound"

    /// 激活成功后要不要自动播放。只有激活成功、且从没播过才播。
    public static func shouldAutoPlay(activationSucceeded: Bool, alreadyShown: Bool) -> Bool {
        activationSucceeded && !alreadyShown
    }

    /// 启动时：这台 Mac 已经激活但没有标记（升级前就激活了），补上标记，
    /// 免得以后解绑再激活时当成第一次。
    public static func shouldMarkOnLaunch(isActivated: Bool, alreadyShown: Bool) -> Bool {
        isActivated && !alreadyShown
    }

    /// 读音效开关：没设过时是开。
    public static func soundEnabled(_ stored: Any?) -> Bool {
        (stored as? Bool) ?? true
    }
}

// MARK: - 尺寸和文字宽度

/// 卡片的尺寸，以及标题、标签放不放得下的估算。界面用同样的数字布局；
/// 实际显示还带 lineLimit(1) 和 minimumScaleFactor，估算只是保证正常字号下不缩。
public enum ProUnlockLayout {
    public static let cardWidth: Double = 560
    public static let cardHeight: Double = 760
    public static let cornerRadius: Double = 28
    /// 上部夜景占卡片高度的比例。
    public static let sceneFraction: Double = 0.6
    /// 下部面板左右留白。
    public static let panelPadding: Double = 24
    public static let chipColumns = 3
    public static let chipSpacing: Double = 10
    /// 胶囊里图标、间距和左右内边距加起来。
    public static let chipChrome: Double = chipIconWidth + chipIconSpacing + chipHorizontalPadding * 2
    public static let chipIconWidth: Double = 14
    public static let chipIconSpacing: Double = 5
    public static let chipHorizontalPadding: Double = 10
    public static let chipHeight: Double = 34
    public static let chipFontSize: Double = 13
    public static let titleFontSize: Double = 30
    /// 标题两侧的小光芒，各占的宽度（含间距）。
    public static let titleSparkWidth: Double = 26 + 8
    public static let subtitleFontSize: Double = 14
    /// 最小缩放：放不下时最多缩到这个比例。
    public static let minimumScale: Double = 0.7

    public static var contentWidth: Double { cardWidth - panelPadding * 2 }

    /// 一个胶囊的宽度。
    public static var chipWidth: Double {
        (contentWidth - chipSpacing * Double(chipColumns - 1)) / Double(chipColumns)
    }

    /// 胶囊里留给文字的宽度。
    public static var chipTextWidth: Double { chipWidth - chipChrome }

    /// 标题能用的宽度。
    public static var titleTextWidth: Double { contentWidth - titleSparkWidth * 2 }

    /// 粗略估算一行文字的宽度（圆体粗体）：汉字和全角符号按一个字号宽，
    /// 大写字母 0.68 个，小写字母和数字 0.58 个，空格和窄标点 0.3 个。偏宽估，宁可多留。
    public static func estimatedWidth(_ text: String, fontSize: Double) -> Double {
        var units = 0.0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x2E80...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || (0xFF00...0xFFEF).contains(v) {
                units += 1.0
            } else if CharacterSet.uppercaseLetters.contains(scalar) || "MW@%".unicodeScalars.contains(scalar) {
                units += 0.68
            } else if " .,:;!'|ilI".unicodeScalars.contains(scalar) {
                units += 0.3
            } else {
                units += 0.58
            }
        }
        return units * fontSize
    }

    /// 在 width 里按 fontSize 放得下（不缩）。
    public static func fits(_ text: String, fontSize: Double, width: Double) -> Bool {
        estimatedWidth(text, fontSize: fontSize) <= width
    }
}
