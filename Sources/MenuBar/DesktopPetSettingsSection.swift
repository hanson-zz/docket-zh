import AppKit
import SwiftUI

/// 设置 ▸ 小组件 ▸ 桌面宠物：总开关（默认关）和废纸篓救回（单独默认关）。
/// 第一次打开救回时先说明要哪两项权限，同意了才打开。
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
                    Text("小熊猫贴在程序坞上沿散步、发呆，几分钟没操作就睡觉，点它会跳一下。全屏 App 或程序坞自动隐藏时不显示。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            if settings.enabled {
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
            Text("开着专注计时时小熊猫坐在程序坞上陪你，完成一轮会欢呼（码头 Pro）。")
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
