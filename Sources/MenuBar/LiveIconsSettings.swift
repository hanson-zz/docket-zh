import SwiftUI

/// 设置 ▸ 扩展栏：动态图标。总开关默认关；打开后访达、Chrome 各有子开关，
/// 下面是「AI 额度水位」：一个总开关，ChatGPT、Claude、Codex 三个勾选，
/// 和「显示：」5 小时 / 每周 / 取更紧的（默认取更紧的）；再下面是「消息未读」：信息、微信、邮件三个勾选，
/// 风格简洁 / 趣味，和一个用演示未读数的预览；最后是「日历」子开关（默认开）和「提前开始：」
/// 倒计时提前量（10 / 15 / 30 / 45 / 60 分钟，默认 30）。
struct LiveIconsSettingRow: View {
    @AppStorage(LiveIconToggles.masterKey) private var enabled = false
    @AppStorage(LiveIconToggles.finderKey) private var finder = true
    @AppStorage(LiveIconToggles.chromeKey) private var chrome = true
    @AppStorage(LiveBrowser.safariKey) private var safari = true
    @AppStorage(LiveIconToggles.openAIKey) private var chatGPT = true
    @AppStorage(LiveIconToggles.codexKey) private var codex = true
    @AppStorage(LiveIconToggles.claudeKey) private var claude = true
    @AppStorage(LiveIconToggles.quotaKey) private var quota = true
    @AppStorage(LiveIconToggles.percentKey) private var percent = true
    @AppStorage(LiveQuotaPreference.key) private var window = LiveQuotaPreference.default.rawValue
    @AppStorage(LiveBadgeApp.messages.toggleKey) private var messages = true
    @AppStorage(LiveBadgeApp.wechat.toggleKey) private var wechat = true
    @AppStorage(LiveBadgeApp.mail.toggleKey) private var mail = true
    @AppStorage(LiveBadgeStyle.key) private var badgeStyle = LiveBadgeStyle.default.rawValue
    @AppStorage(LiveIconToggles.calendarKey) private var calendar = true
    @AppStorage(LiveCalendar.leadKey) private var calendarLead = LiveCalendar.defaultLeadMinutes
    @State private var demoCount = 4

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("动态图标"))
                Text(tr("让扩展栏上几个 App 的图标本身动起来，只在有事发生时动。系统开了减弱动态效果时不转、不流动，低电量模式下放慢。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if enabled {
            Group {
                sub($finder, tr("访达"), tr("访达图标整张换成小熊猫：两颗眼珠跟着鼠标指针看，指针停下几秒后慢慢回正，隔几秒眨一下眼。"))
                sub($chrome, tr("Chrome"),
                    tr("鼠标停上去时中间的彩色圆盘轻转一下弹回；当前标签页在加载时，图标边缘走一道细蓝弧，加载完淡出。读加载状态需要允许码头控制 Chrome。「下载」文件夹里有正在下的文件时右下角挂下载徽标，在放声音时挂播放徽标。"))
                sub($safari, tr("Safari"),
                    tr("鼠标停上去时表盘轻摆两下停住，外壳不动；网页在加载时图标边缘走一道细蓝弧（要辅助功能权限）；「下载」文件夹里有正在下的文件时右下角挂下载徽标和真实进度，在放声音时挂播放徽标。读不到就不画。"))
                sub($quota, tr("AI 额度水位"),
                    tr("ChatGPT、Claude、Codex 图标下部灌水，水位是还剩多少额度，没有数据时不画；鼠标停在图标上时，名称下面显示多久后重置。ChatGPT 和 Codex 共用同一份 Codex 额度数据。"))
                VStack(alignment: .leading, spacing: 6) {
                    aiApp($chatGPT, "ChatGPT", bundleID: LiveIconApp.chatGPTBundleID)
                    aiApp($claude, "Claude", bundleID: LiveIconApp.claudeBundleID)
                    aiApp($codex, "Codex", bundleID: LiveIconApp.codexBundleIDs[0])
                    Text(tr("勾掉的 App 图标不动。Codex 正在干活时，ChatGPT 和 Codex 图标边缘有一道白光绕圈。Claude 读本机 Claude 命令行已登录的账号，只读不上传，令牌只发给 Anthropic；没登录时不画。第一次读取时 macOS 可能弹框问是否允许码头使用钥匙串里的这一项。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 20)
                if quota && (chatGPT || claude || codex) {
                    Picker(selection: $window) {
                        Text(tr("5 小时")).tag(LiveQuotaPreference.session.rawValue)
                        Text(tr("每周")).tag(LiveQuotaPreference.weekly.rawValue)
                        Text(tr("取更紧的")).tag(LiveQuotaPreference.tighter.rawValue)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("显示："))
                            Text(tr("取更紧的：哪个窗口剩得少就看哪个。固定 5 小时或每周时，那个窗口没有数据就不画。"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 20)
                    Toggle(tr("水位左下角显示剩余百分比"), isOn: $percent)
                        .padding(.leading, 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("消息未读"))
                    Text(tr("信息、微信、邮件图标右上角显示未读数，来新消息时轻弹一下，邮件左上角再闪三道光。未读数取自系统程序坞上它们自己的角标，需要辅助功能权限；只读数字，不读消息内容，读不到时图标保持原样。邮件开着写信窗口时右下角挂铅笔，发件箱里有信在发时挂一圈小环（要允许码头控制邮件，只数封数）。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    aiApp($messages, tr("信息", context: "app"), bundleID: LiveBadgeApp.messages.bundleID)
                    aiApp($wechat, tr("微信"), bundleID: LiveBadgeApp.wechat.bundleID)
                    aiApp($mail, tr("邮件"), bundleID: LiveBadgeApp.mail.bundleID)
                }
                .padding(.leading, 20)
                if messages || wechat || mail {
                    Picker(selection: $badgeStyle) {
                        Text(tr("简洁")).tag(LiveBadgeStyle.subtle.rawValue)
                        Text(tr("趣味")).tag(LiveBadgeStyle.playful.rawValue)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("风格："))
                            Text(tr("简洁：保持原色，只有角标。趣味：未读越多颜色越热，2 到 3 条蓝、4 到 6 条紫、7 到 8 条紫粉、9 条及以上红粉，角标旁有闪光、火焰或液滴。"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 20)
                    badgePreview
                        .padding(.leading, 20)
                }
                sub($calendar, tr("日历"),
                    tr("日历图标换成今天的星期和日期。下一场日程开始前一段时间里，图标下部的液面随剩余时间从满降到底，底部小胶囊写倒计时，剩 5 分钟变暖橙，到点写「即将开始」「进行中」，随后整枚图标顺时针转一圈换到下一场；减弱动态效果时不转直接换。悬停显示今天剩下的日程。只读今天的定时日程（不含全天和已拒绝的），不读备注、不上传；没有日历权限或今天没有日程时图标保持原样。"))
                if calendar {
                    Picker(selection: $calendarLead) {
                        ForEach(LiveCalendar.leadChoices, id: \.self) { minutes in
                            Text(tr("\(minutes) 分钟")).tag(minutes)
                        }
                    } label: {
                        Text(tr("提前开始："))
                    }
                    .padding(.leading, 20)
                }
            }
            .padding(.leading, 16)
        }
    }

    /// 预览：用演示未读数看每一档的样子，不碰真实消息。
    private var badgePreview: some View {
        let app: LiveBadgeApp = wechat ? .wechat : (messages ? .messages : .mail)
        return HStack(spacing: 14) {
            if let image = AppCatalog.shared.icon(forBundleID: app.bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .modifier(LiveBadgeModifier(app: app, side: 56, demo: .count(demoCount), demoPulse: demoCount))
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
            Stepper(value: $demoCount, in: LiveBadgeDemo.range) {
                Text(tr("预览：\(demoCount) 条未读"))
            }
        }
    }

    private func sub(_ value: Binding<Bool>, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 一个 AI App 的勾选：App 自己的图标（没装时不画）、名字、行尾勾选框。
    private func aiApp(_ value: Binding<Bool>, _ name: String, bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let image = AppCatalog.shared.icon(forBundleID: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            Text(verbatim: name)
            Spacer(minLength: 8)
            Toggle(name, isOn: value)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
    }
}
