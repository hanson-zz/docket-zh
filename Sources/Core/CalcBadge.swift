import Foundation

/// 「算」卡片的字牌：小熊猫脸框的拟人计算器（第三轮效果图变体 E）。
///
///     ┌──────────────┐   方底照旧是 TileBadge（主题色铺底、细边、圆角 0.26）
///     │ ╭──●──●──╮   │   橙红脸框，上框两颗奶白眉斑
///     │ │ ▌   ◠  │   │   深紫墨色屏幕，两只白胶囊眼，右眼眨成 ^ 弧
///     │ ◖────────◗   │   下框两角奶白腮（裁进脸框里）
///     │ (+)  (−)     │   2×2 胶囊键：前三个读卡片主题色，
///     │ (×)  (＝)    │   「＝」是小熊猫橙红
///     └──────────────┘
///
/// 这里只放比例和颜色：所有位置都按边长的比例写（0...1，左上角是原点，y 向下），
/// 界面那边乘上边长自己画，所以 40、34、32、26pt 各尺寸用的是同一张图。
/// 数值取自 design/calc-badge-v3/calc-badge-v3.py 的变体 E。
public enum CalcBadge {

    /// 字牌用到的几种边长：扩展栏横排 40、小一号 34、竖排货架 32、计算卡竖排 26。
    public static let sizes: [Double] = [40, 34, 32, 26]

    /// 边长比例里的一个框：左上 `(x0, y0)`、右下 `(x1, y1)`。
    public struct Box: Equatable, Sendable {
        public var x0: Double
        public var y0: Double
        public var x1: Double
        public var y1: Double

        public init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
            self.x0 = x0
            self.y0 = y0
            self.x1 = x1
            self.y1 = y1
        }

        public var width: Double { x1 - x0 }
        public var height: Double { y1 - y0 }
        public var midX: Double { (x0 + x1) / 2 }
        public var midY: Double { (y0 + y1) / 2 }

        /// `other` 整个落在这个框里（边上算在里面）。
        public func contains(_ other: Box) -> Bool {
            other.x0 >= x0 - 1e-9 && other.y0 >= y0 - 1e-9 && other.x1 <= x1 + 1e-9 && other.y1 <= y1 + 1e-9
        }

        public func contains(x: Double, y: Double) -> Bool {
            x >= x0 - 1e-9 && x <= x1 + 1e-9 && y >= y0 - 1e-9 && y <= y1 + 1e-9
        }

        public func overlaps(_ other: Box) -> Bool {
            x0 < other.x1 && other.x0 < x1 && y0 < other.y1 && other.y0 < y1
        }
    }

    /// 整个字牌（方底）。
    public static let plate = Box(0, 0, 1, 1)

    // MARK: 脸

    /// 橙红脸框：套在屏幕外的一层圆角矩形。
    public static let face = Box(0.11, 0.07, 0.89, 0.50)
    public static let faceCorner = 0.13
    /// 脸框上缘一圈渐隐的亮边。
    public static let faceRim = 0.014

    /// 下框两角的奶白腮：两只椭圆，画的时候裁进脸框里。
    public static let cheeks = [Box(0.05, 0.34, 0.31, 0.58), Box(0.69, 0.34, 0.95, 0.58)]

    /// 深紫墨色显示屏（浅色外观下不是纯黑）。
    public static let screen = Box(0.17, 0.19, 0.83, 0.445)
    public static let screenCorner = 0.075
    public static let screenRim = 0.018

    /// 两只眼睛的横向中心。
    public static let eyeCenters = (left: 0.385, right: 0.615)

    /// 上框两颗奶白眉斑，在两只眼睛正上方。
    public static let brows = [eyeCenters.left, eyeCenters.right].map { Box($0 - 0.065, 0.092, $0 + 0.065, 0.170) }

    /// 左眼：睁着的白色竖胶囊，垂直居中在屏幕里。
    public static let openEye: Box = {
        let w = 0.085, h = 0.16, cy = screen.midY
        return Box(eyeCenters.left - w / 2, cy - h / 2, eyeCenters.left + w / 2, cy + h / 2)
    }()

    /// 右眼：眨成向上拱的 ^ 弧。椭圆弧的中心、半径、起止角（度，0 在右、顺时针，y 向下）和线宽。
    public struct Wink: Equatable, Sendable {
        public var centerX: Double
        public var centerY: Double
        public var radiusX: Double
        public var radiusY: Double
        public var startDegrees: Double
        public var endDegrees: Double
        public var lineWidth: Double

        /// 弧上的点（含两头），界面连成一条圆头折线。
        public func points(steps: Int = 24) -> [(x: Double, y: Double)] {
            let n = max(2, steps)
            return (0...n).map { i in
                let a = (startDegrees + (endDegrees - startDegrees) * Double(i) / Double(n)) * .pi / 180
                return (x: centerX + radiusX * cos(a), y: centerY + radiusY * sin(a))
            }
        }
    }

    public static let wink = Wink(centerX: eyeCenters.right, centerY: screen.midY + 0.025,
                                  radiusX: 0.066, radiusY: 0.058,
                                  startDegrees: 195, endDegrees: 345, lineWidth: 0.055)

    // MARK: 按键

    public enum Key: CaseIterable, Sendable {
        case plus, minus, times, equals

        /// 「＝」是小熊猫橙红，其余三个读卡片主题色。
        public var isAccent: Bool { self == .equals }
    }

    /// 2×2 按键占的区域和键之间的缝。
    public static let keypad = Box(0.15, 0.555, 0.85, 0.875)
    public static let keyGap = 0.045

    /// 四个胶囊键，按 + − × ＝ 的顺序（左上、右上、左下、右下）。
    public static let keys: [Box] = {
        let kw = (keypad.width - keyGap) / 2
        let kh = (keypad.height - keyGap) / 2
        let xs = [keypad.x0, keypad.x0 + kw + keyGap]
        let ys = [keypad.y0, keypad.y0 + kh + keyGap]
        return [(0, 0), (1, 0), (0, 1), (1, 1)].map { c, r in Box(xs[c], ys[r], xs[c] + kw, ys[r] + kh) }
    }()

    public static func key(_ key: Key) -> Box {
        keys[Key.allCases.firstIndex(of: key) ?? 0]
    }

    /// 按键上缘渐隐亮边的线宽（比例）。
    public static let keyRim = 0.014

    /// 符号的线宽（pt）：大约边长的 3.4%，最细 1pt，26pt 下不发虚。
    public static let minimumStroke = 1.0

    public static func symbolStroke(size: Double) -> Double {
        max(minimumStroke, 0.034 * size)
    }

    /// 「＝」两道横线细一点（0.72 倍），也不细过 1pt。
    public static func equalsStroke(size: Double) -> Double {
        max(minimumStroke, symbolStroke(size: size) * 0.72)
    }

    /// 符号一臂的长度（比例，从键中心量起）：小尺寸稍大一点，免得缩成一个点。
    public static func symbolArm(size: Double) -> Double {
        key(.plus).height * (size >= 32 ? 0.27 : 0.30)
    }

    /// 符号的线段（比例坐标），界面用圆头描边画。
    public static func symbolSegments(_ key: Key, size: Double) -> [((Double, Double), (Double, Double))] {
        let box = self.key(key)
        let cx = box.midX, cy = box.midY, k = symbolArm(size: size)
        switch key {
        case .plus:
            return [((cx - k, cy), (cx + k, cy)), ((cx, cy - k), (cx, cy + k))]
        case .minus:
            return [((cx - k, cy), (cx + k, cy))]
        case .times:
            let q = k * 0.78
            return [((cx - q, cy - q), (cx + q, cy + q)), ((cx - q, cy + q), (cx + q, cy - q))]
        case .equals:
            let d = k * 0.55
            return [((cx - k, cy - d), (cx + k, cy - d)), ((cx - k, cy + d), (cx + k, cy + d))]
        }
    }

    // MARK: 颜色

    /// 小熊猫橙红（脸框底端、「＝」键）。
    public static let panda = ColorCode(red: 0xE0 / 255.0, green: 0x68 / 255.0, blue: 0x2C / 255.0)
    /// 脸框顶端的亮一档。
    public static let pandaHighlight = ColorCode(red: 0xF2 / 255.0, green: 0x8E / 255.0, blue: 0x4E / 255.0)
    /// 眉斑、腮的奶白。
    public static let cream = ColorCode(red: 0xFF / 255.0, green: 0xF6 / 255.0, blue: 0xEC / 255.0)
    /// 橙红「＝」键上的深棕符号。
    public static let equalsInk = ColorCode(red: 60 / 255.0, green: 20 / 255.0, blue: 4 / 255.0)
    /// 眼睛的白（带一点紫）。
    public static let eyeWhite = ColorCode(red: 250 / 255.0, green: 248 / 255.0, blue: 1)

    /// 屏幕的竖向渐变：浅色外观是深紫墨色（不是纯黑，免得在淡紫方底上太跳），深色外观近黑。
    public static func screenColors(dark: Bool) -> (top: ColorCode, bottom: ColorCode) {
        dark
            ? (rgb(30, 22, 44), rgb(14, 10, 22))
            : (rgb(58, 40, 96), rgb(34, 24, 58))
    }

    /// 屏幕上缘高光的起始不透明度。
    public static func screenRimOpacity(dark: Bool) -> Double {
        dark ? 45 / 255.0 : 70 / 255.0
    }

    /// 主题色按键的底色：深色外观直接用主题色，浅色外观往深紫里压一点（12%），
    /// 白符号在浅底卡片上更稳。`main` 传已经调过可读性的主题色。
    public static func keyFill(main: ColorCode, dark: Bool) -> ColorCode {
        dark ? main : main.mixed(with: rgb(60, 30, 140), by: 0.12)
    }

    /// 按键的竖向渐变：上端往白里调 22%，下端往黑里压 10%。
    public static func keyGradient(_ fill: ColorCode) -> (top: ColorCode, bottom: ColorCode) {
        (fill.mixed(with: ColorCode(red: 1, green: 1, blue: 1), by: 0.22),
         fill.mixed(with: ColorCode(red: 0, green: 0, blue: 0), by: 0.10))
    }

    /// 主题色键上的符号用深色（true）还是白色：白色够 3:1（图形的最低对比度）就用白，
    /// 像默认的紫；用户把卡片换成黄、薄荷这类浅色时换成深色，免得白符号看不见。
    public static func keyInkIsDark(on fill: ColorCode) -> Bool {
        WidgetTint.contrastRatio(fill, ColorCode(red: 1, green: 1, blue: 1)) < WidgetTint.minimumContrast
    }

    /// 浅色主题键上的深色符号。
    public static let darkKeyInk = rgb(30, 20, 50)

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> ColorCode {
        ColorCode(red: r / 255, green: g / 255, blue: b / 255)
    }
}
