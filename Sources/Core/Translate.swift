import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// 翻译：the parts of the translate widget that are plain logic.
///
/// The translating itself is Apple's on-device Translation framework, which
/// lives in the app target (see `TranslateDetail`): it needs a SwiftUI view to
/// hand out a session, and the test target compiles only this folder. What is
/// here is everything around it that can be checked without a Mac's language
/// packs: which way to translate, what the languages are called in Chinese,
/// and how the recent translations are kept in the widget's config.
///
/// Keys in the config, none of them catalog defaults (they are edited in the
/// panel, never in Settings):
/// - `source`: a language code, or `auto` (the default) to detect it.
/// - `target`: the language chosen by hand, read only with `autoDirection` off.
/// - `history`: the last translations, newest first, one string each.
public struct TranslateLanguage: Equatable, Hashable, Sendable, Identifiable {
    /// BCP 47, as `Locale.Language(identifier:)` takes it: `en`, `zh-Hans`.
    public var code: String
    /// What it is called in Chinese: 英语, 简体中文.
    public var name: String
    /// One or two characters for the tile's pair: 英, 中.
    public var short: String

    public var id: String { code }

    public init(code: String, name: String, short: String) {
        self.code = code
        self.name = name
        self.short = short
    }
}

/// One finished translation.
public struct TranslateRecord: Equatable, Hashable, Sendable {
    public var source: String
    public var target: String
    public var sourceText: String
    public var resultText: String

    public init(source: String, target: String, sourceText: String, resultText: String) {
        self.source = source
        self.target = target
        self.sourceText = sourceText
        self.resultText = resultText
    }
}

public enum Translate {
    public static let sourceKey = "source"
    public static let targetKey = "target"
    public static let historyKey = "history"
    /// `source` when the language is detected rather than chosen.
    public static let auto = "auto"

    /// More than a page of text is a document, and the panel is not a
    /// document translator; the editor stops taking characters here.
    public static let maxCharacters = 5000
    public static let maxHistory = 20
    /// Each side of a history entry is cut to this, so twenty long pastes do
    /// not turn every profile write into a quarter of a megabyte.
    public static let maxHistoryText = 1000

    // MARK: Languages

    /// The languages offered first, in the order a Chinese speaker reaches
    /// for them. The panel shows the ones the Mac's Translation actually
    /// supports, and any further ones it supports after these.
    public static let common: [TranslateLanguage] = [
        TranslateLanguage(code: "zh-Hans", name: tr("简体中文"), short: "中"),
        TranslateLanguage(code: "zh-Hant", name: tr("繁体中文"), short: "繁"),
        TranslateLanguage(code: "en", name: tr("英语"), short: "英"),
        TranslateLanguage(code: "ja", name: tr("日语"), short: "日"),
        TranslateLanguage(code: "ko", name: tr("韩语"), short: "韩"),
        TranslateLanguage(code: "fr", name: tr("法语"), short: "法"),
        TranslateLanguage(code: "de", name: tr("德语"), short: "德"),
        TranslateLanguage(code: "es", name: tr("西班牙语"), short: "西"),
        TranslateLanguage(code: "it", name: tr("意大利语"), short: "意"),
        TranslateLanguage(code: "pt", name: tr("葡萄牙语"), short: "葡"),
        TranslateLanguage(code: "ru", name: tr("俄语"), short: "俄"),
        TranslateLanguage(code: "ar", name: tr("阿拉伯语"), short: "阿"),
        TranslateLanguage(code: "th", name: tr("泰语"), short: "泰"),
        TranslateLanguage(code: "vi", name: tr("越南语"), short: "越"),
        TranslateLanguage(code: "id", name: tr("印度尼西亚语"), short: "印尼"),
        TranslateLanguage(code: "tr", name: tr("土耳其语"), short: "土"),
        TranslateLanguage(code: "nl", name: tr("荷兰语"), short: "荷"),
        TranslateLanguage(code: "pl", name: tr("波兰语"), short: "波"),
        TranslateLanguage(code: "uk", name: tr("乌克兰语"), short: "乌"),
        TranslateLanguage(code: "hi", name: tr("印地语"), short: "印地"),
    ]

    public static let chinese = "zh-Hans"
    public static let english = "en"

    /// Our code for a language the system names by its full identifier.
    ///
    /// `Locale.Language` reports `zh-Hans-CN`, `zh-CN`, `en-US`, `pt-BR` or
    /// `en-Latn-US` depending on where it came from; the list above keys on
    /// the language alone, plus the script for Chinese, where it is the whole
    /// difference between the two entries.
    public static func code(for identifier: String) -> String {
        let parts = identifier.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").map(String.init)
        guard let language = parts.first?.lowercased(), !language.isEmpty else { return identifier }
        guard language == "zh" else { return language }
        let rest = parts.dropFirst().map { $0.lowercased() }
        if rest.contains("hant") || rest.contains("tw") || rest.contains("hk") || rest.contains("mo") {
            return "zh-Hant"
        }
        return chinese
    }

    public static func language(_ code: String) -> TranslateLanguage? {
        let key = Self.code(for: code)
        return common.first { $0.code == key }
    }

    /// 英语 for `en`, and the code itself for a language we have no name for
    /// (the panel asks the system's locale for those instead).
    public static func name(_ code: String) -> String {
        if code == auto { return tr("自动检测") }
        return language(code)?.name ?? code
    }

    public static func short(_ code: String) -> String {
        if code == auto { return tr("自动") }
        // 英文界面用语言代码的前两个字母（ZH、JA、EN），中文界面用一个字（中、日、英）。
        if L10n.isEnglish {
            let base = code.split(separator: "-").first.map(String.init) ?? code
            return code == "zh-Hant" ? "TC" : base.prefix(2).uppercased()
        }
        return language(code)?.short ?? code
    }

    /// "中 ⇄ 英": what the tile says it translates between.
    public static func pairText(source: String, target: String) -> String {
        "\(short(source)) ⇄ \(short(target))"
    }

    public static func isChinese(_ code: String) -> Bool {
        Self.code(for: code).hasPrefix("zh")
    }

    /// Whether two codes are the same language, so translating between
    /// them would hand the text straight back.
    public static func same(_ a: String, _ b: String) -> Bool {
        code(for: a) == code(for: b)
    }

    /// The voice to read a language in. Chinese needs its region, or the
    /// system picks whichever Chinese voice it likes.
    public static func speechCode(_ code: String) -> String {
        switch Self.code(for: code) {
        case "zh-Hans": "zh-CN"
        case "zh-Hant": "zh-TW"
        case "en": "en-US"
        case "pt": "pt-BR"
        case let other: other
        }
    }

    // MARK: Detecting

    /// Counts of the scripts in a text, ignoring spaces, digits and
    /// punctuation, which every language shares.
    public struct ScriptCounts: Equatable, Sendable {
        public var han = 0
        public var kana = 0
        public var hangul = 0
        public var other = 0

        public var letters: Int { han + kana + hangul + other }
    }

    public static func scripts(_ text: String) -> ScriptCounts {
        var counts = ScriptCounts()
        for scalar in text.unicodeScalars {
            let v = scalar.value
            switch v {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0xF900...0xFAFF:
                counts.han += 1
            case 0x3040...0x30FF, 0x31F0...0x31FF:
                counts.kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
                counts.hangul += 1
            default:
                if scalar.properties.isAlphabetic { counts.other += 1 }
            }
        }
        return counts
    }

    /// Share of a text's letters that are Chinese characters, 0 to 1.
    public static func hanRatio(_ text: String) -> Double {
        let counts = scripts(text)
        guard counts.letters > 0 else { return 0 }
        return Double(counts.han) / Double(counts.letters)
    }

    /// Whether a text reads as Chinese.
    ///
    /// By characters, not words: "Hello 世界" is seven letters of which two
    /// are Chinese, and a Chinese character carries about as much as an
    /// English word, so a quarter is the line rather than a half. Any kana
    /// makes it Japanese, whatever its kanji, and any hangul makes it Korean.
    public static func looksChinese(_ text: String) -> Bool {
        let counts = scripts(text)
        guard counts.han > 0, counts.kana == 0, counts.hangul == 0 else { return false }
        return Double(counts.han) / Double(counts.letters) >= 0.25
    }

    /// The text's language by its script alone, for the three that can be
    /// told that way. Nil for anything written in letters.
    public static func scriptLanguage(_ text: String) -> String? {
        let counts = scripts(text)
        guard counts.letters > 0 else { return nil }
        if counts.kana > 0, counts.kana + counts.han >= counts.other { return "ja" }
        if counts.hangul > 0, counts.hangul >= counts.other { return "ko" }
        if looksChinese(text) { return chinese }
        return nil
    }

    /// The text's language: by script where that settles it, then by the
    /// system's language recogniser where there is one. Nil when neither
    /// knows, and the Translation framework is left to work it out.
    public static func detect(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let byScript = scriptLanguage(trimmed) { return byScript }
        #if canImport(NaturalLanguage)
        if let language = NLLanguageRecognizer.dominantLanguage(for: trimmed),
           language != .undetermined {
            return code(for: language.rawValue)
        }
        #endif
        return nil
    }

    /// Where a text goes.
    ///
    /// With the smart direction on (the default), Chinese goes to English and
    /// everything else to Simplified Chinese, so the same panel reads an
    /// English page and writes an English reply. Off, the chosen target
    /// stands, whatever the text.
    ///
    /// `source` is the detected or chosen language, nil when unknown; the
    /// text's own script is the fallback for that.
    public static func target(source: String?, text: String, chosen: String, smart: Bool) -> String {
        guard smart else { return chosen.isEmpty ? chinese : chosen }
        if let source { return isChinese(source) ? english : chinese }
        return looksChinese(text) ? english : chinese
    }

    /// The text as the editor keeps it: no more than the limit.
    public static func clamped(_ text: String) -> String {
        text.count > maxCharacters ? String(text.prefix(maxCharacters)) : text
    }

    /// The first line of a text, for a one-line glance.
    public static func snippet(_ text: String, limit: Int = 60) -> String {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = line.trimmingCharacters(in: .whitespaces)
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    // MARK: History

    /// `source \t target \t text \t result`, with backslashes, tabs and line
    /// breaks escaped so a pasted paragraph stays one entry.
    public static func encode(_ record: TranslateRecord) -> String {
        [record.source, record.target, record.sourceText, record.resultText]
            .map(escape).joined(separator: "\t")
    }

    public static func decode(_ line: String) -> TranslateRecord? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map { unescape(String($0)) }
        guard fields.count == 4, !fields[0].isEmpty, !fields[1].isEmpty,
              !fields[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return TranslateRecord(source: fields[0], target: fields[1],
                               sourceText: fields[2], resultText: fields[3])
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\\": out += "\\\\"
            case "\t": out += "\\t"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\r\n": out += "\\n"
            default: out.append(character)
            }
        }
        return out
    }

    private static func unescape(_ text: String) -> String {
        var out = ""
        var escaping = false
        for character in text {
            if escaping {
                switch character {
                case "t": out += "\t"
                case "n": out += "\n"
                case "r": out += "\r"
                default: out.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                out.append(character)
            }
        }
        if escaping { out += "\\" }
        return out
    }

    public static func history(_ config: WidgetConfig) -> [TranslateRecord] {
        Array(config.strings(historyKey).compactMap(decode).prefix(maxHistory))
    }

    public static func store(_ history: [TranslateRecord], in config: inout WidgetConfig) {
        config.set(historyKey, .list(history.prefix(maxHistory).map { .string(encode($0)) }))
    }

    /// The history with a new translation at the top.
    ///
    /// Translating as you type finishes a translation at every pause, so
    /// "hel", "hello" and "hello wor" would each become an entry. A new one
    /// that extends or trims the newest, in the same direction, replaces it
    /// instead; the same text again moves to the top rather than repeating.
    /// Each side is cut to `maxHistoryText`, and the list to `maxHistory`.
    public static func recording(_ record: TranslateRecord, in history: [TranslateRecord]) -> [TranslateRecord] {
        let text = record.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return history }
        var entry = record
        entry.sourceText = String(text.prefix(maxHistoryText))
        entry.resultText = String(record.resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxHistoryText))

        var rest = history.filter {
            !($0.sourceText == entry.sourceText && same($0.source, entry.source) && same($0.target, entry.target))
        }
        if let newest = rest.first, same(newest.target, entry.target),
           newest.sourceText.hasPrefix(entry.sourceText) || entry.sourceText.hasPrefix(newest.sourceText) {
            rest.removeFirst()
        }
        return Array(([entry] + rest).prefix(maxHistory))
    }

    public static func removing(at index: Int, from history: [TranslateRecord]) -> [TranslateRecord] {
        guard history.indices.contains(index) else { return history }
        var copy = history
        copy.remove(at: index)
        return copy
    }

    // MARK: Settings

    /// 点按卡片时: open the panel, or open it on whatever is on the clipboard.
    public enum ClickAction: String, CaseIterable, Sendable {
        case panel
        case clipboard

        public var title: String {
            switch self {
            case .panel: tr("打开面板")
            case .clipboard: tr("翻译剪贴板")
            }
        }
    }

    public static func clickAction(_ config: WidgetConfig) -> ClickAction {
        ClickAction(rawValue: config.string("clickAction", default: "panel")) ?? .panel
    }

    public static func smartDirection(_ config: WidgetConfig) -> Bool {
        config.bool("autoDirection", default: true)
    }

    public static func source(_ config: WidgetConfig) -> String {
        let raw = config.string(sourceKey, default: auto)
        return raw.isEmpty ? auto : raw
    }

    public static func chosenTarget(_ config: WidgetConfig) -> String {
        let raw = config.string(targetKey, default: english)
        return raw.isEmpty ? english : raw
    }

    /// The pair the tile shows: the last translation's, or the direction a
    /// Chinese text would go before there is one.
    public static func tilePair(_ config: WidgetConfig) -> String {
        if let last = history(config).first { return pairText(source: last.source, target: last.target) }
        let source = Self.source(config)
        if smartDirection(config) {
            if source == auto || isChinese(source) { return pairText(source: chinese, target: english) }
            return pairText(source: source, target: chinese)
        }
        return pairText(source: source == auto ? chinese : source, target: chosenTarget(config))
    }
}
