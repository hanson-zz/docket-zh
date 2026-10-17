import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 还没下完的文件：图标先是一张灰色的底，彩色的图标从下往上慢慢“灌”满，
/// 灌到哪儿就是下到哪儿，水面那一条有一道细亮线。不知道总大小时，
/// 一道光带从下往上反复扫过图标。打开“减少动态效果”时光带停在中间。
///
/// 图标按下完以后的文件类型取（“电影.mp4.crdownload”画视频图标），
/// 不读文件内容。
struct DownloadProgressIcon: View {
    var download: ActiveDownload
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let icon = Image(nsImage: Self.icon(for: download))
        ZStack {
            icon.resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(0)
                .opacity(0.35)
            if let fraction = download.fraction {
                filled(icon, fraction: fraction)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { tick in
                    sweep(icon, now: tick.date)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(download.finalName)，\(DownloadProgress.caption(download.fraction))")
    }

    private func filled(_ icon: Image, fraction: Double) -> some View {
        let level = size * CGFloat(min(max(fraction, 0), 1))
        return icon.resizable()
            .aspectRatio(contentMode: .fit)
            .mask(alignment: .bottom) {
                Rectangle().frame(height: level)
            }
            .overlay(alignment: .bottom) {
                // 水面的亮线，满了就不画。
                if fraction > 0.02 && fraction < 0.98 {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: size * 0.62, height: max(1, size * 0.025))
                        .shadow(color: .white.opacity(0.8), radius: 2)
                        .offset(y: -level)
                }
            }
            // 减少动态效果：水位直接跳到新进度，不慢慢涨。
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: fraction)
    }

    private func sweep(_ icon: Image, now: Date) -> some View {
        let period = 1.6
        let phase = reduceMotion ? 0.5
            : now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return icon.resizable()
            .aspectRatio(contentMode: .fit)
            .mask {
                LinearGradient(colors: [.clear, .white, .clear], startPoint: .bottom, endPoint: .top)
                    .frame(height: size * 0.55)
                    .offset(y: size * (0.8 - 1.6 * phase))
            }
    }

    /// 下完以后那种文件的图标；不知道类型时是普通文件图标。
    static func icon(for download: ActiveDownload) -> NSImage {
        let ext = DownloadProgress.finalExtension(download.file.name)
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        return NSWorkspace.shared.icon(for: type)
    }
}

/// 面板里“正在下载”的一排：图标灌水、名字、百分比。
struct DownloadingStrip: View {
    var downloads: [ActiveDownload]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正在下载")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.6))
            HStack(alignment: .top, spacing: 8) {
                ForEach(downloads.prefix(4)) { download in
                    VStack(spacing: 3) {
                        DownloadProgressIcon(download: download, size: 44)
                        Text(download.finalName)
                            .font(WidgetStyle.caption(10))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(DownloadProgress.caption(download.fraction))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                            .rollingValue(download.fraction)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassPane(cornerRadius: 10)
                    .help(download.finalName)
                }
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }
}
