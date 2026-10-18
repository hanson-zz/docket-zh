import SwiftUI
@preconcurrency import Translation

/// The last translation at a glance: what it came out as, and which way it
/// went ("中 ⇄ 英").
///
/// Typing happens in the panel, for the same reason 「算」 (the calculator,
/// converter and currency in one) is worked in its own: a field on the card
/// would take the click that opens it. Text dropped on the card is translated right here, and
/// lands in the panel's history like any other.
struct TranslateTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var targeted = false
    @State private var configuration: TranslationSession.Configuration?
    @State private var pending: TranslateJob?
    @State private var working = false

    private var last: TranslateRecord? {
        context.isPreview
            ? TranslateRecord(source: Translate.chinese, target: Translate.english,
                              sourceText: tr("你好，世界"), resultText: "Hello, world")
            : Translate.history(instance.config).first
    }

    private var pair: String {
        context.isPreview ? tr("中 ⇄ 英") : Translate.tilePair(instance.config)
    }

    private var value: String {
        if working { return tr("正在翻译…") }
        guard let last else { return tr("点按开始翻译") }
        return Translate.snippet(last.resultText)
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 4) {
                    badge(size: 30)
                    Text(pair)
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(last == nil && !working ? tr("拖入文字") : value)
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 2)
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    badge(size: WidgetStyle.badge)
                    TileReading(value: value, caption: tr("翻译 · \(pair)"), valueSize: 14)
                    Spacer(minLength: 0)
                }
            }
        }
        .dropTargetOutline(targeted)
        .dropDestination(for: String.self) { items, _ in
            guard !context.isPreview else { return false }
            return translate(items.joined(separator: "\n"))
        } isTargeted: { targeted = $0 }
        .translationTask(configuration) { session in
            guard let job = pending else { return }
            let outcome = await TranslationRunner.run(session, job: job) {}
            guard pending == job, outcome != .cancelled else { return }
            pending = nil
            working = false
            if case .done(let record) = outcome {
                WidgetWriter.write(instance) { config in
                    Translate.store(Translate.recording(record, in: Translate.history(config)), in: &config)
                }
            }
        }
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            Image(systemName: "translate")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(WidgetStyle.primary)
                .symbolEffect(.pulse, isActive: working)
        }
    }

    /// Translates dropped text the way the panel would: the chosen or
    /// detected source, and the smart direction unless it is switched off.
    private func translate(_ dropped: String) -> Bool {
        let text = Translate.clamped(dropped.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else { return false }
        let config = instance.config
        let chosen = Translate.source(config)
        let source = chosen == Translate.auto ? Translate.detect(text) : chosen
        let target = Translate.target(source: source, text: text,
                                      chosen: Translate.chosenTarget(config),
                                      smart: Translate.smartDirection(config))
        if let source, Translate.same(source, target) { return false }
        let job = TranslateJob(text: text, source: source, target: target)
        pending = job
        working = true
        let next = TranslationRunner.configuration(for: job)
        if TranslationRunner.samePair(configuration, next) {
            configuration?.invalidate()
        } else {
            configuration = next
        }
        return true
    }
}
