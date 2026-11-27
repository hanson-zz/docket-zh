import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置 ▸ 时间洞察：只管采集权限、隐私和配置，不放任何统计页面。统计从扩展栏卡片
/// 进主面板，再从主面板进「完整统计」窗口。
///
/// - 基础记录（免费）：记录前台应用（关掉等于暂停）、空闲判定阈值、排除的应用。
/// - 高级统计（Pro）：窗口标题、网站域名两项各自单独授权，默认关；没解锁时不能打开，
///   并写明原因；还没接通的写「开发中」，打开了也不采。
/// - 隐私与数据（免费）：说明、导出、在访达中显示、清空。
///
/// 设置是全局的（`TimeInsightsSettings`），不跟着某张卡片，改了立刻生效。
struct TimeInsightsSettingsPane: View {
    private var tracker: TimeInsightsTracker { .shared }

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    private var unlocked: Bool { licenseUnlocked || supporter }

    @State private var confirmingClear = false
    @State private var message: String? = nil
    @State private var permissionChecks = 0

    var body: some View {
        Form {
            basicSection
            excludedSection
            advancedSection
            TimeInsightsRulesEditor()
            privacySection
        }
        .formStyle(.grouped)
    }

    // MARK: 基础记录

    private var basicSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { !tracker.settings.paused },
                set: { tracker.setPaused(!$0) })) {
                    subtitled(tr("记录前台应用"),
                              tr("记录你正在使用的前台应用和使用时长。关掉等于暂停记录，主面板上也能随时暂停。"))
                }
            Picker(selection: Binding(
                get: { tracker.settings.idleMinutes },
                set: { value in tracker.update { $0.idleMinutes = value } })) {
                    ForEach(idleChoices, id: \.self) { minutes in
                        Text(tr("\(minutes) 分钟")).tag(minutes)
                    }
                } label: {
                    subtitled(tr("空闲判定阈值"),
                              tr("超过这个时间没有键盘、鼠标或触控板操作，就不再算活跃，只算前台停留。只读取距上次操作多久，不读取按了什么。"))
                }
        } header: {
            header(tr("基础记录"), symbol: "chart.bar.fill", pro: false)
        }
    }

    private var excludedSection: some View {
        Section {
            if tracker.settings.excludedBundleIDs.isEmpty {
                Text(tr("还没有排除的应用。排除后，这个应用在前台时不记录。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ForEach(tracker.settings.excludedBundleIDs, id: \.self) { bundleID in
                HStack(spacing: 8) {
                    TimeInsightsAppIcon(bundleID: bundleID)
                        .frame(width: 20, height: 20)
                    Text(verbatim: Self.displayName(bundleID))
                    Spacer()
                    Button(tr("移除")) { tracker.include(bundleID) }
                }
            }
            HStack {
                Button(tr("添加应用…")) { pickApp() }
                if let app = tracker.lastOtherApp, !tracker.settings.isExcluded(app.bundleID) {
                    Button(tr("排除最近使用的 \(app.name)")) { tracker.exclude(app.bundleID) }
                }
            }
            Text(tr("码头自身、登录窗口和屏幕保护程序默认不计入。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(tr("排除的应用"))
        }
    }

    // MARK: 高级统计（Pro）

    private var advancedSection: some View {
        Section {
            consentRow(.windowTitles,
                       title: tr("窗口标题统计"),
                       detail: tr("记录前台窗口的标题（如文档名），标题会截短并去掉邮箱、长数字。需要辅助功能权限。"),
                       isOn: tracker.settings.windowTitlesOptIn) { on in
                tracker.update { $0.windowTitlesOptIn = on }
            }
            if unlocked && tracker.settings.windowTitlesOptIn {
                let _ = permissionChecks
                HStack(spacing: 8) {
                    Image(systemName: tracker.accessibilityTrusted ? "checkmark.shield" : "lock.shield")
                        .foregroundStyle(tracker.accessibilityTrusted ? .green : .secondary)
                    Text(tracker.accessibilityTrusted
                         ? tr("辅助功能已授权，非敏感 App 的标题可以记录")
                         : tr("尚未获得 macOS 辅助功能权限，不会读取任何窗口标题"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    if !tracker.accessibilityTrusted {
                        Button(tr("申请授权…")) {
                            NativeTimeInsightsWindowTitleSource.requestAccessibilityPermission()
                            permissionChecks += 1
                        }
                    }
                    Button(tr("检查状态")) { permissionChecks += 1 }
                        .buttonStyle(.borderless)
                }
                Text(tr("出于隐私考虑，浏览器、密码管理器及系统安全窗口不采集标题；标题会先隐藏邮箱和长数字。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            consentRow(.websites,
                       title: tr("网站域名统计"),
                       detail: tr("在 Safari、Chrome、Edge 里只记当前标签页的域名，不记网址路径和查询内容，私密窗口不记。需要浏览器扩展；扩展尚未接通，不会采集。"),
                       isOn: tracker.settings.websitesOptIn) { on in
                tracker.update { $0.websitesOptIn = on }
            }
            if !unlocked {
                HStack(spacing: 8) {
                    Text(tr("这两项是码头 Pro 功能，解锁后才能打开。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(tr("解锁码头 Pro…")) { PaywallWindow.shared.show() }
                }
            }
            Text(tr("购买 Pro 不等于同意采集：每一项都要你在这里单独打开，默认关闭，随时可以关掉。关掉后不再采集，已记录的仍可查看、导出或清空。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            header(tr("高级统计"), symbol: "square.stack.3d.up.fill", pro: true)
        }
    }

    /// 一项单独授权的开关。没解锁不能开；没接通时写「开发中」，不能开。
    /// 降级以后之前打开的开关照样能关掉（关掉永远免费）。
    private func consentRow(_ feature: TimeInsightsProFeature, title: String, detail: String,
                            isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        let connected = feature.isConnected
        let canTurnOn = unlocked && connected
        return Toggle(isOn: Binding(get: { isOn && connected },
                                    set: { on in if !on || canTurnOn { set(on) } })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    ProBadge()
                    if !connected {
                        Text(tr("开发中"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!(canTurnOn || (isOn && connected)))
        .help(!connected ? tr("这一项还在开发中，现在不采集。")
              : (!unlocked ? tr("解锁码头 Pro 后才能打开") : tr("单独授权，随时可以关掉")))
    }

    // MARK: 隐私与数据（免费）

    private var privacySection: some View {
        Section {
            Text(tr("默认只记录应用名称和时长；窗口标题和网站要单独授权。不读按键内容、不截图、不做文字识别、不上传，记录只存在这台 Mac 上，保留最近 \(tracker.settings.retentionDays) 天。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(tr("导出 CSV…")) { export() }
                Button(tr("在访达中显示")) {
                    NSWorkspace.shared.activateFileViewerSelecting([tracker.storageURL])
                }
                Spacer()
                Button(tr("清空数据…"), role: .destructive) { confirmingClear = true }
            }
            Text(tr("基础导出包括时间、应用和分类，免费。暂停、排除、清空也都免费。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = tracker.storageProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            }
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } header: {
            header(tr("隐私与数据"), symbol: "checkmark.shield.fill", pro: false)
        }
        .confirmationDialog(tr("清空这台 Mac 上全部时间洞察记录？不能撤销。"), isPresented: $confirmingClear) {
            Button(tr("清空"), role: .destructive) {
                tracker.clearAll()
                message = tr("已清空全部记录。")
            }
            Button(tr("取消"), role: .cancel) {}
        }
    }

    // MARK: 小工具

    private func header(_ title: String, symbol: String, pro: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
            if pro { ProBadge() }
        }
    }

    private func subtitled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

/// 设置 ▸ 小组件 里时间洞察那一节：设置都搬到了侧栏的「时间洞察」，这里只留一个入口，
/// 不再重复开关。
struct TimeInsightsSettingsLink: View {
    var body: some View {
        Section(tr("时间洞察")) {
            HStack(spacing: 8) {
                Text(tr("记录开关、空闲判定、排除的应用、高级统计授权和数据管理都在 设置 ▸ 时间洞察。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(tr("打开")) { SettingsSelection.shared.current = TimeInsightsSettingsTab.id }
            }
        }
    }
}

/// 设置窗口侧栏里「时间洞察」这一页的 id。
enum TimeInsightsSettingsTab {
    static let id = "TimeInsights"
}
