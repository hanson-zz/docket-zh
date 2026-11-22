import Foundation

/// 刘海小岛电台卡片上要显示的东西：左边插画用哪套外观、右边「CH 03 / 06」。
///
/// 外观和台号都从开始播放的那个收音机小组件读（和电台面板同一份配置），
/// 读不到（没有小组件、播放列表来自别处）时外观用经典、台号按播放列表算。
public enum NotchIslandRadio {
    /// 插画缺图时退回的那张（原来卡片上固定用的小猫收音机）。
    public static let fallbackArtName = "RadioMeow"

    /// 所选外观：有电台小组件配置就读它（`RadioSkin.stored`），没有就是经典。
    public static func skin(_ config: WidgetConfig?) -> RadioSkin {
        guard let config else { return .fallback }
        return RadioSkin.stored(config)
    }

    /// 依次试的插画资源名：先当前外观的 `radio-art-<rawValue>`，缺图再退回 `RadioMeow`。
    public static func artNames(_ skin: RadioSkin) -> [String] {
        [RadioPanelReadout.artName(skin), fallbackArtName]
    }

    /// 掌机像素那套是像素画，放大缩小要最近邻，不然糊边。
    public static func pixelated(_ skin: RadioSkin) -> Bool {
        skin == .pixel
    }

    /// 当前台在收藏里排第几：先按正在放的那一台找（备用地址相同也算），
    /// 找不到用存着的序号，没有收藏时 0。
    public static func index(of current: RadioStation?, in stations: [RadioStation], stored: Int) -> Int {
        guard !stations.isEmpty else { return 0 }
        if let current, let hit = stations.firstIndex(where: { $0.matches(current) }) { return hit }
        return RadioDial.clamp(stored, count: stations.count)
    }

    /// 「CH 03 / 06」的两段，和电台面板头部同一套（`RadioPanelReadout.channel`）。
    public static func channel(of current: RadioStation?, in stations: [RadioStation],
                               stored: Int) -> (current: String, total: String) {
        RadioPanelReadout.channel(index: index(of: current, in: stations, stored: stored), count: stations.count)
    }

    /// 读屏念的台号（「频道 03 / 06」），和电台面板、桌面卡片同一句 `RadioDial.channelOfTotal`。
    /// 没有收藏时空字符串。
    public static func spokenChannel(of current: RadioStation?, in stations: [RadioStation], stored: Int) -> String {
        guard !stations.isEmpty else { return "" }
        return RadioDial.channelOfTotal(index(of: current, in: stations, stored: stored), count: stations.count)
    }
}
