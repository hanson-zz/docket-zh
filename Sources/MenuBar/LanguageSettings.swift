import AppKit
import SwiftUI

/// 设置 ▸ 通用 ▸ 语言：跟随系统 / 简体中文 / English。
///
/// 选择写进本应用的 AppleLanguages，系统在启动时读它，所以切换后要重启码头。
struct LanguageSection: View {
    @State private var language = AppLanguage.current()
    /// 启动时的选择，用来判断是否需要提示重启。
    @State private var launched = AppLanguage.current()

    var body: some View {
        Section {
            Picker("语言", selection: $language) {
                ForEach(AppLanguage.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .onChange(of: language) { _, newValue in
                newValue.apply()
            }
            if language != launched {
                LabeledContent {
                    Button("立即重启") { AppRelauncher.relaunch() }
                } label: {
                    Text("切换语言后需要重启码头才能生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("默认跟随系统语言；系统语言不是中文或英文时显示英文。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 退出后重新打开自己。等一秒让当前进程先退出，免得新进程被当成同一个实例。
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try task.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }
}
