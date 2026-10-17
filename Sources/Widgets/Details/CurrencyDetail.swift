import AppKit
import SwiftUI

/// The amount, the pair, and the same amount in the other common currencies.
struct CurrencyDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft = ""
    @FocusState private var typing: Bool

    private var service: CurrencyService { CurrencyService.shared }
    private var from: String { instance.config.string("from", default: "USD") }
    private var to: String { instance.config.string("to", default: "CNY") }
    private var stored: Double {
        let value = instance.config.double("amount", default: 100)
        return value.isFinite ? value : 100
    }
    private var amount: Double { UnitConverter.parse(draft) ?? stored }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.green))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("", text: $draft, prompt: Text(CurrencyNames.format(stored, code: from)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .focused($typing)
                        .onSubmit { commit() }
                        .onChange(of: typing) { _, active in if !active { commit() } }
                    menu(from) { code in write("from", code) }
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .glassPane(cornerRadius: 12)

                HStack(spacing: 8) {
                    Text(converted(to))
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .rollingValue(converted(to))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        let (a, b) = (from, to)
                        WidgetWriter.write(instance) {
                            $0.set("from", .string(b))
                            $0.set("to", .string(a))
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.14), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("交换币种")
                    menu(to) { code in write("to", code) }
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                .glassPane(cornerRadius: 12)

                others
                footer
            }
        }
        .onAppear { if !context.isPreview { service.start() } }
    }

    private func converted(_ code: String) -> String {
        guard !context.isPreview, let value = service.rates?.convert(amount, from: from, to: code) else {
            return context.isPreview && code == "CNY" ? "712.40" : "-"
        }
        return CurrencyNames.format(value, code: code)
    }

    /// The amount in the next few common currencies, skipping the pair.
    private var others: some View {
        let codes = CurrencyNames.common.map { $0.code }.filter { $0 != from && $0 != to }.prefix(6)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                         spacing: 6) {
            ForEach(Array(codes), id: \.self) { code in
                StatChip(label: "\(CurrencyNames.name(code)) \(code)", value: converted(code))
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(status)
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
                Button("刷新") { service.refresh(force: true) }
                    .buttonStyle(.plain)
                    .font(WidgetStyle.label(11))
                    .foregroundStyle(.white.opacity(0.8))
                    .disabled(context.isPreview || service.loading)
            }
            Button(CurrencyService.attribution) { NSWorkspace.shared.open(CurrencyService.attributionURL) }
                .buttonStyle(.plain)
                .font(WidgetStyle.caption(10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var status: String {
        if context.isPreview { return tr("示例数据") }
        if service.loading && service.rates == nil { return tr("正在获取汇率…") }
        guard let rates = service.rates else { return tr("无法获取汇率，请检查网络连接") }
        let date = rates.updated.formatted(.dateTime.month().day().hour().minute())
        return service.failed ? tr("离线，使用 \(date) 的汇率") : tr("汇率更新于 \(date)")
    }

    private func menu(_ selected: String, choose: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(CurrencyNames.common, id: \.code) { item in
                Button("\(item.name) \(item.code)") { choose(item.code) }
            }
        } label: {
            Text(selected)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color.white.opacity(0.14), in: .capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func write(_ key: String, _ code: String) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { $0.set(key, .string(code)) }
    }

    private func commit() {
        guard !context.isPreview, let value = UnitConverter.parse(draft) else { return }
        WidgetWriter.write(instance) { $0.set("amount", .number(value)) }
        draft = ""
    }
}
