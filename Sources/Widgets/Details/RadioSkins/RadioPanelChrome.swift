import AppKit
import SwiftUI

// 收音机面板九套外观共用的紧凑头部和外观画廊（照 files/uploads/radio-mock 的 CH 03 效果图）。
//
//     网络电台                                   [ ||| 正在收听 ]
//     [ 经典调谐 v ]                                 （插画）
//     CH 03 / 06                                     （小熊猫）
//     音乐之声
//     HLS · 网络直播
//
// 数值全取实时：外观名是当前画的外观，CH 是当前台和收藏总数，第二行是这一台的流格式
// （播放中出错或有节目名时换成那一句），状态胶囊跟播放器走。
// 右上角收音机插画是可选的图 Resources/RadioArt/radio-art-<rawValue>.png，存在就显示
// （约 64pt），缺图不画、布局自然收拢，不用代码画仿制品。

/// 右上角的收音机插画，按外观找图，找不到是 nil。读过一次就记住（包里的图不会变）。
/// 用 `Bundle.image(forResource:)` 读，同名的 @2x 一起认，Retina 屏上用 512 那张。
@MainActor
enum RadioArtwork {
    private static var cache: [String: NSImage?] = [:]

    static func image(_ skin: RadioSkin) -> NSImage? {
        let name = RadioPanelReadout.artName(skin)
        if let hit = cache[name] { return hit }
        let image = Bundle.main.image(forResource: name)
        cache.updateValue(image, forKey: name)
        return image
    }
}

/// 头一行：左边天线图标和“网络电台”，右边状态胶囊（播放时跳动的小竖条加“正在收听”）。
struct RadioPanelTopBar: View {
    var model: RadioSkinModel

    var body: some View {
        let colors = model.colors
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.accentText)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(colors.accent.opacity(0.16)))
                .accessibilityHidden(true)
            Text(verbatim: tr("网络电台"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colors.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if model.playing && !model.buffering {
                    RadioBars(active: !model.isPreview, color: colors.accentText, barWidth: 2, height: 10)
                } else {
                    Circle()
                        .fill(model.buffering ? colors.accentText : colors.text.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
                Text(verbatim: model.status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.text.opacity(model.playing ? 0.9 : 0.66))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .readableGlass(in: Capsule())
            .overlay(Capsule().strokeBorder(colors.text.opacity(0.1), lineWidth: 0.5))
            .accessibilityElement(children: .combine)
        }
    }
}

/// 外观名胶囊、CH 03 / 06、台名、HLS · 网络直播；右边插画和小熊猫（都没有时这一栏不占地方）。
struct RadioCompactReadout: View {
    var model: RadioSkinModel
    /// 画廊开着（胶囊上的箭头朝上）。
    var galleryOpen: Bool
    /// 点外观名胶囊：开、关外观画廊。预览里是 nil，胶囊只是个标签。
    var onSkinTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = model.colors
        let art = RadioArtwork.image(model.skin)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                skinChip(colors)
                    .padding(.bottom, 2)
                channel(colors)
                Text(verbatim: model.stationName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(13.0 / 24.0)
                Text(verbatim: model.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.detailIsProblem ? colors.accentText : colors.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if art != nil || model.panda != nil {
                ZStack(alignment: .bottomLeading) {
                    if let art {
                        Image(nsImage: art)
                            .resizable()
                            // 掌机像素是像素画，最近邻缩放保持方块边缘；其余平滑缩放。
                            .interpolation(model.skin == .pixel ? .none : .high)
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    if let pose = model.panda {
                        PandaStateView(pose: pose, size: PandaStage.regular.side)
                            .transition(.opacity)
                    }
                }
                .frame(width: art == nil ? PandaStage.regular.side : (model.panda == nil ? 64 : 92),
                       height: art == nil ? PandaStage.regular.side : 64)
                .padding(.top, 2)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: PandaMotion.transition), value: model.panda)
    }

    @ViewBuilder
    private func skinChip(_ colors: RadioSkinColors) -> some View {
        let label = HStack(spacing: 4) {
            Text(verbatim: model.skin.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
            if onSkinTap != nil {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .rotationEffect(.degrees(galleryOpen ? 180 : 0))
            }
        }
        .foregroundStyle(colors.text.opacity(0.86))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(colors.text.opacity(0.08)))
        .overlay(Capsule().strokeBorder(colors.text.opacity(galleryOpen ? 0.3 : 0.12), lineWidth: 0.6))
        .contentShape(Capsule())
        if let onSkinTap {
            Button(action: onSkinTap) { label }
                .buttonStyle(.plain)
                .help(galleryOpen ? tr("收起外观") : tr("换外观"))
                .accessibilityLabel(tr("外观：\(model.skin.title)"))
                .accessibilityHint(galleryOpen ? tr("收起外观") : tr("换外观"))
        } else {
            label
        }
    }

    private func channel(_ colors: RadioSkinColors) -> some View {
        let parts = RadioPanelReadout.channel(index: model.index, count: model.count)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(verbatim: "CH")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(colors.secondary)
            Text(verbatim: parts.current)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colors.accentText)
                .contentTransition(.numericText())
                .animation(model.isPreview || reduceMotion ? nil : .snappy, value: model.index)
            Text(verbatim: "/ \(parts.total)")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(colors.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.channelOfTotal)
    }
}

/// 外观画廊：九套外观各一格，格子里是这套外观主视觉的实时缩略（真实视图缩小画，不是截图），
/// 下面写名字；Pro 的在缩略图右上角标 Pro 角标，不和名字挤在一行。选中的那格描边。
struct RadioSkinGallery: View {
    /// 当前画的外观。
    var current: RadioSkin
    /// 每套外观的预览数据（预览模式，回调什么也不做，动画停住）。
    var preview: (RadioSkin) -> RadioSkinModel
    /// 画廊整体用的颜色（当前外观的调色板）。
    var colors: RadioSkinColors
    /// 内容区宽度，算一排几格。
    var width: CGFloat
    var onPick: (RadioSkin) -> Void

    /// 缩略图取景框（按面板主视觉的宽度 288 加边距），按格子宽度整体缩小。
    private static let source = CGSize(width: 312, height: 224)

    var body: some View {
        let columns = RadioPanelReadout.galleryColumns(width: Double(width))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns),
                  spacing: 10) {
            ForEach(RadioSkin.allCases, id: \.self) { skin in cell(skin) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.text.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(colors.text.opacity(0.1), lineWidth: 0.5))
    }

    private func cell(_ skin: RadioSkin) -> some View {
        let on = skin == current
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            onPick(skin)
        } label: {
            VStack(spacing: 5) {
                thumbnail(skin)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(on ? colors.accentText : colors.text.opacity(0.12),
                                                lineWidth: on ? 2 : 0.6))
                    .overlay(alignment: .topTrailing) {
                        if skin.isPro {
                            ProBadge().padding(3)
                        }
                    }
                Text(verbatim: skin.title)
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? colors.text : colors.text.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(skin.title)
        .accessibilityLabel(skin.isPro ? tr("\(skin.title)，Pro") : skin.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func thumbnail(_ skin: RadioSkin) -> some View {
        let model = preview(skin)
        let source = Self.source
        return Color.clear
            .aspectRatio(source.width / source.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let scale = proxy.size.width / source.width
                    ZStack {
                        RadioModernBackdrop(model: model)
                        RadioSkinFace(model: model)
                            .frame(width: 288)
                    }
                    .frame(width: source.width, height: source.height)
                    .environment(\.colorScheme, model.tone == .dark ? .dark : .light)
                    .allowsHitTesting(false)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
            .accessibilityHidden(true)
    }
}
