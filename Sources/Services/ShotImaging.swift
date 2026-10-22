import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Vision

/// 截图编辑工具条的图像部分：本机识别文字（带每行的位置）、马赛克底图、取底色、
/// 把标注和译文画进原尺寸图、编码成 PNG / JPG。都只在内存里处理，不另存副本。
/// 排版和判断在 Core/ShotEditor.swift，有测试。
enum ShotImaging {
    /// CGImage 在线程间传递用。图本身不可变，只读。
    struct Box: @unchecked Sendable {
        let image: CGImage
    }

    // MARK: 识别文字

    /// Vision 识别图里的文字，简体、繁体中文和英文，精确模式。每行一块，位置换成
    /// 左上角为原点的比例。在后台线程跑。
    nonisolated static func recognize(_ box: Box) async -> [ShotTextBlock] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: box.image, options: [:])
                try? handler.perform([request])
                let blocks = (request.results ?? []).compactMap { observation -> ShotTextBlock? in
                    guard let text = observation.topCandidates(1).first?.string,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let r = observation.boundingBox
                    return ShotTextBlock(text: text, rect: CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height))
                }
                continuation.resume(returning: blocks)
            }
        }
    }

    // MARK: 马赛克底图

    /// 整张图缩小再用最近邻放大回原尺寸：标注里的马赛克就是从这张图裁一块盖上去。
    /// `cell` 是一格多少像素。
    static func pixelated(_ image: CGImage, cell: CGFloat) -> CGImage? {
        let w = image.width, h = image.height
        let cols = max(1, Int((CGFloat(w) / max(cell, 1)).rounded(.up)))
        let rows = max(1, Int((CGFloat(h) / max(cell, 1)).rounded(.up)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let big = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let blocks = small.makeImage() else { return nil }
        big.interpolationQuality = .none
        big.draw(blocks, in: CGRect(x: 0, y: 0, width: w, height: h))
        return big.makeImage()
    }

    // MARK: 底色

    /// 一块区域（比例，左上角为原点）的平均颜色，给译文块当底色。取块四周一圈更像
    /// 背景，但字少时整块平均也够用，而且一次绘制就出来。
    static func averageColor(_ image: CGImage, in rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let crop = CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                          width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height)).integral
        var pixel = [UInt8](repeating: 255, count: 4)
        guard crop.width >= 1, crop.height >= 1, let piece = image.cropping(to: crop),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return (1, 1, 1) }
        pixel.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(piece, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    // MARK: 画进原尺寸图

    /// 一块译文：位置是选区里的点，底色和字色已经挑好。
    struct OverlayPaint {
        var item: ShotOverlayItem
        var background: (r: Double, g: Double, b: Double)
        var darkInk: Bool
    }

    /// 底图，加上译文块（显示译文时），再加上标注。`pointSize` 是选区在屏幕上的大小（点），
    /// 线宽、字号按“像素 / 点”放大，和屏幕上看到的一样。
    static func render(_ image: CGImage, pixelated: CGImage?, marks: [ShotMark], overlay: [OverlayPaint],
                       pointSize: CGSize) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, pointSize.width > 0, pointSize.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = CGSize(width: w, height: h)
        let scale = CGFloat(w) / pointSize.width
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        // 下面都按左上角为原点画：翻一下坐标系，文字再单独翻回来。
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        for paint in overlay {
            drawOverlay(paint, on: ctx, scale: scale)
        }
        for mark in marks {
            draw(mark, on: ctx, size: size, scale: scale, pixelated: pixelated)
        }
        return ctx.makeImage()
    }

    private static func cgColor(_ c: ShotColor) -> CGColor {
        let rgb = c.rgb
        return CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    private static func draw(_ mark: ShotMark, on ctx: CGContext, size: CGSize, scale: CGFloat, pixelated: CGImage?) {
        let width = mark.stroke.lineWidth * scale
        let p = { (q: CGPoint) in ShotGeometry.point(q, in: size) }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(cgColor(mark.color))
        ctx.setFillColor(cgColor(mark.color))
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch mark.tool {
        case .rectangle:
            ctx.stroke(rect(mark, size))
        case .ellipse:
            ctx.strokeEllipse(in: rect(mark, size))
        case .arrow:
            let a = p(mark.start), b = p(mark.end)
            let (l, r) = ShotGeometry.arrowHead(from: a, to: b, lineWidth: width)
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
            ctx.move(to: l)
            ctx.addLine(to: b)
            ctx.addLine(to: r)
            ctx.closePath()
            ctx.fillPath()
        case .pen:
            let points = mark.points.map(p)
            guard let first = points.first else { return }
            ctx.move(to: first)
            for point in points.dropFirst() { ctx.addLine(to: point) }
            ctx.strokePath()
        case .mosaic:
            guard let pixelated else { return }
            let r = rect(mark, size)
            ctx.clip(to: r)
            // 已经翻过坐标系，图要再翻一次才是正的。
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .none
            ctx.draw(pixelated, in: CGRect(origin: .zero, size: size))
        case .text:
            let font = NSFont.systemFont(ofSize: mark.stroke.textSize * scale, weight: .bold)
            let color = NSColor(cgColor: cgColor(mark.color)) ?? .red
            drawText(mark.text, font: font, color: color, origin: p(mark.start), width: size.width - p(mark.start).x,
                     on: ctx, outline: mark.color == .white ? NSColor.black : NSColor.white)
        }
    }

    private static func rect(_ mark: ShotMark, _ size: CGSize) -> CGRect {
        let r = mark.rect
        return CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
    }

    private static func drawOverlay(_ paint: OverlayPaint, on ctx: CGContext, scale: CGFloat) {
        let r = paint.item.rect
        let rect = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: paint.background.r, green: paint.background.g, blue: paint.background.b, alpha: 0.96))
        let corner = min(3 * scale, rect.height / 2, rect.width / 2)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        let font = NSFont.systemFont(ofSize: paint.item.fontSize * scale, weight: .medium)
        drawText(paint.item.translation, font: font, color: paint.darkInk ? NSColor(white: 0.08, alpha: 1) : .white,
                 origin: CGPoint(x: rect.minX + 2 * scale, y: rect.minY + 1 * scale),
                 width: rect.width - 4 * scale, height: rect.height - 2 * scale, on: ctx, outline: nil)
    }

    /// 在左上角为原点的坐标系里画一段会自动换行的文字。`outline` 给标注文字描一圈细边，
    /// 浅色截图上的白字、深色截图上的黑字也看得清。
    private static func drawText(_ text: String, font: NSFont, color: NSColor, origin: CGPoint, width: CGFloat,
                                 height: CGFloat = 100_000, on ctx: CGContext, outline: NSColor?) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let outline {
            attributes[.strokeColor] = outline.withAlphaComponent(0.85)
            attributes[.strokeWidth] = -3.0
        }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(width: max(width, font.pointSize), height: height)
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, constraint, nil)
        let box = CGRect(x: 0, y: 0, width: constraint.width, height: max(fitted.height, font.pointSize))
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), nil)
        ctx.saveGState()
        // CoreText 要左下角为原点：在文字的位置再翻回来。
        ctx.translateBy(x: origin.x, y: origin.y + box.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    // MARK: 编码

    static func data(_ image: CGImage, format: CaptureFormat) -> Data? {
        let type: UTType = format == .jpg ? .jpeg : .png
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = format == .jpg ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// 放到剪贴板：PNG 和 TIFF 都放，聊天软件和预览都能直接粘贴。
    @MainActor
    @discardableResult
    static func copy(_ image: CGImage) -> Bool {
        guard let png = data(image, format: .png) else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            board.setData(tiff, forType: .tiff)
        }
        return true
    }

    /// 存进截图文件夹，文件名和系统截图一样（最近截图认得出来）。返回新文件。
    @MainActor
    static func save(_ image: CGImage, format: CaptureFormat) -> URL? {
        guard let data = data(image, format: format) else { return nil }
        let folder = FolderFeed.folder(for: .screenshots)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = FileRename.unique(CaptureFileName.screenshot(at: .now, format: format), taken: taken)
        let url = folder.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .withoutOverwriting)
        } catch {
            return nil
        }
        FolderFeed.shared(.screenshots).refresh(force: true)
        return url
    }

    /// 读 screencapture 刚写的临时文件，读完马上删掉，图只留在内存里。
    nonisolated static func loadAndDiscard(_ url: URL) -> Box? {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // 画进内存里的一张新图，文件删掉后不再回头读它。
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage().map(Box.init(image:))
    }
}
