import AppKit
import SwiftUI

// The files the file widgets are photographed reading.
//
// The photo frame, the file shelf, Downloads and recent screenshots all show
// what is on disk, and the disk of whoever runs this is theirs: their
// pictures, their downloads, the name of whatever they captured last. So the
// tool makes its own files and points the widgets at those. Nothing here is a
// mock of a widget: each widget reads real files through its own service, they
// are only files made for the purpose.
//
// The pictures are drawn here rather than shipped, so the repository carries
// no photograph, and so nobody's artwork ends up in the README: two soft
// gradients and a horizon, in the same palette as the backdrop. The
// screenshot is a real one of Docket, a widget rendered offscreen.
//
// Two of the four widgets read folders the tool cannot choose: Downloads is
// always ~/Downloads, and recent screenshots is wherever `screencapture`
// writes. Writing into those would litter a real Mac, so it only happens when
// SHOTS_DISPOSABLE=1 says the machine is a throwaway one, which is what the
// screenshot workflow sets on its CI runner. Anywhere else those two panels
// are captured from their own sample state and say so.

@MainActor
enum Fixtures {
    /// A throwaway machine: CI, nothing of anybody's on it.
    static var disposable: Bool {
        ProcessInfo.processInfo.environment["SHOTS_DISPOSABLE"] == "1"
    }

    /// Made once per run, under the temporary directory.
    static let root: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "docket-shots-fixtures-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// The folder the photo frame is pointed at.
    static var pictures: URL { root.appending(path: "图片", directoryHint: .isDirectory) }

    /// Palettes for the drawn pictures: sky top, sky bottom, land.
    private static let palettes: [(NSColor, NSColor, NSColor)] = [
        (NSColor(srgbRed: 0.98, green: 0.62, blue: 0.36, alpha: 1),
         NSColor(srgbRed: 0.55, green: 0.32, blue: 0.62, alpha: 1),
         NSColor(srgbRed: 0.20, green: 0.14, blue: 0.28, alpha: 1)),
        (NSColor(srgbRed: 0.42, green: 0.70, blue: 0.96, alpha: 1),
         NSColor(srgbRed: 0.85, green: 0.92, blue: 0.98, alpha: 1),
         NSColor(srgbRed: 0.24, green: 0.45, blue: 0.40, alpha: 1)),
        (NSColor(srgbRed: 0.12, green: 0.16, blue: 0.36, alpha: 1),
         NSColor(srgbRed: 0.36, green: 0.49, blue: 0.98, alpha: 1),
         NSColor(srgbRed: 0.07, green: 0.09, blue: 0.18, alpha: 1)),
        (NSColor(srgbRed: 0.99, green: 0.83, blue: 0.55, alpha: 1),
         NSColor(srgbRed: 0.91, green: 0.57, blue: 0.42, alpha: 1),
         NSColor(srgbRed: 0.45, green: 0.30, blue: 0.24, alpha: 1)),
        (NSColor(srgbRed: 0.60, green: 0.84, blue: 0.80, alpha: 1),
         NSColor(srgbRed: 0.95, green: 0.95, blue: 0.90, alpha: 1),
         NSColor(srgbRed: 0.30, green: 0.52, blue: 0.48, alpha: 1)),
        (NSColor(srgbRed: 0.75, green: 0.55, blue: 0.85, alpha: 1),
         NSColor(srgbRed: 0.98, green: 0.78, blue: 0.80, alpha: 1),
         NSColor(srgbRed: 0.36, green: 0.24, blue: 0.40, alpha: 1)),
    ]

    /// A horizon: a gradient sky, a sun, and two soft ridges.
    static func landscape(_ index: Int, size: CGSize = CGSize(width: 1200, height: 800)) -> Data? {
        let (top, bottom, land) = palettes[index % palettes.count]
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -90)
            let sun = CGRect(x: rect.width * (0.22 + 0.1 * Double(index % 3)), y: rect.height * 0.55,
                             width: rect.height * 0.14, height: rect.height * 0.14)
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSBezierPath(ovalIn: sun).fill()
            for (layer, alpha) in [(0, 0.55), (1, 1.0)] {
                let path = NSBezierPath()
                let base = rect.height * (layer == 0 ? 0.42 : 0.28)
                path.move(to: CGPoint(x: 0, y: 0))
                path.line(to: CGPoint(x: 0, y: base))
                let steps = 6
                for step in 1...steps {
                    let x = rect.width * Double(step) / Double(steps)
                    let wobble = sin(Double(step + index + layer * 2) * 1.7) * rect.height * 0.08
                    path.curve(to: CGPoint(x: x, y: base + wobble),
                               controlPoint1: CGPoint(x: x - rect.width / Double(steps) * 0.6,
                                                      y: base + wobble + rect.height * 0.06),
                               controlPoint2: CGPoint(x: x - rect.width / Double(steps) * 0.3,
                                                      y: base + wobble))
                }
                path.line(to: CGPoint(x: rect.width, y: 0))
                path.close()
                land.withAlphaComponent(alpha).setFill()
                path.fill()
            }
            return true
        }
        return png(image)
    }

    private static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// A screenshot of Docket itself: one of its tiles, drawn offscreen on
    /// the shelf's colour.
    static func screenshotOfDocket(_ kind: WidgetKind) -> Data? {
        guard let instance = WidgetCatalog.make(kind) else { return nil }
        let view = WidgetTile(instance: instance, context: WidgetContext(isPreview: true))
            .padding(40)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// A one-page PDF with a title and a few ruled lines.
    static func document(title: String) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        pdf.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
        (title as NSString).draw(at: CGPoint(x: 60, y: 760),
                                 withAttributes: [.font: NSFont.boldSystemFont(ofSize: 28)])
        NSColor(white: 0.85, alpha: 1).setFill()
        for line in 0..<14 {
            NSBezierPath(rect: CGRect(x: 60, y: 700 - line * 30, width: line % 4 == 3 ? 280 : 470,
                                      height: 8)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        pdf.endPDFPage()
        pdf.closePDF()
        return data as Data
    }

    private static func write(_ data: Data?, to url: URL, age: TimeInterval = 0) {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)
        let date = Date().addingTimeInterval(-age)
        try? FileManager.default.setAttributes([.modificationDate: date, .creationDate: date],
                                               ofItemAtPath: url.path)
    }

    /// The photo frame's folder: six drawn pictures.
    static func makePictures() {
        for index in 0..<6 {
            write(landscape(index), to: pictures.appending(path: "风景 \(index + 1).png"),
                  age: Double(index) * 3600)
        }
    }

    /// Three files for the file shelf to hold. Returns their paths.
    static func makeShelfFiles() -> [String] {
        let folder = root.appending(path: "暂存", directoryHint: .isDirectory)
        let files: [(URL, Data?)] = [
            (folder.appending(path: "季度报告.pdf"), document(title: "季度报告")),
            (folder.appending(path: "海报草图.png"), landscape(2, size: CGSize(width: 800, height: 1000))),
            (folder.appending(path: "会议纪要.txt"), Data("会议纪要\n\n1. 确认发布日期\n2. 整理反馈\n".utf8)),
        ]
        for (url, data) in files { write(data, to: url) }
        return files.map { $0.0.path }
    }

    /// Downloads, on a disposable machine only.
    static func makeDownloads() {
        guard disposable else { return }
        let folder = FolderFeed.folder(for: .downloads)
        write(document(title: "发票"), to: folder.appending(path: "发票.pdf"), age: 60)
        write(landscape(1), to: folder.appending(path: "壁纸.png"), age: 600)
        write(document(title: "使用说明"), to: folder.appending(path: "使用说明.pdf"), age: 3600)
        write(Data("名称,数量\n苹果,3\n香蕉,5\n".utf8), to: folder.appending(path: "清单.csv"), age: 7200)
        write(landscape(4), to: folder.appending(path: "旅行照片.png"), age: 86_400)
    }

    /// Screenshots of Docket, named the way macOS names them, wherever
    /// `screencapture` writes, on a disposable machine only.
    static func makeScreenshots() {
        guard disposable else { return }
        let folder = FolderFeed.folder(for: .screenshots)
        let names = DateFormatter()
        names.locale = Locale(identifier: "zh_CN")
        names.dateFormat = "yyyy-MM-dd ah.mm.ss"
        let kinds: [WidgetKind] = [.weather, .clock, .calendar, .music, .system]
        for (index, kind) in kinds.enumerated() {
            let age = Double(index) * 900 + 120
            let stamp = names.string(from: Date().addingTimeInterval(-age))
            write(screenshotOfDocket(kind), to: folder.appending(path: "截屏\(stamp).png"), age: age)
        }
    }

    /// A few copies for the clipboard history, on a disposable machine only:
    /// on anybody else's Mac this would overwrite what they last copied.
    static func fillClipboard() async {
        guard disposable else { return }
        ClipboardHistory.shared.start()
        let board = NSPasteboard.general
        for text in ["Docket 中文版 v0.3.1", "#0A84FF", "https://github.com/hanson-zz/docket-zh",
                     "明天上午十点开会"] {
            board.clearContents()
            board.setString(text, forType: .string)
            try? await Task.sleep(for: .seconds(1.2))
        }
    }
}
