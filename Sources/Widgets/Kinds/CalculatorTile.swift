import SwiftUI

/// 「算」：计算器、单位换算和汇率换算合成的一张卡片。
///
///     [算]  100 USD              汇率
///           712.40 CNY
///
/// 卡片只显示最后一次（或固定的那一条）的结果，输入在面板里：底栏收不了
/// 键盘，卡片上放输入框会吃掉打开面板的那一下。点结果的数字就复制它，点
/// 卡片别处照旧打开面板。汇率的结果跟着汇率表实时重算，所以固定一条
/// `1 USD` 就能一直看着汇率。
struct CalculatorTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var copied = false
    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var service: CurrencyService { CurrencyService.shared }

    /// 库里的示例：效果图上那一条，画成真的一样，但不读汇率。
    private static let sample = SmartCalc.Outcome(kind: .currency, value: 712.4, text: "712.40", unit: "CNY",
                                                  source: "100.00 USD", sourceUnit: "USD", rate: 7.124,
                                                  category: nil)

    private var input: String { context.isPreview ? "100 USD" : SmartCalc.shown(instance.config) }

    private var reading: Result<SmartCalc.Outcome, SmartCalc.Failure>? {
        if context.isPreview { return .success(Self.sample) }
        guard !input.isEmpty else { return nil }
        return SmartCalc.evaluate(input, rates: service.rates,
                                  preferences: SmartCalc.Preferences(instance.config))
    }

    private var kind: SmartCalc.Kind? {
        switch reading {
        case .success(let out)?: out.kind
        case .failure(let failure)?: failure == .empty ? nil : failure.kind
        case nil: nil
        }
    }

    private var resultText: String {
        switch reading {
        case .success(let out)?: out.text
        case .failure?: "-"
        case nil: "0"
        }
    }

    private var unitText: String {
        if case .success(let out)? = reading { return out.unit }
        return ""
    }

    /// 悬停时的一句：汇率的日期、单位的类别，或者为什么算不出来。
    private var hint: String {
        switch reading {
        case .success(let out)?:
            switch out.kind {
            case .currency:
                guard !context.isPreview, let rates = service.rates else { return tr("示例数据") }
                let date = rates.updated.formatted(.dateTime.month().day().hour().minute())
                return tr("汇率更新于 \(date)") + "\n" + tr("点数字复制结果")
            case .unit:
                return (out.category?.title ?? "") + "\n" + tr("点数字复制结果")
            case .math:
                return tr("点数字复制结果")
            }
        case .failure(let failure)?:
            return failure.message
        case nil:
            return tr("点按输入 100 USD、5 km 或 3*4+2")
        }
    }

    /// 字牌上「算」的颜色：卡片的主题色，面板和引导里没有主题色时用默认的紫。
    private var accent: Color {
        if let theme { return theme.main(dark: scheme == .dark) }
        let palette = WidgetTint.defaultPalette(.calculator)
        return Color(code: WidgetTint.readable(palette.main, dark: scheme == .dark))
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 3) {
                    badge(size: 26)
                    Text(resultText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .rollingValue(resultText)
                    Text(unitText.isEmpty ? (kind?.tag ?? tr("算")) : unitText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    badge(size: WidgetStyle.badge)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(input.isEmpty ? tr("点按开始计算") : input)
                                .font(WidgetStyle.note)
                                .foregroundStyle(WidgetStyle.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            if copied {
                                tag(tr("已复制"), color: accent)
                            } else if let kind {
                                tag(kind.tag, color: color(of: kind))
                            }
                        }
                        Button(action: copy) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(resultText)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(WidgetStyle.primary)
                                    .monospacedDigit()
                                    .rollingValue(resultText)
                                if !unitText.isEmpty {
                                    Text(unitText)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(WidgetStyle.secondary)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(context.isPreview)
                        .accessibilityLabel(tr("复制结果 \(resultText) \(unitText)"))
                    }
                }
            }
        }
        .help(hint)
        .onAppear { startRatesIfNeeded() }
        .onChange(of: input) { _, _ in startRatesIfNeeded() }
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            switch SmartCalc.badge(english: L10n.isEnglish) {
            case .character(let glyph):
                Text(verbatim: glyph)
                    .font(.system(size: size * 0.48, weight: .heavy))
                    .foregroundStyle(accent)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(accent)
            }
        }
        .accessibilityHidden(true)
    }

    /// 三类各一个颜色：汇率绿、单位黄、计算橙，和效果图一致，只是小标签。
    private func color(of kind: SmartCalc.Kind) -> Color {
        switch kind {
        case .currency: Color(hex: "#34C759")
        case .unit: Color(hex: "#FFCC00")
        case .math: Color(hex: "#FF9F0A")
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(color.opacity(0.18), in: .capsule)
            .transition(.opacity)
    }

    private func copy() {
        guard !context.isPreview, case .success(let out)? = reading else { return }
        ColorSampling.copy(out.copyText)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copied = false }
        }
    }

    private func startRatesIfNeeded() {
        guard !context.isPreview, SmartCalc.parse(input).kind == .currency else { return }
        service.start()
    }
}
