import AppKit
import SwiftUI

/// 股票、自选股面板的「编辑」：输入代码或名称添加、红钮删除、拖柄排序，
/// 自选股每行再点「持仓」填股数和成本价。
///
/// 只管界面和输入；改哪个设置键、怎么写回由面板给的回调决定（规则在 Core 的
/// `StockBoard.settingSymbols`、`settingHolding`，见 StockEditing.swift）。
struct StockSymbolEditor: View {
    var symbols: [String]
    /// 自选股才有持仓；股票卡片是 nil，行里不出「持仓」。
    var holdings: [String: StockBoard.Holding]?
    var accent: Color
    var isPreview: Bool
    var subtitle: (String) -> String
    var onAdd: (String) -> Void
    var onRemove: (String) -> Void
    var onMove: (Int, Int) -> Void
    var onHolding: (String, StockBoard.Holding?) -> Void

    @State private var query = ""
    @State private var remote: [StockSearch.Hit] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var searching = false
    /// 正在拖的那只和拖了多远。
    @State private var drag: (symbol: String, offset: CGFloat)?
    /// 正在填持仓的那只，和两个框里的字。
    @State private var holdingSymbol: String?
    @State private var sharesText = ""
    @State private var costText = ""

    private static let rowHeight: CGFloat = 38
    private static let rowSpacing: CGFloat = 4

    private var hits: [StockSearch.Hit] {
        StockSearch.merged(local: StockSearch.local(query), remote: remote, guess: StockSearch.guess(query))
    }
    private var full: Bool { symbols.count >= StockBoard.editorLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            if StockSearch.query(query) != nil { results }
            VStack(spacing: Self.rowSpacing) {
                ForEach(Array(symbols.enumerated()), id: \.element) { index, symbol in
                    row(symbol, index: index)
                        .zIndex(drag?.symbol == symbol ? 1 : 0)
                    if holdingSymbol == symbol, holdings != nil { holdingEditor(symbol) }
                }
            }
            Text(holdings != nil ? tr("拖右边的把手排序；填了持仓，上面就算今日盈亏，填了成本价再算持仓盈亏。")
                                 : tr("拖右边的把手排序，卡片按这个顺序轮播。"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: 搜索

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            TextField("", text: $query, prompt: Text(tr("输入代码或名称，比如 NVDA、茅台、0700")))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .onSubmit { if let first = hits.first { add(first.symbol) } }
                .onChange(of: query) { _, text in search(text) }
            if searching {
                ProgressView().controlSize(.mini)
            }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(tr("清空"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        }
        .disabled(isPreview)
    }

    /// 停手 0.35 秒再去问接口，打字时不每个字都发一次请求。
    private func search(_ text: String) {
        searchTask?.cancel()
        remote = []
        guard let query = StockSearch.query(text), !isPreview else {
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await StockService.search(query)
            guard !Task.isCancelled else { return }
            remote = found
            searching = false
        }
    }

    @ViewBuilder
    private var results: some View {
        let list = hits
        if list.isEmpty {
            Text(searching ? tr("正在搜索…") : tr("没找到。可以直接输入代码，比如 600519、0700、NVDA。"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 4) {
                ForEach(list, id: \.symbol) { hit in resultRow(hit) }
            }
        }
    }

    private func resultRow(_ hit: StockSearch.Hit) -> some View {
        let added = symbols.contains(hit.symbol)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(hit.name.isEmpty ? StockBoard.displaySymbol(hit.symbol) : hit.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(hit.exchange.isEmpty ? hit.symbol : "\(hit.symbol) · \(hit.exchange)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button {
                add(hit.symbol)
            } label: {
                Text(added ? tr("已添加") : tr("添加"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(added ? .white.opacity(0.5) : Color.black.opacity(0.85))
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(added ? Color.white.opacity(0.08) : accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(added || full || isPreview)
            .help(full ? tr("最多 \(StockBoard.editorLimit) 只") : "")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.10)))
    }

    private func add(_ symbol: String) {
        guard !isPreview, !symbols.contains(StockBoard.normalised(symbol)) else { return }
        guard !full else { NSSound.beep(); return }
        onAdd(symbol)
        query = ""
        remote = []
    }

    // MARK: 一行

    private func row(_ symbol: String, index: Int) -> some View {
        let removable = StockBoard.canRemove(count: symbols.count)
        let offset = drag?.symbol == symbol ? drag?.offset ?? 0 : 0
        return HStack(spacing: 8) {
            Button {
                if holdingSymbol == symbol { holdingSymbol = nil }
                onRemove(symbol)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(red: 0.92, green: 0.3, blue: 0.3))
                    .opacity(removable ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!removable || isPreview)
            .help(removable ? tr("删除 \(StockBoard.displaySymbol(symbol))") : tr("至少留一只"))
            VStack(alignment: .leading, spacing: 0) {
                Text(StockBoard.displaySymbol(symbol))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                let name = subtitle(symbol)
                if !name.isEmpty {
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            if let holdings { holdingButton(symbol, holdings[symbol]) }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: Self.rowHeight)
                .contentShape(Rectangle())
                .gesture(dragGesture(symbol, index: index))
                .help(tr("拖动排序"))
                .accessibilityLabel(tr("拖动排序"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: Self.rowHeight)
        .glassPane(cornerRadius: 10)
        .offset(y: offset)
        .shadow(color: .black.opacity(drag?.symbol == symbol ? 0.35 : 0), radius: 6, y: 2)
        .contextMenu {
            Button(tr("上移")) { onMove(index, index - 1) }.disabled(index == 0)
            Button(tr("下移")) { onMove(index, index + 1) }.disabled(index == symbols.count - 1)
            Button(tr("删除"), role: .destructive) { onRemove(symbol) }.disabled(!removable)
        }
    }

    private func dragGesture(_ symbol: String, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if holdingSymbol != nil { holdingSymbol = nil }
                drag = (symbol, value.translation.height)
            }
            .onEnded { value in
                let target = StockBoard.dragTarget(from: index, offset: Double(value.translation.height),
                                                   rowHeight: Double(Self.rowHeight + Self.rowSpacing),
                                                   count: symbols.count)
                drag = nil
                if target != index, !isPreview { onMove(index, target) }
            }
    }

    // MARK: 持仓

    private func holdingButton(_ symbol: String, _ holding: StockBoard.Holding?) -> some View {
        let open = holdingSymbol == symbol
        return Button {
            if open {
                holdingSymbol = nil
            } else {
                sharesText = holding.map { StockBoard.numberText($0.shares) } ?? ""
                costText = holding?.cost.map(StockBoard.numberText) ?? ""
                holdingSymbol = symbol
            }
        } label: {
            Text(StockBoard.holdingLabel(holding))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white.opacity(holding == nil ? 0.7 : 0.95))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    if holding == nil {
                        Capsule().strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                    } else {
                        Capsule().fill(.white.opacity(open ? 0.24 : 0.14))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
        .help(tr("填持仓股数和成本价"))
    }

    private func holdingEditor(_ symbol: String) -> some View {
        let shares = StockBoard.number(sharesText)
        let costOK = costText.trimmingCharacters(in: .whitespaces).isEmpty
            || (StockBoard.number(costText).map { $0 > 0 } ?? false)
        let valid = (shares.map { $0 != 0 } ?? false) && costOK
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                field(tr("\(StockBoard.displaySymbol(symbol)) 股数"), text: $sharesText, prompt: "100")
                field(tr("成本价（可选）"), text: $costText, prompt: "238.00")
            }
            // 黄金白银切换单位时成本价不换算（用户定的），在这里说一声。
            if PreciousMetal.hasUnitSwitch(symbol) {
                Text(tr("切换单位时成本价不会换算"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if holdings?[symbol] != nil {
                    Button(tr("清除持仓")) {
                        onHolding(symbol, nil)
                        holdingSymbol = nil
                    }
                }
                Spacer(minLength: 0)
                Button(tr("取消")) { holdingSymbol = nil }
                Button(tr("保存")) { saveHolding(symbol) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.09)))
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TextField("", text: text, prompt: Text(verbatim: prompt))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13).monospacedDigit())
                .onSubmit { if let symbol = holdingSymbol { saveHolding(symbol) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveHolding(_ symbol: String) {
        guard let shares = StockBoard.number(sharesText), shares != 0 else { NSSound.beep(); return }
        let costRaw = costText.trimmingCharacters(in: .whitespaces)
        var cost: Double?
        if !costRaw.isEmpty {
            guard let value = StockBoard.number(costRaw), value > 0 else { NSSound.beep(); return }
            cost = value
        }
        onHolding(symbol, StockBoard.Holding(shares: shares, cost: cost))
        holdingSymbol = nil
    }
}
