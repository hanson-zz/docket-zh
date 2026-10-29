import SwiftUI

// MARK: - 卜卦 · 面板
//
// 液态玻璃面板 340 宽（和同组的扫雷、拔牙一样），里面所有东西都按卡片真实内容宽
// （Divination.panelContentWidth，340 是 266）排，不会把整列撑宽、被面板裁掉右边。
// 顶上三段切换（每日一签 / 起卦 / 解忧书）和音效开关，底下一行「仅供娱乐」。
// 不铺背景色、不发光：颜色只在签级、卦辞、变爻红点、主按钮和金色点缀上。
// 「减少动态效果」打开时签筒不抖、龟壳不晃不翻、铜钱不弹、书页不翻，直接出结果。

struct DivinationDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: DivinationPage?
    // 每日一签
    @State private var tubeShakes = 0
    @State private var dropStick = false
    @State private var stickBusy = false
    // 起卦
    @State private var question = ""
    @State private var shellPhase: PandaWithShell.Phase = .idle
    @State private var shellShakes = 0
    @State private var coinDrops = 0
    @State private var castBusy = false
    @State private var viewing: Casting?
    @State private var showHistory = false
    // 解忧书
    @State private var bookQuestion = ""
    @State private var bookFlips = 0
    @State private var bookBusy = false

    private static let width = CGFloat(Divination.panelContentWidth)

    private var config: WidgetConfig { instance.config }
    private var currentPage: DivinationPage {
        page ?? (context.isPreview ? .stick : Divination.page(config))
    }
    private var soundOn: Bool { context.isPreview ? true : Divination.soundOn(config) }

    var body: some View {
        DetailCard {
            Color.clear
        } content: {
            VStack(spacing: 12) {
                header
                Group {
                    switch currentPage {
                    case .stick: stickPage
                    case .coins: coinsPage
                    case .book: bookPage
                    }
                }
                .frame(width: Self.width)
                Text(tr("仅供娱乐"))
                    .font(.system(size: CGFloat(Divination.disclaimerFont)))
                    .foregroundStyle(Color.panelTertiary)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: Self.width)
        }
    }

    // MARK: 顶上

    private var header: some View {
        HStack(spacing: 8) {
            segmented
            ToothRoundButton(symbol: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             diameter: 30, help: soundOn ? tr("音效：开") : tr("音效：关")) {
                guard !context.isPreview else { return }
                DivinationPlay.toggleSound(in: instance)
            }
        }
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(DivinationPage.allCases, id: \.self) { item in
                let selected = item == currentPage
                Button {
                    page = item
                    guard !context.isPreview else { return }
                    DivinationPlay.setPage(item, in: instance)
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: selected ? .bold : .semibold))
                        .foregroundStyle(selected ? Color.panelPrimary : Color.panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if selected { Capsule().fill(Color.panelRaised).panelLift() }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.panelFill))
        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .frame(maxWidth: .infinity)
    }

    // MARK: 每日一签

    private var todayIndex: Int? {
        context.isPreview ? 36 : Divination.todayStick(config, now: context.now)
    }

    private var stickPage: some View {
        let index = stickBusy ? nil : todayIndex
        return VStack(spacing: 10) {
            PandaWithTube(size: 120, shakes: tubeShakes, drop: dropStick, cheering: index != nil)
                .frame(maxWidth: .infinity)
            if let index {
                stickResult(index)
            } else {
                Text(stickBusy ? tr("沙沙沙……") : tr("诚心默念，摇出今天的一签"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                DivinationPrimaryButton(title: tr("摇一摇"), enabled: !stickBusy) { shake() }
            }
        }
    }

    private func stickResult(_ index: Int) -> some View {
        let stick = FortuneStick.all[index]
        return VStack(spacing: 8) {
            Text(verbatim: Divination.stickNumber(index))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
            StickLevelBanner(level: stick.level, size: 34)
            VStack(spacing: 3) {
                ForEach(stick.poemLines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.custom("Songti SC", size: 17).weight(.semibold))
                        .foregroundStyle(Color.panelPrimary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                labeled(tr("今日宜："), stick.good, tint: DivinationStyle.red)
                labeled(tr("今日忌："), stick.avoid, tint: Color.panelPrimary)
                Text(verbatim: stick.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.panelStroke, lineWidth: 0.5))
            DivinationGlassButton(title: tr("今天已抽 · 明天再来")) {
                guard !context.isPreview else { return }
                DivinationPlay.play(.tick, for: instance)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func labeled(_ label: String, _ value: String, tint: Color) -> some View {
        (Text(label).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
            + Text(verbatim: value).font(.system(size: 14)).foregroundStyle(Color.panelPrimary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shake() {
        guard !context.isPreview, !stickBusy else { return }
        if todayIndex != nil { return }
        if reduceMotion {
            DivinationPlay.drawStick(in: instance)
            DivinationPlay.play(.tick, for: instance)
            return
        }
        stickBusy = true
        tubeShakes += 1
        DivinationPlay.play(.rattle, for: instance)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(860))
            dropStick = true
            DivinationPlay.play(.tick, for: instance)
            try? await Task.sleep(for: .milliseconds(450))
            DivinationPlay.drawStick(in: instance)
            dropStick = false
            stickBusy = false
        }
    }

    // MARK: 起卦

    private var current: Casting {
        if context.isPreview { return DivinationSamples.casting }
        return Divination.casting(config)
    }

    private var shown: Casting { viewing ?? current }

    private var coinsPage: some View {
        let casting = shown
        return VStack(spacing: 10) {
            if viewing == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("心里想问的事（可不填）"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                    questionField($question)
                }
            } else {
                viewingBar(casting)
            }
            PandaWithShell(size: 92, phase: shellPhase, shakes: shellShakes)
                .frame(maxWidth: .infinity)
            CoinRow(faces: casting.tosses.last, size: 34, drops: coinDrops)
                .frame(maxWidth: .infinity)
            Text(Divination.castingSummary(casting))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
            figures(casting)
            if let primary = casting.primary { reading(casting, primary: primary) }
            if viewing == nil { castButtons(casting) }
            historySection
        }
    }

    private func questionField(_ text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(tr("比如：这个月换工作合适吗")))
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(Color.panelPrimary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .glassPane(cornerRadius: 10)
            .onChange(of: text.wrappedValue) { _, value in
                if value.count > Divination.questionLimit {
                    text.wrappedValue = String(value.prefix(Divination.questionLimit))
                }
            }
    }

    private func viewingBar(_ casting: Casting) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.timeText(casting.time))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                Text(casting.question.isEmpty ? tr("没写问题") : casting.question)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(tr("回到当前")) { viewing = nil }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DivinationStyle.red)
        }
    }

    private func figures(_ casting: Casting) -> some View {
        let changing = Set(casting.changingIndices)
        return HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 6) {
                HexagramFigure(yang: casting.lines.map(\.isYang), changing: changing,
                               width: 64, lineHeight: 8, spacing: 5)
                Text(tr("本卦"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
            }
            if let changed = casting.changed {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .padding(.bottom, 18)
                VStack(spacing: 6) {
                    HexagramFigure(yang: changed.yang, faded: true, width: 64, lineHeight: 8, spacing: 5)
                    Text(tr("变卦"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(casting))
    }

    private func accessibility(_ casting: Casting) -> String {
        guard let primary = casting.primary else { return Divination.castingSummary(casting) }
        if let changed = casting.changed { return "\(primary.fullName) → \(changed.fullName)" }
        return primary.fullName
    }

    private func reading(_ casting: Casting, primary: Hexagram) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: casting.changed.map { "\(primary.fullName) → \($0.fullName)" } ?? primary.fullName)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: "第\(Divination.chineseNumber(primary.number))卦 \(primary.symbol)")
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
            Text(verbatim: "\(primary.name)：\(primary.judgment)")
                .font(.custom("Songti SC", size: 15).weight(.semibold))
                .foregroundStyle(DivinationStyle.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(casting.changingTexts, id: \.self) { text in
                Text(verbatim: text)
                    .font(.custom("Songti SC", size: 14))
                    .foregroundStyle(Color.panelPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 4) {
                Text(verbatim: primary.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                if let changed = casting.changed {
                    Text(verbatim: tr("往后看：") + changed.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.panelStroke, lineWidth: 0.5))
        }
    }

    private func castButtons(_ casting: Casting) -> some View {
        let title: String
        if casting.isComplete {
            title = tr("再起一卦")
        } else if casting.count == 0 {
            title = tr("起卦")
        } else {
            title = tr("摇第 \(casting.count + 1) 爻")
        }
        return HStack(spacing: 8) {
            DivinationPrimaryButton(title: title, enabled: !castBusy) { cast(all: false) }
            DivinationGlassButton(title: tr("一次起完")) { cast(all: true) }
                .frame(width: 92)
                .disabled(castBusy)
                .help(tr("剩下的几爻一次摇完"))
        }
    }

    private func cast(all: Bool) {
        guard !context.isPreview, !castBusy else { return }
        viewing = nil
        if reduceMotion {
            DivinationPlay.toss(in: instance, question: question, all: all)
            DivinationPlay.play(.clink, for: instance)
            return
        }
        castBusy = true
        shellPhase = .shaking
        shellShakes += 1
        DivinationPlay.play(.jingle, for: instance)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(all ? 420 : 680))
            DivinationSoundPlayer.stop(.jingle)
            shellPhase = .pouring
            DivinationPlay.toss(in: instance, question: question, all: all)
            coinDrops += 1
            DivinationPlay.play(.clink, for: instance)
            try? await Task.sleep(for: .milliseconds(620))
            shellPhase = .idle
            castBusy = false
        }
    }

    private var historyItems: [Casting] {
        context.isPreview ? [] : Divination.history(config)
    }

    @ViewBuilder private var historySection: some View {
        let items = historyItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    showHistory.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(tr("最近记录"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "\(items.count)")
                            .font(.system(size: 13))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.panelSecondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if showHistory {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        historyRow(item)
                    }
                    Button(tr("清空记录")) {
                        DivinationPlay.clearHistory(in: instance)
                        viewing = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                }
            }
            .padding(.top, 2)
        }
    }

    private func historyRow(_ item: Casting) -> some View {
        Button {
            viewing = item
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.question.isEmpty ? tr("没写问题") : item.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                    Text(Self.timeText(item.time))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelTertiary)
                }
                Spacer(minLength: 4)
                Text(verbatim: [item.primary?.name, item.changed?.name].compactMap { $0 }.joined(separator: "→"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DivinationStyle.red)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(viewing == item ? Color.panelSelected : Color.panelFill))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private static func timeText(_ time: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.interfaceLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }

    // MARK: 解忧书

    private var lastPage: Int? {
        if context.isPreview { return 0 }
        return Divination.lastPage(config)
    }

    private var bookPage: some View {
        VStack(spacing: 10) {
            Text(tr("心里默想一个问题"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.panelPrimary)
            questionField($bookQuestion)
            ZStack(alignment: .top) {
                DivinationPanda(name: "pet-panda-cheer", size: 64)
                OpenBook(width: 226, flips: bookFlips)
                    .padding(.top, 48)
            }
            .frame(maxWidth: .infinity)
            answer
                .frame(minHeight: 92)
            DivinationPrimaryButton(title: tr("翻一页"), enabled: !bookBusy) { flip() }
        }
    }

    @ViewBuilder private var answer: some View {
        if let index = lastPage, !bookBusy {
            let parts = WorryBook.split(WorryBook.answers[index])
            VStack(spacing: 2) {
                Text(verbatim: parts.first)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(parts.second == nil ? DivinationStyle.red : Color.panelPrimary)
                if let second = parts.second {
                    Text(verbatim: second)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(DivinationStyle.red)
                }
                Text(tr("第 \(index + 1) 页"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        } else {
            Text(bookBusy ? tr("哗啦……") : tr("想好了，就翻开看看"))
                .font(.system(size: 15))
                .foregroundStyle(Color.panelSecondary)
        }
    }

    private func flip() {
        guard !context.isPreview, !bookBusy else { return }
        DivinationPlay.play(.page, for: instance)
        if reduceMotion {
            DivinationPlay.turnPage(in: instance)
            return
        }
        bookBusy = true
        bookFlips += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            DivinationPlay.turnPage(in: instance)
            withAnimation(.easeOut(duration: 0.2)) { bookBusy = false }
        }
    }
}

/// 小组件库和截图里的示例：泰卦九三变成临卦（固定的一卦）。
enum DivinationSamples {
    static let casting: Casting = {
        let yang = [true, true, true], young = [true, true, false], yin = [true, false, false]
        return Casting(question: "", time: 1_800_000_000, tosses: [young, young, yang, yin, yin, yin])
    }()
}
