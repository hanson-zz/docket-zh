import Foundation

/// 收音机面板紧凑头部和收藏列表里的字，全部按当前收藏和当前台实时算，不写死。
///
/// 头部从上到下：外观名小胶囊、“CH 03 / 06”、台名大字、“HLS · 网络直播”；
/// 收藏列表上面一行“我的收藏 · 6 个电台”。右上角的收音机插画是可选的图
/// `radio-art-<rawValue>.png`（放在 Resources/RadioArt），缺图就不画。
public enum RadioPanelReadout {
    /// “CH 03 / 06”里的两段：当前台的编号和收藏总数，都是两位。没有收藏时是 “--” 和 “00”。
    public static func channel(index: Int, count: Int) -> (current: String, total: String) {
        guard count > 0 else { return ("--", "00") }
        let current = RadioDial.clamp(index, count: count)
        return (RadioDial.channelText(current), RadioDial.channelText(count - 1))
    }

    /// 流格式那一段：“HLS”“MP3”“AAC”，认不出时 nil。和 `RadioStation.detail` 同一套判断，
    /// 只取格式，不带码率。
    public static func format(_ station: RadioStation) -> String? {
        let codec = station.codec.trimmingCharacters(in: .whitespaces).uppercased()
        if !codec.isEmpty, codec != "UNKNOWN" { return String(codec.prefix(5)) }
        let url = station.url.lowercased()
        if url.contains(".m3u8") { return "HLS" }
        if url.hasSuffix(".mp3") || url.contains(".mp3?") { return "MP3" }
        if url.hasSuffix(".aac") || url.contains(".aac?") { return "AAC" }
        return nil
    }

    /// 台名下面那一行：“HLS · 网络直播”，知道码率时“MP3 · 64 kbps · 网络直播”，
    /// 什么都不知道时只写“网络直播”。没有台时是 nil（头部改写提示语）。
    public static func streamLine(_ station: RadioStation?) -> String? {
        guard let station else { return nil }
        var parts: [String] = []
        if let format = format(station) { parts.append(format) }
        if station.bitrate > 0 { parts.append("\(station.bitrate) kbps") }
        parts.append(tr("网络直播"))
        return parts.joined(separator: " · ")
    }

    /// “6 个电台”。
    public static func stationCount(_ count: Int) -> String {
        tr("\(max(0, count)) 个电台")
    }

    /// 右上角收音机插画的资源名（不带扩展名）。
    public static func artName(_ skin: RadioSkin) -> String {
        "radio-art-\(skin.rawValue)"
    }

    /// 画廊一排放几格：每格至少 `minimum` 宽，最少 2 格、最多 4 格。
    public static func galleryColumns(width: Double, minimum: Double = 84, spacing: Double = 8) -> Int {
        guard width > 0, minimum > 0 else { return 2 }
        let fit = Int(((width + spacing) / (minimum + spacing)).rounded(.down))
        return min(4, max(2, fit))
    }
}
