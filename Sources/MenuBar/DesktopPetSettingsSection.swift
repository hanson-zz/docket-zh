import AppKit
import SwiftUI

/// 设置 ▸ 小组件 ▸ 桌面宠物：总开关（默认关）、停靠位置、大小、头顶气泡、唤出快捷键
/// 和废纸篓救回（单独默认关）。第一次打开救回时先说明要哪两项权限，同意了才打开。
struct DesktopPetSettingsSection: View {
    @Binding var settings: DesktopPetSettings

    @AppStorage("desktopPet.rescueExplained") private var explained = false
    @State private var explaining = false
    private var trash: TrashMonitor { .shared }

    var body: some View {
        Section {
            Toggle(isOn: $settings.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("桌面宠物")
                    Text("小熊猫贴在程序坞上沿散步，或者蜷在屏幕边上。点它跳一下并浮出快捷条，按住可以拖到别处，右键有更多选项。全屏 App 时不显示。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            if settings.enabled {
                Picker(selection: $settings.anchor) {
                    ForEach(DesktopPetAnchor.allCases, id: \.self) { anchor in
                        Text(verbatim: anchor.title).tag(anchor)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("停靠位置")
                        Text(anchorNote)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Picker("大小", selection: $settings.size) {
                    ForEach(DesktopPetSize.allCases, id: \.self) { size in
                        Text(verbatim: size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $settings.bubbles) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("头顶气泡")
                        Text("专注开始、还剩 5 分钟和完成，收音机播放的台，插电、充满和低电量，喝水提醒到点时，小熊猫头顶说一句，几秒后消失。同一类 30 秒内只说一次。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent {
                    HStack(spacing: 6) {
                        ShortcutRecorder(combo: settings.hotKey) { settings.hotKey = $0 }
                        if settings.hotKey != nil {
                            Button("清除") { settings.hotKey = nil }
                                .controlSize(.small)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("唤出小熊猫")
                        Text("默认不设。按下时小熊猫跳一下并浮出快捷条（新建快速待办、专注、收音机、展开码头）。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle(isOn: rescueBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("废纸篓救回")
                        Text("刚拖进废纸篓的文件或文件夹（10 秒内），小熊猫跑过去叼回来，放回原处。清空废纸篓不受影响。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                if settings.trashRescue, trash.loaded, trash.needsAccess {
                    LabeledContent {
                        Button("打开设置") { trash.openAccessSettings() }
                    } label: {
                        Text("需要完全磁盘访问权限才看得见废纸篓")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("桌面宠物")
        } footer: {
            Text("开着专注计时时小熊猫坐着陪你，完成一轮会欢呼（码头 Pro）。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .alert(Text("废纸篓救回需要两项权限"), isPresented: $explaining) {
            Button("打开并去授权") {
                turnOnRescue()
                trash.openAccessSettings()
            }
            Button("直接打开") { turnOnRescue() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("完全磁盘访问权限：看见刚放进废纸篓的文件和它原来的位置。自动化里允许码头控制访达：请访达把文件放回原处，第一次放回时系统会问。没有自动化权限时，小熊猫只把文件叼回来，给一个「放回原处」的按钮。")
        }
    }

    /// 停靠位置下面的一行说明，随选项变。
    private var anchorNote: String {
        switch settings.anchor {
        case .dock: tr("在程序坞上沿散步、发呆；程序坞自动隐藏或在侧边时先蜷在屏幕下边缘。")
        case .left, .right: tr("平时趴在边上，偶尔探头、伸懒腰、沿边挪几步，不挡菜单栏和程序坞。")
        case .top: tr("平时趴在菜单栏下方，偶尔探头、伸懒腰、沿边挪几步。")
        case .bottom: tr("平时趴在屏幕底边，偶尔探头、伸懒腰、沿边挪几步。")
        case .free: tr("拖到哪就坐在哪，记住位置。")
        }
    }

    private var rescueBinding: Binding<Bool> {
        Binding(
            get: { settings.trashRescue },
            set: { on in
                if on, !explained {
                    explaining = true
                } else {
                    settings.trashRescue = on
                }
            })
    }

    private func turnOnRescue() {
        explained = true
        settings.trashRescue = true
    }
}
