import CoreGraphics
import Foundation
import ImageIO

/// The colour a Now Playing panel stands on, taken from its artwork.
///
/// Two numbers, not a picture. The panel's ground is a vertical ramp of one
/// hue at two *fixed* brightnesses, and that is the whole reason this is safe:
/// brightness is set by the design rather than read from the image, so the
/// legibility of the text over it can be proven for every value this type can
/// ever hold instead of measured against a handful of covers.
///
/// The proof rests on one property of relative luminance: its coefficients are
/// all positive and every channel of an HSV colour is at most V, so fixing V
/// bounds luminance for every hue and saturation at once. One clamp, total
/// guarantee. See ArtworkTintTests, which sweeps all 51,120 of them.
///
/// Deliberately free of AppKit and SwiftUI so it can live in the core, which
/// is what the test target compiles.
public struct ArtworkTint: Sendable, Equatable {
    /// 0..<1.
    public let hue: Double
    /// Already clamped into the band; see `extract`.
    public let saturation: Double

    /// Light falls from above, so the top stop is the brighter one. Both are
    /// design constants and neither comes from the artwork.
    ///
    /// 0.32 rather than a darker 0.26: it widens the visible chroma span by a
    /// quarter and still clears AAA for the title, where 0.26 bought 10:1 and
    /// spent the difference on nothing. Raising it past 0.34 loses AAA, which
    /// is what the sweep in the tests fails on.
    public static let topBrightness = 0.32
    public static let bottomBrightness = 0.16

    /// A cover more saturated than this is pulled back: past roughly 0.7 a
    /// dark ramp stops reading as a surface and starts reading as a colour
    /// cast.
    public static let saturationCap = 0.70

    /// And one less saturated is pushed up to here.
    ///
    /// Not arbitrary. Real album art measures 0.02 to 0.06 averaged across
    /// the frame, so anything honest about the mean renders the same neutral
    /// grey for every record ever pressed. The floor is what makes a blue
    /// cover look blue.
    public static let saturationFloor = 0.34

    /// Below this there is no hue worth showing, and the ground goes neutral
    /// rather than inventing one. A white cover and a black cover both land
    /// here, which is correct: neither has a colour.
    public static let greyThreshold = 0.08

    public init(hue: Double, saturation: Double) {
        self.hue = hue
        self.saturation = saturation
    }

    public var top: (red: Double, green: Double, blue: Double) {
        Self.rgb(hue: hue, saturation: saturation, value: Self.topBrightness)
    }

    public var bottom: (red: Double, green: Double, blue: Double) {
        Self.rgb(hue: hue, saturation: saturation, value: Self.bottomBrightness)
    }

    /// 「正在播放」面板改版后不再整面铺封面色：深色玻璃打底，只在顶上叠一层封面
    /// 主色的光晕，透明度不超过 15%，往下 55% 处消失。光晕用这个色相的亮色，
    /// 叠在深色上才看得出是什么颜色。
    public static let glowOpacity = 0.15
    public static let glowReach = 0.55
    public static let glowBrightness = 0.85

    public var glow: (red: Double, green: Double, blue: Double) {
        Self.rgb(hue: hue, saturation: saturation, value: Self.glowBrightness)
    }

    // MARK: Extraction

    /// The dominant hue of an image, or nil if the data is not an image.
    ///
    /// A mean is the obvious approach and it does not work: averaging a
    /// colourful frame yields grey-brown, because opposing hues cancel. This
    /// buckets hues instead and weights each pixel by how much colour it
    /// actually carries, so the answer is the hue with the most chroma behind
    /// it rather than the arithmetic middle of everything.
    ///
    /// 16x16 because the question is "what colour is this", which survives
    /// almost any amount of downsampling, and because ImageIO decodes a
    /// thumbnail that size without ever building the full bitmap.
    public static func extract(_ data: Data) -> ArtworkTint? {
        guard let pixels = thumbnail(data) else { return nil }

        // Twelve buckets: fine enough to tell blue from cyan, coarse enough
        // that a gradient across one wall of a room does not split in two.
        let buckets = 12
        var mass = [Double](repeating: 0, count: buckets)
        var hueSum = [Double](repeating: 0, count: buckets)
        var saturationSum = [Double](repeating: 0, count: buckets)

        for pixel in pixels {
            let (hue, saturation, value) = hsv(pixel)
            // Near-grey and near-black pixels have no hue to contribute and
            // would otherwise vote with whatever rounding gave them.
            guard saturation > 0.15, value > 0.10 else { continue }
            let weight = saturation * value
            let bucket = min(buckets - 1, Int(hue * Double(buckets)))
            mass[bucket] += weight
            hueSum[bucket] += hue * weight
            saturationSum[bucket] += saturation * weight
        }

        guard let winner = mass.indices.max(by: { mass[$0] < mass[$1] }),
              mass[winner] > 0
        else {
            // No pixel carried any colour, so the artwork is greyscale.
            return ArtworkTint(hue: 0, saturation: 0)
        }

        let hue = hueSum[winner] / mass[winner]
        let raw = saturationSum[winner] / mass[winner]
        let saturation = raw < greyThreshold
            ? 0
            : min(saturationCap, max(saturationFloor, raw))
        return ArtworkTint(hue: hue, saturation: saturation)
    }

    /// Off the main actor for the one caller that is already on it.
    ///
    /// `Task.detached` rather than a plain `Task`, which would inherit the
    /// caller's isolation and do the decode exactly where it must not.
    public static func extracted(from data: Data) async -> ArtworkTint? {
        await Task.detached(priority: .utility) { extract(data) }.value
    }

    // MARK: Pixels

    /// Straight RGBA bytes from a 16x16 thumbnail.
    private static func thumbnail(_ data: Data) -> [(Double, Double, Double)]? {
        let side = 16
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
              ] as CFDictionary)
        else { return nil }

        // Drawn into a context we describe rather than read from the image's
        // own, because artwork arrives in whatever colour space and byte
        // order its origin felt like and reading those by hand is how a blue
        // cover comes out orange.
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let context = bytes.withUnsafeMutableBytes { buffer -> CGContext? in
            CGContext(data: buffer.baseAddress,
                      width: side, height: side,
                      bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let context else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        return stride(from: 0, to: bytes.count, by: 4).compactMap { i in
            let alpha = Double(bytes[i + 3]) / 255
            // A transparent pixel has no colour of its own; premultiplied
            // values there are zero and would vote black.
            guard alpha > 0.5 else { return nil }
            return (Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255)
        }
    }

    // MARK: Colour

    private static func hsv(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
        let (r, g, b) = rgb
        let high = max(r, g, b), low = min(r, g, b)
        let delta = high - low
        guard delta > 0 else { return (0, 0, high) }
        let hue: Double
        switch high {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        return ((hue < 0 ? hue + 6 : hue) / 6, high > 0 ? delta / high : 0, high)
    }

    static func rgb(hue: Double, saturation: Double,
                    value: Double) -> (red: Double, green: Double, blue: Double) {
        guard saturation > 0 else { return (value, value, value) }
        let sector = (hue - hue.rounded(.down)) * 6
        let index = Int(sector)
        let f = sector - Double(index)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let t = value * (1 - saturation * (1 - f))
        return switch index {
        case 0: (value, t, p)
        case 1: (q, value, p)
        case 2: (p, value, t)
        case 3: (p, q, value)
        case 4: (t, p, value)
        default: (value, p, q)
        }
    }
}
