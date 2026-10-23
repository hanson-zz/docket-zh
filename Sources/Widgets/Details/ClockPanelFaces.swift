import SwiftUI

// 八套时钟面板，跟着卡片的外观走（见 `ClockPanelKind`）。每套只有头部和主题
// 是自己的，下面的信息模块都是 `ClockPanelSections`。

/// 每套面板都拿这三样：这一秒的读数、能不能改城市、改了以后怎么写回。
struct ClockPanelInput {
    var model: ClockPanelModel
    var editable: Bool
    var onPick: (Int, WorldCity) -> Void
}

private extension ClockPanelModel {
    /// 此处现在是不是白天（06:00 到 18:00）。
    var isDayHere: Bool { ClockPanelData.isDaytime(hour: Calendar.current.component(.hour, from: now)) }

    var secondValue: Int { Int(digits.second) ?? 0 }

    /// “10月20日 星期二”。
    var monthDayWeekday: String {
        ClockPanelWeekday.monthDay(now, zone: .current) + " " + ClockPanelWeekday.of(now, zone: .current)
    }

    var lunarLine: String { tr("农历") + daily.lunar.date }
}

private let neonPink = Color(red: 1, green: 0.29, blue: 0.45)
private let neonTeal = Color(red: 0.3, green: 0.68, blue: 0.76)
private let neonGreen = Color(red: 0.45, green: 0.8, blue: 0.45)
private let neonAmber = Color(red: 0.95, green: 0.8, blue: 0.3)
private let nixieOrange = Color(red: 1, green: 0.6, blue: 0.16)

// MARK: - 像素

/// 点阵屏：点阵纹理底、大号点阵时间、主题色小点阵秒，冒号按奇偶秒闪，
/// 48 格今天进度。
struct PixelClockPanel: View {
    var input: ClockPanelInput

    private var theme: ClockPanelTheme {
        ClockPanelTheme(ink: .white.opacity(0.92), dim: .white.opacity(0.6), rule: .white.opacity(0.22),
                        tile: .white.opacity(0.05), tileStroke: .white.opacity(0.04),
                        accent: input.model.tint.accent(or: .orange),
                        lit: .white.opacity(0.88), unlit: .white.opacity(0.1),
                        figures: .pixel, bar: .cells(48), axis: true, dottedRule: true)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard {
            PixelGridBackdrop()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(model, theme)
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick)
            }
        }
    }

    private func header(_ model: ClockPanelModel, _ theme: ClockPanelTheme) -> some View {
        let d = model.digits
        let dot: CGFloat = 6.2
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                PanelPixelText(text: d.hour + ":" + d.minute, dot: dot, color: theme.ink, colonOn: model.colonOn)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: [d.meridiem, model.zoneLabel].compactMap { $0 }.joined(separator: " "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.dim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    PanelPixelText(text: ":" + d.second, dot: 3.1, color: theme.accent, colonOn: model.colonOn)
                }
            }
            .frame(height: dot * CGFloat(PixelFont.height))
            Text(verbatim: model.fullDate)
                .font(.system(size: 15))
                .foregroundStyle(theme.ink.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClockFormat.time(model.now, zone: .current) + ", " + model.fullDate)
    }
}

// MARK: - 液晶

/// 七段数码管，暗段留残影；墨色单色，不吃颜色面板的强调色（和液晶卡片一样）。
struct LCDClockPanel: View {
    var input: ClockPanelInput

    private let ink = Color(white: 0.1)

    private var theme: ClockPanelTheme {
        ClockPanelTheme(ink: ink, dim: ink.opacity(0.74), rule: ink.opacity(0.22),
                        tile: .clear, tileStroke: ink.opacity(0.35),
                        accent: ink.opacity(0.42), lit: ink, unlit: ink.opacity(0.08),
                        figures: .segment, bar: .cells(24), axis: true, accentTerm: false)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard(glows: false) {
            ZStack {
                SupporterClockFace.fill("lcd")
                // 液晶玻璃上一点点从上往下的反光。
                LinearGradient(colors: [.white.opacity(0.12), .clear, .black.opacity(0.05)],
                               startPoint: .top, endPoint: .bottom)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(model)
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick)
            }
        }
    }

    private func header(_ model: ClockPanelModel) -> some View {
        let d = model.digits
        let c = Calendar.current.dateComponents([.month, .day], from: model.now)
        let monthDay = String(format: "%02d-%02d", c.month ?? 1, c.day ?? 1)
        let day = model.isDayHere
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: d.weekday)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                SegmentText(text: monthDay, height: 15, ink: ink)
                Spacer(minLength: 4)
                // 液晶图标：有闹钟时闹钟亮，没有留残影；日月亮一个，另一个留残影。
                HStack(spacing: 3) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(tr("闹"))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(ink.opacity(model.alarm != nil ? 1 : 0.1))
                Image(systemName: "sun.max.fill").foregroundStyle(ink.opacity(day ? 1 : 0.1))
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "moon.fill").foregroundStyle(ink.opacity(day ? 0.1 : 1))
                    .font(.system(size: 12, weight: .semibold))
            }
            HStack(alignment: .bottom, spacing: 10) {
                SegmentText(text: d.hour + ":" + d.minute, height: 62, ink: ink, colonOn: model.colonOn)
                VStack(alignment: .leading, spacing: 6) {
                    Text(d.meridiem ?? tr("秒"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.74))
                    SegmentText(text: d.second, height: 26, ink: ink)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClockFormat.time(model.now, zone: .current) + ", " + model.fullDate)
    }
}

// MARK: - 经典

/// 原来的天空背景上加日出日落、昼长、今天进度、三张世界时钟小卡，
/// 时区和 UTC 合成一行。标准和大号数字的卡片开它。
struct ClassicClockPanel: View {
    var input: ClockPanelInput

    private var theme: ClockPanelTheme {
        let accent = input.model.tint.accent(or: .orange)
        // 液态玻璃：跟着浅色/深色走（ClockPanelCard(forceDark: false)）。
        return ClockPanelTheme(ink: .panelPrimary, dim: .panelSecondary, rule: .panelSeparator,
                               tile: .panelFill, tileStroke: .panelStroke,
                               accent: accent, lit: accent, unlit: .panelTrack,
                               figures: .rounded, bar: .line)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard(forceDark: false) {
            ClockPanelSky(now: model.now)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    ClockPanelTime(now: model.now, zone: .current, size: 50)
                    Text(verbatim: model.fullDate + " · " + model.lunarLine)
                        .font(.system(size: 14))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, 12)
                if let sun = model.daily.sun {
                    sunRow(sun)
                        // 留出天空里太阳那道弧的位置。
                        .padding(.top, 34)
                }
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick,
                                   cityCards: true, passedWording: true, extra: AnyView(zoneRow(model, theme)))
            }
        }
    }

    private func sunRow(_ sun: (rise: String, set: String, length: String)) -> some View {
        HStack(spacing: 6) {
            Text(tr("日出 \(sun.rise)"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
            Spacer(minLength: 4)
            Text(tr("昼长 \(sun.length)"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 4)
            Text(tr("日落 \(sun.set)"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func zoneRow(_ model: ClockPanelModel, _ theme: ClockPanelTheme) -> some View {
        HStack(spacing: 8) {
            Text(tr("时区"))
                .font(.system(size: 14))
                .foregroundStyle(theme.dim)
            Spacer(minLength: 6)
            Text(verbatim: ClockPanelFormat.zoneName(.current, at: model.now) + " · " + model.zoneLabel)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassPane(cornerRadius: 10)
    }
}

/// 经典面板的天空：上面是原来的天空（太阳在这个钟点的位置），往下接天空
/// 底边的颜色，卡片再长也不会把太阳那道弧拉到底。
struct ClockPanelSky: View {
    var now: Date

    @Environment(\.panelForcedDark) private var forcedDark
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        // 液态玻璃：往下接的底色和 SkyBackdrop 一样只是玻璃上一层淡色；
        // 保持暗色时还是压暗的实心天色。
        let base: Color = forcedDark
            ? (SkyBackdrop.palette(hour).last ?? MeshBackdrop.graphite)
            : (SkyBackdrop.rawPalette(hour).last ?? .clear).opacity(scheme == .light ? 0.26 : 0.38)
        ZStack(alignment: .top) {
            base
            SkyBackdrop(date: now, zone: .current)
                .frame(height: 240)
        }
    }
}

// MARK: - 模拟表盘

/// 头部一只大表盘（带秒针，秒针用强调色），旁边是星期、日期、数字时间和农历；
/// 世界时钟是三张带小表盘的卡片。模拟表盘和秒圈的卡片开它。
struct AnalogClockPanel: View {
    var input: ClockPanelInput

    @Environment(\.colorScheme) private var scheme

    private var theme: ClockPanelTheme {
        // 没选颜色时和卡片小表盘秒针同一个默认色（时钟琥珀，`ClockHands.defaultColor`），
        // 不再是系统橙。
        let accent = input.model.tint.accent(or: Color(code: ClockHands.defaultColor))
        // 液态玻璃：跟着浅色/深色走（ClockPanelCard(forceDark: false)）。
        return ClockPanelTheme(ink: .panelPrimary, dim: .panelSecondary, rule: .panelSeparator,
                               tile: .panelFill, tileStroke: .panelStroke,
                               accent: accent, lit: accent, unlit: .panelTrack,
                               figures: .rounded, bar: .line)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard(forceDark: false) {
            MeshBackdrop(color: .orange)
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    PanelDial(now: model.now, diameter: 112,
                              accent: model.secondHand.resolved(dark: scheme == .dark, on: .panel))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: ClockPanelWeekday.of(model.now, zone: .current))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                        Text(verbatim: ClockPanelWeekday.monthDay(model.now, zone: .current))
                            .font(.system(size: 14))
                            .foregroundStyle(theme.dim)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(verbatim: model.digits.hour.trimmingCharacters(in: .whitespaces) + ":" + model.digits.minute)
                                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.panelPrimary)
                            Text(verbatim: ":" + model.digits.second)
                                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(theme.accent.panelReadable)
                        }
                        .padding(.top, 2)
                        Text(verbatim: model.lunarLine)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.dim)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ClockFormat.time(model.now, zone: .current) + ", " + model.fullDate)
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick,
                                   cityCards: true, dials: true)
            }
        }
    }
}

/// 面板头部的大表盘：十二个刻度、12/3/6/9 四个数字、时分针，秒针和中心点用
/// 和卡片小表盘同一个来源的颜色（`ClockHands.source`，按面板底调明暗）。
struct PanelDial: View {
    var now: Date
    var diameter: CGFloat
    var accent: Color

    private var angles: (hour: Double, minute: Double, second: Double) {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let second = Double(c.second ?? 0)
        let minute = Double(c.minute ?? 0) + second / 60
        let hour = Double((c.hour ?? 0) % 12) + minute / 60
        return (hour / 12 * 360, minute / 60 * 360, second / 60 * 360)
    }

    var body: some View {
        let a = angles
        ZStack {
            Circle().fill(.panelFill)
            Circle().strokeBorder(.panelQuaternary, lineWidth: 1)
            ForEach(0..<60, id: \.self) { mark in
                let major = mark % 5 == 0
                Capsule()
                    .fill(major ? Color.panelSecondary : Color.panelQuaternary)
                    .frame(width: major ? 1.8 : 0.8, height: diameter * (major ? 0.07 : 0.035))
                    .offset(y: -diameter * 0.44)
                    .rotationEffect(.degrees(Double(mark) * 6))
            }
            ForEach([12, 3, 6, 9], id: \.self) { number in
                let angle = Double(number % 12) / 12 * 2 * Double.pi
                Text(verbatim: "\(number)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.panelSecondary)
                    .offset(x: sin(angle) * diameter * 0.31, y: -cos(angle) * diameter * 0.31)
            }
            hand(length: diameter * 0.24, width: 3, degrees: a.hour, color: .panelPrimary)
            hand(length: diameter * 0.36, width: 2, degrees: a.minute, color: .panelPrimary)
            hand(length: diameter * 0.4, width: 1, degrees: a.second, color: accent)
            Circle().fill(accent).frame(width: 5, height: 5)
        }
        .frame(width: diameter, height: diameter)
    }

    private func hand(length: CGFloat, width: CGFloat, degrees: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}

// MARK: - 翻页

/// 头部一排大翻页卡片：普通翻页、折叠翻页、大号带时分秒各按卡片的画法；
/// 小数字也画在小卡片上。翻页、折叠和大号带时分秒的卡片开它，Pro 样式没解锁时
/// 卡片画成翻页，也开它。
struct FlipClockPanel: View {
    var input: ClockPanelInput
    var face: ClockFace

    private var theme: ClockPanelTheme {
        ClockPanelTheme(ink: .white, dim: .white.opacity(0.62), rule: .white.opacity(0.1),
                        tile: .white.opacity(0.06), tileStroke: .white.opacity(0.08),
                        accent: input.model.tint.accent(or: .orange),
                        lit: .white.opacity(0.8), unlit: .white.opacity(0.1),
                        figures: .flip, bar: .cells(24), axis: true)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard {
            LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    cards(model, theme)
                        .frame(maxWidth: .infinity)
                    Text(verbatim: [model.monthDayWeekday, model.lunarLine, model.digits.meridiem]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ClockFormat.time(model.now, zone: .current) + ", " + model.fullDate)
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick)
            }
        }
    }

    @ViewBuilder
    private func cards(_ model: ClockPanelModel, _ theme: ClockPanelTheme) -> some View {
        let d = model.digits
        let hour = d.hour.trimmingCharacters(in: .whitespaces)
        switch face {
        case .bigFlipCards:
            HStack(alignment: .top, spacing: 10) {
                group(d.hour, label: tr("时"), ink: .white, theme)
                group(d.minute, label: tr("分"), ink: .white, theme)
                group(d.second, label: tr("秒"), ink: theme.accent, theme)
            }
        case .foldFlip:
            HStack(alignment: .bottom, spacing: 6) {
                FoldFlipText(text: (hour.count == 1 ? "0" + hour : hour) + ":" + d.minute, size: 46, maxWidth: 196)
                FoldFlipText(text: d.second, size: 24, maxWidth: 52)
            }
        default:
            HStack(spacing: 6) {
                PanelFlipCard(text: hour, size: 42, ink: .white)
                PanelFlipCard(text: d.minute, size: 42, ink: .white)
                PanelFlipCard(text: d.second, size: 42, ink: theme.accent)
            }
        }
    }

    private func group(_ pair: String, label: String, ink: Color, _ theme: ClockPanelTheme) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(Array(pair.enumerated()), id: \.offset) { _, ch in
                    DarkFlipCard(text: ch == " " ? "" : String(ch), width: 33, height: 50, ink: ink)
                }
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.dim)
        }
    }
}

/// 面板上的大号翻页卡片：和卡片上的 `FlipCard` 一个样子，多一个字色（秒数染强调色）。
struct PanelFlipCard: View {
    var text: String
    var size: CGFloat
    var ink: Color

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(ink)
            .padding(.horizontal, size * 0.18)
            .frame(height: size * 1.32)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .fill(.white.opacity(0.1))
                    Rectangle()
                        .fill(Color.black.opacity(0.28))
                        .frame(height: 1)
                }
            }
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: text)
    }
}

// MARK: - 中文

/// 大号中文报时（“九点五十七分”），农历年月日和节气放在显眼处，衬线字，
/// 暖色的墨和朱砂。中文样式的卡片开它。
struct WordsClockPanel: View {
    var input: ClockPanelInput

    private static let paper = Color(red: 0.95, green: 0.92, blue: 0.86)

    private var theme: ClockPanelTheme {
        let ink = Self.paper
        return ClockPanelTheme(ink: ink, dim: ink.opacity(0.64), rule: ink.opacity(0.14),
                               tile: .white.opacity(0.04), tileStroke: ink.opacity(0.1),
                               accent: input.model.tint.accent(or: Color(red: 0.9, green: 0.42, blue: 0.32)),
                               lit: ink.opacity(0.75), unlit: ink.opacity(0.1),
                               figures: .serif, bar: .line, design: .serif)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard {
            LinearGradient(colors: [Color(red: 0.16, green: 0.145, blue: 0.13), Color(red: 0.09, green: 0.085, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(model, theme)
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick,
                                   showsLunar: false)
            }
        }
    }

    private func header(_ model: ClockPanelModel, _ theme: ClockPanelTheme) -> some View {
        let c = Calendar.current.dateComponents([.hour, .minute], from: model.now)
        let said = ChineseTimeText.say(hour: c.hour ?? 0, minute: c.minute ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: said.period + " · " + ClockPanelWeekday.of(model.now, zone: .current))
                    .font(theme.font(15))
                    .foregroundStyle(theme.dim)
                Spacer(minLength: 6)
                Text(verbatim: ChineseTimeText.number(model.secondValue) + "秒")
                    .font(theme.font(15))
                    .foregroundStyle(theme.accent)
            }
            Text(verbatim: said.time)
                .font(theme.font(36, .medium))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: said.time)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: model.daily.lunarYear + " " + model.daily.lunar.date)
                    .font(theme.font(17, .semibold))
                    .foregroundStyle(theme.ink.opacity(0.92))
                if let term = model.daily.lunar.term {
                    Text(term)
                        .font(theme.font(14))
                        .foregroundStyle(theme.accent)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.top, 2)
            Text(verbatim: model.fullDate)
                .font(theme.font(14))
                .foregroundStyle(theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 霓虹（Pro）

/// 暗底上的霓虹数字，光晕只贴着字和细框，不往外铺。霓虹卡片开它。
struct NeonClockPanel: View {
    var input: ClockPanelInput

    private var theme: ClockPanelTheme {
        ClockPanelTheme(ink: .white.opacity(0.9), dim: .white.opacity(0.6), rule: neonTeal.opacity(0.28),
                        tile: .clear, tileStroke: neonTeal.opacity(0.35),
                        accent: input.model.tint.accent(or: neonPink),
                        lit: neonTeal, unlit: neonTeal.opacity(0.12),
                        figures: .neon, figureInk: neonTeal, bar: .cells(24), axis: true,
                        glow: neonTeal, accentTerm: false)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard {
            SupporterClockFace.fill("neon")
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(model, theme)
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick)
            }
        }
    }

    private func header(_ model: ClockPanelModel, _ theme: ClockPanelTheme) -> some View {
        let d = model.digits
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: d.hour.trimmingCharacters(in: .whitespaces) + ":" + d.minute)
                    .font(.system(size: 54, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(neonPink)
                    .clockPanelGlow(neonPink, 6)
                Text(verbatim: d.second)
                    .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.accent)
                    .clockPanelGlow(theme.accent, 4)
                if let meridiem = d.meridiem {
                    Text(verbatim: meridiem)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(neonAmber)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Capsule().fill(neonTeal).frame(height: 1).clockPanelGlow(neonTeal, 2)
            HStack(spacing: 0) {
                Text(verbatim: ClockPanelWeekday.monthDay(model.now, zone: .current))
                    .foregroundStyle(neonGreen)
                Spacer(minLength: 6)
                Text(verbatim: model.lunarLine)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 6)
                Text(verbatim: d.weekday)
                    .foregroundStyle(neonAmber)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(neonTeal.opacity(0.85), lineWidth: 1)
                .clockPanelGlow(neonTeal, 3)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClockFormat.time(model.now, zone: .current) + ", " + model.fullDate)
    }
}

// MARK: - 实景（Pro）

/// 辉光管：头部一排暖橙的管子（时、分、秒），秒数那两支跟着强调色。实景卡片开它。
struct NixieClockPanel: View {
    var input: ClockPanelInput

    private static let warm = Color(red: 1, green: 0.88, blue: 0.74)

    private var theme: ClockPanelTheme {
        ClockPanelTheme(ink: Self.warm.opacity(0.94), dim: Self.warm.opacity(0.6), rule: nixieOrange.opacity(0.18),
                        tile: .white.opacity(0.04), tileStroke: nixieOrange.opacity(0.16),
                        accent: input.model.tint.accent(or: nixieOrange),
                        lit: nixieOrange.opacity(0.75), unlit: nixieOrange.opacity(0.1),
                        figures: .nixie, figureInk: nixieOrange, bar: .cells(24), axis: true, accentTerm: false)
    }

    var body: some View {
        let theme = self.theme
        let model = input.model
        ClockPanelCard {
            ZStack {
                SupporterClockFace.fill("nixie")
                RadialGradient(colors: [nixieOrange.opacity(0.08), .clear], center: .top, startRadius: 0, endRadius: 220)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(model, theme)
                ClockPanelSections(model: model, theme: theme, editable: input.editable, onPick: input.onPick)
            }
        }
    }

    private func header(_ model: ClockPanelModel, _ theme: ClockPanelTheme) -> some View {
        let d = model.digits
        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                tubes(d.hour, color: nixieOrange)
                NixieColon(height: 48).frame(width: 12)
                tubes(d.minute, color: nixieOrange)
                NixieColon(height: 48).frame(width: 12)
                tubes(d.second, color: theme.accent)
            }
            .frame(maxWidth: .infinity)
            Text(verbatim: [model.fullDate, model.lunarLine, d.meridiem].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 14))
                .foregroundStyle(theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClockFormat.time(model.now, zone: .current) + ", " + model.fullDate)
    }

    private func tubes(_ pair: String, color: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(pair.enumerated()), id: \.offset) { _, ch in
                NixieTube(digit: ch == " " ? nil : String(ch), width: 33, height: 56, orange: color)
            }
        }
    }
}
