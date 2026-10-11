import AppKit
import SwiftUI

/// The repository's counters, a link to it, and the optional token.
struct GitHubDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var token = ""

    private var service: GitHubService { GitHubService.shared }
    private var slug: String { instance.config.string("repo", default: "hanson-zz/docket-zh") }

    private var stats: GitHubStats? {
        if context.isPreview {
            return GitHubStats(fullName: "hanson-zz/docket-zh", stars: 128, forks: 9, watchers: 4,
                               openIssuesAndPulls: 5, openPulls: 2)
        }
        return service.stats(for: slug)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.purple))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "chevron.left.forwardslash.chevron.right",
                            title: stats?.fullName ?? slug,
                            subtitle: subtitle)
                if let stats {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                              spacing: 6) {
                        StatChip(label: "星标", value: GitHubStats.short(stats.stars))
                        StatChip(label: "复刻", value: GitHubStats.short(stats.forks))
                        StatChip(label: "关注", value: GitHubStats.short(stats.watchers))
                        StatChip(label: "议题",
                                 value: GitHubStats.short(stats.openIssues ?? stats.openIssuesAndPulls))
                        StatChip(label: "拉取请求", value: stats.openPulls.map(GitHubStats.short) ?? "-")
                        StatChip(label: "通知",
                                 value: context.isPreview ? "-" : service.notifications.map { "\($0)" } ?? "-")
                    }
                } else {
                    PanelNote(symbol: "network", text: service.error(for: slug) ?? "正在读取…").frame(height: 90)
                }
                HStack(spacing: 8) {
                    PanelButton(title: "在 GitHub 上打开", symbol: "arrow.up.right", prominent: true) {
                        guard !context.isPreview, let parsed = RepoSlug.parse(slug),
                              let url = URL(string: "https://github.com/\(parsed.owner)/\(parsed.repo)") else { return }
                        NSWorkspace.shared.open(url)
                    }
                    PanelButton(title: "刷新", symbol: "arrow.clockwise") {
                        guard !context.isPreview else { return }
                        service.refresh(slug, force: true)
                    }
                }
                tokenSection
            }
        }
        .onAppear { if !context.isPreview { service.refresh(slug) } }
    }

    private var subtitle: String {
        if context.isPreview { return "示例数据" }
        return service.hasToken ? "已使用个人访问令牌" : "公开数据 · 未使用令牌"
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("个人访问令牌（可选）")
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 6) {
                SecureField("", text: $token, prompt: Text(service.hasToken ? "已保存在钥匙串中" : "ghp_… 或 github_pat_…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .glassPane(cornerRadius: 7)
                    .onSubmit(save)
                Button(service.hasToken && token.isEmpty ? "移除" : "保存") {
                    if token.isEmpty { service.setToken(nil) } else { save() }
                }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white)
                .disabled(context.isPreview || (token.isEmpty && !service.hasToken))
            }
            Text("令牌只保存在这台 Mac 的钥匙串中，用于提高请求上限并显示未读通知数。读取通知需要令牌具有 notifications 权限。")
                .font(WidgetStyle.caption(10))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        guard !context.isPreview, !token.isEmpty else { return }
        service.setToken(token)
        token = ""
        service.refresh(slug, force: true)
    }
}
