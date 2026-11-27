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
                    Text("小熊猫贴在程序坞上沿散步，或者蜷在屏幕边上。点它跳一下并浮出快捷条，按住可以拖到别处，右键有更多选项。把文件拖到它身上就放进文件暂存。全屏 App 时不显示。")
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
                Toggle(isOn: $settings.stretchReminder) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("活动提醒")
                        Text("连续打字约 50 分钟，小熊猫伸个懒腰，提醒你起来活动一下。中间停下超过 5 分钟或离开电脑就重新计时，专注计时进行中不提醒。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle(isOn: $settings.downloadNotice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下载完成提示")
                        Text("下载文件夹里有文件下好时，小熊猫叼着纸团过来说一声，单击它在访达中显示。第一次可能要允许码头访问下载文件夹。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle(isOn: $settings.pointerPeek) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("指针旁探头")
                        Text("鼠标约 20 秒没动，所选吉祥物在指针旁探出头，一动鼠标、按键或点按就收起。正在打字时不出来。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Toggle(isOn: $settings.livelyFace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("灵动表情")
                        Text("小熊猫正面坐着时，眼睛跟着指针看；单击吃一惊，摸头会害羞，连点会晕乎乎。只用指针位置，不记录。系统打开「减弱动态效果」时不跟随指针，表情只换图不加动效。")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if settings.livelyFace {
                    Toggle(isOn: $settings.headParallax) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("头部立体跟随（实验）")
                            Text("跟着指针轻微倾头。需要开启灵动表情，小熊猫正面坐在程序坞或桌面上时生效。使用现有图片分层，不改变原有脸型；低电量或减弱动态效果时关闭。默认关闭。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Toggle(isOn: $settings.typingCompanion) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("打字陪伴")
                            Text("跟着打字节奏点头、前爪轻敲。需要开启灵动表情，小熊猫正面坐在程序坞或桌面上时生效。只读取系统提供的“距上次按键时间”，不读取、记录或上传按键内容；低电量或减弱动态效果时不动。默认关闭。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if settings.typingCompanion {
                        HStack {
                            Button("预览打字动作（3 秒）") {
                                DesktopPetController.shared.previewTyping()
                            }
                            .disabled(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                                      || ProcessInfo.processInfo.isLowPowerModeEnabled)
                            .help("独立播放动作，不依赖系统键盘检测；需要小熊猫位于程序坞上或随意摆放的位置。")
                            Spacer(minLength: 8)
                        }
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            Text(keyboardActivityStatus)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text("测试说明：先点预览，确认小熊猫能点头和交替轻敲前爪；再正常输入文字。如果预览会动、打字不动，请看上方键盘活动状态。系统开启低电量或减弱动态效果时暂停动画。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle(isOn: $settings.mouseButtonCompanion) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("鼠标双爪联动（实验）")
                            Text("按住鼠标左键时左爪轻敲，按住右键时右爪轻敲；两键一起按时双爪同时响应。只在正面小熊猫静坐、没有其他表情时生效。只读鼠标当前是否按住，不记录点击位置或轨迹；减弱动态效果与低电量时停用。默认关闭。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Toggle(isOn: $settings.mouseHunt) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("鼠标掠过反应")
                            Text("指针快速经过附近时小熊猫会短暂惊讶，约 7 秒冷却。需要开启灵动表情，小熊猫正面坐在程序坞或桌面上时生效。只使用即时坐标，不记录轨迹。减弱动态效果时不触发。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Toggle(isOn: $settings.quietInCalls) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("通话时藏起")
                        Text("麦克风在用（通话、开会）时，桌宠和探头先藏起来，挂断后再出来。只看麦克风开没开，不录音。")
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

    /// 状态只显示“距上一次按键的时间”是否新鲜，不接收键值、文本或按键历史。
    private var keyboardActivityStatus: String {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        guard idle.isFinite, idle >= 0 else {
            return "键盘活动：系统当前无法读取（预览按钮仍可测试动画）"
        }
        return idle <= DesktopPetCompanionState.keyFreshWindow
            ? "键盘活动：已检测到输入"
            : "键盘活动：等待输入"
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
