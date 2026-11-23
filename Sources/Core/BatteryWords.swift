import Foundation

/// 电池卡片和面板上的几句话，迷你卡片、多设备圆环悬停和详情面板头部都从这里取，
/// 三处说法一致，数字也用同一种取整（`BatteryColorMap.percent`）。
public enum BatteryWords {
    /// 有内置电池的 Mac 都是笔记本，迷你卡片和面板头部写 MacBook。
    public static let macName = "MacBook"

    /// 迷你卡片第一行：「MacBook · 80%」，读不到电量时「MacBook · -」。
    public static func title(name: String, level: Double, present: Bool) -> String {
        "\(name) · \(percentText(level: level, present: present))"
    }

    /// 「80%」，读不到电量是「-」，绝不编一个出来。
    public static func percentText(level: Double, present: Bool) -> String {
        guard present, level.isFinite else { return "-" }
        return "\(BatteryColorMap.percent(level))%"
    }

    /// 读不到电量时那一格写什么：连着写「电量不可获取」，不在写「未连接」。
    public static func absentWord(unreadable: Bool) -> String {
        unreadable ? tr("电量不可获取") : tr("未连接")
    }

    /// 配件读数超过 `BluetoothBatteries.staleAfter` 没更新时的提示。
    public static var staleWord: String { tr("数据已过期") }

    /// 详情面板配件行（和 Mac 以外的固定格）的小字：
    /// 读不到时「电量不可获取」「未连接」（有充电盒读数时后面接「盒 45%」）；
    /// 读得到时「正在充电」「使用电池」或「左 80% · 右 78% · 盒 45%」，过期时前面加「数据已过期 · 」。
    public static func accessoryCaption(present: Bool, unreadable: Bool = false, stale: Bool = false,
                                        charging: Bool, parts: String?) -> String {
        guard present else {
            let word = absentWord(unreadable: unreadable)
            if unreadable, let parts { return "\(word) · \(parts)" }
            return word
        }
        let base: String
        if let parts {
            base = charging ? tr("正在充电 · \(parts)") : parts
        } else {
            base = charging ? tr("正在充电") : tr("使用电池")
        }
        return stale ? "\(staleWord) · \(base)" : base
    }

    /// 充电这件事本身：「正在充电」「已充满」「未充电」；用电池时 nil（没有接电源就谈不上充没充）。
    public static func chargeWord(level: Double, charging: Bool, onPower: Bool, charged: Bool = false) -> String? {
        if charging { return tr("正在充电") }
        guard onPower else { return nil }
        return charged || BatteryColorMap.percent(level) >= 100 ? tr("已充满") : tr("未充电")
    }

    /// 电源这件事：「已接电源」「使用电池」。
    public static func source(onPower: Bool, charging: Bool) -> String {
        onPower || charging ? tr("已接电源") : tr("使用电池")
    }

    /// 迷你卡片第二行：「接通电源 · 未充电」「接通电源 · 正在充电」「接通电源 · 已充满」
    /// 「使用电池」「未连接」。配件不知道接没接电源，充电时写「正在充电」。
    public static func powerLine(level: Double, charging: Bool, onPower: Bool, present: Bool,
                                 charged: Bool = false, unreadable: Bool = false, stale: Bool = false) -> String {
        guard present else { return absentWord(unreadable: unreadable) }
        if stale { return staleWord }
        if onPower {
            let word = chargeWord(level: level, charging: charging, onPower: true, charged: charged) ?? tr("未充电")
            return tr("接通电源 · \(word)")
        }
        return charging ? tr("正在充电") : tr("使用电池")
    }

    /// 多设备圆环悬停的说明，三行：设备名；连接状态（和电量、电源）；更新时间。
    /// `charged` 和迷你卡片同一个来源（macOS 认为已充满），两处写法一致。
    /// 连着但读不到电量时第二行是「已连接 · 电量不可获取」；读数过期时多一行「数据已过期」，
    /// `updated` 也应当传那份读数真正读到的时刻。
    public static func hover(name: String, level: Double, charging: Bool, onPower: Bool, present: Bool,
                             charged: Bool = false, unreadable: Bool = false, stale: Bool = false,
                             updated: Date?, now: Date) -> String {
        var lines = [name]
        if present {
            lines.append(tr("已连接 · \(percentText(level: level, present: true)) · \(powerLine(level: level, charging: charging, onPower: onPower, present: true, charged: charged))"))
            if stale { lines.append(staleWord) }
        } else if unreadable {
            lines.append(tr("已连接 · \(absentWord(unreadable: true))"))
        } else {
            lines.append(tr("未连接"))
        }
        if let updated { lines.append(tr("更新于 \(updatedText(updated, now: now))")) }
        return lines.joined(separator: "\n")
    }

    /// 时刻「15:32」，详情面板底部「更新于 15:32」用。
    public static func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 详情面板底部那一行：「更新于 15:32」；没有采样时 nil，不显示。
    public static func panelUpdated(_ sampledAt: Date?) -> String? {
        sampledAt.map { tr("更新于 \(clock($0))") }
    }

    /// 「刚刚」（10 秒内）、「12 秒前」（1 分钟内），再往前写时刻「15:32」。
    public static func updatedText(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 10 { return tr("刚刚") }
        if seconds < 60 { return tr("\(seconds) 秒前") }
        return clock(date)
    }
}
