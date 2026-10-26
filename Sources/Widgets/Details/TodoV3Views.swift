import AppKit
import SwiftUI

// 快速待办 v3 面板和卡片共用的几样小东西：标签色、进度环、彩点、最近 7 天小圆点、
// 深色撤销条、面板里的键盘（⌘1 到 ⌘5、⌘0、⌘T、⌥↑ / ⌥↓、⌘Z）。

extension TodoTag {
    /// 色块、色条用的原色。
    var color: Color { Color(hex: hex) }
    /// 圆圈、细色条用：浅色玻璃上不到 3:1 时压深一点（黄色、绿色），深色下原样。
    var graphic: Color { color.panelGraphic }
}

/// 进度环：轨道 + 圆头弧，全部做完变绿。环里放什么由调用方给。
struct TodoProgressRing<Inner: View>: View {
    var fraction: Double
    var complete: Bool
    var lineWidth: CGFloat
    var tint: Color
    var inner: Inner

    init(fraction: Double, complete: Bool, lineWidth: CGFloat, tint: Color, @ViewBuilder inner: () -> Inner) {
        self.fraction = fraction
        self.complete = complete
        self.lineWidth = lineWidth
        self.tint = tint
        self.inner = inner()
    }

    static var green: Color { Color(hex: "#2FA36B") }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.panelTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: complete ? 1 : max(0, min(1, fraction)))
                .stroke((complete ? Self.green : tint).panelGraphic,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            inner
        }
        .accessibilityHidden(true)
    }
}

/// 小熊猫图片（Resources/Pet/pet-panda-*.png），找不到时什么也不画。
struct TodoPanda: View {
    var name: String
    var size: CGFloat

    var body: some View {
        if let image = PandaArt.image(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// 「今天」清空时小熊猫周围的五色小彩点：不发光，开头从中间撒开一下，之后停在原处。
struct TodoConfetti: View {
    var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 每个点：角度（弧度）、离中心的远近（0...1）、颜色、大小、是不是短条。
    private static let dots: [(angle: Double, reach: Double, tag: TodoTag, size: CGFloat, bar: Bool)] = [
        (-2.7, 0.92, .purple, 4, true), (-2.3, 0.70, .orange, 5, false), (-1.95, 0.98, .green, 4, true),
        (-1.2, 0.95, .yellow, 4, true), (-0.75, 0.78, .red, 5, false), (-0.35, 1.0, .purple, 4, true),
        (0.15, 0.86, .orange, 4, true), (0.6, 0.96, .green, 5, false), (2.55, 0.92, .yellow, 4, true),
        (2.95, 0.80, .red, 5, false), (1.2, 1.0, .orange, 4, false), (-3.05, 1.0, .green, 4, true),
    ]

    var body: some View {
        if let startedAt, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: Date().timeIntervalSince(startedAt) > 1)) { timeline in
                canvas(progress: min(1, max(0, timeline.date.timeIntervalSince(startedAt) / 0.6)))
            }
        } else {
            canvas(progress: 1)
        }
    }

    private func canvas(progress: Double) -> some View {
        let eased = 1 - (1 - progress) * (1 - progress)
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for (index, dot) in Self.dots.enumerated() {
                let reach = radius * dot.reach * eased
                let point = CGPoint(x: center.x + cos(dot.angle) * reach, y: center.y + sin(dot.angle) * reach)
                var piece = context
                piece.opacity = 0.35 + 0.65 * eased
                piece.translateBy(x: point.x, y: point.y)
                piece.rotate(by: .radians(dot.angle + Double(index)))
                let rect = dot.bar
                    ? CGRect(x: -dot.size, y: -1, width: dot.size * 2, height: 2)
                    : CGRect(x: -dot.size / 2, y: -dot.size / 2, width: dot.size, height: dot.size)
                let shape = dot.bar ? Path(roundedRect: rect, cornerRadius: 1) : Path(ellipseIn: rect)
                piece.fill(shape, with: .color(dot.tag.color))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 最近 7 天的小圆点：清空过的绿底白勾，没清空的空心圈，最后一个写「今」。
struct TodoWeekDots: View {
    var days: [Bool]
    var labels: [String]?
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: labels == nil ? 4 : 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, cleared in
                VStack(spacing: 4) {
                    ZStack {
                        if cleared {
                            Circle().fill(TodoProgressRing<EmptyView>.green.panelGraphic)
                            Image(systemName: "checkmark")
                                .font(.system(size: size * 0.5, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Color.panelTertiary, lineWidth: 1.2)
                        }
                    }
                    .frame(width: size, height: size)
                    if let labels, index < labels.count {
                        Text(labels[index])
                            .font(.system(size: 13, weight: index == days.count - 1 ? .bold : .regular))
                            .foregroundStyle(index == days.count - 1 ? Color.panelPrimary : Color.panelSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: labels == nil ? nil : .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("最近 7 天清空了 \(days.filter { $0 }.count) 天"))
    }

    /// 7 个日子下面的字：星期几的短名，最后一个是「今」。
    static func labels(_ days: [String], calendar: Calendar = .current) -> [String] {
        days.enumerated().map { index, key in
            if index == days.count - 1 { return tr("今") }
            guard let date = TodoDay.date(key, calendar: calendar) else { return "" }
            switch calendar.component(.weekday, from: date) {
            case 1: return tr("日")
            case 2: return tr("一")
            case 3: return tr("二")
            case 4: return tr("三")
            case 5: return tr("四")
            case 6: return tr("五")
            default: return tr("六")
            }
        }
    }
}

/// 底部的深色撤销条：勾掉或删掉后停 6 秒，点「撤销 ⌘Z」放回原处。
/// 深色实底在浅色、深色玻璃上都是同一个样子（像系统的提示条），不是大面积发光。
struct TodoUndoToast: View {
    var step: TodoUndoStep
    var more: Int
    var undo: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(step.kind == .deleted ? Color.white.opacity(0.25) : TodoProgressRing<EmptyView>.green)
                Image(systemName: step.kind == .deleted ? "trash" : "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 16, height: 16)
            Text(step.caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.96))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Button(action: undo) {
                Text(more > 0 ? tr("撤销（还有 \(more) 步）") : tr("撤销 ⌘Z"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "#FFB273"))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("撤销"))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(scheme == .dark ? Color(white: 0.30, opacity: 0.96) : Color(red: 0.157, green: 0.157, blue: 0.18, opacity: 0.94)))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

// MARK: - 键盘

/// 面板里的键：⌘1 到 ⌘5 标颜色、⌘0 清除、⌘T 移到今天 / 稍后、⌥↑ / ⌥↓ 挪一格、⌘Z 撤销。
enum TodoKey: Equatable {
    case tag(Int)
    case clearTag
    case toggleToday
    case move(Int)
    case undo
}

/// 在面板所在的窗口里听键盘。输入法正在组字时（有 marked text）一律放过，不抢键；
/// `handle` 返回 false 的也放过，交给系统照常处理。
struct TodoKeyCatcher: NSViewRepresentable {
    var handle: (TodoKey) -> Bool

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handle = handle
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.handle = handle
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.stop()
    }

    final class CatcherView: NSView {
        var handle: ((TodoKey) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      let key = Self.key(for: event) else { return event }
                if let input = window.firstResponder as? NSTextInputClient, input.hasMarkedText() { return event }
                return self.handle?(key) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        static func key(for event: NSEvent) -> TodoKey? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.option] || flags == [.option, .function] || flags == [.option, .numericPad, .function] {
                switch event.keyCode {
                case 126: return .move(-1)
                case 125: return .move(1)
                default: return nil
                }
            }
            guard flags == [.command] else { return nil }
            // 数字和字母按键位认，中文输入法开着时也一样。
            switch event.keyCode {
            case 18: return .tag(1)
            case 19: return .tag(2)
            case 20: return .tag(3)
            case 21: return .tag(4)
            case 23: return .tag(5)
            case 29: return .clearTag
            case 17: return .toggleToday
            case 6: return .undo
            default: return nil
            }
        }
    }
}
