import Foundation

/// How the widget library matches what someone types.
///
/// A name typed the way people actually type it: the Chinese name, its
/// pinyin ("tianqi"), its initials ("tq"), the English name ("weather") or a
/// common synonym ("番茄钟" for 专注计时). Matching is case and space blind.
public enum WidgetSearch {
    /// English names and synonyms by `WidgetKind.rawValue`.
    public static let keywords: [String: [String]] = [
        "clock": ["clock", "time", "表盘", "时间"],
        "world": ["world clock", "timezone", "时区"],
        "stopwatch": ["stopwatch", "计时器"],
        "timer": ["timer", "focus", "pomodoro", "番茄钟", "专注", "倒计时"],
        "progress": ["progress", "进度", "今年", "本月"],
        "countdown": ["countdown", "倒数"],
        "alarm": ["alarm", "闹铃", "起床"],
        "calendar": ["calendar", "event", "日程", "会议"],
        "reminders": ["reminders", "todo", "待办"],
        "notes": ["notes", "sticky", "备忘", "笔记"],
        "music": ["music", "now playing", "spotify", "音乐", "歌曲", "播放", "网易云", "netease", "cloudmusic", "小宇宙", "播客", "podcast", "xiaoyuzhou"],
        "battery": ["battery", "电量", "充电"],
        "system": ["system", "cpu", "memory", "内存", "处理器"],
        "network": ["network", "speed", "网速", "流量", "wifi", "wi-fi", "信号", "无线"],
        "ai-usage": ["codex", "ai", "chatgpt", "openai", "用量", "额度"],
        "shortcut": ["shortcuts", "自动化"],
        "airdrop": ["airdrop", "传文件"],
        "weather": ["weather", "forecast", "温度", "下雨", "预报"],
        "stock": ["stock", "股市", "行情"],
        "watchlist": ["watchlist", "stocks", "股票"],
        "crypto": ["crypto", "bitcoin", "btc", "比特币", "币"],
        "photos": ["photos", "照片", "图片"],
        "screenshots": ["screenshots", "截屏"],
        "downloads": ["downloads", "下载文件夹"],
        "file-shelf": ["file shelf", "drop", "暂存", "拖放"],
        "clipboard": ["clipboard", "paste", "粘贴板", "复制", "拷贝"],
        "color-picker": ["color picker", "colour", "颜色", "吸管"],
        "converter": ["converter", "unit", "换算", "单位"],
        "capture": ["capture", "screenshot", "截屏", "录屏"],
        "emoji": ["emoji", "表情"],
        "search": ["search", "搜索", "查找"],
        "volume": ["volume", "sound", "声音"],
        "toggles": ["toggles", "quick", "开关", "深色模式"],
        "github": ["github", "git", "仓库"],
        "currency": ["currency", "exchange", "汇率", "美元", "人民币"],
        "calculator": ["calculator", "计算"],
        "mail": ["mail", "email", "邮箱", "未读"],
        "recorder": ["recorder", "voice memo", "录音机"],
        "bookmarks": ["bookmarks", "links", "网址", "链接"],
        "app-switcher": ["app switcher", "running apps", "切换应用", "运行中"],
        "wallpaper": ["wallpaper", "背景", "桌面"],
        "microphone": ["microphone", "mic", "mute", "静音"],
        "gauges": ["gauges", "disk", "storage", "磁盘", "存储", "仪表"],
        "posture": ["posture", "stand up", "break", "站起来", "休息"],
        "todo": ["todo", "tasks", "待办", "清单"],
        "ambient": ["ambient", "white noise", "rain", "白噪音", "雨声"],
        "lunar": ["lunar", "holiday", "农历", "节假日", "调休"],
        "trash": ["trash", "bin", "垃圾桶", "回收站"],
        "habit": ["habit", "streak", "打卡", "习惯"],
        "week": ["week", "agenda", "本周", "日程"],
        "app-volume": ["app volume", "mixer", "音量"],
        "radio": ["radio", "fm", "电台", "广播"],
        "anniversary": ["anniversary", "birthday", "生日", "倒数日"],
        "water": ["water", "drink", "hydration", "喝水", "饮水"],
        "translate": ["translate", "translation", "英文", "中英"],
        "pet": ["pet", "tamagotchi", "red panda", "宠物", "小熊猫", "养成"],
    ]

    /// The pinyin of `text` without tones, as one run ("tianqi") and as its
    /// initials ("tq"). Latin words pass through whole.
    public static func pinyin(_ text: String) -> (full: String, initials: String) {
        let latin = (text.applyingTransform(.toLatin, reverse: false) ?? text)
            .applyingTransform(.stripDiacritics, reverse: false) ?? text
        let words = latin.lowercased().split { !$0.isLetter && !$0.isNumber }
        return (words.joined(), String(words.compactMap(\.first)))
    }

    private static func squash(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    /// Whether `query` matches any of `names` (or the kind's keywords).
    public static func matches(_ query: String, names: [String], kind: String) -> Bool {
        let q = squash(query)
        guard !q.isEmpty else { return true }
        let texts = names + (keywords[kind] ?? [])
        for text in texts {
            if squash(text).contains(q) { return true }
            let p = pinyin(text)
            if p.full.contains(q) { return true }
            // Initials only from the start, so "q" alone does not match half the library.
            if q.count >= 2, p.initials.hasPrefix(q) { return true }
        }
        return false
    }

    /// The permission a kind cannot work without, for the library's badge.
    /// Optional ones (weather's location, clipboard's paste-on-click) are left out.
    public static let permissions: [String: String] = [
        "calendar": "日历",
        "week": "日历",
        "reminders": "提醒事项",
        "mail": "自动化（邮件）",
        "music": "自动化（音乐 App）",
        "recorder": "麦克风",
        "app-volume": "录制系统音频",
        "trash": "完全磁盘访问权限",
        "capture": "屏幕录制",
    ]
}
