import SwiftUI

/// A repository's stars, with its open issues and pull requests under them.
struct GitHubTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: GitHubService { GitHubService.shared }
    private var slug: String { instance.config.string("repo", default: "hanson-zz/docket-zh") }

    /// The library's card is drawn from a sample, never from a request.
    private var stats: GitHubStats? {
        if context.isPreview {
            return GitHubStats(fullName: "hanson-zz/docket-zh", stars: 128, forks: 9, watchers: 4,
                               openIssuesAndPulls: 5, openPulls: 2)
        }
        return service.stats(for: slug)
    }

    private var caption: String {
        if let stats {
            var parts = ["\(GitHubStats.short(stats.openIssues ?? stats.openIssuesAndPulls)) 议题"]
            if let pulls = stats.openPulls { parts.append("\(GitHubStats.short(pulls)) PR") }
            if !context.isPreview, let n = service.notifications, n > 0 { parts.append("\(n) 通知") }
            return parts.joined(separator: " · ")
        }
        return service.error(for: slug) ?? "正在读取…"
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 3) {
                    badge(size: 30)
                    Text(stats.map { "★ \(GitHubStats.short($0.stars))" } ?? "-")
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
                        Text(RepoSlug.parse(slug)?.repo ?? slug)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WidgetStyle.secondary)
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                            Text(stats.map { GitHubStats.short($0.stars) } ?? "-")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(WidgetStyle.primary)
                                .monospacedDigit()
                                .rollingValue(stats?.stars ?? 0)
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
        .onAppear { if !context.isPreview { service.refresh(slug) } }
        .onChange(of: slug) { _, new in if !context.isPreview { service.refresh(new) } }
        // Every ten minutes, on the shelf's own tick.
        .onChange(of: Int(context.now.timeIntervalSince1970) / 600) {
            if !context.isPreview { service.refresh(slug) }
        }
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
        }
    }
}
