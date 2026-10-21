import SwiftUI
import AppKit

/// 天气面板里能横向滚动的区域（逐小时那一排），面板坐标（左上角原点）。
/// 两指左右滑落在里面时让它自己滚，不换城市。
@MainActor
final class CitySwipeZones {
    var hourly: CGRect = .zero

    func contains(_ point: CGPoint) -> Bool {
        hourly.width > 0 && hourly.contains(point)
    }
}

/// 天气面板的触控板两指左右滑和左右方向键。
///
/// 垫在浏览态后面，自己不接点击（命中测试永远 nil），用本地事件监视器看这个
/// 面板窗口的滚动和按键：面板调了 `makeKey`，事件会送到本 App。滚动事件照样
/// 往下传，面板的上下滚动和逐小时的横向滚动都不受影响；只是落在可横向滚动的
/// 区域（`isExcluded`，或者指针下面是一个内容比可视区宽的 NSScrollView）里的
/// 滑动这一下不算换城市。惯性阶段的事件不喂，手指抬起时才定换不换，一下最多换一个。
///
/// 方向键只在面板是 key 窗口、焦点不在输入框里时接，接了就吞掉。
struct CitySwipeCatcher: NSViewRepresentable {
    var enabled: Bool
    var isExcluded: (CGPoint) -> Bool
    /// 拖动中的横向位移（手指方向，pt）。
    var onChange: (Double) -> Void
    /// 一下滑动结束：+1 下一个、-1 上一个、nil 不换（弹回）。
    var onEnd: (Int?) -> Void
    var onKey: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        update(view)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        update(view)
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.stop()
    }

    private func update(_ view: CatcherView) {
        view.enabled = enabled
        view.isExcluded = isExcluded
        view.onChange = onChange
        view.onEnd = onEnd
        view.onKey = onKey
    }

    final class CatcherView: NSView {
        var enabled = false
        var isExcluded: ((CGPoint) -> Bool)?
        var onChange: ((Double) -> Void)?
        var onEnd: ((Int?) -> Void)?
        var onKey: ((Int) -> Void)?

        private var monitors: [Any] = []
        private var tracker = WeatherCitySwipe.Tracker()
        /// 这一下滑动从开头就算不算（落在横向滚动区域里的整下都不算）。
        private var tracking = false
        private var moved = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
                self?.scrolled(event)
                return event
            }) { monitors.append(scroll) }
            if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                guard let self, self.pressed(event) else { return event }
                return nil
            }) { monitors.append(keys) }
        }

        func stop() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
            tracker = WeatherCitySwipe.Tracker()
            tracking = false
            moved = false
        }

        // MARK: 两指滑

        private func scrolled(_ event: NSEvent) {
            guard let window, event.window === window else { return }
            // 惯性的尾巴不算，手指抬起时已经定了。
            guard event.momentumPhase.isEmpty else { return }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                tracker.begin()
                moved = false
                tracking = enabled && event.hasPreciseScrollingDeltas && accepts(event)
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                guard tracking else { return }
                tracking = false
                let step = event.phase.contains(.cancelled) ? nil : tracker.end()
                if moved || step != nil { onEnd?(step) }
                moved = false
                return
            }
            // 鼠标滚轮（没有阶段）不管。
            guard tracking, !event.phase.isEmpty else { return }
            // 「自然滚动」打开时位移和手指同向，关掉时反向；换算成手指方向。
            let sign: Double = event.isDirectionInvertedFromDevice ? 1 : -1
            let horizontal = tracker.feed(dx: Double(event.scrollingDeltaX) * sign,
                                          dy: Double(event.scrollingDeltaY) * sign,
                                          at: event.timestamp)
            if horizontal {
                moved = true
                onChange?(tracker.translation)
            }
        }

        /// 这一下从哪儿开始：在面板这块里，不在可横向滚动的区域里。
        private func accepts(_ event: NSEvent) -> Bool {
            let local = convert(event.locationInWindow, from: nil)
            guard bounds.contains(local) else { return false }
            let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
            if isExcluded?(point) == true { return false }
            return !overHorizontalScroller(event)
        }

        /// 指针下面是不是一个横向放不下、能左右滚的 NSScrollView。
        private func overHorizontalScroller(_ event: NSEvent) -> Bool {
            guard let content = window?.contentView else { return false }
            let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            var view = content.hitTest(point)
            while let current = view {
                if let scroll = current as? NSScrollView, let document = scroll.documentView,
                   document.frame.width > scroll.contentView.bounds.width + 1 {
                    return true
                }
                view = current.superview
            }
            return false
        }

        // MARK: 方向键

        private func pressed(_ event: NSEvent) -> Bool {
            guard enabled, let window, event.window === window, window.isKeyWindow else { return false }
            guard event.keyCode == 123 || event.keyCode == 124 else { return false }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty else { return false }
            // 在输入框里打字时方向键是挪光标。
            if window.firstResponder is NSText { return false }
            onKey?(event.keyCode == 123 ? -1 : 1)
            return true
        }
    }
}
