import SwiftUI

// 世界时钟城市卡右上角的地标线稿。
//
// 每个地标一个 SwiftUI Shape，坐标按 100×100 的方格画（底边 y = 100），只描边
// 不填充。画的时候先把路径缩放到视图大小，再描边，所以线宽在任何尺寸下都是
// 同一个值（`CityLandmarkMark.lineWidth`），跟着文字颜色走，不用图片资源。
// 城市到地标的映射在 Core（`WorldCity.landmark`），北京和上海同一个时区，
// 地标不同。

/// 地标的路径：100×100 方格里的线稿，缩放到视图里最大的正方形，居中。
enum LandmarkPaths {
    static func path(_ landmark: CityLandmark, in rect: CGRect) -> Path {
        var p = Path()
        switch landmark {
        case .templeOfHeaven: templeOfHeaven(&p)
        case .orientalPearl: orientalPearl(&p)
        case .bigBen: bigBen(&p)
        case .empireState: empireState(&p)
        case .tokyoTower: tokyoTower(&p)
        case .eiffelTower: eiffelTower(&p)
        case .sydneyOpera: sydneyOpera(&p)
        case .burjKhalifa: burjKhalifa(&p)
        case .marinaBaySands: marinaBaySands(&p)
        case .skyline: skyline(&p)
        }
        let side = min(rect.width, rect.height)
        let scale = side / 100
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return p.applying(transform)
    }

    /// 北京 天坛祈年殿：三层台基、三重檐圆攒尖、宝顶。
    static func templeOfHeaven(_ p: inout Path) {
        p.move(to: .init(x: 8, y: 100))
        p.addLine(to: .init(x: 92, y: 100))
        p.move(to: .init(x: 10, y: 100))
        p.addLine(to: .init(x: 10, y: 93))
        p.addLine(to: .init(x: 90, y: 93))
        p.addLine(to: .init(x: 90, y: 100))
        p.move(to: .init(x: 18, y: 93))
        p.addLine(to: .init(x: 18, y: 87))
        p.addLine(to: .init(x: 82, y: 87))
        p.addLine(to: .init(x: 82, y: 93))
        p.move(to: .init(x: 26, y: 87))
        p.addLine(to: .init(x: 26, y: 81))
        p.addLine(to: .init(x: 74, y: 81))
        p.addLine(to: .init(x: 74, y: 87))
        p.move(to: .init(x: 35, y: 81))
        p.addLine(to: .init(x: 35, y: 71))
        p.move(to: .init(x: 65, y: 81))
        p.addLine(to: .init(x: 65, y: 71))
        p.move(to: .init(x: 42, y: 81))
        p.addLine(to: .init(x: 42, y: 71))
        p.move(to: .init(x: 50, y: 81))
        p.addLine(to: .init(x: 50, y: 71))
        p.move(to: .init(x: 58, y: 81))
        p.addLine(to: .init(x: 58, y: 71))
        p.move(to: .init(x: 20, y: 72))
        p.addQuadCurve(to: .init(x: 36, y: 61), control: .init(x: 30, y: 70))
        p.addLine(to: .init(x: 64, y: 61))
        p.addQuadCurve(to: .init(x: 80, y: 72), control: .init(x: 70, y: 70))
        p.closeSubpath()
        p.move(to: .init(x: 39, y: 61))
        p.addLine(to: .init(x: 39, y: 53))
        p.move(to: .init(x: 61, y: 61))
        p.addLine(to: .init(x: 61, y: 53))
        p.move(to: .init(x: 50, y: 61))
        p.addLine(to: .init(x: 50, y: 53))
        p.move(to: .init(x: 27, y: 54))
        p.addQuadCurve(to: .init(x: 41, y: 44), control: .init(x: 35, y: 52))
        p.addLine(to: .init(x: 59, y: 44))
        p.addQuadCurve(to: .init(x: 73, y: 54), control: .init(x: 65, y: 52))
        p.closeSubpath()
        p.move(to: .init(x: 42, y: 44))
        p.addLine(to: .init(x: 42, y: 37))
        p.move(to: .init(x: 58, y: 44))
        p.addLine(to: .init(x: 58, y: 37))
        p.move(to: .init(x: 33, y: 38))
        p.addQuadCurve(to: .init(x: 44, y: 28), control: .init(x: 41, y: 36))
        p.addQuadCurve(to: .init(x: 56, y: 28), control: .init(x: 50, y: 20))
        p.addQuadCurve(to: .init(x: 67, y: 38), control: .init(x: 59, y: 36))
        p.closeSubpath()
        p.move(to: .init(x: 50, y: 22))
        p.addLine(to: .init(x: 50, y: 15))
        p.addEllipse(in: CGRect(x: 47.4, y: 8.4, width: 5.2, height: 5.2))
    }

    /// 上海 东方明珠：三根斜撑、两个大球、小球、天线。
    static func orientalPearl(_ p: inout Path) {
        p.move(to: .init(x: 30, y: 100))
        p.addLine(to: .init(x: 45, y: 70))
        p.move(to: .init(x: 70, y: 100))
        p.addLine(to: .init(x: 55, y: 70))
        p.move(to: .init(x: 50, y: 100))
        p.addLine(to: .init(x: 50, y: 74))
        p.addEllipse(in: CGRect(x: 39, y: 51, width: 22, height: 22))
        p.move(to: .init(x: 39, y: 62))
        p.addLine(to: .init(x: 61, y: 62))
        p.move(to: .init(x: 47, y: 51))
        p.addLine(to: .init(x: 47, y: 35))
        p.move(to: .init(x: 53, y: 51))
        p.addLine(to: .init(x: 53, y: 35))
        p.addEllipse(in: CGRect(x: 43.5, y: 22.5, width: 13, height: 13))
        p.addEllipse(in: CGRect(x: 47, y: 12.5, width: 6, height: 6))
        p.move(to: .init(x: 50, y: 22.5))
        p.addLine(to: .init(x: 50, y: 18.5))
        p.move(to: .init(x: 50, y: 12.5))
        p.addLine(to: .init(x: 50, y: 0))
        p.move(to: .init(x: 24, y: 100))
        p.addLine(to: .init(x: 76, y: 100))
    }

    /// 伦敦 大本钟（伊丽莎白塔）和议会大厦一段。
    static func bigBen(_ p: inout Path) {
        p.move(to: .init(x: 41, y: 100))
        p.addLine(to: .init(x: 41, y: 47))
        p.move(to: .init(x: 59, y: 100))
        p.addLine(to: .init(x: 59, y: 47))
        p.move(to: .init(x: 41, y: 62))
        p.addLine(to: .init(x: 59, y: 62))
        p.move(to: .init(x: 41, y: 78))
        p.addLine(to: .init(x: 59, y: 78))
        p.move(to: .init(x: 37, y: 47))
        p.addLine(to: .init(x: 63, y: 47))
        p.addLine(to: .init(x: 63, y: 28))
        p.addLine(to: .init(x: 37, y: 28))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: 43, y: 30.5, width: 14, height: 14))
        p.move(to: .init(x: 50, y: 37.5))
        p.addLine(to: .init(x: 50, y: 33))
        p.move(to: .init(x: 50, y: 37.5))
        p.addLine(to: .init(x: 53, y: 39))
        p.move(to: .init(x: 40, y: 28))
        p.addLine(to: .init(x: 40, y: 19))
        p.addLine(to: .init(x: 60, y: 19))
        p.addLine(to: .init(x: 60, y: 28))
        p.move(to: .init(x: 45, y: 28))
        p.addLine(to: .init(x: 45, y: 22))
        p.move(to: .init(x: 50, y: 28))
        p.addLine(to: .init(x: 50, y: 22))
        p.move(to: .init(x: 55, y: 28))
        p.addLine(to: .init(x: 55, y: 22))
        p.move(to: .init(x: 38, y: 19))
        p.addLine(to: .init(x: 50, y: 2))
        p.addLine(to: .init(x: 62, y: 19))
        p.move(to: .init(x: 59, y: 100))
        p.addLine(to: .init(x: 59, y: 82))
        p.addLine(to: .init(x: 72, y: 82))
        p.addLine(to: .init(x: 72, y: 76))
        p.addLine(to: .init(x: 76, y: 72))
        p.addLine(to: .init(x: 80, y: 76))
        p.addLine(to: .init(x: 80, y: 82))
        p.addLine(to: .init(x: 96, y: 82))
        p.addLine(to: .init(x: 96, y: 100))
        p.move(to: .init(x: 64, y: 82))
        p.addLine(to: .init(x: 64, y: 78))
        p.move(to: .init(x: 88, y: 82))
        p.addLine(to: .init(x: 88, y: 78))
        p.move(to: .init(x: 66, y: 100))
        p.addLine(to: .init(x: 66, y: 90))
        p.move(to: .init(x: 74, y: 100))
        p.addLine(to: .init(x: 74, y: 90))
        p.move(to: .init(x: 82, y: 100))
        p.addLine(to: .init(x: 82, y: 90))
        p.move(to: .init(x: 90, y: 100))
        p.addLine(to: .init(x: 90, y: 90))
    }

    /// 纽约 帝国大厦：层层收进和尖顶。
    static func empireState(_ p: inout Path) {
        p.move(to: .init(x: 24, y: 100))
        p.addLine(to: .init(x: 24, y: 84))
        p.addLine(to: .init(x: 34, y: 84))
        p.addLine(to: .init(x: 34, y: 62))
        p.addLine(to: .init(x: 40, y: 62))
        p.addLine(to: .init(x: 40, y: 40))
        p.addLine(to: .init(x: 44, y: 40))
        p.addLine(to: .init(x: 44, y: 30))
        p.addLine(to: .init(x: 47, y: 30))
        p.addLine(to: .init(x: 47, y: 20))
        p.addLine(to: .init(x: 53, y: 20))
        p.addLine(to: .init(x: 53, y: 30))
        p.addLine(to: .init(x: 56, y: 30))
        p.addLine(to: .init(x: 56, y: 40))
        p.addLine(to: .init(x: 60, y: 40))
        p.addLine(to: .init(x: 60, y: 62))
        p.addLine(to: .init(x: 66, y: 62))
        p.addLine(to: .init(x: 66, y: 84))
        p.addLine(to: .init(x: 76, y: 84))
        p.addLine(to: .init(x: 76, y: 100))
        p.move(to: .init(x: 50, y: 20))
        p.addLine(to: .init(x: 50, y: 2))
        p.move(to: .init(x: 48, y: 13))
        p.addLine(to: .init(x: 52, y: 13))
        p.move(to: .init(x: 45, y: 100))
        p.addLine(to: .init(x: 45, y: 44))
        p.move(to: .init(x: 50, y: 100))
        p.addLine(to: .init(x: 50, y: 32))
        p.move(to: .init(x: 55, y: 100))
        p.addLine(to: .init(x: 55, y: 44))
        p.move(to: .init(x: 24, y: 92))
        p.addLine(to: .init(x: 76, y: 92))
        p.move(to: .init(x: 34, y: 72))
        p.addLine(to: .init(x: 66, y: 72))
    }

    /// 东京塔：弧形塔腿、两层展望台、天线。
    static func tokyoTower(_ p: inout Path) {
        p.move(to: .init(x: 18, y: 100))
        p.addQuadCurve(to: .init(x: 45, y: 48), control: .init(x: 36, y: 82))
        p.move(to: .init(x: 82, y: 100))
        p.addQuadCurve(to: .init(x: 55, y: 48), control: .init(x: 64, y: 82))
        p.move(to: .init(x: 32, y: 100))
        p.addQuadCurve(to: .init(x: 68, y: 100), control: .init(x: 50, y: 80))
        p.move(to: .init(x: 39, y: 52))
        p.addLine(to: .init(x: 61, y: 52))
        p.addLine(to: .init(x: 61, y: 46))
        p.addLine(to: .init(x: 39, y: 46))
        p.closeSubpath()
        p.move(to: .init(x: 45, y: 46))
        p.addLine(to: .init(x: 48, y: 24))
        p.move(to: .init(x: 55, y: 46))
        p.addLine(to: .init(x: 52, y: 24))
        p.move(to: .init(x: 46, y: 24))
        p.addLine(to: .init(x: 54, y: 24))
        p.addLine(to: .init(x: 54, y: 20))
        p.addLine(to: .init(x: 46, y: 20))
        p.closeSubpath()
        p.move(to: .init(x: 50, y: 20))
        p.addLine(to: .init(x: 50, y: 2))
        p.move(to: .init(x: 28, y: 88))
        p.addLine(to: .init(x: 72, y: 88))
        p.move(to: .init(x: 35, y: 74))
        p.addLine(to: .init(x: 65, y: 74))
        p.move(to: .init(x: 41, y: 62))
        p.addLine(to: .init(x: 59, y: 62))
        p.move(to: .init(x: 29, y: 88))
        p.addLine(to: .init(x: 65, y: 74))
        p.move(to: .init(x: 71, y: 88))
        p.addLine(to: .init(x: 35, y: 74))
        p.move(to: .init(x: 36, y: 74))
        p.addLine(to: .init(x: 59, y: 62))
        p.move(to: .init(x: 64, y: 74))
        p.addLine(to: .init(x: 41, y: 62))
        p.move(to: .init(x: 46, y: 40))
        p.addLine(to: .init(x: 54, y: 40))
        p.move(to: .init(x: 47, y: 32))
        p.addLine(to: .init(x: 53, y: 32))
    }

    /// 巴黎 埃菲尔铁塔：瘦高、两层平台、拱。
    static func eiffelTower(_ p: inout Path) {
        p.move(to: .init(x: 22, y: 100))
        p.addQuadCurve(to: .init(x: 46, y: 40), control: .init(x: 40, y: 74))
        p.addQuadCurve(to: .init(x: 49.5, y: 6), control: .init(x: 48, y: 22))
        p.move(to: .init(x: 78, y: 100))
        p.addQuadCurve(to: .init(x: 54, y: 40), control: .init(x: 60, y: 74))
        p.addQuadCurve(to: .init(x: 50.5, y: 6), control: .init(x: 52, y: 22))
        p.move(to: .init(x: 34, y: 100))
        p.addQuadCurve(to: .init(x: 66, y: 100), control: .init(x: 50, y: 82))
        p.move(to: .init(x: 31, y: 76))
        p.addLine(to: .init(x: 69, y: 76))
        p.move(to: .init(x: 29, y: 73))
        p.addLine(to: .init(x: 71, y: 73))
        p.move(to: .init(x: 42, y: 52))
        p.addLine(to: .init(x: 58, y: 52))
        p.move(to: .init(x: 41, y: 49))
        p.addLine(to: .init(x: 59, y: 49))
        p.move(to: .init(x: 50, y: 6))
        p.addLine(to: .init(x: 50, y: 1))
        p.move(to: .init(x: 36, y: 73))
        p.addLine(to: .init(x: 56, y: 52))
        p.move(to: .init(x: 64, y: 73))
        p.addLine(to: .init(x: 44, y: 52))
        p.move(to: .init(x: 45, y: 49))
        p.addLine(to: .init(x: 52, y: 26))
        p.move(to: .init(x: 55, y: 49))
        p.addLine(to: .init(x: 48, y: 26))
    }

    /// 悉尼 歌剧院：帆形壳、台基、水纹。
    static func sydneyOpera(_ p: inout Path) {
        p.move(to: .init(x: 4, y: 88))
        p.addLine(to: .init(x: 96, y: 88))
        p.move(to: .init(x: 8, y: 88))
        p.addLine(to: .init(x: 8, y: 93))
        p.addLine(to: .init(x: 92, y: 93))
        p.addLine(to: .init(x: 92, y: 88))
        p.move(to: .init(x: 14, y: 88))
        p.addQuadCurve(to: .init(x: 38, y: 52), control: .init(x: 18, y: 62))
        p.addQuadCurve(to: .init(x: 32, y: 88), control: .init(x: 30, y: 68))
        p.move(to: .init(x: 30, y: 88))
        p.addQuadCurve(to: .init(x: 60, y: 44), control: .init(x: 36, y: 54))
        p.addQuadCurve(to: .init(x: 52, y: 88), control: .init(x: 50, y: 64))
        p.move(to: .init(x: 50, y: 88))
        p.addQuadCurve(to: .init(x: 80, y: 56), control: .init(x: 58, y: 60))
        p.addQuadCurve(to: .init(x: 72, y: 88), control: .init(x: 71, y: 70))
        p.move(to: .init(x: 70, y: 88))
        p.addQuadCurve(to: .init(x: 90, y: 70), control: .init(x: 76, y: 72))
        p.addQuadCurve(to: .init(x: 86, y: 88), control: .init(x: 85, y: 78))
        p.move(to: .init(x: 6, y: 98))
        p.addQuadCurve(to: .init(x: 16, y: 98), control: .init(x: 11, y: 96))
        p.addQuadCurve(to: .init(x: 26, y: 98), control: .init(x: 21, y: 100))
        p.addQuadCurve(to: .init(x: 36, y: 98), control: .init(x: 31, y: 96))
        p.addQuadCurve(to: .init(x: 46, y: 98), control: .init(x: 41, y: 100))
        p.addQuadCurve(to: .init(x: 56, y: 98), control: .init(x: 51, y: 96))
        p.addQuadCurve(to: .init(x: 66, y: 98), control: .init(x: 61, y: 100))
        p.addQuadCurve(to: .init(x: 76, y: 98), control: .init(x: 71, y: 96))
        p.addQuadCurve(to: .init(x: 86, y: 98), control: .init(x: 81, y: 100))
        p.addQuadCurve(to: .init(x: 96, y: 98), control: .init(x: 91, y: 96))
    }

    /// 迪拜 哈利法塔：阶梯收分的尖塔。
    static func burjKhalifa(_ p: inout Path) {
        p.move(to: .init(x: 36, y: 100))
        p.addLine(to: .init(x: 36, y: 80))
        p.addLine(to: .init(x: 40, y: 80))
        p.addLine(to: .init(x: 40, y: 62))
        p.addLine(to: .init(x: 43, y: 62))
        p.addLine(to: .init(x: 43, y: 46))
        p.addLine(to: .init(x: 46, y: 46))
        p.addLine(to: .init(x: 46, y: 32))
        p.addLine(to: .init(x: 48, y: 32))
        p.addLine(to: .init(x: 48, y: 18))
        p.addLine(to: .init(x: 49.5, y: 18))
        p.addLine(to: .init(x: 50, y: 1))
        p.addLine(to: .init(x: 50.5, y: 18))
        p.addLine(to: .init(x: 52, y: 18))
        p.addLine(to: .init(x: 52, y: 32))
        p.addLine(to: .init(x: 54, y: 32))
        p.addLine(to: .init(x: 54, y: 46))
        p.addLine(to: .init(x: 57, y: 46))
        p.addLine(to: .init(x: 57, y: 62))
        p.addLine(to: .init(x: 60, y: 62))
        p.addLine(to: .init(x: 60, y: 80))
        p.addLine(to: .init(x: 64, y: 80))
        p.addLine(to: .init(x: 64, y: 100))
        p.move(to: .init(x: 50, y: 100))
        p.addLine(to: .init(x: 50, y: 24))
        p.move(to: .init(x: 28, y: 100))
        p.addLine(to: .init(x: 72, y: 100))
    }

    /// 新加坡 滨海湾金沙：三栋楼和顶上的船形空中花园。
    static func marinaBaySands(_ p: inout Path) {
        p.move(to: .init(x: 18, y: 100))
        p.addLine(to: .init(x: 20, y: 42))
        p.move(to: .init(x: 30, y: 100))
        p.addLine(to: .init(x: 29, y: 42))
        p.move(to: .init(x: 44, y: 100))
        p.addLine(to: .init(x: 45, y: 42))
        p.move(to: .init(x: 56, y: 100))
        p.addLine(to: .init(x: 55, y: 42))
        p.move(to: .init(x: 70, y: 100))
        p.addLine(to: .init(x: 71, y: 42))
        p.move(to: .init(x: 82, y: 100))
        p.addLine(to: .init(x: 80, y: 42))
        p.move(to: .init(x: 6, y: 38))
        p.addLine(to: .init(x: 94, y: 35))
        p.addQuadCurve(to: .init(x: 92, y: 41), control: .init(x: 97, y: 38))
        p.addLine(to: .init(x: 10, y: 42))
        p.addQuadCurve(to: .init(x: 6, y: 38), control: .init(x: 6, y: 41))
        p.closeSubpath()
        p.move(to: .init(x: 10, y: 100))
        p.addLine(to: .init(x: 90, y: 100))
    }

    /// 没有专属地标的城市：通用天际线。
    static func skyline(_ p: inout Path) {
        p.move(to: .init(x: 6, y: 100))
        p.addLine(to: .init(x: 6, y: 74))
        p.addLine(to: .init(x: 18, y: 74))
        p.addLine(to: .init(x: 18, y: 100))
        p.move(to: .init(x: 18, y: 100))
        p.addLine(to: .init(x: 18, y: 58))
        p.addLine(to: .init(x: 30, y: 58))
        p.addLine(to: .init(x: 30, y: 100))
        p.move(to: .init(x: 30, y: 100))
        p.addLine(to: .init(x: 30, y: 80))
        p.addLine(to: .init(x: 38, y: 80))
        p.addLine(to: .init(x: 38, y: 100))
        p.move(to: .init(x: 38, y: 100))
        p.addLine(to: .init(x: 38, y: 40))
        p.addLine(to: .init(x: 46, y: 34))
        p.addLine(to: .init(x: 54, y: 40))
        p.addLine(to: .init(x: 54, y: 100))
        p.move(to: .init(x: 46, y: 34))
        p.addLine(to: .init(x: 46, y: 26))
        p.move(to: .init(x: 54, y: 100))
        p.addLine(to: .init(x: 54, y: 64))
        p.addLine(to: .init(x: 66, y: 64))
        p.addLine(to: .init(x: 66, y: 100))
        p.move(to: .init(x: 66, y: 100))
        p.addLine(to: .init(x: 66, y: 50))
        p.addLine(to: .init(x: 78, y: 50))
        p.addLine(to: .init(x: 78, y: 100))
        p.move(to: .init(x: 78, y: 100))
        p.addLine(to: .init(x: 78, y: 78))
        p.addLine(to: .init(x: 94, y: 78))
        p.addLine(to: .init(x: 94, y: 100))
        p.move(to: .init(x: 22, y: 66))
        p.addLine(to: .init(x: 26, y: 66))
        p.move(to: .init(x: 22, y: 74))
        p.addLine(to: .init(x: 26, y: 74))
        p.move(to: .init(x: 42, y: 50))
        p.addLine(to: .init(x: 50, y: 50))
        p.move(to: .init(x: 42, y: 60))
        p.addLine(to: .init(x: 50, y: 60))
        p.move(to: .init(x: 70, y: 58))
        p.addLine(to: .init(x: 74, y: 58))
        p.move(to: .init(x: 70, y: 66))
        p.addLine(to: .init(x: 74, y: 66))
        p.move(to: .init(x: 4, y: 100))
        p.addLine(to: .init(x: 96, y: 100))
    }
}

/// 按城市的地标选对应的线稿。
struct LandmarkShape: Shape {
    var landmark: CityLandmark

    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(landmark, in: rect)
    }
}

/// 北京 天坛祈年殿：三层台基、三重檐圆攒尖、宝顶。
struct TempleOfHeavenShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.templeOfHeaven, in: rect)
    }
}

/// 上海 东方明珠：三根斜撑、两个大球、小球、天线。
struct OrientalPearlShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.orientalPearl, in: rect)
    }
}

/// 伦敦 大本钟（伊丽莎白塔）和议会大厦一段。
struct BigBenShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.bigBen, in: rect)
    }
}

/// 纽约 帝国大厦：层层收进和尖顶。
struct EmpireStateShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.empireState, in: rect)
    }
}

/// 东京塔：弧形塔腿、两层展望台、天线。
struct TokyoTowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.tokyoTower, in: rect)
    }
}

/// 巴黎 埃菲尔铁塔：瘦高、两层平台、拱。
struct EiffelTowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.eiffelTower, in: rect)
    }
}

/// 悉尼 歌剧院：帆形壳、台基、水纹。
struct SydneyOperaShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.sydneyOpera, in: rect)
    }
}

/// 迪拜 哈利法塔：阶梯收分的尖塔。
struct BurjKhalifaShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.burjKhalifa, in: rect)
    }
}

/// 新加坡 滨海湾金沙：三栋楼和顶上的船形空中花园。
struct MarinaBaySandsShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.marinaBaySands, in: rect)
    }
}

/// 没有专属地标的城市：通用天际线。
struct SkylineShape: Shape {
    func path(in rect: CGRect) -> Path {
        LandmarkPaths.path(.skyline, in: rect)
    }
}

/// 只描边的地标，线宽固定，不随大小变粗变细。
struct CityLandmarkMark: View {
    var landmark: CityLandmark
    var color: Color = .white
    var lineWidth: CGFloat = CityLandmarkMark.lineWidth

    static let lineWidth: CGFloat = 1.1

    var body: some View {
        LandmarkShape(landmark: landmark)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }
}
