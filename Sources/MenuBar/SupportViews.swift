import AppKit
import SwiftUI

/// Contact, sharing and sponsorship, shared by Settings and the sponsor window.
/// Design carried over from the author's other app, Shiduo.
enum Support {
    static let email = "694561981@qq.com"
    static let repoURL = URL(string: "https://github.com/\(UpdateService.releasesRepository)")!
    static let kofiURL = URL(string: "https://ko-fi.com/hanson528")!
    static let shareText = tr("码头 Dockling：免费开源的 Mac 程序坞扩展栏，把常用 App、文件夹和小组件放在屏幕边上。")

    static func mailURL(subject: String, body: String = "") -> URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if !body.isEmpty { c.queryItems?.append(URLQueryItem(name: "body", value: body)) }
        return c.url ?? URL(string: "mailto:\(email)")!
    }

    static var feedbackURL: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let chip = tr("Apple 芯片")
        #else
        let chip = "Intel"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let body = tr("\n\n\n---\n码头 \(version) · macOS \(os) · \(chip)")
        return mailURL(subject: tr("码头反馈"), body: body)
    }

    static func openFeedback() { NSWorkspace.shared.open(feedbackURL) }
    static func openRepo() { NSWorkspace.shared.open(repoURL) }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Loose PNGs in the app bundle's Resources, so no asset catalog is needed.
    static func image(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// 赞助信按界面语言选中文或英文。
    static var sponsorLetter: String { L10n.isEnglish ? sponsorLetterEnglish : sponsorLetterChinese }

    static let sponsorLetterEnglish = """
    Hi everyone, I'm Hanson 👋

    I like making small, handy tools for the Mac 💻. Dockling is one of them: completely free, open source, collects no data, and just wants your favorite apps, folders and widgets within reach ⚓️.

    I build it in evenings and on weekends. I'd love more time to polish it, fix more bugs, add the features people actually want 🚀, and keep making useful open source tools 🌱.

    If Dockling makes your Mac nicer to use, feel free to buy me a coffee ☕. The amount doesn't matter; every bit of support is trust and encouragement. If sponsoring isn't convenient, that's totally fine too. Sharing it with friends or starring it on GitHub means just as much to me 💖.

    Thank you.

    Best,
    Hanson
    """

    static let sponsorLetterChinese = """
    大家好，我是 Hanson 👋

    我喜欢给 Mac 💻 做一些小而顺手的工具。码头就是其中之一：完全免费、开源，不收集任何数据，只想让你的常用 App、文件夹和小组件伸手就能拿到 ⚓️。

    做它用的是下班和周末的时间。我的愿望是能有更多时间把它打磨好，修更多 bug，加大家真正想要的功能 🚀，也继续做更多有用的开源小工具 🌱。

    如果码头让你的 Mac 用起来更顺手，欢迎请我喝杯咖啡 ☕。金额不重要，每一份支持都是对我的信任和鼓励。不方便赞助也完全没关系，分享给朋友、在 GitHub 上点个星，对我同样意义重大 💖。

    谢谢你。

    此致，
    Hanson
    """
}

/// Settings: contact, promotion and feedback.
struct SupportSections: View {
    var body: some View {
        Section {
            LabeledContent("网站") {
                Link("GitHub · \(UpdateService.releasesRepository)", destination: Support.repoURL)
                    .contextMenu { Button("拷贝链接") { Support.copy(Support.repoURL.absoluteString) } }
            }
            LabeledContent("邮箱") {
                Link(Support.email, destination: Support.mailURL(subject: tr("关于码头")))
                    .contextMenu { Button("拷贝邮箱") { Support.copy(Support.email) } }
            }
        } header: {
            Text("联系我们")
        } footer: {
            Text("右键点击链接可以拷贝。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("推广") {
            HStack(spacing: 10) {
                ShareLink(item: Support.repoURL, message: Text(Support.shareText)) {
                    Label("分享给朋友", systemImage: "square.and.arrow.up.fill")
                        .frame(maxWidth: .infinity)
                }
                Button { Support.openRepo() } label: {
                    Label {
                        Text("在 GitHub 上星标")
                    } icon: {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    .frame(maxWidth: .infinity)
                }
                Button { SponsorWindow.shared.show() } label: {
                    Label {
                        Text("赞助")
                    } icon: {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
        }

        Section {
            Button("发送反馈…") { Support.openFeedback() }
                .buttonStyle(.link)
        }

        LicenseSection()
    }
}

/// The sponsor window: a letter beside WeChat / Alipay / Ko-fi codes.
/// Whether this Mac has unlocked the supporter colours.
///
/// The honour system, said plainly in the window that sets it: there is no
/// server to ask and the code is public, so a check would stop no one and
/// only get in the way of people who did support it.
enum Supporter {
    static let key = "supporter.unlocked"
    static var isUnlocked: Bool { UserDefaults.standard.bool(forKey: key) }
}

struct SponsorView: View {
    @State private var method = SponsorMethod.preferred
    @AppStorage(Supporter.key) private var unlocked = false

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("支持码头")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                ScrollView {
                    Text(Support.sponsorLetter)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    ShareLink(item: Support.repoURL, message: Text(Support.shareText)) {
                        Label("分享给朋友", systemImage: "square.and.arrow.up")
                    }
                    Button { Support.openRepo() } label: {
                        Label("去 GitHub 点星", systemImage: "star")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if unlocked {
                        Label("已解锁 Pro 专属配色、表盘和角色，谢谢你！", systemImage: "heart.fill")
                            .foregroundStyle(Color(hex: ShelfColor.redPanda.hex))
                        Text("配色在 设置 ▸ 扩展栏 ▸ 外观；表盘在时钟小组件的样式里：霓虹、实景、液晶，翻页样式的卡片可选“大号带时分秒”；角色在喝水小组件里：柴犬、橘猫、企鹅、水獭、章鱼。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        // “我已赞助”凭诚信解锁已停用，老赞助者改领兑换码；按过的照旧算解锁。
                        Label("老赞助者请联系作者领取码头 Pro 兑换码，在 设置 ▸ 码头 Pro 输入即可解锁。", systemImage: "gift")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: 330)

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(SponsorMethod.allCases) { m in
                        Button { method = m } label: {
                            HStack(spacing: 5) {
                                Image(systemName: m.symbol)
                                Text(m.title)
                            }
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(method == m ? Color.white : m.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(method == m ? m.color : m.color.opacity(0.12))
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(m.hint)
                    }
                }
                .frame(width: 270)

                Group {
                    if let code = Support.image(method.imageName) {
                        Image(nsImage: code)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.quaternary)
                    }
                }
                .frame(width: 240, height: 326)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

                if method == .kofi {
                    Button { NSWorkspace.shared.open(Support.kofiURL) } label: {
                        Label("在 Ko-fi 上请我喝咖啡", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(method.color)
                    .contextMenu { Button("拷贝链接") { Support.copy(Support.kofiURL.absoluteString) } }
                    Text("支持 PayPal 和信用卡，适合海外用户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(tr("用\(method.title)扫一扫，金额随意"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(width: 660, height: 500)
    }
}

@MainActor
final class SponsorWindow: HostedWindow {
    static let shared = SponsorWindow()

    func show() {
        present(SponsorView(), title: tr("支持码头"), size: NSSize(width: 660, height: 500))
    }
}
