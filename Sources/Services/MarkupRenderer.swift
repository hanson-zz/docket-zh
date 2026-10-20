import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// 把截图标注画到图上。面板里的预览和拷贝、存出去的原尺寸图走同一套，
/// 线宽、字号、马赛克格子都按图宽算（见 `MarkupGeometry`），所以看到的就是得到的。
/// 原图文件从不改写。
@MainActor
enum MarkupRenderer {
    /// 读一张截图。`maxPixel` 给预览用，读缩小的那份；nil 读原尺寸。
    static func load(_ url: URL, maxPixel: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        if let maxPixel {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 图的像素尺寸，只读文件头。
    nonisolated static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    /// 底图加上所有标注。
    static func render(_ image: CGImage, marks: [Markup]) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let size = CGSize(width: w, height: h)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        for mark in marks {
            draw(mark, on: ctx, base: image, size: size)
        }
        return ctx.makeImage()
    }

    /// CoreGraphics 的原点在左下角，标注记的是左上角为原点的比例。
    private static func flip(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
    }

    private static func color(_ c: MarkupColor) -> CGColor {
        let rgb = c.rgb
        return CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    private static func draw(_ mark: Markup, on ctx: CGContext, base: CGImage, size: CGSize) {
        let width = MarkupGeometry.lineWidth(imageWidth: size.width)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(color(mark.color))
        ctx.setFillColor(color(mark.color))
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        // 浅色截图上也看得清：一层很淡的阴影。
        ctx.setShadow(offset: CGSize(width: 0, height: -width * 0.4), blur: width * 1.2,
                      color: CGColor(gray: 0, alpha: 0.35))
        switch mark.tool {
        case .arrow:
            let a = flip(mark.start, size)
            let b = flip(mark.end, size)
            let (l, r) = MarkupGeometry.arrowHead(from: a, to: b, length: width * 5)
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.move(to: l)
            ctx.addLine(to: b)
            ctx.addLine(to: r)
            ctx.strokePath()
        case .box:
            let r = mark.rect
            let rect = CGRect(x: r.minX * size.width, y: (1 - r.maxY) * size.height,
                              width: r.width * size.width, height: r.height * size.height)
            // 圆角不能超过边长的一半，否则 CGPath 会直接崩溃（扁长的框）。
            let corner = max(0, min(width * 1.5, rect.width / 2, rect.height / 2))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.strokePath()
        case .mosaic:
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            mosaic(mark.rect, on: ctx, base: base, size: size)
        case .text:
            text(mark, on: ctx, size: size)
        }
    }

    /// 把那一块缩小再用最近邻放大回去，就是马赛克。取的是原图，不是画过的。
    private static func mosaic(_ r: CGRect, on ctx: CGContext, base: CGImage, size: CGSize) {
        // cropping 的原点在左上角。
        let crop = CGRect(x: r.minX * size.width, y: r.minY * size.height,
                          width: r.width * size.width, height: r.height * size.height).integral
        guard crop.width >= 1, crop.height >= 1, let piece = base.cropping(to: crop) else { return }
        let cell = MarkupGeometry.mosaicCell(imageWidth: size.width)
        let cols = max(1, Int((crop.width / cell).rounded(.up)))
        let rows = max(1, Int((crop.height / cell).rounded(.up)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = CGContext(data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        small.interpolationQuality = .medium
        small.draw(piece, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let blocks = small.makeImage() else { return }
        ctx.interpolationQuality = .none
        ctx.draw(blocks, in: CGRect(x: crop.minX, y: size.height - crop.maxY, width: crop.width, height: crop.height))
        ctx.interpolationQuality = .high
    }

    private static func text(_ mark: Markup, on ctx: CGContext, size: CGSize) {
        let fontSize = MarkupGeometry.textSize(imageWidth: size.width)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attributed = NSAttributedString(string: mark.text, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: color(mark.color)) ?? .white,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        let top = flip(mark.start, size)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: top.x, y: top.y - ascent)
        CTLineDraw(line, ctx)
    }

    // MARK: 输出

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// 图像放到剪贴板：PNG 和 TIFF 都放，聊天软件和预览都能直接粘贴。
    static func copy(_ image: CGImage) -> Bool {
        guard let png = pngData(image) else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            board.setData(tiff, forType: .tiff)
        }
        return true
    }

    /// 存成同一个文件夹里的新图，返回新文件；原图不动。
    static func saveCopy(_ image: CGImage, besides original: URL) -> URL? {
        guard let png = pngData(image) else { return nil }
        let folder = original.deletingLastPathComponent()
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let target = folder.appendingPathComponent(MarkupNaming.newName(original: original.lastPathComponent, taken: taken))
        do {
            try png.write(to: target, options: .withoutOverwriting)
            return target
        } catch {
            return nil
        }
    }
}
