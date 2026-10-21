import AppKit
import SwiftUI

/// 音量：这台 Mac 从哪儿出声、总共多大声。
///
/// 上面一排输出设备（MacBook 扬声器、AirPods、显示器……），点一下就切过去，
/// 和控制中心里选一样，不用跳去系统设置；设备多于三个时最后一格是“…”，
/// 弹出全部设备。下面一根总音量，点喇叭静音。每个应用自己的音量归“应用音量”，
/// 这首歌归“正在播放”，这里都不放。
struct VolumeTile: View {
    /// 颜色面板里选的主题色（`WidgetTintStyle`），选过颜色时原来写死的强调色跟着换。
    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    var instance: WidgetInstance
    var context: WidgetContext

    private var audio: AudioOutput { AudioOutput.shared }

    private var level: Double? { context.isPreview ? 0.58 : audio.volume }
    private var muted: Bool { context.isPreview ? false : audio.muted }

    private static let sampleDevices = [
        OutputDevice(id: 1, uid: "sample.builtin", name: tr("MacBook Pro 扬声器"), transport: .builtIn),
        OutputDevice(id: 2, uid: "sample.airpods", name: "AirPods Pro", transport: .bluetooth),
        OutputDevice(id: 3, uid: "sample.display", name: tr("显示器"), transport: .hdmi),
    ]

    private var devices: [OutputDevice] { context.isPreview ? Self.sampleDevices : audio.devices }
    private var currentID: UInt32? { context.isPreview ? 2 : audio.currentID }

    private var current: OutputDevice? { devices.first { $0.id == currentID } }

    private var name: String {
        if context.isPreview { return "AirPods Pro" }
        return current?.name ?? audio.deviceName
    }

    private static let pink = Color(hex: PaletteColor.pink.hex)
    /// 选中的输出设备：原来的粉，选过颜色就换成选的。
    private var accent: Color { theme.chosen(or: Self.pink, dark: scheme == .dark) }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical { column } else { strip }
        }
        .onAppear { if !context.isPreview { audio.start() } }
    }

    // MARK: 底栏 200×62

    private var strip: some View {
        let picked = OutputDevices.visible(devices, current: currentID)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                ForEach(picked.shown) { device in
                    deviceButton(device, width: 28, height: 22)
                }
                if picked.overflow > 0 { moreButton(height: 22) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name.isEmpty ? tr("无输出设备") : name)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(devices.count > 1 ? tr("点图标换输出") : tr("只有一个输出"))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, 3)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                muteButton(size: 12)
                slider
                if let level {
                    Text(OutputDevices.percentText(muted ? 0 : level))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(WidgetStyle.primary)
                        .frame(minWidth: 30, alignment: .trailing)
                }
            }
        }
    }

    // MARK: 侧边栏 76 宽

    private var column: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                if let current {
                    Button {
                        guard !context.isPreview else { return }
                        OutputMenu.popUp(devices: devices, current: currentID)
                    } label: {
                        deviceGlyph(current, selected: true, width: 26, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(tr("换输出设备"))
                    .accessibilityLabel(tr("换输出设备，现在是 \(current.name)"))
                }
                if let level {
                    Text(OutputDevices.percentText(muted ? 0 : level))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            HStack(spacing: 3) {
                muteButton(size: 10)
                slider
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var slider: some View {
        if let level {
            Slider(value: Binding(
                get: { muted ? 0 : level },
                set: { if !context.isPreview { audio.set(volume: $0) } }),
                   in: 0...1)
                .controlSize(.mini)
                .tint(WidgetStyle.primary)
                .disabled(context.isPreview)
                .accessibilityLabel(tr("总音量"))
        } else {
            Text("此设备不支持调节音量")
                .font(WidgetStyle.caption(13))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    private func muteButton(size: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            audio.setMuted(!audio.muted)
        } label: {
            Image(systemName: speaker)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(muted ? Color(hex: PaletteColor.red.hex) : WidgetStyle.primary)
                .frame(width: size + 6, height: size + 6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(muted ? tr("取消静音") : tr("静音"))
        .accessibilityLabel(muted ? tr("取消静音") : tr("静音"))
    }

    private func deviceButton(_ device: OutputDevice, width: CGFloat, height: CGFloat) -> some View {
        let selected = device.id == currentID
        return Button {
            guard !context.isPreview, !selected else { return }
            audio.select(device)
        } label: {
            deviceGlyph(device, selected: selected, width: width, height: height)
        }
        .buttonStyle(.plain)
        .help(device.name)
        .accessibilityLabel(selected ? tr("\(device.name)（正在使用）") : tr("切换到 \(device.name)"))
    }

    private func deviceGlyph(_ device: OutputDevice, selected: Bool, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
            .fill(selected ? accent.opacity(0.32) : WidgetStyle.primary.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
                    .strokeBorder(selected ? accent.opacity(0.55) : .clear, lineWidth: 0.75)
            }
            .overlay {
                Image(systemName: OutputDevices.symbol(for: device))
                    .font(.system(size: height * 0.52, weight: .medium))
                    .foregroundStyle(WidgetStyle.primary.opacity(selected ? 1 : 0.62))
            }
            .frame(width: width, height: height)
            .contentShape(.rect)
    }

    private func moreButton(height: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            OutputMenu.popUp(devices: devices, current: currentID)
        } label: {
            RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
                .fill(WidgetStyle.primary.opacity(0.08))
                .overlay {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WidgetStyle.secondary)
                }
                .frame(width: 16, height: height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("全部输出设备"))
        .accessibilityLabel(tr("全部输出设备"))
    }

    private var speaker: String {
        guard let level, !muted else { return "speaker.slash.fill" }
        switch level {
        case 0: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// 全部输出设备的菜单，当前的打勾，选一项就切过去。
@MainActor
final class OutputMenu: NSObject {
    private var chosen: OutputDevice?
    private let devices: [OutputDevice]

    private init(devices: [OutputDevice]) {
        self.devices = devices
    }

    static func popUp(devices: [OutputDevice], current: UInt32?) {
        let picker = OutputMenu(devices: OutputDevices.sorted(devices))
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: tr("输出设备")))
        for (index, device) in picker.devices.enumerated() {
            let item = NSMenuItem(title: device.name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = picker
            item.tag = index
            item.state = device.id == current ? .on : .off
            item.image = NSImage(systemSymbolName: OutputDevices.symbol(for: device), accessibilityDescription: nil)
            menu.addItem(item)
        }
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        if let device = picker.chosen, device.id != current {
            AudioOutput.shared.select(device)
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard devices.indices.contains(sender.tag) else { return }
        chosen = devices[sender.tag]
    }
}
