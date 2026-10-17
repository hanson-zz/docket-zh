import AppKit
import SwiftUI

// Pieces shared by the widgets that show files: Photos, Screenshots,
// Downloads and the File Shelf. Every picture goes through `Thumbnails`, so
// nothing here ever decodes a file at full size.

/// A file's picture filling whatever frame it is given, cropped rather than
/// letterboxed, with its icon while the thumbnail is still being made.
struct FileThumb: View {
    var url: URL
    var pixels: Int = 320
    /// Icons are drawn whole; only real thumbnails are cropped to fill.
    var fill = true

    var body: some View {
        Color.clear
            .overlay {
                if let image = Thumbnails.shared.image(for: url, pixels: pixels) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: fill ? .fill : .fit)
                } else {
                    Image(nsImage: Thumbnails.shared.icon(for: url))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                        .opacity(0.8)
                }
            }
            .clipped()
    }
}

/// A stand-in picture for the library, which must not read anybody's disk:
/// opening Add Widget should never be the thing that triggers a folder
/// permission prompt.
struct SamplePicture: View {
    var symbol = "mountain.2.fill"

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.36),
                                    Color(red: 0.55, green: 0.32, blue: 0.62)],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 14, height: 14)
                .offset(x: 18, y: -26)
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(.black.opacity(0.35))
                .offset(x: 6, y: 10)
        }
        .clipped()
    }
}

/// Glass capsule button, the shape every panel uses for its actions.
struct PanelButton: View {
    var title: String
    var symbol: String?
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(WidgetStyle.label(12))
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Color.white.opacity(prominent ? 0.24 : 0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// The headline every file panel opens with: a glyph, a title and a line
/// saying where the files come from.
struct PanelHeader: View {
    var symbol: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(WidgetStyle.label(16))
                    .foregroundStyle(WidgetStyle.primary)
                Text(subtitle)
                    .font(WidgetStyle.caption(11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Said in words where a list would be empty.
struct PanelNote: View {
    var symbol: String
    var text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.5))
            Text(text)
                .font(WidgetStyle.caption(12))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A grid of file thumbnails: click opens, drag carries the file out, and a
/// secondary click offers the rest.
///
/// A fixed height, because the panel measures itself once when it opens and
/// a grid that grew afterwards would be cut off.
struct FileGrid: View {
    var files: [ListedFile]
    var columns = 4
    var height: CGFloat = 236
    var isImage = true
    var onTrash: ((ListedFile) -> Void)?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns),
                      spacing: 6) {
                ForEach(files) { file in
                    FileThumb(url: file.url, pixels: 240, fill: isImage)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.white.opacity(0.06))
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        .contentShape(.rect(cornerRadius: 8))
                        .onTapGesture { FileActions.open(file.url) }
                        .onDrag { FileActions.dragProvider(file.url) }
                        .contextMenu { FileMenu(file: file, onTrash: onTrash) }
                        .help(file.name)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: height)
    }
}

/// One row per file: icon, name, age and size.
struct FileRows: View {
    var files: [ListedFile]
    var now: Date
    var height: CGFloat = 236
    var onTrash: ((ListedFile) -> Void)?
    var onRemove: ((ListedFile) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(files) { file in
                    HStack(spacing: 10) {
                        FileThumb(url: file.url, pixels: 96, fill: file.isImage)
                            .frame(width: 30, height: 30)
                            .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name)
                                .font(WidgetStyle.label(12))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(detail(file))
                                .font(WidgetStyle.caption(10))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .glassPane(cornerRadius: 9)
                    .contentShape(.rect(cornerRadius: 9))
                    .onTapGesture { FileActions.open(file.url) }
                    .onDrag { FileActions.dragProvider(file.url) }
                    .contextMenu { FileMenu(file: file, onTrash: onTrash, onRemove: onRemove) }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: height)
    }

    private func detail(_ file: ListedFile) -> String {
        var parts = [RelativeAge.caption(file.date, now: now)]
        if file.isDirectory { parts.append(tr("文件夹")) }
        else if let size = FileActions.size(file.size) { parts.append(size) }
        return parts.joined(separator: " · ")
    }
}

/// What a secondary click on a file offers.
struct FileMenu: View {
    var file: ListedFile
    var onTrash: ((ListedFile) -> Void)?
    var onRemove: ((ListedFile) -> Void)?

    var body: some View {
        Button("打开") { FileActions.open(file.url) }
        Button("在访达中显示") { FileActions.reveal([file.url]) }
        Divider()
        if file.isImage {
            Button("拷贝图像") { FileActions.copyImage(file.url) }
        }
        Button("拷贝文件") { FileActions.copyFile(file.url) }
        if let onRemove {
            Divider()
            Button("移出暂存") { onRemove(file) }
        }
        if let onTrash {
            Divider()
            Button("移到废纸篓") { onTrash(file) }
        }
    }
}

extension View {
    /// Lets a picture run edge to edge inside a `WidgetSurface`, which
    /// insets its content horizontally for text.
    func bleedingThroughSurfaceInset() -> some View {
        padding(.horizontal, -WidgetStyle.inset)
    }
}
