import AppKit
import SwiftUI
@preconcurrency import UserNotifications

/// 设置 ▸ 小组件 ▸ Codex 用量 ▸ 声音：等你确认（默认开）、一轮完成、额度快用完
/// （默认关），和用哪个 macOS 提示音。声音跟着系统通知走，勿扰和专注模式由系统
/// 静音；码头的通知被关了时在开关下面提示去开启，还没问过时给一个「允许通知」。
struct CodexSoundSettings: View {
    var instance: WidgetInstance
    var write: ((inout WidgetConfig) -> Void) -> Void

    var body: some View {
        let sound = CodexChimeSettings(config: instance.config)
        Section {
            toggle(CodexChimeSettings.waitingKey, title: tr("等你确认"),
                   note: tr("Codex 要你批准一条命令或修改时响"), on: sound.waiting)
            toggle(CodexChimeSettings.doneKey, title: tr("一轮完成"),
                   note: tr("每做完一轮响一下"), on: sound.done)
            toggle(CodexChimeSettings.quotaKey, title: tr("额度快用完"),
                   note: tr("5 小时或每周额度用到 80% 时响一下"), on: sound.quota)
            Picker(tr("提示音"), selection: Binding(
                get: { CodexChimeSettings(config: instance.config).tone },
                set: { tone in
                    write { $0.set(CodexChimeSettings.toneKey, .string(tone)) }
                    NSSound(named: NSSound.Name(tone))?.play()
                })) {
                ForEach(CodexChimeSettings.tones, id: \.self) { tone in
                    Text(verbatim: tone).tag(tone)
                }
            }
            .disabled(!sound.anyOn)
            CodexNotificationAsk(active: sound.anyOn)
        } header: {
            Text("声音")
        } footer: {
            Text("默认只开「等你确认」。声音跟着系统通知响，勿扰和专注模式下由系统静音。")
        }
    }

    private func toggle(_ key: String, title: String, note: String, on: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { on },
            set: { value in write { $0.set(key, .bool(value)) } })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                NotificationsOffNote(active: on)
            }
        }
    }
}

/// 还没问过通知权限时（系统设置里没有码头这一项）：给一个「允许通知」，点了
/// 请系统弹授权框。被拒绝的情况由开关下面的 `NotificationsOffNote` 提示。
private struct CodexNotificationAsk: View {
    var active: Bool
    @State private var undecided = false

    var body: some View {
        Group {
            if active && undecided {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.orange)
                    Text("码头还没有通知权限，提示音要靠系统通知才能响。")
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("允许通知") {
                        CodexService.shared.requestNotificationPermission()
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            await read()
                        }
                    }
                }
            }
        }
        .task(id: active) { await read() }
    }

    private func read() async {
        guard NotificationAccess.canReadSettings(bundleURL: Bundle.main.bundleURL) else { return }
        let raw = await Self.status()
        undecided = raw == 0
    }

    private nonisolated static func status() async -> Int {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus.rawValue
    }
}
