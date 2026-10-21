import AppKit
import Observation
import SwiftUI

/// 按全局快捷键弹出的快速待办小输入框：输入一句，回车记到扩展栏上第一个
/// 快速待办（放在分组里的也找得到），不打开面板。
///
/// 快捷键默认不设，在“设置 ▸ 快捷键”里录制（`PersistedState.quickTodoHotKey`）。
/// 小框和刘海对话一样是不抢前台的面板，按 Esc 或点外面就收起。
@MainActor
final class QuickTodoCapture {
    static let shared = QuickTodoCapture()

    weak var app: AppState?

    private var panel: KeyablePanel?
    private let model = QuickTodoCaptureModel()
    private var monitors: [Any] = []

    private init() {}

    func apply(_ combo: KeyCombo?) {
        TodoHotKey.shared.onPress = { [weak self] in self?.toggle() }
        TodoHotKey.shared.update(combo)
    }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() {
        isOpen ? close() : show()
    }

    /// 记到哪一个：当前扩展栏布局里从头数第一个快速待办，顶层没有时找分组里的
    /// （见 `QuickTodo.captureTarget`）。
    func target() -> WidgetInstance? {
        QuickTodo.captureTarget(in: app?.customProfile?.items ?? [])
    }

    private func show() {
        model.text = ""
        model.hasTarget = target() != nil
        model.session = UUID()
        let panel = existingOrNewPanel()
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        else { return }
        let size = QuickTodoCaptureView.size
        let visible = screen.visibleFrame
        let origin = CGPoint(x: visible.midX - size.width / 2,
                             y: visible.maxY - visible.height * 0.26 - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        watchForDismissal()
    }

    func close() {
        stopWatching()
        panel?.orderOut(nil)
    }

    fileprivate func submit(_ text: String) {
        guard let target = target() else {
            NSSound.beep()
            return
        }
        guard QuickTodo.clean(text) != nil else {
            close()
            return
        }
        TodoLog.add(text, to: target)
        close()
    }

    private func existingOrNewPanel() -> KeyablePanel {
        if let panel { return panel }
        let size = QuickTodoCaptureView.size
        let hosting = NSHostingView(rootView: QuickTodoCaptureView(model: model,
                                                                   submit: { [weak self] in self?.submit($0) }))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        let panel = KeyablePanel(contentRect: CGRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .statusBar
        self.panel = panel
        return panel
    }

    /// 点小框外面收起。
    private func watchForDismissal() {
        stopWatching()
        let dismiss: (NSEvent) -> Void = { [weak self] event in
            guard let self, let panel = self.panel else { return }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            guard !panel.frame.contains(point) else { return }
            self.close()
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: dismiss) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            dismiss(event)
            return event
        }) { monitors.append(local) }
    }

    private func stopWatching() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

@MainActor @Observable
final class QuickTodoCaptureModel {
    var text = ""
    /// 扩展栏上有没有快速待办可记。
    var hasTarget = true
    /// 每弹出一次换一个，输入框据此重新拿焦点。
    var session = UUID()
}

/// 小框本身：一个圆圈、一行字、右边“回车记下”。液态玻璃，跟着设置里的浅色/深色外观走；
/// 降低透明度时换实心底。
struct QuickTodoCaptureView: View {
    static let size = CGSize(width: 460, height: 58)

    @Bindable var model: QuickTodoCaptureModel
    var submit: (String) -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
            TextField("", text: $model.text,
                      prompt: Text(model.hasTarget ? tr("记一条待办") : tr("先在扩展栏上添加一个快速待办"))
                        .foregroundStyle(Color.panelTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(Color.panelPrimary)
                .focused($focused)
                .disabled(!model.hasTarget)
                .onSubmit { submit(model.text) }
            Text(model.hasTarget ? tr("回车记下") : tr("按 Esc 关闭"))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 18)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if reduceTransparency {
                shape.fill(scheme == .dark ? Color(hex: "#1C1C1E") : Color(hex: "#F4F4F6"))
            } else {
                Color.clear.glassEffect(.regular, in: shape)
            }
        }
        .clipShape(shape)
        .onAppear { focused = true }
        .onChange(of: model.session) { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("快速待办"))
    }
}
