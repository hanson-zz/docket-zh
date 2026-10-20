import SwiftUI

// 收音机外观：掌机像素（Pro）。
//
// 红色液晶屏，像素数字和像素小熊猫；底部 5 格调谐条，三角指着当前台。暗色是红字黑屏，浅色是黑字红屏，收藏当前行用像素爱心。
// 设计稿 design/radio-skins2.png 第 4 列，配色和尺寸见 design/radio-skins2.py 的 skin_pixel / tile_pixel
// （面板按 1.25 倍、卡片按 264 × 62 画，卡片落到 212 × 62 时按比例收窄）。
//
// 只改这个文件。数据和回调都在 `RadioSkinModel`（见 RadioSkinKit.swift），颜色从
// `model.colors` 取，暗色、浅色两版已按 `model.tone` 选好。第一版先用经典布局加
// 掌机像素配色，保证可选、可播放。

/// 掌机像素：面板上半部分（头一行、主视觉、台名、走带键、音量），宽 288pt。
struct RadioSkinPixelPanel: RadioSkinPanelFace {
    var model: RadioSkinModel

    /// 整张面板卡片的底。
    static func backdrop(_ model: RadioSkinModel) -> some View {
        RadioSkinBackdrop(model: model)
    }

    var body: some View {
        RadioSkinBasicPanel(model: model)
    }
}

/// 掌机像素：212 × 62 卡片的内容；`vertical` 时是侧边竖排的小卡片。
struct RadioSkinPixelCard: RadioSkinCardFace {
    var model: RadioSkinModel
    var vertical: Bool

    var body: some View {
        RadioSkinBasicCard(model: model, vertical: vertical)
    }
}
