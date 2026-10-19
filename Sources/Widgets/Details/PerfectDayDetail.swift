import AppKit
import SwiftUI

/// 小熊猫的竹篮的面板，和月度分享图用同一套竹篮、竹叶和日历：标题里直接
/// 左右切月，今天三项（缺的项目给一个小胶囊），竹篮当主角配三档图例，一句
/// 「已过 N 天 · 收到 M 片」，日历，底部固定两个按钮：徽章（点开是码头木牌
/// 徽章和规则）和分享这个月。
struct PerfectDayDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    /// Months back from this one; 0 is the current month.
    @State private var monthsBack = 0
    @State private var anchor = ShareAnchorBox()
    @State private var notice: String?
    @State private var showBadges = false

    /// As far back as the history is kept.
    private static let maxMonthsBack = 26
    /// 分享按钮的颜色，和设计稿、分享图右上角的暖光同一个小熊猫橙。
    private static let shareHex = "#C0502A"

    private var center: PerfectDayCenter { .shared }
    private var calendar: Calendar { PerfectDay.calendar }

    /// The week starts where the Mac's own settings start it.
    private var firstWeekday: Int { Calendar.autoupdatingCurrent.firstWeekday }

    private var month: Date {
        calendar.date(byAdding: .month, value: -monthsBack, to: context.now) ?? context.now
    }

    private var records: [PerfectDayRecord] {
        context.isPreview ? PerfectDay.sample(today: context.now) : center.records(now: context.now)
    }

    private var today: [PerfectDayProgress] {
        context.isPreview ? PerfectDayCenter.sampleProgress : center.progress(now: context.now)
    }

    var body: some View {
        let all = records
        let items = today
        let shownMonth = month
        let got = PerfectDay.leavesSoFar(all, month: shownMonth, today: context.now)
        return DetailCard {
            BasketForestBackdrop(bambooHeight: 92)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(month: shownMonth, cheer: got > 0)
                        todaySection(items)
                        basketSection(all, month: shownMonth, got: got)
                        statusLine(all, month: shownMonth)
                        PerfectCalendarGrid(
                            weeks: PerfectDay.monthGrid(all, month: shownMonth, today: context.now,
                                                        firstWeekday: firstWeekday),
                            weekdays: PerfectDay.weekdaySymbols(firstWeekday: firstWeekday),
                            leafSize: 18, shareStyle: true)
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: 580)
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                // 底部两个按钮在滚动区外面，内容再长也一直在。
                bottomBar(all, month: shownMonth)
            }
        }
        .onAppear { if !context.isPreview { center.refresh(now: context.now) } }
    }

    // MARK: Header

    private func header(month: Date, cheer: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("小熊猫的竹篮")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 4) {
                    Button { monthsBack = min(Self.maxMonthsBack, monthsBack + 1) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 18, height: 26)
                            .contentShape(.rect)
                    }
                    .disabled(monthsBack >= Self.maxMonthsBack)
                    .help("上个月")
                    Text(PerfectDay.panelMonthTitle(month))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Button { monthsBack = max(0, monthsBack - 1) } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 18, height: 26)
                            .contentShape(.rect)
                    }
                    .disabled(monthsBack == 0)
                    .opacity(monthsBack == 0 ? 0.35 : 1)
                    .help("下个月")
                    // 只有不在本月时才有，整个面板就这一个。
                    if monthsBack != 0 {
                        Button { monthsBack = 0 } label: {
                            Text("回到本月")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.white.opacity(0.14)))
                        }
                        .padding(.leading, 4)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            BasketPanda(cheer: cheer, height: 70)
                .padding(.top, -6)
        }
    }

    // MARK: Today

    @ViewBuilder
    private func todaySection(_ items: [PerfectDayProgress]) -> some View {
        if items.isEmpty {
            // 一个来源小组件都没有：照旧给小熊猫空状态，点一下去添加小组件。
            PandaEmptyState(empty: .basket, title: tr("添加小组件"), panel: true) {
                guard !context.isPreview else { return }
                LibraryWindow.shared.openFromEmptyState()
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("今天")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 8) {
                    ForEach(items) { item in todayCard(item) }
                }
            }
        }
    }

    private func todayCard(_ item: PerfectDayProgress) -> some View {
        let tint = Color(hex: item.item.hex)
        return VStack(spacing: 5) {
            PerfectItemRing(progress: item, size: 28, track: .white)
            Text(item.item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            if let fix = PerfectDay.fix(for: item) {
                Button { open(fix, for: item.item) } label: {
                    Text(fix.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.2)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(item.detail)
            } else {
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.vertical, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .glassPane(cornerRadius: 10)
    }

    /// 没设习惯：有习惯打卡小组件就打开它的面板去新建，没有就去添加小组件；
    /// 没放喝水或专注计时：去添加小组件。
    private func open(_ fix: PerfectDayFix, for item: PerfectDayItem) {
        guard !context.isPreview else { return }
        if fix == .newHabit, let habit = center.widgets().first(where: { $0.kind == .habit }) {
            WidgetPanelOpener.shared.open(habit.id)
        } else {
            LibraryWindow.shared.openFromEmptyState()
        }
    }

    // MARK: Basket

    private func basketSection(_ all: [PerfectDayRecord], month: Date, got: Int) -> some View {
        let counts = PerfectDay.counts(all, month: month)
        let leaves = PerfectDay.leaves(all, month: month)
        return HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 6) {
                BambooBasket(leaves: got == 0 ? [] : leaves, width: 150, emptyText: nil, heapAtRim: true)
                Text(PerfectDay.basketCaption(leaves: got))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .fixedSize()
            }
            legend(counts)
        }
    }

    /// 三档各一行：竹叶、名字、拿叶条件和 ×N，0 片时整行淡下去。
    private func legend(_ counts: [PerfectDayTier: Int]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(PerfectDay.legendLines) { line in
                let count = counts[line.tier] ?? 0
                HStack(spacing: 8) {
                    LeafGlyph(tier: line.tier, size: 24)
                        .opacity(count == 0 ? 0.6 : 1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(line.tier.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(line.condition)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text("×\(count)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(count == 0 ? Color.white.opacity(0.3) : Color(hex: line.tier.hexes.light))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statusLine(_ all: [PerfectDayRecord], month: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
            Text(PerfectDay.shareStatus(all, month: month, today: context.now))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: Bottom bar

    private func badgeStatuses(_ all: [PerfectDayRecord]) -> [PerfectBadgeStatus] {
        PerfectBadges.statuses(records: all,
                               input: context.isPreview ? PerfectBadgeInput(focusMinutes: 900) : center.badgeInput(),
                               earned: context.isPreview ? [:] : center.archive.earned,
                               years: context.isPreview ? [:] : center.archive.festivalYears,
                               today: context.now)
    }

    private func bottomBar(_ all: [PerfectDayRecord], month: Date) -> some View {
        let statuses = badgeStatuses(all)
        let unlocked = statuses.filter(\.unlocked).count
        // 空月（到今天一片都没有）不分享：按钮置灰，写上先去拿第一片。
        let blocked = PerfectDay.shareBlockedHint(all, month: month, today: context.now)
        return VStack(spacing: 6) {
            if let notice {
                Text(notice)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            HStack(spacing: 10) {
                Button { showBadges.toggle() } label: {
                    Text(tr("徽章 \(unlocked) / \(statuses.count)"))
                        .monospacedDigit()
                }
                .buttonStyle(BasketBarButtonStyle(fill: .white.opacity(0.1), stroke: .white.opacity(0.12)))
                .popover(isPresented: $showBadges, arrowEdge: .top) {
                    badgePopover(statuses)
                }
                Button { share(all, month: month) } label: {
                    Text(blocked ?? (monthsBack == 0 ? tr("分享这个月") : tr("分享这个月的竹篮")))
                }
                .buttonStyle(BasketBarButtonStyle(fill: blocked == nil ? panelTint.accent(or: Color(hex: Self.shareHex))
                                                                         : .white.opacity(0.05),
                                                  stroke: .white.opacity(blocked == nil ? 0 : 0.1),
                                                  ink: blocked == nil ? panelTint.ink(or: .white) : .white,
                                                  dimmed: blocked != nil))
                .background(ShareAnchor(box: anchor))
                .disabled(context.isPreview || blocked != nil)
                .help(blocked == nil ? tr("分享这个月") : tr("收到第一片竹叶后就能分享"))
                .contextMenu {
                    Button("分享…") { share(all, month: month) }
                    Button("存储到桌面") { saveToDesktop(all, month: month) }
                    Button("拷贝图片") { copy(all, month: month) }
                }
                // 看得见的「…」：存储到桌面、拷贝图片不只藏在右键里。
                Menu {
                    Button("存储到桌面") { saveToDesktop(all, month: month) }
                    Button("拷贝图片") { copy(all, month: month) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(blocked == nil ? 0.85 : 0.35))
                        .frame(width: 34, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.12)))
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(context.isPreview || blocked != nil)
                .help(tr("存储到桌面或拷贝图片"))
            }
        }
    }

    // MARK: Badges

    /// 徽章弹层：原来面板底部的码头木牌徽章，按分类分组，下面是怎么算。
    private func badgePopover(_ statuses: [PerfectBadgeStatus]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("徽章 \(statuses.filter(\.unlocked).count) / \(statuses.count)"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                ForEach(PerfectBadges.grouped(statuses)) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.category.title) \(group.statuses.filter(\.unlocked).count)/\(group.statuses.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        badgeGrid(group.statuses)
                    }
                }
                rules
            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
        .frame(width: 380, height: 520)
        .background(LinearGradient(colors: [Color(hex: "#1F3A26"), Color(hex: "#101C15")],
                                   startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
    }

    private func badgeGrid(_ statuses: [PerfectBadgeStatus]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4),
                  spacing: 12) {
            ForEach(statuses) { status in
                VStack(spacing: 4) {
                    PerfectBadgeMedal(status: status, size: 54)
                    Text(status.shownTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(status.isLit ? 1 : 0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(badgeLine(status))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(status.shownCondition)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// 已解锁写日期；隐藏徽章只给提示，不露进度；其他写条件和进度。
    private func badgeLine(_ status: PerfectBadgeStatus) -> String {
        if let line = status.festivalLine { return line }
        if status.unlocked { return earnedLine(status) }
        if status.isConcealed { return status.shownCondition }
        return "\(status.shownCondition)\n\(status.progressText)"
    }

    private func earnedLine(_ status: PerfectBadgeStatus) -> String {
        guard let key = status.earnedOn, let date = HabitTracker.date(fromKey: key) else { return tr("已解锁") }
        let c = calendar.dateComponents([.month, .day], from: date)
        return tr("\(c.month ?? 0)月\(c.day ?? 0)日解锁")
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("怎么算")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(PerfectDay.rules(focusGoal: context.isPreview ? FocusLog.defaultGoal : center.focusGoal()))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sharing

    private func image(_ all: [PerfectDayRecord], month: Date) -> (NSImage, Data)? {
        PerfectDayShareImage.render(records: all, month: month, today: context.now, firstWeekday: firstWeekday)
    }

    private func fileName(_ month: Date) -> String {
        tr("码头竹篮-\(PerfectDay.monthTitle(month)).png")
    }

    private func share(_ all: [PerfectDayRecord], month: Date) {
        guard let png = image(all, month: month)?.1 else { return say(tr("图片生成失败")) }
        let url = FileManager.default.temporaryDirectory.appending(path: fileName(month))
        do { try png.write(to: url, options: .atomic) } catch { return say(tr("图片生成失败")) }
        let picker = NSSharingServicePicker(items: [url])
        if let view = anchor.view, view.window != nil {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                        of: view, preferredEdge: .minY)
        }
    }

    private func saveToDesktop(_ all: [PerfectDayRecord], month: Date) {
        guard let png = image(all, month: month)?.1,
              let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        else { return say(tr("图片生成失败")) }
        var url = desktop.appending(path: fileName(month))
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appending(path: tr("码头竹篮-\(PerfectDay.monthTitle(month)) \(n).png"))
            n += 1
        }
        do {
            try png.write(to: url, options: .atomic)
            say(tr("已存储到桌面：\(url.lastPathComponent)"))
        } catch {
            say(tr("无法存储到桌面"))
        }
    }

    private func copy(_ all: [PerfectDayRecord], month: Date) {
        guard let rendered = image(all, month: month) else { return say(tr("图片生成失败")) }
        let (picture, png) = rendered
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([picture])
        board.setData(png, forType: .png)
        say(tr("已拷贝图片"))
    }

    private func say(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if notice == text { notice = nil } }
        }
    }
}

/// 面板底部的两个大按钮：等宽、圆角，置灰时字也淡下去。
private struct BasketBarButtonStyle: ButtonStyle {
    var fill: Color
    var stroke: Color = .clear
    /// 字色：主题色按钮按亮度选深色或白色（`PanelTint.ink`），其余是白字。
    var ink: Color = .white
    var dimmed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(ink.opacity(dimmed ? 0.45 : 1))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(stroke, lineWidth: 0.5))
            .contentShape(.rect(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Shared with the share card

/// 竹林深绿底：上浅下深，右上角一点小熊猫橙的暖光，竹子贴在右上角页边。
/// 面板和分享图共用。
struct BasketForestBackdrop: View {
    var bambooHeight: CGFloat = 118

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: "#1F3A26"), Color(hex: "#101C15")],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "#C0502A").opacity(0.22), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 360)
            BambooStalks(height: bambooHeight)
                .opacity(0.16)
                .padding(.trailing, 10)
        }
    }
}

/// 右上角的小熊猫：空月是 idle 在等，有收获是 cheer。面板和分享图共用。
struct BasketPanda: View {
    var cheer: Bool
    var height: CGFloat

    var body: some View {
        if let image = PetArt.image(.redPanda, cheer ? .cheer : .idle) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .accessibilityHidden(true)
        } else {
            LeafGlyph(tier: cheer ? .gold : nil, size: height * 0.7, emptyInk: .white)
        }
    }
}

// MARK: - Share image

/// The picture shared from the panel: the basket, the counts (or, for an
/// empty month, how a leaf is earned), one status line, the calendar, 码头's
/// name and the month, on a bamboo grove's dark green.
struct PerfectDayShareCard: View {
    var records: [PerfectDayRecord]
    var month: Date
    var today: Date
    var firstWeekday: Int

    var body: some View {
        let counts = PerfectDay.counts(records, month: month)
        let leaves = PerfectDay.leaves(records, month: month)
        let got = PerfectDay.leavesSoFar(records, month: month, today: today)
        let isEmpty = got == 0
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("码头 · 小熊猫的竹篮")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(PerfectDay.shareTitle(month))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, 4)
                Spacer(minLength: 8)
                BasketPanda(cheer: !isEmpty, height: 88)
                    .padding(.top, -8)
                    .padding(.trailing, -4)
            }
            HStack(alignment: .center, spacing: 26) {
                VStack(spacing: 8) {
                    BambooBasket(leaves: isEmpty ? [] : leaves, width: 196, emptyText: nil, heapAtRim: true)
                    Text(PerfectDay.basketCaption(leaves: got))
                        .font(.system(size: isEmpty ? 15 : 14, weight: isEmpty ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(isEmpty ? 0.78 : 0.75))
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.leading, 6)
                if isEmpty { rules } else { tally(counts) }
            }
            VStack(alignment: .leading, spacing: 12) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                Text(PerfectDay.shareStatus(records, month: month, today: today))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            PerfectCalendarGrid(weeks: PerfectDay.monthGrid(records, month: month, today: today,
                                                            firstWeekday: firstWeekday),
                                weekdays: PerfectDay.weekdaySymbols(firstWeekday: firstWeekday),
                                leafSize: 22, shareStyle: true)
            HStack {
                Text("喝水 · 习惯 · 专注，每天给小熊猫一片竹叶")
                Spacer()
                Text("码头 Dockling")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(28)
        .frame(width: 520)
        // 竹子贴着右上角页边，在小熊猫后面，止于标题区，不进日历。
        .background { BasketForestBackdrop(bambooHeight: 118) }
        .environment(\.colorScheme, .dark)
    }

    /// 有收获：三档各几片。
    private func tally(_ counts: [PerfectDayTier: Int]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(PerfectDayTier.allCases.reversed()) { tier in
                HStack(spacing: 10) {
                    LeafGlyph(tier: tier, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tier.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(tier.leafName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 8)
                    Text("×\(counts[tier] ?? 0)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: tier.hexes.light))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 空月：每天怎么拿竹叶，和 `PerfectDay.tier` 的规则一致。
    private var rules: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("每天怎么拿竹叶")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
            Text("看喝水、习惯、专注达标几项")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PerfectDay.shareRuleLines) { line in
                    HStack(spacing: 8) {
                        LeafGlyph(tier: line.tier, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.condition)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                            Text(line.tier.leafName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: line.tier.hexes.light).opacity(0.9))
                        }
                    }
                }
            }
            .padding(.top, 14)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(PerfectDay.shareRuleNotes, id: \.self) { note in
                    Text(note)
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.top, 12)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum PerfectDayShareImage {
    /// The card at twice its size, as an image and as PNG data.
    static func render(records: [PerfectDayRecord], month: Date, today: Date,
                       firstWeekday: Int) -> (NSImage, Data)? {
        let renderer = ImageRenderer(content: PerfectDayShareCard(records: records, month: month, today: today,
                                                                  firstWeekday: firstWeekday))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let image = NSImage(size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        image.addRepresentation(rep)
        return (image, png)
    }
}

/// Where the share sheet's menu is anchored: the share button's own view.
@MainActor
final class ShareAnchorBox {
    weak var view: NSView?
}

struct ShareAnchor: NSViewRepresentable {
    var box: ShareAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}
