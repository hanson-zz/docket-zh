import SwiftUI

/// 最近截图：只管“结果”。最新一张画大，底部写多久以前，右边 2×2 四格放后面几张，
/// 放不下时最后一格写“+N”（见 `RecentShots`）。
///
/// 每张都能直接拖进聊天窗口、邮件或文件夹。拖移只挂在图片本身上，卡片四周和
/// 图片之间的空隙仍然归扩展栏，按住那里照旧能挪动卡片；点一下（不拖）打开面板。
/// 竖排扩展栏的窄卡片只放最新一张。
struct ScreenshotsTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var feed: FolderFeed { FolderFeed.shared(.screenshots) }

    private var files: [ListedFile] { context.isPreview ? [] : feed.files }

    var body: some View {
        WidgetSurface {
            Group {
                if context.position.isVertical {
                    column
                } else {
                    row
                }
            }
            .bleedingThroughSurfaceInset()
        }
        .onAppear { if !context.isPreview { feed.start() } }
    }

    // MARK: 横排：一张大图加四格

    private let gap: CGFloat = 4
    private let pad: CGFloat = 6

    @ViewBuilder
    private var row: some View {
        if context.isPreview {
            strip(heroView: hero(SamplePicture(symbol: "macwindow"), caption: tr("2 分钟前"), url: nil),
                  thumbs: [AnyView(SamplePicture(symbol: "doc.text")), AnyView(SamplePicture(symbol: "photo")),
                           AnyView(SamplePicture(symbol: "chart.bar")), AnyView(moreCell(6))])
        } else if let latest = files.first {
            strip(heroView: hero(FileThumb(url: latest.url, pixels: 360).id(latest.url),
                                 caption: RelativeAge.caption(latest.date, now: context.now), url: latest.url)
                    .accessibilityLabel(tr("最近截图：\(latest.name)")),
                  thumbs: cells())
        } else {
            empty
        }
    }

    /// 右边四格：后面几张截图，放不下时最后一格是“+N”。
    private func cells() -> [AnyView] {
        let plan = RecentShots.strip(count: files.count)
        var cells: [AnyView] = files.dropFirst().prefix(plan.thumbs).map { AnyView(thumb($0)) }
        if plan.more > 0 { cells.append(AnyView(moreCell(plan.more))) }
        return cells
    }

    private func strip(heroView: some View, thumbs: [AnyView]) -> some View {
        GeometryReader { proxy in
            let h = proxy.size.height - pad * 2
            let w = proxy.size.width - pad * 2
            // 大图约占四成宽，右边两列。
            let heroW = (w * 0.46).rounded()
            let cellW = max(0, (w - heroW - gap * 2) / 2)
            let cellH = max(0, (h - gap) / 2)
            HStack(spacing: gap) {
                heroView
                    .frame(width: heroW, height: h)
                    .clipShape(.rect(cornerRadius: 7, style: .continuous))
                Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                    GridRow {
                        cell(thumbs, 0, cellW, cellH)
                        cell(thumbs, 1, cellW, cellH)
                    }
                    GridRow {
                        cell(thumbs, 2, cellW, cellH)
                        cell(thumbs, 3, cellW, cellH)
                    }
                }
            }
            .padding(pad)
        }
    }

    @ViewBuilder
    private func cell(_ thumbs: [AnyView], _ index: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
        Group {
            if index < thumbs.count {
                thumbs[index]
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(WidgetStyle.primary.opacity(0.05))
            }
        }
        .frame(width: w, height: h)
        .clipShape(.rect(cornerRadius: 5, style: .continuous))
    }

    private func hero(_ image: some View, caption: String, url: URL?) -> some View {
        image
            .overlay(alignment: .bottomLeading) {
                Text(caption)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
            }
            .modifier(DragsFile(url: url))
    }

    private func thumb(_ file: ListedFile) -> some View {
        FileThumb(url: file.url, pixels: 160)
            .id(file.url)
            .modifier(DragsFile(url: file.url))
            .help(file.name)
            .accessibilityLabel(file.name)
    }

    private func moreCell(_ count: Int) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(WidgetStyle.primary.opacity(0.2), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(WidgetStyle.primary.opacity(0.05)))
            .overlay {
                Text(verbatim: "+\(count)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(WidgetStyle.secondary)
            }
            .accessibilityLabel(tr("还有 \(count) 张"))
    }

    // MARK: 竖排：只放最新一张

    @ViewBuilder
    private var column: some View {
        if context.isPreview {
            SamplePicture(symbol: "macwindow")
        } else if let latest = files.first {
            FileThumb(url: latest.url, pixels: 240).id(latest.url)
                .modifier(DragsFile(url: latest.url))
                .accessibilityLabel(tr("最近截图：\(latest.name)"))
        } else {
            empty
        }
    }

    private var empty: some View {
        PandaEmptyTile(empty: .screenshots, title: tr("截取屏幕"), instance: instance, context: context)
    }
}

/// 把一张截图交给拖移，能丢进任何收文件的地方。预览（没有文件）时什么都不挂。
private struct DragsFile: ViewModifier {
    var url: URL?

    func body(content: Content) -> some View {
        if let url {
            content
                .contentShape(.rect)
                .onDrag { FileActions.dragProvider(url) }
        } else {
            content
        }
    }
}
