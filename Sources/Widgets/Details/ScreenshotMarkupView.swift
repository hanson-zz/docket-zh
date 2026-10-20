import AppKit
import SwiftUI

/// 截图标注：箭头、框、马赛克、文字，4 种颜色，撤销；「拷贝」把画好的图放进
/// 剪贴板，「存为新图」在同一个文件夹里另存一张，原图从不改写。
///
/// 画好的几笔由 `MarkupRenderer` 画进预览图（和存出去的是同一套画法，按图宽算
/// 线宽和字号），正在拖的那一笔用 SwiftUI 画在上面，松手才加进去。
struct ScreenshotMarkupView: View {
    var url: URL
    var palette: FilePanelPalette
    var feed: FolderFeed
    var onDone: () -> Void

    @State private var base: CGImage?
    @State private var failed = false
    @State private var preview: CGImage?
    @State private var document = MarkupDocument()
    @State private var tool: MarkupTool = .arrow
    @State private var color: MarkupColor = .red
    /// 正在拖的那一笔（比例坐标）。
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    /// 文字工具点下去的位置和正在输入的字。
    @State private var textAt: CGPoint?
    @State private var textDraft = ""
    @State private var notice: String?
    @State private var noticeID = 0
    /// 点「完成」时还有没拷贝、没存的标注，先问一句。
    @State private var askDiscard = false
    @FocusState private var textFocused: Bool

    private static let canvasHeight: CGFloat = 196
    private static let previewPixels = 1400

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilePanelHeader(title: tr("标注"), subtitle: tr("画完直接拷贝，原图不动"),
                            button: tr("完成"), prominent: true, palette: palette) { finish() }
            if askDiscard { discardBar }
            canvas
            tools
            colorRow
            if let notice {
                Text(verbatim: notice)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                bigButton(tr("存为新图"), solid: false) { saveCopy() }
                bigButton(tr("拷贝"), solid: true) { copy() }
            }
            .disabled(base == nil)
            .opacity(base == nil ? 0.45 : 1)
        }
        .task(id: url) { load() }
        .onChange(of: document) { _, _ in redraw() }
        .onChange(of: tool) { _, _ in commitText() }
        .onChange(of: textFocused) { old, new in
            if old, !new { commitText() }
        }
        .task(id: noticeID) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { notice = nil }
        }
    }

    // MARK: 画布

    private var canvas: some View {
        GeometryReader { proxy in
            let box = proxy.size
            let imageSize = base.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
            let rect = MarkupGeometry.fit(image: imageSize, in: box)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.25)
                if let shown = preview ?? base {
                    Image(decorative: shown, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                } else if failed {
                    PanelNote(symbol: "exclamationmark.triangle", text: tr("这张图读不出来"))
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                live(in: rect, imageWidth: imageSize.width)
                if let textAt {
                    textField(at: MarkupGeometry.point(textAt, in: rect), rect: rect, imageWidth: imageSize.width)
                }
            }
            .contentShape(.rect)
            .gesture(drawGesture(rect: rect))
        }
        .frame(height: Self.canvasHeight)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
        .accessibilityLabel(tr("标注画布"))
    }

    private func drawGesture(rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard base != nil, rect.width > 0 else { return }
                if tool == .text { return }
                if dragStart == nil { dragStart = MarkupGeometry.normalized(value.startLocation, in: rect) }
                dragEnd = MarkupGeometry.normalized(value.location, in: rect)
            }
            .onEnded { value in
                guard base != nil, rect.width > 0 else { return }
                let start = MarkupGeometry.normalized(value.startLocation, in: rect)
                let end = MarkupGeometry.normalized(value.location, in: rect)
                if tool == .text {
                    commitText()
                    guard rect.contains(value.location) else { return }
                    textAt = end
                    textDraft = ""
                    WidgetDetailWindow.shared.focusField { textFocused = true }
                } else {
                    document.add(tool, color: color, from: start, to: end)
                }
                dragStart = nil
                dragEnd = nil
            }
    }

    /// 正在拖的那一笔，画在面板坐标里。
    @ViewBuilder
    private func live(in rect: CGRect, imageWidth: CGFloat) -> some View {
        if let a = dragStart, let b = dragEnd {
            let scale = imageWidth > 0 ? rect.width / imageWidth : 1
            let width = max(1.5, MarkupGeometry.lineWidth(imageWidth: imageWidth) * scale)
            let p = MarkupGeometry.point(a, in: rect)
            let q = MarkupGeometry.point(b, in: rect)
            let shade = Color(hex: color.hex)
            switch tool {
            case .arrow:
                Path { path in
                    let (l, r) = MarkupGeometry.arrowHead(from: p, to: q, length: width * 5)
                    path.move(to: p)
                    path.addLine(to: q)
                    path.move(to: l)
                    path.addLine(to: q)
                    path.addLine(to: r)
                }
                .stroke(shade, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            case .box:
                Path(roundedRect: MarkupGeometry.rect(from: p, to: q), cornerRadius: width * 1.5)
                    .stroke(shade, lineWidth: width)
            case .mosaic:
                Path(MarkupGeometry.rect(from: p, to: q))
                    .fill(.white.opacity(0.18))
                    .overlay(Path(MarkupGeometry.rect(from: p, to: q))
                        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            case .text:
                EmptyView()
            }
        }
    }

    private func textField(at point: CGPoint, rect: CGRect, imageWidth: CGFloat) -> some View {
        let scale = imageWidth > 0 ? rect.width / imageWidth : 1
        let size = max(13, MarkupGeometry.textSize(imageWidth: imageWidth) * scale)
        let width = max(80, rect.maxX - point.x - 4)
        return TextField("", text: $textDraft, prompt: Text(verbatim: tr("输入文字，回车")).foregroundStyle(.white.opacity(0.5)))
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(hex: color.hex))
            .focused($textFocused)
            .onSubmit { commitText() }
            .onExitCommand { textAt = nil; textDraft = "" }
            .padding(.horizontal, 3)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.accent.opacity(0.9), lineWidth: 1))
            .offset(x: min(point.x, max(0, rect.maxX - width)), y: max(0, point.y - 2))
    }

    // MARK: 工具和颜色

    private var tools: some View {
        HStack(spacing: 6) {
            ForEach(MarkupTool.allCases, id: \.self) { item in
                let on = item == tool
                Button { tool = item } label: {
                    VStack(spacing: 4) {
                        toolGlyph(item)
                            .frame(height: 18)
                        Text(verbatim: item.title)
                            .font(.system(size: 13, weight: on ? .bold : .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(on ? palette.ink : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(on ? palette.accent : .white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(on ? 0 : 0.14), lineWidth: 0.6))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func toolGlyph(_ item: MarkupTool) -> some View {
        switch item {
        case .arrow: Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .bold))
        case .box: Image(systemName: "rectangle").font(.system(size: 15, weight: .semibold))
        case .mosaic: Image(systemName: "square.grid.3x3.fill").font(.system(size: 14))
        case .text: Text(verbatim: "T").font(.system(size: 17, weight: .bold))
        }
    }

    private var colorRow: some View {
        HStack(spacing: 10) {
            Text(verbatim: tr("颜色"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
            ForEach(MarkupColor.allCases, id: \.self) { item in
                Button { color = item } label: {
                    Circle()
                        .fill(Color(hex: item.hex))
                        .frame(width: 19, height: 19)
                        .padding(3.5)
                        .overlay(Circle().strokeBorder(.white.opacity(item == color ? 1 : 0), lineWidth: 1.6))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == color ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Button {
                if textAt != nil { textAt = nil; textDraft = "" } else { document.undo() }
            } label: {
                Text(verbatim: tr("撤销"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!document.canUndo && textAt == nil)
            .opacity(document.canUndo || textAt != nil ? 1 : 0.45)
            .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .glassPane(cornerRadius: 12)
    }

    private func bigButton(_ title: String, solid: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 15, weight: solid ? .bold : .semibold))
                .foregroundStyle(solid ? palette.ink : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(solid ? palette.accent : .white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(.white.opacity(solid ? 0 : 0.14), lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var discardBar: some View {
        HStack(spacing: 8) {
            Text(verbatim: tr("还没拷贝或保存，放弃这次标注？"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(tr("放弃")) { askDiscard = false; onDone() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FilePanelPalette.red)
            Button(tr("继续标注")) { askDiscard = false }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPane(cornerRadius: 10)
    }

    // MARK: 动作

    private func load() {
        base = MarkupRenderer.load(url, maxPixel: Self.previewPixels)
        failed = base == nil
        document.clear()
        preview = nil
    }

    private func redraw() {
        guard let base else { return }
        preview = document.isEmpty ? nil : MarkupRenderer.render(base, marks: document.marks)
    }

    private func commitText() {
        guard let at = textAt else { return }
        let text = textDraft
        textAt = nil
        textDraft = ""
        document.add(.text, color: color, from: at, to: at, text: text)
    }

    /// 原尺寸读一遍再画，拷贝和存出去的是清楚的原图。
    private func fullImage() -> CGImage? {
        commitText()
        guard let full = MarkupRenderer.load(url) else { return nil }
        return MarkupRenderer.render(full, marks: document.marks)
    }

    private func copy() {
        guard let image = fullImage(), MarkupRenderer.copy(image) else {
            say(tr("拷贝没成功"))
            NSSound.beep()
            return
        }
        document.markExported()
        say(tr("已拷贝，可以直接粘贴"))
    }

    private func saveCopy() {
        guard let image = fullImage(), let saved = MarkupRenderer.saveCopy(image, besides: url) else {
            say(tr("存图没成功（可能没有权限）"))
            NSSound.beep()
            return
        }
        document.markExported()
        feed.refresh(force: true)
        say(tr("已存为「\(saved.lastPathComponent)」，原图没动"))
    }

    private func finish() {
        commitText()
        if document.dirty && !askDiscard {
            withAnimation(.snappy(duration: 0.2)) { askDiscard = true }
        } else {
            onDone()
        }
    }

    private func say(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        noticeID += 1
    }
}
