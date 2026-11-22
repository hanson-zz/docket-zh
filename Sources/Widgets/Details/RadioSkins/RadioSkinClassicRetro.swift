import SwiftUI

// 收音机外观：经典调谐（免费）和三款复古机身（木壳电子管、复古便携、数码卡座，Pro）的
// 面板主视觉、走带键、音量。头部统一在 RadioPanelChrome.swift。
//
// 经典调谐：半圆刻度表盘加红指针，拖动或点刻度换台，放在一块浅浅的托盘里。
// 复古机身：Kinds/RadioSkins.swift 里画好的机身，整体缩到 `RadioRetroDraw.faceScale`
// （约小两成，标签字号先放大回去，缩完仍是 13pt）。浅色版复古便携是奶油色皮革、
// 数码卡座是浅色拉丝机身，深色版是深色皮革、石墨机身；木壳两版一样。
// 走带键和音量用调色板（`RadioSkinPalette.look`），浅色、深色都看得清。

/// 经典调谐：表盘托盘。
struct RadioSkinClassicFace: View {
    var model: RadioSkinModel

    var body: some View {
        let colors = model.colors
        RadioArcDial(count: model.count, index: model.index, accent: colors.accentText, needle: Color(hex: "#FF453A"),
                     ink: colors.text) { target in
            guard !model.isPreview else { return }
            model.onTune(target)
        }
        .frame(height: 74)
        .padding(.horizontal, 30)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.text.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(colors.text.opacity(0.08), lineWidth: 0.6))
    }
}

/// 经典调谐：表盘、走带键、音量。
struct RadioSkinClassicPanel: View {
    var model: RadioSkinModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RadioSkinClassicFace(model: model)
            RadioSkinTransport(model: model)
            RadioSkinVolume(model: model)
        }
    }
}

/// 复古机身缩小后的样子。复古便携的天线伸出机身顶上，这里给它让出位置。
struct RadioSkinRetroFace: View {
    var model: RadioSkinModel

    private var size: CGSize {
        switch model.skin {
        case .wood: RadioWoodFace.size
        case .transistor: RadioTransistorFace.bodySize
        default: RadioDeckFace.size
        }
    }

    /// 机身顶上多出来的一截（天线、拨轮）。
    private var overhang: CGFloat { model.skin == .transistor ? RadioTransistorFace.top : 0 }

    var body: some View {
        let k = RadioRetroDraw.faceScale
        RadioRetroFace(skin: model.skin, light: model.tone == .light, count: model.count, index: model.index,
                       playing: model.playing, volume: model.volume, stationName: model.stationName,
                       animated: !model.isPreview,
                       onTune: { target in
                           guard !model.isPreview else { return }
                           model.onTune(target)
                       },
                       onNext: {
                           guard !model.isPreview else { return }
                           model.onNext()
                       })
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .scaleEffect(k, anchor: .topLeading)
        .frame(width: size.width * k, height: size.height * k, alignment: .topLeading)
        .padding(.top, overhang * k)
        .frame(maxWidth: .infinity)
    }
}

/// 复古机身、走带键、音量。
struct RadioSkinRetroPanel: View {
    var model: RadioSkinModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RadioSkinRetroFace(model: model)
            RadioSkinTransport(model: model)
            RadioSkinVolume(model: model)
        }
    }
}
