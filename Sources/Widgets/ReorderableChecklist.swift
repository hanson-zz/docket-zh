import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 通用的「可拖动勾选列表」：每行左边拖柄、接着一个勾、再是名字。
///
/// 设置页里系统活动的指标、圆环仪表、快速开关、环境音的声音、摸鱼时钟显示项
/// 用它代替原来的一列开关；快速开关和圆环仪表的面板编辑也用它。规则在 Core 的
/// `OrderedChecklist`：勾上的按存的先后排在前面，拖动排序；没勾的跟在后面，
/// 拖柄画淡、不能拖。拖动时每经过一行就写一次，卡片立刻跟着变。
///
/// 拖不动的场合（辅助功能、触控板不方便）右键菜单有上移、下移、移到最前。
struct ReorderableChecklist: View {
    struct Choice: Identifiable {
        var value: String
        var title: String
        var isPro: Bool = false
        var id: String { value }
    }

    enum Look {
        /// 设置窗口：跟着系统的浅色、深色。
        case settings
        /// 深色玻璃面板：白字，勾用面板的强调色。
        case panel(accent: Color, ink: Color)
    }

    var choices: [Choice]
    var saved: [String]
    var look: Look = .settings
    /// 最多勾几项；nil 不限。
    var limit: Int?
    /// 勾上前问一下（Pro 工具没解锁时返回 false，由调用方弹付费墙）。
    var canEnable: (String) -> Bool = { _ in true }
    var write: ([String]) -> Void

    @State private var dragging: String?

    private var all: [String] { choices.map(\.value) }
    private var rows: [OrderedChecklist.Row] { OrderedChecklist.rows(saved: saved, all: all) }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.value) { row in
                if let choice = choices.first(where: { $0.value == row.value }) {
                    rowView(choice, on: row.on)
                }
            }
        }
        .onContinuousHover { _ in
            // 拖到窗口外面松手不会有 performDrop；鼠标回来、按键已松开时收起“拖动中”。
            if dragging != nil, NSEvent.pressedMouseButtons == 0 { dragging = nil }
        }
        .onDisappear { dragging = nil }
        .animation(.easeInOut(duration: 0.15), value: saved)
    }

    // MARK: 一行

    @ViewBuilder
    private func rowView(_ choice: Choice, on: Bool) -> some View {
        let isDragging = dragging == choice.value
        let row = HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondary.opacity(on ? (isDragging ? 1 : 0.8) : 0.3))
                .frame(width: 16)
                .help(on ? tr("拖动排序") : tr("勾上后才能排序"))
                .accessibilityHidden(true)
            Button {
                toggle(choice.value, to: !on)
            } label: {
                HStack(spacing: 8) {
                    check(on)
                    Text(verbatim: choice.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primary)
                        .lineLimit(1)
                    if choice.isPro { ProBadge() }
                    Spacer(minLength: 0)
                    if isDragging {
                        Text(verbatim: tr("拖动中"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(rowFill(isDragging)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(isDragging ? accent.opacity(0.8) : .clear, lineWidth: 1.2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(choice.title)
        .accessibilityValue(on ? tr("已勾选") : tr("未勾选"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle(choice.value, to: !on) }

        if on {
            row
                .onDrag {
                    dragging = choice.value
                    return NSItemProvider(object: choice.value as NSString)
                }
                .onDrop(of: [UTType.text], delegate: Drop(target: choice.value, dragging: $dragging, move: move))
                .contextMenu { moveMenu(choice.value) }
                .accessibilityAction(named: Text(verbatim: tr("上移"))) { step(choice.value, by: -1) }
                .accessibilityAction(named: Text(verbatim: tr("下移"))) { step(choice.value, by: 1) }
        } else {
            row
                .onDrop(of: [UTType.text], delegate: Drop(target: choice.value, dragging: $dragging, move: move))
        }
    }

    private func check(_ on: Bool) -> some View {
        ZStack {
            if on {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(ink)
            } else {
                Circle().strokeBorder(secondary.opacity(0.6), lineWidth: 1.3)
            }
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private func moveMenu(_ value: String) -> some View {
        let order = OrderedChecklist.ordered(saved, all: all)
        Button(tr("移到最前")) {
            if let first = order.first, let next = OrderedChecklist.move(saved: saved, all: all, value: value, onto: first) {
                write(next)
            }
        }
        .disabled(order.first == value)
        Button(tr("上移")) { step(value, by: -1) }
            .disabled(order.first == value)
        Button(tr("下移")) { step(value, by: 1) }
            .disabled(order.last == value)
    }

    // MARK: 写

    private func toggle(_ value: String, to on: Bool) {
        if on, !canEnable(value) { return }
        guard let next = OrderedChecklist.toggle(saved: saved, all: all, value: value, on: on, limit: limit) else {
            if !on { NSSound.beep() }
            return
        }
        write(next)
    }

    private func step(_ value: String, by offset: Int) {
        if let next = OrderedChecklist.step(saved: saved, all: all, value: value, by: offset) { write(next) }
    }

    private func move(_ value: String, onto target: String) {
        if let next = OrderedChecklist.move(saved: saved, all: all, value: value, onto: target) {
            withAnimation(.easeInOut(duration: 0.15)) { write(next) }
        }
    }

    /// 经过哪一行就挪到哪一行的位置；松手只收起“拖动中”。
    private struct Drop: DropDelegate {
        var target: String
        @Binding var dragging: String?
        var move: (String, String) -> Void

        func validateDrop(info: DropInfo) -> Bool { dragging != nil }

        func dropEntered(info: DropInfo) {
            guard let dragging, dragging != target else { return }
            move(dragging, target)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            dragging = nil
            return true
        }
    }

    // MARK: 颜色

    private var primary: Color {
        switch look {
        case .settings: .primary
        case .panel: .panelPrimary
        }
    }

    private var secondary: Color {
        switch look {
        case .settings: .secondary
        case .panel: .panelSecondary
        }
    }

    private var accent: Color {
        switch look {
        case .settings: .accentColor
        case .panel(let accent, _): accent
        }
    }

    /// 主题色写成字：面板在浅色玻璃上加深一档。
    private var accentText: Color {
        switch look {
        case .settings: .accentColor
        case .panel(let accent, _): accent.panelReadable
        }
    }

    private var ink: Color {
        switch look {
        case .settings: .white
        case .panel(_, let ink): ink
        }
    }

    private func rowFill(_ dragging: Bool) -> Color {
        switch look {
        case .settings: dragging ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05)
        case .panel: dragging ? Color.panelFillStrong : Color.panelFill
        }
    }
}
