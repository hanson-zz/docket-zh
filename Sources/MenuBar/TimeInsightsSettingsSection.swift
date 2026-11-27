import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置 ▸ 小组件 ▸ 时间洞察：暂停记录、空闲判定、排除的应用、清空和导出（全部免费），
/// 以及窗口标题、网站两项 Pro 采集的单独同意（阶段 A 待接通，开关不可用）。
///
/// 设置是全局的（`TimeInsightsSettings`），不跟着某张卡片，改了立刻生效。
struct TimeInsightsSettingsSection: View {
    private var tracker: TimeInsightsTracker { .shared }

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    private var unlocked: Bool { licenseUnlocked || supporter }

    @State private var confirmingClear = false
    @State private var message: String? = nil

    var body: some View {
        Section(tr("采集")) {
            Toggle(tr("暂停记录"), isOn: Binding(
                get: { tracker.settings.paused },
                set: { tracker.setPaused($0) }))
            Picker(tr("无操作多久算离开"), selection: Binding(
                get: { tracker.settings.idleMinutes },
                set: { value in tracker.update { $0.idleMinutes = value } })) {
                    ForEach(idleChoices, id: \.self) { minutes in
                        Text(tr("\(minutes) 分钟")).tag(minutes)
                    }
                }
            Text(tr("超过这个时间没有键盘、鼠标或触控板操作，就不再算活跃，只算前台停留。只读取距上次操作多久，不读取按了什么。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section(tr("排除的应用")) {
            if tracker.settings.excludedBundleIDs.isEmpty {
                Text(tr("还没有排除的应用。排除后，这个应用在前台时不记录。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ForEach(tracker.settings.excludedBundleIDs, id: \.self) { bundleID in
                HStack {
                    Text(verbatim: Self.displayName(bundleID))
                    Spacer()
                    Button(tr("移除")) { tracker.include(bundleID) }
                }
            }
            Button(tr("添加应用…")) { pickApp() }
        }

        Section(tr("数据")) {
            HStack {
                Button(tr("导出 CSV…")) { export() }
                Button(tr("在访达中显示")) {
                    NSWorkspace.shared.activateFileViewerSelecting([tracker.storageURL])
                }
                Spacer()
                Button(tr("清空数据…"), role: .destructive) { confirmingClear = true }
            }
            Text(tr("记录只存在这台 Mac 上，不上传。保留最近 \(tracker.settings.retentionDays) 天。基础导出包括时间、应用和分类。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(tr("清空这台 Mac 上全部时间洞察记录？不能撤销。"), isPresented: $confirmingClear) {
            Button(tr("清空"), role: .destructive) {
                tracker.clearAll()
                message = tr("已清空全部记录。")
            }
            Button(tr("取消"), role: .cancel) {}
        }

        Section {
            Toggle(isOn: .constant(false)) {
                ProLabel(title: tr("统计窗口标题"), isPro: true)
            }
            .disabled(true)
            Toggle(isOn: .constant(false)) {
                ProLabel(title: tr("统计网站域名"), isPro: true)
            }
            .disabled(true)
            Text(tr("待接通：这两项还在开发中，现在不采集任何窗口标题或网站。接通后也要你在这里逐项打开，购买 Pro 不会自动打开。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(tr("更多统计"))
        }
    }

    private var idleChoices: [Int] {
        var all = TimeInsightsSettings.idleChoices
        if !all.contains(tracker.settings.idleMinutes) { all.append(tracker.settings.idleMinutes) }
        return all.sorted()
    }

    static func displayName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { tracker.exclude(id) }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "TimeInsights-\(stamp).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tracker.exportCSV(to: url)
            message = tr("已导出：\(url.lastPathComponent)")
        } catch {
            message = tr("导出失败")
        }
    }
}
