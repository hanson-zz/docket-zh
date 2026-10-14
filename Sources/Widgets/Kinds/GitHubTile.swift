import SwiftUI

/// The followed repositories' stars, with a red badge for what is new since
/// they were last marked read. One project shows its name; several show
/// "N 个项目" and their stars together. Tapping opens the panel.
struct GitHubTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: GitHubService { GitHubService.shared }
    private var repos: [String] { GitHubWatch.repos(instance.config) }

    /// The library's card is drawn from a sample, never from a request.
    private static let sample = GitHubStats(fullName: GitHubWatch.defaultRepo, stars: 128, forks: 9,
                                            watchers: 4, openIssuesAndPulls: 5, openPulls: 2)

    private var allStats: [GitHubStats] {
        context.isPreview ? [Self.sample] : repos.compactMap { service.stats(for: $0) }
    }

    /// Nil until at least one repository has answered.
    private var stars: Int? {
        let stats = allStats
        return stats.isEmpty ? nil : stats.reduce(0) { $0 + $1.stars }
    }

    private var newCount: Int {
        context.isPreview ? 3 : service.totalFeedback(repos)
    }

    private var caption: String {
        let stats = allStats
        guard !stats.isEmpty else {
            return repos.lazy.compactMap { service.error(for: $0) }.first ?? "正在读取…"
        }
        if newCount > 0 { return "\(newCount) 条新反馈" }
        let issues = stats.reduce(0) { $0 + ($1.openIssues ?? $1.openIssuesAndPulls) }
        var parts = ["\(GitHubStats.short(issues)) 议题"]
        if stats.allSatisfy({ $0.openPulls != nil }) {
            parts.append("\(GitHubStats.short(stats.reduce(0) { $0 + ($1.openPulls ?? 0) })) PR")
        }
        if !context.isPreview, let n = service.notifications, n > 0 { parts.append("\(n) 通知") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 3) {
                    badge(size: 30)
                    Text(stars.map { "★ \(GitHubStats.short($0))" } ?? "-")
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                HStack(spacing: 10) {
                    badge(size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GitHubWatch.tileTitle(repos))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WidgetStyle.secondary)
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                            Text(stars.map { GitHubStats.short($0) } ?? "-")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(WidgetStyle.primary)
                                .monospacedDigit()
                                .rollingValue(stars ?? 0)
                        }
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
            }
        }
        // The service keeps its own schedule (the shelf hands it every
        // GitHub widget's list); this only makes sure a tile that has just
        // appeared, or just changed its list, is not left waiting for it.
        .onAppear { if !context.isPreview { service.refreshAll(repos) } }
        .onChange(of: repos) { _, new in if !context.isPreview { service.refreshAll(new) } }
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
        }
        .overlay(alignment: .topTrailing) {
            if let text = GitHubWatch.badgeText(newCount) {
                Text(text)
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 5, y: -5)
            }
        }
    }
}
