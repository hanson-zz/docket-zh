import AppKit
import SwiftUI

/// 小熊猫的竹篮的面板：今天三项、月份切换、本月竹篮、三档计数、月度频率条、
/// 日历视图、码头木牌徽章，以及把本月竹篮做成一张图分享出去。
struct PerfectDayDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// Months back from this one; 0 is the current month.
    @State private var monthsBack = 0
    @State private var anchor = ShareAnchorBox()
    @State private var notice: String?

    /// As far back as the history is kept.
    private static let maxMonthsBack = 26

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
        let tier = PerfectDay.record(items, key: "").tier
        let shownMonth = month
        return DetailCard {
            MeshBackdrop(color: Color(hex: PerfectDay.bambooHex))
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(tier: tier)
                    todayRows(items)
                    Divider().overlay(.white.opacity(0.1))
                    monthBar(shownMonth)
                    basketSection(all, month: shownMonth)
                    section("月度竹叶频率") {
                        PerfectFrequencyStrip(days: PerfectDay.monthDays(all, month: shownMonth, today: context.now))
                    }
                    section("日历视图") {
                        PerfectCalendarGrid(
                            weeks: PerfectDay.monthGrid(all, month: shownMonth, today: context.now,
                                                        firstWeekday: firstWeekday),
                            weekdays: PerfectDay.weekdaySymbols(firstWeekday: firstWeekday))
                    }
                    badgeSection(all)
                    shareRow(all, month: shownMonth)
                    rules
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 600)
            .scrollIndicators(.automatic)
        }
        .onAppear { if !context.isPreview { center.refresh(now: context.now) } }
    }

    // MARK: Today

    private func header(tier: PerfectDayTier?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("小熊猫的竹篮")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text(tier.map { "今天是\($0.title)" } ?? "今天还没有竹叶")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(PerfectDay.subline(tier))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            PandaWithLeaf(tier: tier, size: 56)
        }
    }

    private func todayRows(_ items: [PerfectDayProgress]) -> some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                VStack(spacing: 5) {
                    PerfectItemRing(progress: item, size: 26, track: .white)
                    Text(item.item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(item.mark == .met ? "已达标" : item.detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .glassPane(cornerRadius: 10)
            }
        }
    }

    // MARK: Month

    private func monthBar(_ month: Date) -> some View {
        HStack(spacing: 8) {
            Button { monthsBack = min(Self.maxMonthsBack, monthsBack + 1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(monthsBack >= Self.maxMonthsBack)
            .help("上个月")
            Text(PerfectDay.monthTitle(month))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(minWidth: 90)
            Button { monthsBack = max(0, monthsBack - 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(monthsBack == 0)
            .help("下个月")
            Spacer()
            if monthsBack != 0 {
                Button("回到本月") { monthsBack = 0 }
                    .controlSize(.small)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
    }

    private func basketSection(_ all: [PerfectDayRecord], month: Date) -> some View {
        let counts = PerfectDay.counts(all, month: month)
        return VStack(spacing: 12) {
            BambooBasket(leaves: PerfectDay.leaves(all, month: month), width: 170)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                ForEach(PerfectDayTier.allCases.reversed()) { tier in
                    VStack(spacing: 4) {
                        LeafGlyph(tier: tier, size: 30)
                        Text(tier.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("×\(counts[tier] ?? 0)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.black.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(hex: tier.hexes.light)))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassPane(cornerRadius: 10)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            content()
        }
    }

    // MARK: Badges

    private func badgeSection(_ all: [PerfectDayRecord]) -> some View {
        let statuses = PerfectBadges.statuses(records: all,
                                              focusMinutes: context.isPreview ? 900 : center.focusMinutes,
                                              earned: context.isPreview ? [:] : center.archive.earned)
        let unlocked = statuses.filter(\.unlocked).count
        return section("徽章 \(unlocked)/\(statuses.count)") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PerfectBadges.grouped(statuses)) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.category.title) \(group.statuses.filter(\.unlocked).count)/\(group.statuses.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        badgeGrid(group.statuses)
                    }
                }
            }
        }
    }

    private func badgeGrid(_ statuses: [PerfectBadgeStatus]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4),
                  spacing: 12) {
            ForEach(statuses) { status in
                VStack(spacing: 4) {
                    PerfectBadgeMedal(status: status, size: 54)
                    Text(status.shownTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(status.unlocked ? 1 : 0.6))
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
        if status.unlocked { return earnedLine(status) }
        if status.isConcealed { return status.shownCondition }
        return "\(status.shownCondition)\n\(status.progressText)"
    }

    private func earnedLine(_ status: PerfectBadgeStatus) -> String {
        guard let key = status.earnedOn, let date = HabitTracker.date(fromKey: key) else { return "已解锁" }
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)月\(c.day ?? 0)日解锁"
    }

    // MARK: Sharing

    private func shareRow(_ all: [PerfectDayRecord], month: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    share(all, month: month)
                } label: {
                    Label(monthsBack == 0 ? "分享本月竹篮" : "分享这个月的竹篮", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: PerfectDay.bambooHex))
                .background(ShareAnchor(box: anchor))
                Button("存储到桌面") { saveToDesktop(all, month: month) }
                    .buttonStyle(.bordered)
                Button("拷贝图片") { copy(all, month: month) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
            .disabled(context.isPreview)
            if let notice {
                Text(notice)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
                    .transition(.opacity)
            }
        }
    }

    private func image(_ all: [PerfectDayRecord], month: Date) -> (NSImage, Data)? {
        PerfectDayShareImage.render(records: all, month: month, today: context.now, firstWeekday: firstWeekday)
    }

    private func fileName(_ month: Date) -> String {
        "码头竹篮-\(PerfectDay.monthTitle(month)).png"
    }

    private func share(_ all: [PerfectDayRecord], month: Date) {
        guard let png = image(all, month: month)?.1 else { return say("图片生成失败") }
        let url = FileManager.default.temporaryDirectory.appending(path: fileName(month))
        do { try png.write(to: url, options: .atomic) } catch { return say("图片生成失败") }
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
        else { return say("图片生成失败") }
        var url = desktop.appending(path: fileName(month))
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appending(path: "码头竹篮-\(PerfectDay.monthTitle(month)) \(n).png")
            n += 1
        }
        do {
            try png.write(to: url, options: .atomic)
            say("已存储到桌面：\(url.lastPathComponent)")
        } catch {
            say("无法存储到桌面")
        }
    }

    private func copy(_ all: [PerfectDayRecord], month: Date) {
        guard let rendered = image(all, month: month) else { return say("图片生成失败") }
        let (picture, png) = rendered
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([picture])
        board.setData(png, forType: .png)
        say("已拷贝图片")
    }

    private func say(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if notice == text { notice = nil } }
        }
    }

    // MARK: Rules

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
}

// MARK: - Share image

/// The red panda with today's leaf in its paws: the pet's own drawing when
/// the bundle has it, otherwise the leaf alone.
struct PandaWithLeaf: View {
    var tier: PerfectDayTier?
    var size: CGFloat

    var body: some View {
        if let panda = PetArt.image(.redPanda, tier == nil ? .idle : .eat) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: panda)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                LeafGlyph(tier: tier, size: size * 0.45, emptyInk: .white)
                    .offset(x: size * 0.08, y: size * 0.04)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            LeafGlyph(tier: tier, size: size, emptyInk: .white)
        }
    }
}

/// The picture shared from the panel: the basket, the three counts, the
/// calendar, 码头's name and the month, on a bamboo grove's dark green.
struct PerfectDayShareCard: View {
    var records: [PerfectDayRecord]
    var month: Date
    var today: Date
    var firstWeekday: Int

    var body: some View {
        let counts = PerfectDay.counts(records, month: month)
        let leaves = PerfectDay.leaves(records, month: month)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("码头 · 小熊猫的竹篮")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(PerfectDay.monthTitle(month))的竹篮")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                PandaWithLeaf(tier: .gold, size: 60)
            }
            HStack(alignment: .center, spacing: 22) {
                BambooBasket(leaves: leaves, width: 200)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PerfectDayTier.allCases.reversed()) { tier in
                        HStack(spacing: 10) {
                            LeafGlyph(tier: tier, size: 34)
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
                    Text("小熊猫这个月收到 \(leaves.count) 片竹叶")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
            PerfectFrequencyStrip(days: PerfectDay.monthDays(records, month: month, today: today), height: 18)
            PerfectCalendarGrid(weeks: PerfectDay.monthGrid(records, month: month, today: today,
                                                            firstWeekday: firstWeekday),
                                weekdays: PerfectDay.weekdaySymbols(firstWeekday: firstWeekday),
                                leafSize: 26)
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
        .background {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [Color(hex: "#1F3A26"), Color(hex: "#101C15")],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: "#C0502A").opacity(0.22), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 360)
                BambooStalks(height: 220)
                    .opacity(0.18)
                    .padding(.trailing, 18)
            }
        }
        .environment(\.colorScheme, .dark)
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
