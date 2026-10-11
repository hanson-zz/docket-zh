import SwiftUI

/// An amount in one currency and what it comes to in another, with a swap.
///
/// The amount is typed in the panel; the pair is chosen there or in Settings.
struct CurrencyTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: CurrencyService { CurrencyService.shared }
    private var from: String { instance.config.string("from", default: "USD") }
    private var to: String { instance.config.string("to", default: "CNY") }
    private var amount: Double {
        let stored = instance.config.double("amount", default: 100)
        return stored.isFinite ? stored : 100
    }

    /// The library's sample is a plausible figure drawn as one, never shown
    /// on the shelf: there the reading is the provider's or nothing.
    private var result: String {
        if context.isPreview { return "712.40" }
        guard let value = service.rates?.convert(amount, from: from, to: to) else { return "-" }
        return CurrencyNames.format(value, code: to)
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 3) {
                    Text("\(CurrencyNames.format(amount, code: from)) \(from)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetStyle.secondary)
                    Text(result)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                    chip(to)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(CurrencyNames.format(amount, code: from)) \(CurrencyNames.name(from))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WidgetStyle.secondary)
                            .monospacedDigit()
                        Text(result)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .monospacedDigit()
                            .rollingValue(result)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    Spacer(minLength: 0)
                    VStack(spacing: 1) {
                        chip(from)
                        Button {
                            guard !context.isPreview else { return }
                            let (a, b) = (from, to)
                            WidgetWriter.write(instance) {
                                $0.set("from", .string(b))
                                $0.set("to", .string(a))
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(WidgetStyle.secondary)
                                .frame(width: 22, height: 12)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("交换币种")
                        chip(to)
                    }
                }
            }
        }
        .onAppear { if !context.isPreview { service.start() } }
    }

    private func chip(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WidgetStyle.primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minWidth: 34)
            .frame(height: 16)
            .background(WidgetStyle.primary.opacity(0.1), in: .capsule)
    }
}
