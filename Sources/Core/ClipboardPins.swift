import Foundation

/// 剪贴板收藏：加了星标的文本，存在小组件自己的设置里，退出后也还在。
///
/// The history itself stays in memory only (see `ClipboardHistory`); a pin
/// is something you chose to keep, so it is written down, under `pins`,
/// which like the todo list's `items` is contents rather than a setting.
public enum ClipboardPins {
    public static let key = "pins"
    public static let maxPins = 50
    /// A snippet, a template, an address: not a whole document.
    public static let maxLength = 5_000

    public static func pins(_ config: WidgetConfig) -> [String] {
        var seen = Set<String>()
        return config.strings(key).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func store(_ pins: [String], in config: inout WidgetConfig) {
        config.set(key, .list(pins.prefix(maxPins).map { .string($0) }))
    }

    public static func isPinned(_ text: String, in pins: [String]) -> Bool {
        pins.contains(clip(text))
    }

    static func clip(_ text: String) -> String { String(text.prefix(maxLength)) }

    /// Pins a text at the top, or unpins it if it is already there.
    public static func toggling(_ text: String, in pins: [String]) -> [String] {
        let value = clip(text)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return pins }
        if pins.contains(value) { return pins.filter { $0 != value } }
        return Array(([value] + pins).prefix(maxPins))
    }

    /// Swaps a pin for its edited text in the same place. An empty edit
    /// changes nothing; an edit that matches another pin keeps just one.
    public static func replacing(_ old: String, with new: String, in pins: [String]) -> [String] {
        let value = clip(new)
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = pins.firstIndex(of: old) else { return pins }
        var result = pins
        result[index] = value
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    public static func moving(_ text: String, by offset: Int, in pins: [String]) -> [String] {
        guard let index = pins.firstIndex(of: text) else { return pins }
        let target = min(max(index + offset, 0), pins.count - 1)
        var result = pins
        result.remove(at: index)
        result.insert(text, at: target)
        return result
    }

    /// Every word of the query appears in the text, ignoring case, width and
    /// accents, so "wifi 密码" finds "家里 WiFi 的密码是…".
    public static func matches(_ text: String, query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return words.allSatisfy { text.range(of: String($0), options: options) != nil }
    }
}
