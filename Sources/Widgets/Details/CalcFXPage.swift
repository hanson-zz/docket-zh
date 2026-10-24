import AppKit
import SwiftUI

/// 「算」面板的汇率页：从 / 到两行，大号数字，中间一个对调键；点币种在面板里
/// 打开可搜索的选择器；下面是汇率本身和更新时间、操作、多币种（Pro）、收藏和记录。
///
/// 金额栏可以写算式（`1299*3+50`），也可以连币种一起写（`100 eur to jpy`），两行跟着变。
/// 判断和换算都在 Core 的 `CurrencyDesk`，这里只负责画、接键盘和写配置。
///
/// 键盘：↩ 记下这一条（卡片显示它，进记录），⌘C 拷贝结果，⌘⇧C 拷贝整句，
/// ⌘⇧S 对调，⌘D 收藏，⌘E 带去计算页，⌘R 刷新汇率，⌘[ / ⌘] 选「从」/「到」的币种，
/// 金额栏里 ↑ ↓ 在「到」和多币种列表之间换。选择器里 ↑ ↓ 选、↩ 确定。
struct CalcFXPage: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var keypadOn: Bool
    /// 带去计算页：切到计算页，输入框放这个数。
    var onCarry: (String) -> Void
    /// 点了记录里不是汇率的一条：切到计算页重算它。
    var onOpenInCalc: (String) -> Void

    enum Side: Hashable { case from, to, add }
    enum Field: Hashable { case amount, search }

    @State private var working: CurrencyDesk.State?
    @State private var picking: Side?
    @State private var query = ""
    @State private var highlighted = 0
    @State private var editingList = false
    @State private var drag: (from: Int, offset: CGFloat)?
    @State private var flash: String?
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let rowHeight: CGFloat = 40
    static let editRowHeight: CGFloat = 44
    static let rowGap: CGFloat = 6

    private var service: CurrencyService { CurrencyService.shared }
    private var accent: Color { WidgetStyle.tint(.purple) }
    private var gold: Color { Color(hex: "#F5C451") }
    private var unlocked: Bool { context.isPreview || ProAccess.isUnlocked }
    private var listOn: Bool { ProLicenseGate.canUseCurrencyList(unlocked: unlocked) }

    /// 写过之后面板拿到的可能还是打开时那份，写之前读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var config: WidgetConfig { context.isPreview ? instance.config : current.config }
    private var preferences: SmartCalc.Preferences { SmartCalc.Preferences(config) }

    private var desk: CurrencyDesk.State {
        if let working { return working }
        if context.isPreview {
            return CurrencyDesk.State(from: "USD", to: "CNY", amount: "1299*3+50", list: CurrencyDesk.defaultList,
                                      favorites: ["100 USD to CNY", "1 EUR to CNY"])
        }
        return CurrencyDesk.State(config)
    }

    private var rates: CurrencyRates? { context.isPreview ? Self.sampleRates : service.rates }

    private var codes: Set<String> {
        var all = SmartCalc.commonCodes
        if let rates { all.formUnion(rates.rates.keys.map { $0.uppercased() }) }
        return all
    }

    private var conversion: CurrencyDesk.Conversion {
        CurrencyDesk.convert(desk, rates: rates, style: preferences.number, codes: codes)
    }

    /// 库里的示例和没联网时的预览用：一张写死的表，不读网络。
    static let sampleRates = CurrencyRates(base: "CNY",
                                           rates: ["CNY": 1, "USD": 0.14045, "EUR": 0.12108, "JPY": 21.083,
                                                   "HKD": 1.0913, "GBP": 0.10524, "KRW": 195.2, "SGD": 0.1823],
                                           updated: Date(timeIntervalSince1970: 1_761_264_000))

    var body: some View {
        let out = conversion
        VStack(alignment: .leading, spacing: 12) {
            if let picking {
                picker(picking)
            } else {
                rows(out)
                rateLine(out)
                actions(out)
                if keypadOn {
                    CalcKeypad(accent: accent) { press($0) }
                } else {
                    multiCurrency(out)
                    favorites
                    tape
                }
                attribution
            }
        }
        .background { shortcuts(out) }
        .onAppear {
            guard !context.isPreview else { return }
            service.start()
            WidgetDetailWindow.shared.focusField { focus = .amount }
        }
        .onDisappear { persist() }
    }

    // MARK: 从 / 到

    private func rows(_ out: CurrencyDesk.Conversion) -> some View {
        VStack(spacing: 8) {
            fromRow(out)
            toRow(out)
        }
        .overlay { swapButton }
    }

    private func fromRow(_ out: CurrencyDesk.Conversion) -> some View {
        let code = out.reading.from
        return VStack(alignment: .leading, spacing: 4) {
            rowTitle(tr("从", context: "currency"), code: code)
            HStack(alignment: .center, spacing: 10) {
                currencyButton(code, side: .from)
                VStack(alignment: .trailing, spacing: 1) {
                    TextField("", text: Binding(get: { desk.amount }, set: { setAmount($0) }),
                              prompt: Text(verbatim: "1").foregroundStyle(.panelTertiary))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundStyle(.panelPrimary)
                        .focused($focus, equals: .amount)
                        .onSubmit { commit() }
                        .onKeyPress(.upArrow) { cycle(-1); return .handled }
                        .onKeyPress(.downArrow) { cycle(1); return .handled }
                        .accessibilityLabel(tr("金额，可以写算式"))
                    if let failure = out.reading.failure {
                        Text(failure.message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelSecondary)
                            .lineLimit(1)
                    } else if out.reading.isExpression {
                        Text(verbatim: "= " + out.amountText)
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.panelSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 84)
        .glassPane(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focus == .amount ? accent.panelGraphic.opacity(0.9) : Color.clear, lineWidth: 1.4)
        }
        .contentShape(.rect)
        .onTapGesture { WidgetDetailWindow.shared.focusField { focus = .amount } }
    }

    private func toRow(_ out: CurrencyDesk.Conversion) -> some View {
        let code = out.reading.to
        let text = out.result?.text ?? "-"
        return VStack(alignment: .leading, spacing: 4) {
            rowTitle(tr("到", context: "currency"), code: code)
            HStack(alignment: .center, spacing: 10) {
                currencyButton(code, side: .to)
                Button { copy(out.copyText) } label: {
                    Text(verbatim: text)
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .rollingValue(text)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(out.result == nil)
                .help(tr("点数字拷贝结果（⌘C）"))
                .accessibilityLabel(tr("结果 \(text) \(code)，点按拷贝"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 84)
        .glassPane(cornerRadius: 14)
    }

    private func rowTitle(_ title: String, code: String) -> some View {
        Text(verbatim: "\(title) · \(CurrencyCatalog.name(code))")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelSecondary)
            .lineLimit(1)
            .padding(.top, 10)
    }

    private func currencyButton(_ code: String, side: Side) -> some View {
        Button { open(side) } label: {
            HStack(spacing: 6) {
                CurrencyMark(code: code, size: 22)
                Text(verbatim: code)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.panelSecondary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(height: 34)
            .background(Capsule().fill(.panelSelected))
            .contentShape(.capsule)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help(side == .from ? tr("选「从」的币种（⌘[）") : tr("选「到」的币种（⌘]）"))
        .accessibilityLabel(side == .from ? tr("从 \(CurrencyCatalog.name(code))，点按换币种")
                                          : tr("到 \(CurrencyCatalog.name(code))，点按换币种"))
    }

    private var swapButton: some View {
        Button { swapRows() } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.panelRaised).panelLift())
                .overlay { Circle().strokeBorder(.panelStroke, lineWidth: 0.8) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(tr("对调（⌘⇧S）"))
        .accessibilityLabel(tr("对调两种货币"))
    }

    // MARK: 汇率和更新时间

    private func rateLine(_ out: CurrencyDesk.Conversion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: out.rateLine ?? tr("暂时没有 \(out.reading.to) 的汇率"))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(.panelPrimary)
                if let inverse = out.inverseLine {
                    Text(verbatim: inverse)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.panelSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(offline ? Color(hex: "#FF9F0A").panelReadable : Color.panelSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                Button { service.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.panelFill))
                        .contentShape(.circle)
                        .rotationEffect(.degrees(service.loading && !reduceMotion ? 180 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: service.loading)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview || service.loading)
                .help(tr("刷新汇率（⌘R）"))
                .accessibilityLabel(tr("刷新汇率"))
            }
        }
    }

    private var offline: Bool { !context.isPreview && service.failed && service.rates != nil }

    private var status: String {
        if context.isPreview { return tr("示例数据") }
        if service.loading && service.rates == nil { return tr("正在获取汇率…") }
        guard let rates = service.rates else { return tr("无法获取汇率，请检查网络连接") }
        let date = rates.updated.formatted(.dateTime.month().day().hour().minute())
        return service.failed ? tr("离线，使用 \(date) 的汇率") : tr("\(date) 更新")
    }

    // MARK: 操作

    private func actions(_ out: CurrencyDesk.Conversion) -> some View {
        let entry = CurrencyDesk.entry(desk, codes: codes)
        let starred = entry.map { CurrencyDesk.isFavorite($0, in: desk.favorites) } ?? false
        let pinnedEntry = config.string(SmartCalc.pinnedKey)
        let pinned = entry.map { !pinnedEntry.isEmpty && CurrencyDesk.isFavorite(pinnedEntry, in: [$0]) } ?? false
        return HStack(spacing: 8) {
            PanelButton(title: flash == "copy" ? tr("已复制") : tr("拷贝"),
                        symbol: flash == "copy" ? "checkmark" : "doc.on.doc", prominent: true) {
                copy(out.copyText)
            }
            .disabled(out.result == nil)
            .help(tr("拷贝结果（⌘C），整句用 ⌘⇧C"))
            PanelButton(title: tr("带去计算"), symbol: "plus.forwardslash.minus") { carry(out) }
                .disabled(out.result == nil)
                .help(tr("把结果带到计算页接着算（⌘E）"))
            roundButton(symbol: starred ? "star.fill" : "star", on: starred, tint: gold,
                        help: starred ? tr("取消收藏（⌘D）") : tr("收藏这组换算（⌘D）")) { toggleFavorite() }
                .disabled(entry == nil)
            roundButton(symbol: pinned ? "pin.fill" : "pin", on: pinned, tint: accent,
                        help: pinned ? tr("取消固定") : tr("固定到卡片，汇率跟着更新")) { togglePin(entry, pinned: pinned) }
                .disabled(entry == nil)
        }
    }

    private func roundButton(symbol: String, on: Bool, tint: Color, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? tint.panelReadable : Color.panelPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(on ? tint.opacity(0.2) : Color.panelFill))
                .overlay { Circle().strokeBorder(on ? tint.opacity(0.6) : Color.panelStroke, lineWidth: 0.7) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: 多币种（Pro）

    @ViewBuilder
    private func multiCurrency(_ out: CurrencyDesk.Conversion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(tr("多币种"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                ProBadge()
                Spacer(minLength: 0)
                if listOn, !context.isPreview {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { editingList.toggle() }
                    } label: {
                        Text(editingList ? tr("完成") : tr("编辑"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.panelPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(Capsule().fill(editingList ? Color.panelRaised : Color.panelFill))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(tr("添加、删除和拖动排序"))
                }
            }
            if !listOn {
                lockedList
            } else if editingList {
                editList
            } else if out.list.isEmpty {
                Text(desk.shownList.isEmpty ? tr("点「编辑」添加想一起看的币种") : tr("汇率到了就会列出来"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(out.list.enumerated()), id: \.element.id) { index, line in
                        if index > 0 {
                            Rectangle().fill(.panelSeparator).frame(height: 0.6).padding(.leading, 44)
                        }
                        listRow(line)
                    }
                }
                .glassPane(cornerRadius: 12)
                Text(tr("点一行把它设为「从」，金额跟着换"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
        }
    }

    private func listRow(_ line: CurrencyDesk.Line) -> some View {
        Button { promote(line.code) } label: {
            HStack(spacing: 8) {
                CurrencyMark(code: line.code, size: 22)
                Text(verbatim: line.code)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(CurrencyCatalog.name(line.code))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(verbatim: line.text)
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .rollingValue(line.text)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help(tr("设为「从」"))
        .accessibilityLabel(tr("\(CurrencyCatalog.name(line.code)) \(line.text)，点按设为「从」"))
    }

    /// 没解锁：一行说明，点了弹付费墙。存着的列表不动。
    private var lockedList: some View {
        Button {
            guard !context.isPreview else { return }
            PaywallWindow.shared.show()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("一个金额同时换成多种货币"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Text(tr("点一行设为基准，可增删和拖动排序"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .contentShape(.rect)
            .glassPane(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .help(tr("多币种列表是码头 Pro 专属。点一下购买、输入激活码或开始试用。"))
    }

    private var editList: some View {
        let shown = desk.shownList
        let step = Self.editRowHeight + Self.rowGap
        let target = drag.map { CurrencyDesk.dropIndex(from: $0.from, offset: Double($0.offset),
                                                      step: Double(step), count: shown.count) }
        return VStack(spacing: Self.rowGap) {
            ForEach(Array(shown.enumerated()), id: \.element) { index, code in
                editRow(code, index: index, count: shown.count)
                    .offset(y: rowOffset(index, target: target))
                    .zIndex(drag?.from == index ? 1 : 0)
            }
            Button { open(.add) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(CurrencyDesk.canAdd(desk.list) ? tr("添加币种") : tr("最多 \(CurrencyDesk.listLimit) 种"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.panelPrimary)
                .padding(.horizontal, 14)
                .frame(height: Self.editRowHeight)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.panelSecondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!CurrencyDesk.canAdd(desk.list))
        }
    }

    private func rowOffset(_ index: Int, target: Int?) -> CGFloat {
        guard let drag, let target else { return 0 }
        if index == drag.from { return drag.offset }
        let step = Self.editRowHeight + Self.rowGap
        if drag.from < target, index > drag.from, index <= target { return -step }
        if drag.from > target, index < drag.from, index >= target { return step }
        return 0
    }

    private func editRow(_ code: String, index: Int, count: Int) -> some View {
        let lifted = drag?.from == index
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(count > 1 ? 0.6 : 0.25))
                .frame(width: 24, height: Self.editRowHeight)
                .contentShape(.rect)
                .gesture(reorder(index: index, count: count))
                .help(tr("拖动排序"))
                .accessibilityLabel(tr("拖动排序"))
            CurrencyMark(code: code, size: 22)
            Text(verbatim: code)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.panelPrimary)
            Text(CurrencyCatalog.name(code))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { update { $0.list = CurrencyDesk.removing(code, from: $0.list) } } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(hex: "#FF453A").panelReadable)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(hex: "#FF453A").opacity(0.2)))
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(tr("删除"))
            .accessibilityLabel(tr("删除"))
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: Self.editRowHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(lifted ? Color.panelSelected : Color.panelFill))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.5) }
        .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: 8, y: 3)
    }

    private func reorder(index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard count > 1 else { return }
                drag = (index, value.translation.height)
            }
            .onEnded { value in
                guard let from = drag?.from else { return }
                let step = Self.editRowHeight + Self.rowGap
                let to = CurrencyDesk.dropIndex(from: from, offset: Double(value.translation.height),
                                                step: Double(step), count: count)
                drag = nil
                guard to != from else { return }
                update { $0.list = CurrencyDesk.movingShown($0, from: from, to: to) }
            }
    }

    // MARK: 收藏

    @ViewBuilder
    private var favorites: some View {
        let list = desk.favorites
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("收藏"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                CityChipFlow(spacing: 6) {
                    ForEach(list, id: \.self) { entry in favoriteChip(entry) }
                }
            }
        }
    }

    private func favoriteChip(_ entry: String) -> some View {
        let answer = answerText(entry, withUnit: false)
        return Button { load(entry) } label: {
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(gold.panelReadable)
                Text(verbatim: CurrencyDesk.label(entry, codes: codes))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                if !answer.isEmpty {
                    Text(verbatim: answer)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.panelPrimary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Capsule().fill(.panelFill))
            .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help(tr("换到这一组；右键取消收藏"))
        .contextMenu {
            Button(tr("取消收藏")) {
                update { $0.favorites = CurrencyDesk.togglingFavorite(entry, in: $0.favorites) }
            }
        }
    }

    // MARK: 记录

    private var history: [String] {
        context.isPreview ? ["1299*3+50 USD to CNY", "500 HKD to CNY", "5 km"] : config.strings(SmartCalc.historyKey)
    }

    @ViewBuilder
    private var tape: some View {
        let entries = Array(history.prefix(4))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(flash == "commit" ? tr("已记下") : tr("记录"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                    Spacer(minLength: 0)
                    Button(tr("清空")) {
                        guard !context.isPreview else { return }
                        WidgetWriter.write(current) { $0.set(SmartCalc.historyKey, .list([])) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                }
                ForEach(entries, id: \.self) { entry in tapeRow(entry) }
            }
        }
    }

    private func tapeRow(_ entry: String) -> some View {
        let isCurrency = SmartCalc.parse(entry, codes: codes).kind == .currency
        return Button {
            guard !context.isPreview else { return }
            if isCurrency { load(entry) } else { onOpenInCalc(entry) }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: CurrencyDesk.label(entry, codes: codes))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(verbatim: answerText(entry, withUnit: true))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .glassPane(cornerRadius: 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isCurrency ? tr("换到这一条") : tr("在计算页再算一次"))
    }

    private func answerText(_ entry: String, withUnit: Bool) -> String {
        switch SmartCalc.evaluate(entry, rates: rates, preferences: preferences) {
        case .success(let out):
            return withUnit && !out.unit.isEmpty ? "\(out.text) \(out.unit)" : out.text
        case .failure:
            return withUnit ? "-" : ""
        }
    }

    // MARK: 来源

    private var attribution: some View {
        Button(CurrencyService.attribution) { NSWorkspace.shared.open(CurrencyService.attributionURL) }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.panelTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    // MARK: 币种选择器

    private func pickerItems(_ side: Side) -> [CurrencyCatalog.Item] {
        let pinned = [desk.from, desk.to] + desk.list + CurrencyNames.common.map(\.code)
        return CurrencyCatalog.search(query, codes: CurrencyCatalog.codes(rates), pinned: pinned)
    }

    private func picker(_ side: Side) -> some View {
        let items = pickerItems(side)
        let pinned = Set([desk.from, desk.to] + desk.list + CurrencyNames.common.map(\.code))
        let commonCount = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? pinned.intersection(CurrencyCatalog.codes(rates)).count
            : 0
        let title = switch side {
        case .from: tr("选「从」的币种")
        case .to: tr("选「到」的币种")
        case .add: tr("添加到多币种")
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Spacer(minLength: 0)
                Button { close() } label: {
                    Text(tr("取消"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(Capsule().fill(.panelFill))
                        .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                TextField("", text: $query, prompt: Text(tr("搜名称、代码或符号：港币、hkd、$")).foregroundStyle(.panelTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .focused($focus, equals: .search)
                    .onSubmit { if items.indices.contains(highlighted) { choose(items[highlighted].code, side: side) } }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(items.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.panelFill))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(accent.panelGraphic.opacity(0.9), lineWidth: 1.2)
            }
            .onChange(of: query) { _, _ in highlighted = 0 }
            if items.isEmpty {
                Text(tr("没找到「\(query.trimmingCharacters(in: .whitespaces))」"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .frame(height: 44)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index == 0, commonCount > 0 { sectionTitle(tr("常用", context: "currency")) }
                                if index == commonCount, commonCount > 0 {
                                    sectionTitle(tr("全部 \(items.count - commonCount) 种"))
                                }
                                pickerRow(item, side: side, highlighted: index == highlighted)
                                    .id(item.code)
                            }
                        }
                    }
                    .frame(height: 360)
                    .onChange(of: highlighted) { _, index in
                        guard items.indices.contains(index) else { return }
                        reader.scrollTo(items[index].code)
                    }
                }
            }
            Text(tr("↑↓ 选择 · ↩ 确定"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.panelSecondary)
            .padding(.top, 6)
            .padding(.leading, 2)
    }

    private func pickerRow(_ item: CurrencyCatalog.Item, side: Side, highlighted: Bool) -> some View {
        let selected = switch side {
        case .from: item.code == desk.from
        case .to: item.code == desk.to
        case .add: desk.list.contains(item.code)
        }
        return Button { choose(item.code, side: side) } label: {
            HStack(spacing: 8) {
                CurrencyMark(code: item.code, size: 22)
                Text(item.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                Text(verbatim: item.code)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 6)
                if item.symbol != item.code {
                    Text(verbatim: item.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent.panelReadable)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? Color.panelSelected : Color.clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(side == .add && selected)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: 键盘

    /// 看不见的按钮，只为接快捷键。选择器开着时只留 ⌘[ ⌘] 以外的都不接。
    @ViewBuilder
    private func shortcuts(_ out: CurrencyDesk.Conversion) -> some View {
        if picking == nil, !context.isPreview {
            ZStack {
                Button("") { copy(out.copyText) }.keyboardShortcut("c", modifiers: .command)
                Button("") { copy(out.sentence, flashKey: "copy") }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("") { swapRows() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("") { toggleFavorite() }.keyboardShortcut("d", modifiers: .command)
                Button("") { carry(out) }.keyboardShortcut("e", modifiers: .command)
                Button("") { service.refresh(force: true) }.keyboardShortcut("r", modifiers: .command)
                Button("") { open(.from) }.keyboardShortcut("[", modifiers: .command)
                Button("") { open(.to) }.keyboardShortcut("]", modifiers: .command)
            }
            .buttonStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: 动作

    private func setAmount(_ text: String) {
        var next = desk
        next.amount = text
        working = next
    }

    private func press(_ key: CurrencyDesk.Key) {
        setAmount(CurrencyDesk.pressing(key, in: desk.amount))
        WidgetDetailWindow.shared.focusField { focus = .amount }
    }

    /// 改两行、列表或收藏：先落到本地，马上写进配置。
    private func update(_ change: (inout CurrencyDesk.State) -> Void) {
        var next = desk
        change(&next)
        working = next
        persist(next)
    }

    private func persist(_ state: CurrencyDesk.State? = nil) {
        guard !context.isPreview, let state = state ?? working else { return }
        WidgetWriter.write(current) { state.write(into: &$0) }
    }

    private func swapRows() {
        let next = CurrencyDesk.swapped(desk, codes: codes)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { working = next }
        persist(next)
    }

    private func cycle(_ step: Int) {
        let next = CurrencyDesk.cyclingTarget(desk, step: step, codes: codes)
        guard next != desk else { return }
        working = next
        persist(next)
    }

    private func promote(_ code: String) {
        let next = CurrencyDesk.promoting(code, in: desk, rates: rates, codes: codes)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { working = next }
        persist(next)
    }

    private func open(_ side: Side) {
        guard !context.isPreview else { return }
        if side == .add, !CurrencyDesk.canAdd(desk.list) { return }
        query = ""
        highlighted = 0
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { picking = side }
        WidgetDetailWindow.shared.focusField { focus = .search }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { picking = nil }
        WidgetDetailWindow.shared.focusField { focus = .amount }
    }

    private func choose(_ code: String, side: Side) {
        switch side {
        case .from: update { $0 = CurrencyDesk.choosingFrom(code, in: $0, codes: codes) }
        case .to: update { $0 = CurrencyDesk.choosingTo(code, in: $0, codes: codes) }
        case .add: update { $0.list = CurrencyDesk.adding(code, to: $0.list) }
        }
        close()
    }

    private func load(_ entry: String) {
        guard let next = CurrencyDesk.loading(entry, into: desk, codes: codes) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { working = next }
        persist(next)
    }

    /// ↩：记下这一条，卡片显示它，进记录。
    private func commit() {
        guard !context.isPreview else { return }
        let settled = CurrencyDesk.settled(desk, codes: codes)
        working = settled
        guard let entry = CurrencyDesk.entry(settled, codes: codes) else { return }
        WidgetWriter.write(current) { config in
            settled.write(into: &config)
            config.set(SmartCalc.expressionKey, .string(entry))
            config.set(SmartCalc.historyKey,
                       .list(SmartCalc.remembering(entry, in: config.strings(SmartCalc.historyKey)).map { .string($0) }))
        }
        flashing("commit")
    }

    private func toggleFavorite() {
        guard !context.isPreview, let entry = CurrencyDesk.entry(CurrencyDesk.settled(desk, codes: codes), codes: codes)
        else { return }
        update {
            $0 = CurrencyDesk.settled($0, codes: codes)
            $0.favorites = CurrencyDesk.togglingFavorite(entry, in: $0.favorites)
        }
    }

    private func togglePin(_ entry: String?, pinned: Bool) {
        guard !context.isPreview, let entry else { return }
        if pinned {
            WidgetWriter.write(current) { $0.set(SmartCalc.pinnedKey, nil) }
        } else {
            commit()
            WidgetWriter.write(current) { $0.set(SmartCalc.pinnedKey, .string(entry)) }
        }
    }

    private func carry(_ out: CurrencyDesk.Conversion) {
        guard !context.isPreview, let text = out.carryText else { return }
        persist()
        onCarry(text)
    }

    private func copy(_ text: String?, flashKey: String = "copy") {
        guard !context.isPreview, let text else { return }
        ColorSampling.copy(text)
        flashing(flashKey)
    }

    private func flashing(_ key: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { flash = key }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard flash == key else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { flash = nil }
        }
    }
}

// MARK: - 币种标记

/// 旗帜表情；拼不出旗帜的（贵金属、特别提款权）画一个带符号的圆。
struct CurrencyMark: View {
    var code: String
    var size: CGFloat

    var body: some View {
        if let flag = CurrencyCatalog.flag(code) {
            Text(verbatim: flag)
                .font(.system(size: size * 0.9))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Text(verbatim: String(CurrencyCatalog.symbol(code).prefix(2)))
                .font(.system(size: max(9, size * 0.42), weight: .bold))
                .foregroundStyle(.panelPrimary)
                .minimumScaleFactor(0.6)
                .frame(width: size, height: size)
                .background(Circle().fill(.panelSelected))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 小键盘

/// 4 × 5 的小键盘：数字键浮起的白（深色是薄玻璃），运算符和清除淡淡的主题色。
struct CalcKeypad: View {
    var accent: Color
    var onKey: (CurrencyDesk.Key) -> Void

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(CurrencyDesk.keypad.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
    }

    private func isAccent(_ key: CurrencyDesk.Key) -> Bool {
        switch key {
        case .add, .subtract, .multiply, .divide, .clear: true
        default: false
        }
    }

    private func keyButton(_ key: CurrencyDesk.Key) -> some View {
        let tinted = isAccent(key)
        return Button { onKey(key) } label: {
            Group {
                if key == .back {
                    Image(systemName: "delete.left")
                        .font(.system(size: 17, weight: .semibold))
                } else {
                    Text(verbatim: key.title)
                        .font(.system(size: 19, weight: tinted ? .semibold : .bold).monospacedDigit())
                }
            }
            .foregroundStyle(tinted ? accent.panelReadable : Color.panelPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tinted ? accent.opacity(0.2) : Color.panelRaised)
                    .panelLift(!tinted)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(key == .back ? tr("删除") : key == .clear ? tr("清除") : key.title)
    }
}
