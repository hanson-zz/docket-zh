import AppKit
import SwiftUI

/// Where a shortcut is chosen, and where the reason it did not run is said
/// out loud.
///
/// The tile can only ever show a name and a glyph, which is fine until the
/// shortcut is renamed in Shortcuts.app and the name stored here stops
/// matching anything. The tool reports that plainly, on stderr, and this is
/// the surface that can repeat it and offer the list again. Without that the
/// widget would simply stop working one day with nothing to say.
///
/// Having no shortcuts at all is an ordinary state and gets its own words
/// rather than an empty menu: a Mac nobody has opened Shortcuts on has none,
/// and a picker with nothing in it reads as broken. Same judgement as
/// CalendarDetail, which hides its picker rather than show an empty one.
///
/// The list is read when the panel opens. It can only change in Shortcuts.app,
/// and going there means leaving this panel, which dismisses it, so polling
/// would be a timer spent on a value that cannot move while it is on screen.
struct ShortcutDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: ShortcutsService { ShortcutsService.shared }

    private var chosen: String {
        instance.config.string("name").trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        // The widget's own violet. A shortcut carries a colour in Shortcuts,
        // but the tool that lists them names them and nothing else, so the
        // card cannot borrow it.
        DetailCard {
            MeshBackdrop(color: Self.accent)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header
                outcome
                chooser
                HStack(spacing: 8) {
                    button(tr("打开快捷指令"), fill: .white.opacity(0.24), label: .white, action: openShortcuts)
                    if !chosen.isEmpty {
                        button(tr("清除"), fill: .white.opacity(0.14), label: .white) {
                            WidgetWriter.write(instance) { $0.set("name", .string("")) }
                        }
                    }
                }
            }
        }
        .task { await service.load() }
    }

    // MARK: Pieces

    /// The shortcut's name as the headline, and run as the one big control:
    /// a white disc that is the point of the widget.
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(running ? tr("正在运行") : chosen.isEmpty ? tr("请在下方选择") : tr("就绪"))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.6))
                Text(chosen.isEmpty ? tr("未选择快捷指令") : chosen)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if !chosen.isEmpty {
                Button {
                    if running { service.stop() } else { service.run(chosen) }
                } label: {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: running ? 0 : 1.5)
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.24), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(running ? tr("停止") : tr("运行"))
            }
        }
    }

    /// Only ever the last run, and only in words the tool actually produced.
    @ViewBuilder private var outcome: some View {
        switch service.lastRun {
        case .failed(let name, let why) where name == chosen:
            note(why, tint: Self.red)
        case .cancelled(let name) where name == chosen:
            note(tr("已停止。"), tint: nil)
        case .ok(let name) where name == chosen:
            note(tr("已完成。"), tint: nil)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var chooser: some View {
        if let error = service.loadError {
            note(error, tint: Self.red)
        } else if service.loadedAt == nil {
            note(tr("正在读取你的快捷指令。"), tint: nil)
        } else if service.names.isEmpty {
            note(tr("你还没有快捷指令。在“快捷指令”App 中创建一个，它就会显示在这里。"), tint: nil)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(service.names.prefix(Self.visibleRows), id: \.self) { name in
                    row(name)
                }
                if service.names.count > Self.visibleRows {
                    Text(tr("“快捷指令”中还有 \(service.names.count - Self.visibleRows) 个"))
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(10)
            .glassPane()
        }
    }

    private func row(_ name: String) -> some View {
        Button {
            WidgetWriter.write(instance) { $0.set("name", .string(name)) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: name == chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(name == chosen ? Color.white : .white.opacity(0.5))
                Text(name)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(WidgetStyle.caption(11))
            .foregroundStyle(tint ?? .white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func button(_ title: String, fill: Color, label: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WidgetStyle.label(12))
                .foregroundStyle(label)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(fill, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: State

    private var running: Bool { !chosen.isEmpty && service.running == chosen }

    /// The panel sizes itself to its content, so an unbounded list would grow
    /// off the screen. Same cut-off reasoning as RemindersDetail.
    private static let visibleRows = 6

    private static let accent = Color(hex: "#A855F7")
    private static let red = Color(hex: "#FF6B6B")

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        NSWorkspace.shared.open(url)
    }
}
