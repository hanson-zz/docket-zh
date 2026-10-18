import AppKit
import SwiftUI

/// 「算」的面板：一个输入框，结果跟着每次按键变；回车记下这一条，卡片上
/// 显示它，最近记录里三种（汇率、单位、计算）混排。识别和计算在
/// `SmartCalc`，这里只负责画和写配置。
struct CalculatorDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var draft: String?
    @State private var copied = false
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var service: CurrencyService { CurrencyService.shared }
    private var preferences: SmartCalc.Preferences { SmartCalc.Preferences(instance.config) }
    private var history: [String] { instance.config.strings(SmartCalc.historyKey) }
    private var pinned: String { instance.config.string(SmartCalc.pinnedKey) }

    private var text: String {
        draft ?? (context.isPreview ? "100 usd to jpy" : instance.config.string(SmartCalc.expressionKey))
    }

    private func evaluate(_ input: String) -> Result<SmartCalc.Outcome, SmartCalc.Failure>? {
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if context.isPreview {
            return .success(SmartCalc.Outcome(kind: .currency, value: 15_320, text: "15,320", unit: "JPY",
                                              source: "100.00 USD", sourceUnit: "USD", rate: 153.2,
                                              category: nil))
        }
        return SmartCalc.evaluate(input, rates: service.rates, preferences: preferences)
    }

    var body: some View {
        let reading = evaluate(text)
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.purple))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                field
                result(reading)
                actions(reading)
                recent
                footer(reading)
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            typing = true
            if usesCurrency { service.start() }
        }
        .onChange(of: text) { _, _ in
            if !context.isPreview, usesCurrency { service.start() }
        }
    }

    /// 输入框或任何一条记录是汇率时才去取汇率表。
    private var usesCurrency: Bool {
        ([text] + history).contains { SmartCalc.parse($0).kind == .currency }
    }

    // MARK: 输入

    private var field: some View {
        HStack(spacing: 8) {
            TextField("", text: Binding(get: { text }, set: { draft = $0 }),
                      prompt: Text("100 USD、5 km、3*4+2"))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .focused($typing)
                .onSubmit { commit(text) }
            if !text.isEmpty {
                Button {
                    draft = ""
                    typing = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("清除"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glassPane(cornerRadius: 10)
    }

    // MARK: 结果

    private func result(_ reading: Result<SmartCalc.Outcome, SmartCalc.Failure>?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                switch reading {
                case .success(let out)?:
                    HStack(spacing: 6) {
                        tag(out.kind)
                        Text(detail(out))
                            .font(WidgetStyle.caption(11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Button { copy(out) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("= " + out.text)
                                .font(.system(size: 28, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .rollingValue(out.text)
                            if !out.unit.isEmpty {
                                Text(out.unit)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(tr("点数字复制结果"))
                case .failure(let failure)?:
                    if failure.kind == .currency { tag(.currency) }
                    Text(failure.message)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                case nil:
                    Text("输入什么都行：带币种算汇率，带单位做换算，其余当算式。")
                        .font(WidgetStyle.caption(12))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let panda = AIPandaArt.image {
                Image(nsImage: panda)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .accessibilityHidden(true)
            }
        }
    }

    /// 结果上面那一小行：汇率的单价、单位的类别、算式就写「计算」。
    private func detail(_ out: SmartCalc.Outcome) -> String {
        switch out.kind {
        case .currency:
            return out.rateLine ?? out.source
        case .unit:
            return "\(out.source)  ·  \(out.category?.title ?? "")"
        case .math:
            return text.trimmingCharacters(in: .whitespaces)
        }
    }

    private func tag(_ kind: SmartCalc.Kind) -> some View {
        let color: Color = switch kind {
        case .currency: Color(hex: "#34C759")
        case .unit: Color(hex: "#FFCC00")
        case .math: Color(hex: "#FF9F0A")
        }
        return Text(kind.tag)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(color.opacity(0.18), in: .capsule)
    }

    // MARK: 操作

    private func actions(_ reading: Result<SmartCalc.Outcome, SmartCalc.Failure>?) -> some View {
        let current = text.trimmingCharacters(in: .whitespaces)
        let isPinned = !pinned.isEmpty && pinned == current
        return HStack(spacing: 8) {
            PanelButton(title: copied ? tr("已复制") : tr("拷贝结果"),
                        symbol: copied ? "checkmark" : "doc.on.doc", prominent: true) {
                if case .success(let out)? = reading { copy(out) }
            }
            .disabled(!isSuccess(reading))
            PanelButton(title: isPinned ? tr("取消固定") : tr("固定到卡片"),
                        symbol: isPinned ? "pin.slash" : "pin") {
                guard !context.isPreview else { return }
                if isPinned {
                    WidgetWriter.write(instance) { $0.set(SmartCalc.pinnedKey, nil) }
                } else {
                    commit(current)
                    WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) {
                        $0.set(SmartCalc.pinnedKey, .string(current))
                    }
                }
            }
            .disabled(current.isEmpty || (!isPinned && !isSuccess(reading)))
            .help(tr("固定后卡片一直显示这一条，汇率会跟着更新"))
        }
    }

    private func isCurrency(_ reading: Result<SmartCalc.Outcome, SmartCalc.Failure>?) -> Bool {
        switch reading {
        case .success(let out)?: out.kind == .currency
        case .failure(let failure)?: failure.kind == .currency
        case nil: false
        }
    }

    private func isSuccess(_ reading: Result<SmartCalc.Outcome, SmartCalc.Failure>?) -> Bool {
        if case .success? = reading { return true }
        return false
    }

    // MARK: 最近记录

    @ViewBuilder
    private var recent: some View {
        let entries = context.isPreview ? ["100 USD", "5 km", "128*3.5"] : Array(history.prefix(6))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("最近")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer(minLength: 0)
                    Button("清空") {
                        guard !context.isPreview else { return }
                        WidgetWriter.write(instance) { $0.set(SmartCalc.historyKey, .list([])) }
                    }
                    .buttonStyle(.plain)
                    .font(WidgetStyle.label(10))
                    .foregroundStyle(.white.opacity(0.6))
                }
                ForEach(entries, id: \.self) { entry in row(entry) }
            }
        }
    }

    private func row(_ entry: String) -> some View {
        let reading = context.isPreview ? nil : evaluate(entry)
        let answer: String = switch reading {
        case .success(let out)?: out.unit.isEmpty ? out.text : "\(out.text) \(out.unit)"
        default: "-"
        }
        return Button {
            guard !context.isPreview else { return }
            commit(entry)
        } label: {
            HStack(spacing: 6) {
                if entry == pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(entry)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(answer)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .glassPane(cornerRadius: 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("再算一次这一条"))
    }

    // MARK: 汇率来源

    @ViewBuilder
    private func footer(_ reading: Result<SmartCalc.Outcome, SmartCalc.Failure>?) -> some View {
        if usesCurrency || isCurrency(reading) {
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
    }

    private var status: String {
        if context.isPreview { return tr("示例数据") }
        if service.loading && service.rates == nil { return tr("正在获取汇率…") }
        guard let rates = service.rates else { return tr("无法获取汇率，请检查网络连接") }
        let date = rates.updated.formatted(.dateTime.month().day().hour().minute())
        return service.failed ? tr("离线，使用 \(date) 的汇率") : tr("汇率更新于 \(date)")
    }

    // MARK: 写

    /// 记下一条：卡片显示它，放到最近记录最前。
    private func commit(_ entry: String) {
        guard !context.isPreview else { return }
        let entry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = entry
        let base = WidgetWriter.current(instance.id) ?? instance
        WidgetWriter.write(base) { config in
            config.set(SmartCalc.expressionKey, .string(entry))
            guard !entry.isEmpty else { return }
            config.set(SmartCalc.historyKey,
                       .list(SmartCalc.remembering(entry, in: config.strings(SmartCalc.historyKey))
                           .map { .string($0) }))
        }
    }

    private func copy(_ out: SmartCalc.Outcome) {
        guard !context.isPreview else { return }
        ColorSampling.copy(out.copyText)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copied = false }
        }
    }
}
