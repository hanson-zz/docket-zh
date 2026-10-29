import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 卜卦 · 签卡分享图（Pro）
//
// 把当天的签（签号、签级、签诗、宜忌、白话、日期、捧着展开签纸的小熊猫、码头水印；选了星座 / 属相时
// 再加徽章和幸运色、幸运数字）画成 360×640 的竖版卡片，ImageRenderer 按 3 倍出
// 1080×1920 的 PNG。浅色宣纸底、深色墨底两款，配色固定（不跟面板玻璃走），尺寸和
// 文件名在 Core 的 DivinationShareCard。面板里：预览、浅深切换、存储、拷贝、分享。

/// 卡片本身（只用来出图）。
struct DivinationShareCardView: View {
    var index: Int
    var day: String
    var sign: DivinationSign?
    var dark: Bool

    private var stick: FortuneStick { FortuneStick.all[index] }
    private var ink: Color { Color(hex: dark ? DivinationShareCard.darkInkHex : DivinationShareCard.lightInkHex) }
    private var subInk: Color {
        Color(hex: dark ? DivinationShareCard.darkSubInkHex : DivinationShareCard.lightSubInkHex)
    }
    private var paper: Color {
        Color(hex: dark ? DivinationShareCard.darkBackgroundHex : DivinationShareCard.lightBackgroundHex)
    }
    private var red: Color { Color(hex: dark ? Divination.redDarkHex : Divination.redLightHex) }
    private var gold: Color { Color(hex: Divination.goldHex) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("每日一签"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(red)
                Spacer(minLength: 8)
                Text(verbatim: DivinationShareCard.dateText(day: day))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(subInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            Text(verbatim: Divination.stickNumber(index))
                .font(.custom("Songti SC", size: 22).weight(.semibold))
                .foregroundStyle(ink)
            HStack(spacing: 10) {
                ornament
                Text(verbatim: stick.level.title)
                    .font(.custom("Songti SC", size: 50).weight(.heavy))
                    .foregroundStyle(stick.level.isFestive ? red : (stick.level == .good ? gold : ink))
                    .lineLimit(1)
                    .fixedSize()
                ornament.scaleEffect(x: -1)
            }
            .padding(.top, 4)
            VStack(spacing: 6) {
                ForEach(stick.poemLines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.custom("Songti SC", size: 24).weight(.semibold))
                        .foregroundStyle(ink)
                }
            }
            .padding(.top, 14)
            Rectangle().fill(gold.opacity(0.7)).frame(width: 120, height: 1).padding(.vertical, 14)
            VStack(alignment: .leading, spacing: 6) {
                labeled(tr("今日宜："), stick.good, tint: red)
                labeled(tr("今日忌："), stick.avoid, tint: ink)
                Text(verbatim: stick.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(subInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let sign {
                signRow(sign).padding(.top, 12)
            }
            Spacer(minLength: 12)
            HStack(alignment: .bottom) {
                // 和面板第三拍同一张：小熊猫双手捧着展开的签（卡片上签级已经写得很大，纸上不再写）。
                DivinationPoseImage(pose: .qianRead, height: 96)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "码头 Dockling")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(red)
                    Text(tr("仅供娱乐"))
                        .font(.system(size: 13))
                        .foregroundStyle(subInk)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(width: CGFloat(DivinationShareCard.width), height: CGFloat(DivinationShareCard.height))
        .background(paper)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(gold.opacity(0.8), lineWidth: 1.5)
                .padding(12)
        )
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var ornament: some View {
        HStack(spacing: 3) {
            Circle().fill(gold).frame(width: 6, height: 6)
            Rectangle().fill(gold).frame(width: 28, height: 1.5)
        }
    }

    private func labeled(_ label: String, _ value: String, tint: Color) -> some View {
        (Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
            + Text(verbatim: value).font(.system(size: 16)).foregroundStyle(ink))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func signRow(_ sign: DivinationSign) -> some View {
        let luck = Divination.luck(day: day, sign: sign)
        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                Text(verbatim: sign.symbol)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(red))
                Text(verbatim: sign.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink)
            }
            HStack(spacing: 4) {
                Circle().fill(Color(hex: luck.color.hex))
                    .overlay(Circle().strokeBorder(subInk.opacity(0.5), lineWidth: 1))
                    .frame(width: 13, height: 13)
                Text(verbatim: luck.color.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink)
            }
            Text(tr("幸运数字 \(luck.number)"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum DivinationShareImage {
    struct Rendered {
        var image: NSImage
        var png: Data
    }

    static func render(index: Int, day: String, sign: DivinationSign?, dark: Bool) -> Rendered? {
        let renderer = ImageRenderer(content: DivinationShareCardView(index: index, day: day, sign: sign, dark: dark))
        let scale = CGFloat(DivinationShareCard.scale)
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let image = NSImage(size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
        image.addRepresentation(rep)
        return Rendered(image: image, png: png)
    }
}

/// 面板里的签卡页：预览、浅色 / 深色、存储、拷贝、分享。
struct DivinationShareView: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var index: Int
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var dark: Bool?
    @State private var rendered: [Bool: DivinationShareImage.Rendered] = [:]
    @State private var notice: String?
    @State private var anchor = ShareAnchorBox()

    private var isDark: Bool { dark ?? (scheme == .dark) }
    private var day: String { Divination.dayKey(context.now) }
    private var sign: DivinationSign? { Divination.sign(instance.config) }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                DivinationBackButton(title: tr("今天"), action: onClose)
                Spacer(minLength: 4)
                Text(tr("签卡"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
            }
            preview
            lookPicker
            HStack(spacing: 8) {
                DivinationGlassButton(title: tr("存储…"), height: 32) { save() }
                DivinationGlassButton(title: tr("拷贝"), height: 32) { copy() }
                DivinationPrimaryButton(title: tr("分享"), height: 32) { share() }
                    .background(ShareAnchor(box: anchor))
            }
            if let notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .frame(width: CGFloat(Divination.panelContentWidth))
    }

    private var current: DivinationShareImage.Rendered? {
        if let cached = rendered[isDark] { return cached }
        return nil
    }

    private var preview: some View {
        let width: CGFloat = 168
        let height = width * CGFloat(DivinationShareCard.height / DivinationShareCard.width)
        return Group {
            if let image = current?.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color.panelFill)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .frame(maxWidth: .infinity)
        .task(id: isDark) { renderIfNeeded() }
        .accessibilityLabel(tr("签卡预览"))
    }

    private var lookPicker: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { value in
                let on = value == isDark
                Button {
                    dark = value
                } label: {
                    Text(value ? tr("深色") : tr("浅色"))
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? Color.panelPrimary : Color.panelSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background { if on { Capsule().fill(Color.panelRaised).panelLift() } }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.panelFill))
        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .frame(width: 168)
    }

    private func renderIfNeeded() {
        guard rendered[isDark] == nil,
              let made = DivinationShareImage.render(index: index, day: day, sign: sign, dark: isDark) else { return }
        rendered[isDark] = made
    }

    private func image() -> DivinationShareImage.Rendered? {
        renderIfNeeded()
        return rendered[isDark]
    }

    private var fileName: String { DivinationShareCard.fileName(day: day, dark: isDark) }

    private func save() {
        guard !context.isPreview else { return }
        guard let png = image()?.png else { return say(tr("图片生成失败")) }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        // 面板在扩展栏那一层之上，存储窗口要再高一层才不会被它挡住。
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 3)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            say(tr("已存储：\(url.lastPathComponent)"))
        } catch {
            say(tr("无法存储图片"))
        }
    }

    private func copy() {
        guard !context.isPreview else { return }
        guard let made = image() else { return say(tr("图片生成失败")) }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([made.image])
        board.setData(made.png, forType: .png)
        say(tr("已拷贝图片"))
    }

    private func share() {
        guard !context.isPreview else { return }
        guard let png = image()?.png else { return say(tr("图片生成失败")) }
        let url = FileManager.default.temporaryDirectory.appending(path: fileName)
        do { try png.write(to: url, options: .atomic) } catch { return say(tr("图片生成失败")) }
        let picker = NSSharingServicePicker(items: [url])
        if let view = anchor.view, view.window != nil {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                        of: view, preferredEdge: .minY)
        }
    }

    private func say(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if notice == text { notice = nil } }
        }
    }
}
