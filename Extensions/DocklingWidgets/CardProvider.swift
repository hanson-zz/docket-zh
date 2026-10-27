import AppIntents
import SwiftUI
import WidgetKit

// 对应扩展栏某张卡片的小组件共用的时间线：读快照（叠上还没合并的点按），按「编辑小组件」
// 里选的卡片取那一张，没选就取第一张。

/// 「编辑小组件」里选卡片的那几个配置。
protocol CardPickingIntent: WidgetConfigurationIntent {
    var pickedID: String? { get }
}

extension TodoConfigIntent: CardPickingIntent { var pickedID: String? { card?.id } }
extension WaterConfigIntent: CardPickingIntent { var pickedID: String? { card?.id } }
extension AnniversaryConfigIntent: CardPickingIntent { var pickedID: String? { card?.id } }
extension NoteConfigIntent: CardPickingIntent { var pickedID: String? { card?.id } }
extension PetConfigIntent: CardPickingIntent { var pickedID: String? { card?.id } }
extension CalcConfigIntent: CardPickingIntent { var pickedID: String? { card?.id } }

struct CardEntry<Card: Sendable>: TimelineEntry {
    let date: Date
    let words: Words
    /// 主 App 写过快照。没有时提示「打开码头一次」，有快照但没有这种卡片时提示去添加。
    let hasApp: Bool
    let card: Card?
}

struct CardProvider<Intent: CardPickingIntent, Card: Sendable>: AppIntentTimelineProvider {
    typealias Entry = CardEntry<Card>

    /// 快照里这种卡片的全部。
    let cards: @Sendable (SystemWidgetSnapshot) -> [Card]
    let id: @Sendable (Card) -> String
    /// 小组件库里预览用的样子。
    let sample: @Sendable (Words) -> Card
    /// 兜底多久再看一次快照（主 App 改了数据会主动让小组件重画）。
    var refresh: TimeInterval = 30 * 60
    /// 过零点时要换样子（纪念日天数、喝水归零）。
    var midnight = false

    func placeholder(in context: Context) -> Entry {
        let words = Words(lang: Shared.language(nil))
        return Entry(date: .now, words: words, hasApp: true, card: sample(words))
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let real = entry(configuration, at: .now)
        if context.isPreview, real.card == nil { return placeholder(in: context) }
        return real
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date.now
        var next = now.addingTimeInterval(refresh)
        if midnight { next = min(next, nextMidnight(after: now)) }
        return Timeline(entries: [entry(configuration, at: now)], policy: .after(next))
    }

    func entry(_ configuration: Intent, at date: Date) -> Entry {
        let snapshot = Shared.snapshot(now: date)
        let words = Words(lang: Shared.language(snapshot))
        let all = snapshot.map(cards) ?? []
        let picked = configuration.pickedID.flatMap { wanted in all.first { id($0) == wanted } }
        return Entry(date: date, words: words, hasApp: snapshot != nil, card: picked ?? all.first)
    }
}

/// 有卡片画卡片，没有时画提示。
struct CardOrHint<Card: Sendable, Content: View>: View {
    var entry: CardEntry<Card>
    /// 卡片的名字，提示「先在扩展栏添加「快速待办」卡片」用。
    var kind: String
    @ViewBuilder var content: (Card) -> Content

    var body: some View {
        if let card = entry.card {
            content(card)
        } else if entry.hasApp {
            EmptyHint.noCard(entry.words, kind: kind)
        } else {
            EmptyHint.noApp(entry.words)
        }
    }
}
