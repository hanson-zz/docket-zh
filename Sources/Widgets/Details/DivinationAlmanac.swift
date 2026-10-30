import SwiftUI

// MARK: - 卜卦 · 签题、分项解读和真实黄历
//
// 每日一签页用到的三块：签题（典故，英文界面下面加意译）、五项分项解读（家宅、求财、婚姻、出行、
// 事业，可折叠）、黄历（Core 的 ChineseAlmanac：农历、干支、生肖、节气、建除、星宿、宜忌）。
// 面板、签历、签卡、桌面卡片共用这里的写法。字都不小于 13pt，长的折行不截断。

/// 签题：宋体签题，英文界面下面一行英文意译。
struct DivinationStickTitle: View {
    var stick: FortuneStick
    var size: CGFloat = 16

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: stick.title)
                .font(.custom("Songti SC", size: size).weight(.bold))
                .foregroundStyle(DivinationStyle.goldText)
            if L10n.isEnglish {
                Text(verbatim: stick.englishTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 五项分项解读，标题一行可点开 / 收起（默认收起，面板短一点）。
struct DivinationAspectsSection: View {
    var stick: FortuneStick
    @State private var expanded = false

    var body: some View {
        let aspects = stick.localizedAspects.all
        let titles = StickAspects.titles
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(tr("分项解读"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                    Spacer(minLength: 4)
                    Text(expanded ? tr("收起") : tr("展开"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("分项解读"))
            .accessibilityValue(expanded ? tr("收起") : tr("展开"))
            if expanded {
                ForEach(Array(zip(titles, aspects).enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: pair.0)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DivinationStyle.red)
                            .fixedSize()
                        Text(verbatim: pair.1)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.panelStroke, lineWidth: 0.5))
    }
}

/// 面板里的黄历块：农历和生肖年、节气、干支年月日、建除和值日星宿、宜忌。
struct DivinationAlmanacBox: View {
    var date: Date

    var body: some View {
        let day = ChineseAlmanac.day(date)
        let english = L10n.isEnglish
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tr("今日黄历"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DivinationStyle.red)
                Spacer(minLength: 4)
                if let term = day.termText(english: english) {
                    Text(verbatim: term)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DivinationStyle.goldText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DivinationStyle.gold.opacity(0.14)))
                        .fixedSize()
                }
            }
            line(day.lunarLine(english: english), weight: .semibold)
            line(day.ganzhiLine(english: english))
            line(day.dutyLine(english: english))
            words(tr("宜"), day.goodWords(english: english), tint: DivinationStyle.red)
            words(tr("忌"), day.badWords(english: english), tint: Color.panelPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private func line(_ text: String, weight: Font.Weight = .regular) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: weight))
            .foregroundStyle(weight == .regular ? Color.panelSecondary : Color.panelPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func words(_ label: String, _ list: [String], tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .fixedSize()
            Text(verbatim: list.joined(separator: L10n.isEnglish ? ", " : " "))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 卡片上的一行宜忌：放得下就多写几个，放不下逐个减，最后只写一个宜（不缩字）；还放不下写省略号。
struct DivinationYiJiLine: View {
    var date: Date
    /// 依次尝试的（宜几个、忌几个）。
    var attempts: [(Int, Int)] = [(3, 2), (2, 2), (2, 1), (1, 1), (1, 0)]
    var showsLunar = false

    var body: some View {
        let day = ChineseAlmanac.day(date)
        let english = L10n.isEnglish
        ViewThatFits(in: .horizontal) {
            ForEach(Array(attempts.enumerated()), id: \.offset) { _, attempt in
                text(day, attempt.0, attempt.1, english: english, lunar: showsLunar)
            }
            if showsLunar {
                ForEach(Array(attempts.enumerated()), id: \.offset) { _, attempt in
                    text(day, attempt.0, attempt.1, english: english, lunar: false)
                }
            }
            // 最后一档还放不下（英文长词，比如中号签那列 128 宽放「Do: Mourning clothes removal」）：
            // 写省略号收在这一行里，不再整行撑出卡片被裁掉。
            if let last = attempts.last {
                text(day, last.0, last.1, english: english, lunar: false, fits: false)
            }
        }
    }

    /// `fits` 为 false 是最后的兜底：不撑宽，放不下写省略号。
    private func text(_ day: ChineseAlmanac.Day, _ good: Int, _ bad: Int, english: Bool, lunar: Bool,
                      fits: Bool = true) -> some View {
        let yiJi = day.yiJiLine(goodCount: good, badCount: bad, goodLabel: tr("宜"), badLabel: tr("忌"),
                                english: english)
        let prefix = lunar ? day.shortLunar(english: english) + (english ? " · " : "  ") : ""
        return Text(verbatim: prefix + yiJi)
            .font(.system(size: 13))
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: fits, vertical: false)
    }
}
