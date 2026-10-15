import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 摸鱼时钟：左上大标题（距离下班 02:35:18、下班啦、周末快乐），左下几个
/// 半透明小格，右边一只小熊猫。算什么全在 `SlackerClock`，这里只画。
///
/// 省电：倒计时每秒变一次，但只在扩展栏真的显示在屏幕上时才每秒重画
/// （`ShelfVisibility`）。看不见时把时间截到整分钟，内容不变，SwiftUI 就
/// 跳过重画；扩展栏一露出来立刻回到每秒。没有动画，只是数字在变，所以
/// “减少动态效果”不需要另外处理。
struct SlackerTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        let visible = context.isPreview || ShelfVisibility.shared.cardsOnScreen
        let now = context.isPreview ? SlackerSamples.now : context.now
        SlackerTileBody(config: instance.config,
                        now: visible ? now : SlackerSamples.minute(now),
                        known: HolidayService.shared.known,
                        vertical: context.position.isVertical,
                        animates: visible && !context.isPreview)
            .equatable()
            .onAppear { if !context.isPreview { HolidayService.shared.refresh() } }
    }
}

/// 卡片本体。Equatable：输入一样就不重画，看不见时靠这个停下来。
private struct SlackerTileBody: View, Equatable {
    var config: WidgetConfig
    var now: Date
    var known: [Int: [HolidayDay]]
    var vertical: Bool
    var animates: Bool

    nonisolated static func == (a: SlackerTileBody, b: SlackerTileBody) -> Bool {
        a.now == b.now && a.vertical == b.vertical && a.animates == b.animates
            && a.config == b.config && a.known == b.known
    }

    var body: some View {
        let settings = SlackerClock.Settings(config: config)
        let reading = SlackerClock.reading(now: now, settings: settings, known: known)
        let look = SlackerLook(config: config, art: reading.art)
        WidgetSurface(fill: look.background, image: look.image, scrim: look.image == nil ? 0 : 0.18) {
            ZStack {
                if SlackerClock.look(config) == .liquid {
                    SlackerWater(phase: reading.phase, level: SlackerClock.waterLevel(reading.phase, settings: settings),
                                 animates: animates)
                        .padding(.horizontal, -WidgetStyle.inset)
                        .clipShape(.rect(cornerRadius: WidgetStyle.corner, style: .continuous))
                }
                if vertical {
                    column(reading, look)
                } else {
                    SlackerFace(reading: reading, look: look, metrics: .shelf)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SlackerLook.spoken(reading))
    }

    private func column(_ reading: SlackerClock.Reading, _ look: SlackerLook) -> some View {
        let lines = SlackerClock.titleLines(reading.phase)
        return VStack(spacing: 3) {
            SlackerPanda(art: reading.art)
                .frame(width: 44, height: 40)
            Text(lines.top)
                .font(look.font(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let bottom = lines.bottom {
                Text(bottom)
                    .font(look.font(size: 12, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            ForEach(reading.cells) { cell in
                SlackerCellView(cell: cell, look: look, metrics: .column)
            }
        }
        .foregroundStyle(look.text)
        .padding(.vertical, 6)
    }
}

// MARK: - Shared pieces

/// 卡片的大小参数：扩展栏上的 58pt 和面板里放大的那张。
struct SlackerMetrics {
    var title: CGFloat
    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var cellLabel: CGFloat
    var cellValue: CGFloat
    var cellSpacing: CGFloat
    var panda: CGFloat
    var pandaDrop: CGFloat

    static let shelf = SlackerMetrics(title: 16, cellWidth: CGFloat(SlackerClock.cellWidth), cellHeight: 27,
                                      cellLabel: 8.5, cellValue: 11.5, cellSpacing: CGFloat(SlackerClock.cellSpacing),
                                      panda: 60, pandaDrop: 5)
    static let panel = SlackerMetrics(title: 24, cellWidth: 54, cellHeight: 42,
                                      cellLabel: 10.5, cellValue: 16, cellSpacing: 6,
                                      panda: 92, pandaDrop: 8)
    static let column = SlackerMetrics(title: 11, cellWidth: 56, cellHeight: 24,
                                       cellLabel: 8, cellValue: 10, cellSpacing: 4,
                                       panda: 40, pandaDrop: 0)
}

/// 宽卡片：左边标题和小格，右边小熊猫。扩展栏和面板预览共用。
struct SlackerFace: View {
    var reading: SlackerClock.Reading
    var look: SlackerLook
    var metrics: SlackerMetrics

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: metrics.cellSpacing) {
                Text(reading.title)
                    .font(look.font(size: metrics.title, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                if !reading.cells.isEmpty {
                    HStack(spacing: metrics.cellSpacing) {
                        ForEach(reading.cells) { cell in
                            SlackerCellView(cell: cell, look: look, metrics: metrics)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SlackerPanda(art: reading.art)
                .frame(width: metrics.panda, height: metrics.panda)
                .offset(y: metrics.pandaDrop)
        }
        .foregroundStyle(look.text)
    }
}

/// 一个半透明小格：上面一行小字，下面数字和单位。
struct SlackerCellView: View {
    var cell: SlackerClock.Cell
    var look: SlackerLook
    var metrics: SlackerMetrics

    var body: some View {
        VStack(spacing: 0) {
            Text(cell.label)
                .font(look.font(size: metrics.cellLabel, weight: .semibold))
                .opacity(0.9)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(cell.value)
                    .font(look.font(size: metrics.cellValue, weight: .bold))
                    .monospacedDigit()
                if !cell.unit.isEmpty {
                    Text(cell.unit)
                        .font(look.font(size: metrics.cellLabel, weight: .semibold))
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 2)
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .background {
            RoundedRectangle(cornerRadius: metrics.cellHeight * 0.26, style: .continuous)
                .fill(.white.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.cellHeight * 0.26, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
                }
        }
    }
}

/// 液态外观的水：两层波浪从卡片底部涨到今天的工作进度，刚下班的那一分钟
/// 水面闪金光，不上班的日子水满而且不动。只在卡片看得见时动（10 帧的慢
/// 波纹），减少动态效果时是一张静止的图。
struct SlackerWater: View {
    var phase: SlackerClock.Phase
    var level: Double
    var animates: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fps = SlackerClock.liquidFPS(phase, visible: animates, reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? 10), paused: fps == nil)) { timeline in
            let t = fps == nil ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(&context, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let level = min(max(level, 0), 1)
        guard level > 0 else { return }
        // 满水时留一点空，波浪不会顶出卡片上沿。
        let baseY = rect.minY + rect.height * (1 - level * 0.94)
        let steps = 32
        var front = Path()
        for layer in [1, 0] {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            for i in 0...steps {
                let x = Double(i) / Double(steps)
                let lift = BatteryMotion.surface(x: x, t: t, level: max(level * 0.94, 0.3), layer: layer, speed: 0.6)
                path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: baseY - lift * rect.height * 0.6))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            if layer == 1 {
                context.fill(path, with: .color(.white.opacity(0.10)))
            } else {
                front = path
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.26), .white.opacity(0.12)]),
                    startPoint: CGPoint(x: rect.midX, y: baseY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                context.stroke(front, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
            }
        }

        // 刚下班：水面染上一层金色，一起一伏地闪。
        if SlackerClock.isGolden(phase) {
            let glow = reduceMotion ? 0.6 : 0.5 + 0.5 * sin(t * 4)
            let gold = Color(red: 1, green: 0.82, blue: 0.3)
            context.fill(front, with: .color(gold.opacity(0.35 * glow)))
            context.stroke(front, with: .color(gold.opacity(0.9 * glow)), lineWidth: 1.5)
        }
    }
}

/// 小熊猫图：上班敲电脑、下班喝茶、周末在码头睡觉。
struct SlackerPanda: View {
    var art: SlackerClock.Art

    var body: some View {
        if let image = SlackerArt.image(art) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

/// 卡片的颜色、背景图和字体，从配置里读。
@MainActor
struct SlackerLook {
    var background: Color
    var image: NSImage?
    var text: Color
    var fontChoice: SlackerClock.FontChoice

    init(config: WidgetConfig, art: SlackerClock.Art) {
        background = Color(hex: SlackerClock.backgroundHex(config, art: art))
        image = SlackerClock.backgroundImagePath(config).flatMap(SlackerArt.background)
        text = Color(hex: SlackerClock.textHex(config))
        fontChoice = SlackerClock.font(config)
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        Self.font(fontChoice, size: size, weight: weight)
    }

    /// 圆体优先用系统的“圆体-简”（Yuanti SC，可能需要在“字体册”里下载），
    /// 没有时用 SF 圆体，汉字由系统补上。宋体是 macOS 自带的 Songti SC。
    static func font(_ choice: SlackerClock.FontChoice, size: CGFloat, weight: Font.Weight) -> Font {
        switch choice {
        case .system:
            return .system(size: size, weight: weight)
        case .rounded:
            if NSFont(name: "Yuanti SC", size: size) != nil {
                return .custom("Yuanti SC", size: size).weight(weight)
            }
            return .system(size: size, weight: weight, design: .rounded)
        case .mono:
            return .system(size: size, weight: weight, design: .monospaced)
        case .serif:
            if NSFont(name: "Songti SC", size: size) != nil {
                return .custom("Songti SC", size: size).weight(weight)
            }
            return .system(size: size, weight: weight, design: .serif)
        }
    }

    /// 读屏念的一句：“距离下班 02:35:18，发薪 3 天，周五 1 天”。
    static func spoken(_ reading: SlackerClock.Reading) -> String {
        let cells = reading.cells.map { "\($0.label) \($0.value) \($0.unit)".trimmingCharacters(in: .whitespaces) }
        return (["摸鱼时钟，\(reading.title)"] + cells).joined(separator: "，")
    }
}

/// 图片读一次就缓存，和喝水的小熊猫一样是 Resources 里的散装 PNG。
@MainActor
enum SlackerArt {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ art: SlackerClock.Art) -> NSImage? {
        let name = art.imageName
        if let image = cache[name] { return image }
        guard !missing.contains(name),
              let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }

    private static var backgrounds: [String: NSImage] = [:]

    /// 用户选的背景图（已经复制进应用支持目录）。文件不在了就当没有。
    static func background(_ path: String) -> NSImage? {
        if let image = backgrounds[path] { return image }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        backgrounds = [path: image]
        return image
    }

    /// 背景图的存放目录：~/Library/Application Support/<bundle id>/Slacker。
    static var folder: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.docket-zh.app"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "Slacker", directoryHint: .isDirectory)
    }

    /// 选一张本地图片，复制一份到应用支持目录，返回副本的路径。
    /// 原图之后被移动或删除也不影响卡片。
    static func chooseBackground() -> String? {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.message = "选择摸鱼时钟的背景图片"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            let copy = folder.appending(path: "\(UUID().uuidString).\(ext)")
            try fm.copyItem(at: url, to: copy)
            return copy.path
        } catch {
            return nil
        }
    }

    /// 删掉不再使用的副本，只删自己目录里的文件。
    static func discard(_ path: String) {
        guard !path.isEmpty, path.hasPrefix(folder.path) else { return }
        try? FileManager.default.removeItem(atPath: path)
        backgrounds[path] = nil
    }
}

/// 小组件库里的样子：一个周三下午三点多，正好是设计图那一刻。
enum SlackerSamples {
    static var now: Date {
        SlackerClock.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14,
                                                        hour: 15, minute: 24, second: 42)) ?? .now
    }

    /// 截到整分钟。
    static func minute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}
