import SwiftUI

/// 喝水面板，四个标签。
///
/// 今天：杯子页。大杯子的水位是今天的进度，选的角色站在杯子旁边，身上是
/// 原来那套灰/彩水位效果（水面以下全彩、以上发灰、中间白色波浪水面），
/// 水位和杯子同步；表情照旧按 `WaterMood`（喝一杯举杯三秒、达标欢呼、
/// 提醒时段外或三小时没喝打盹），很久没喝渴成骷髅（`WaterParched`）。
/// 旁边是已喝/目标、还差几杯和八个小杯，下面是饮料（内置六种加用户自己
/// 起名的，见 CustomDrinks）、三只杯量按钮（小杯、一杯、大杯，一杯跟设置里
/// 的一杯容量走）和自定义量，再下面是今天的时间轴和记录（撤销上一杯、单条
/// 删除）。
///
/// 统计（连续、本月、7 天平均、柱状、月历和近七天报告）、目标（推荐量、
/// 明细、个人情况、手动目标）、设置（角色、提醒、复位）照旧。
struct WaterDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Tab: Hashable { case today, history, target, goal }

    @State private var tab: Tab = .today
    @State private var drink: DrinkPick = .builtIn(.water)
    /// The drink being added or edited, nil while the editor is closed.
    @State private var draft: DrinkDraft?
    @State private var customAmount = ""
    @State private var editingCustom = false
    @State private var weightText = ""
    @State private var ageText = ""
    @State private var heightText = ""
    @State private var confirmReset = false
    /// 今天的记录展开全部。
    @State private var showsAllEntries = false
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    fileprivate enum Field: Hashable { case amount, weight, age, height }

    /// A built-in drink, or one of the user's own by id.
    private enum DrinkPick: Hashable {
        case builtIn(DrinkType)
        case mine(String)
    }

    private struct DrinkDraft: Equatable {
        /// Nil for a new drink.
        var id: String?
        var name = ""
        var factor = 1.0
        var symbol = CustomDrinks.defaultSymbol
        var error: String?
    }

    private static let weekdays = [tr("一"), tr("二"), tr("三"), tr("四"), tr("五"), tr("六"), tr("日")]

    private var accent: Color { panelTint.accent(or: WaterStyle.water) }
    private var ounces: Bool { WaterIntake.usesOunces(instance.config) }

    private var days: [WaterDay] {
        context.isPreview ? WaterSamples.days(today: context.now) : WaterIntake.days(instance.config)
    }

    var body: some View {
        // A schedule rather than `context.now`, which is frozen for as long
        // as the panel is open: the day can roll over
        // under an open panel.
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            content(now: context.isPreview ? context.now : tick.date)
        }
        .onAppear(perform: loadProfileText)
        .onChange(of: focus) { old, _ in
            // Leaving a field saves it, as Return does.
            switch old {
            case .weight?: saveWeight()
            case .age?: saveAge()
            case .height?: saveHeight()
            default: break
            }
        }
    }

    private func loadProfileText() {
        let weight = instance.config.double(WaterGoal.Key.weight)
        weightText = weight > 0 ? weight.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)) : ""
        let age = instance.config.int(WaterGoal.Key.age)
        ageText = age > 0 ? "\(age)" : ""
        let height = instance.config.double(WaterGoal.Key.height)
        heightText = height > 0 ? height.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)) : ""
    }

    private func content(now: Date) -> some View {
        let all = days
        let result = WaterGoal.result(instance.config, now: now)
        // The library's preview draws the sample week against its own 2000 ml.
        let goal = context.isPreview ? WaterIntake.defaultGoal : result.goal
        let today = WaterIntake.today(all, goal: goal, now: now)
        let streak = WaterIntake.streak(all, goal: goal, today: now)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $tab) {
                    Text("今天").tag(Tab.today)
                    Text("统计").tag(Tab.history)
                    Text("目标").tag(Tab.target)
                    Text("设置").tag(Tab.goal)
                }
                .pickerStyle(.segmented)
                .tint(panelTint.control)
                .labelsHidden()
                .controlSize(.small)

                switch tab {
                case .today: todayPage(today, all: all, now: now, streak: streak)
                case .history:
                    history(all, goal: goal, now: now, streak: streak)
                    // 近七天报告原来挂在每个标签底下，现在归到统计里。
                    // 面板统一限高后默认收起，只留一行和每日平均，点开看柱状图。
                    WaterWeeklyReport(days: all, goal: goal, ounces: ounces, accent: accent, now: now,
                                      foldKey: DetailPanelSections.foldKey(.water, "weekly"))
                case .target: target(result)
                case .goal: goalSettings()
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: tab)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: drink)
    }

    // MARK: 今天：杯子页

    private func todayPage(_ today: WaterDay, all: [WaterDay], now: Date, streak: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            hero(today, all: all, now: now, streak: streak)
            ForEach(earnedNotices) { notice in earnedBanner(notice) }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("饮料")
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(tr("\(picked.title)：按 \(Int((picked.factor * 100).rounded()))% 计入"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                drinkChips
                if draft != nil { drinkEditor }
                amounts
            }
            entries(today, all: all, now: now)
        }
    }

    private var character: WaterCharacter {
        WaterCharacter.shown(instance.config, unlocked: ProAccess.isUnlocked || context.isPreview)
    }

    /// 大杯子加站在旁边的角色，右边已喝/目标、还差几杯、八个小杯、上次和下次。
    private func hero(_ today: WaterDay, all: [WaterDay], now: Date, streak: Int) -> some View {
        let level = WaterIntake.progress(total: today.total, goal: today.goal)
        let done = today.isMet
        let cup = WaterIntake.cupSize(instance.config)
        let cupHeight: CGFloat = 128
        return HStack(alignment: .center, spacing: 12) {
            // 自己的动画时钟，只在面板开着时走：卡片的水面不动，面板的轻轻动。
            // 减少动态效果时水面静止，只每秒看一次表情（喝一杯举杯的三秒）。
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 24, paused: context.isPreview)) { tick in
                let mood: WaterMood = context.isPreview ? .idle : WaterMood.at(tick.date, config: instance.config)
                let parched = !context.isPreview && WaterParched.isParched(instance.config, now: tick.date)
                WaterCupGauge(character: character, mood: mood, level: level, celebrating: done,
                              parched: WaterCupPage.showsSkeleton(parched: parched, mood: mood),
                              height: cupHeight, reduceMotion: reduceMotion,
                              phase: context.isPreview || reduceMotion ? nil : tick.date.timeIntervalSinceReferenceDate,
                              characterScale: 0.66, overlap: 0.14, detailed: true)
                    .overlay(alignment: .topLeading) {
                        Text(verbatim: "\(WaterIntake.percent(total: today.total, goal: today.goal))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                            .padding(.leading, cupHeight * 0.64 * 0.22)
                            .padding(.top, cupHeight * 0.1)
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("今天已喝")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(WaterIntake.figure(today.total, ounces: ounces))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .rollingValue(today.total)
                    Text(verbatim: "/ \(WaterIntake.figure(today.goal, ounces: ounces)) \(WaterIntake.unitLabel(ounces: ounces))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
                statusLine(today, now: now, cup: cup)
                WaterCupRow(filled: WaterPetCards.filledCups(total: today.total, goal: today.goal),
                            slots: WaterPetCards.cupSlots, cupWidth: 11, spacing: 3.5)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: today.total)
                    .padding(.vertical, 2)
                Text(tr("一杯 \(WaterIntake.amount(cup, ounces: ounces))，\(WaterCupPage.cupsToGoal(goal: today.goal, cup: cup)) 杯达标"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
                Label(lastLine(all, now: now), systemImage: "drop.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .help(tr("上次喝水"))
                Label(tr("下次提醒 \(dueLine(now: now))"), systemImage: "bell.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            Label(tr("\(streak) 天"), systemImage: "flame.fill")
                .font(WidgetStyle.label(11))
                .foregroundStyle(streak > 0 ? Color(hex: PaletteColor.orange.hex) : .white.opacity(0.45))
                .monospacedDigit()
                .help(tr("连续达标 \(streak) 天"))
        }
    }

    /// 达标、渴成骷髅，或者还差多少、约几杯。
    private func statusLine(_ today: WaterDay, now: Date, cup: Int) -> some View {
        let parched = !context.isPreview && WaterParched.isParched(instance.config, now: now)
        let text: String
        let color: Color
        if today.isMet {
            text = tr("达标啦！\(character.title)喝饱了")
            color = accent.mix(with: .white, by: 0.4)
        } else if parched {
            text = tr("渴成骷髅了")
            color = Color(hex: PaletteColor.red.hex)
        } else {
            let left = WaterIntake.amount(max(0, today.goal - today.total), ounces: ounces)
            text = tr("还差 \(left)，约 \(WaterCupPage.cupsLeft(total: today.total, goal: today.goal, cup: cup)) 杯")
            color = .white.opacity(0.75)
        }
        return Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private func lastLine(_ all: [WaterDay], now: Date) -> String {
        let line = lastDrinkLine(all, now: now)
        if context.isPreview { return tr("上次 \(line)") }
        guard let last = WaterIntake.lastDrink(all), WaterIntake.calendar.isDate(last, inSameDayAs: now) else { return line }
        return tr("上次 \(line)")
    }

    // MARK: Drinks and amounts

    /// The user's own drinks on the chips; none in the library preview.
    private var myDrinks: [CustomDrink] {
        context.isPreview ? [] : CustomDrinks.visible(instance.config)
    }

    /// What the next cup is logged as. A picked drink that has since been
    /// removed falls back to water.
    private var picked: (type: DrinkType, title: String, factor: Double, id: String?) {
        switch drink {
        case .builtIn(let type):
            return (type, type.title, type.factor, nil)
        case .mine(let id):
            guard let mine = myDrinks.first(where: { $0.id == id }) else {
                return (.water, DrinkType.water.title, DrinkType.water.factor, nil)
            }
            return (.custom, mine.name, mine.factor, mine.id)
        }
    }

    /// The built-in drinks, the user's own, then 自定义 to add one. They wrap
    /// onto a second row rather than squeezing a name into "椰…".
    private var drinkChips: some View {
        let current: DrinkPick = picked.id.map { DrinkPick.mine($0) } ?? DrinkPick.builtIn(picked.type)
        return DrinkChipFlow(spacing: 4) {
            ForEach(DrinkType.allCases.filter { $0 != .custom }) { type in
                drinkChip(symbol: type.symbol, title: type.title, selected: current == .builtIn(type)) {
                    drink = .builtIn(type)
                }
                .help(tr("\(type.title)：按 \(Int((type.factor * 100).rounded()))% 计入"))
            }
            ForEach(myDrinks) { mine in
                drinkChip(symbol: mine.symbol, title: mine.name, selected: current == .mine(mine.id)) {
                    drink = .mine(mine.id)
                }
                .help(tr("\(mine.name)：按 \(mine.percent)% 计入"))
                .contextMenu {
                    Button("编辑") { openEditor(mine) }
                    Button("删除", role: .destructive) { removeDrink(mine.id) }
                }
            }
            let full = myDrinks.count >= CustomDrinks.maxCount
            drinkChip(symbol: "plus", title: tr("自定义"), selected: draft?.id == nil && draft != nil) {
                guard !context.isPreview else { return }
                openEditor(nil)
            }
            .disabled(full || context.isPreview)
            .help(full ? tr("最多 \(CustomDrinks.maxCount) 种自定义饮料") : tr("添加自定义饮料"))
        }
    }

    private func drinkChip(symbol: String, title: String, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(height: 15)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
            .padding(.horizontal, 6)
            .frame(minWidth: 40, maxWidth: .infinity)
            .frame(height: 38)
            // 选中只是亮一点加一圈白描边，不用大块的蓝。
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.18 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.45 : 0), lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: The drink editor

    private func openEditor(_ mine: CustomDrink?) {
        if let mine {
            draft = DrinkDraft(id: mine.id, name: mine.name, factor: mine.factor, symbol: mine.symbol)
        } else {
            draft = DrinkDraft()
        }
    }

    /// Name, share and symbol, inline under the chips: a popover from a
    /// panel that is not the key window may not take typing.
    private var drinkEditor: some View {
        let current = draft ?? DrinkDraft()
        let tooLong = current.name.count > CustomDrinks.maxNameLength
        let canSave = CustomDrinks.cleanName(current.name) != nil && !tooLong
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(current.id == nil ? tr("新饮料") : tr("编辑饮料"))
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(verbatim: "\(current.name.count)/\(CustomDrinks.maxNameLength)")
                    .font(.system(size: 10))
                    .foregroundStyle(tooLong ? Color(hex: PaletteColor.red.hex) : .white.opacity(0.5))
                    .monospacedDigit()
            }
            // The AI form's NSTextField: it takes the cursor when the editor
            // opens, and Esc and Return reach it rather than the panel. No
            // cutting while typing either: pinyin being composed is longer
            // than the name it becomes.
            AIFormField(text: Binding(get: { draft?.name ?? "" },
                                      set: { draft?.name = $0; draft?.error = nil }),
                        placeholder: tr("名字，比如椰子水"), label: tr("饮料名字"), focusOnAppear: true,
                        onSubmit: saveDraft, onCancel: { draft = nil })
                .frame(height: 22)
            Stepper(value: Binding(get: { draft?.factor ?? 1 },
                                   set: { draft?.factor = CustomDrinks.clampFactor($0) }),
                    in: CustomDrinks.factorRange, step: CustomDrinks.factorStep) {
                Text(tr("计入比例 \(Int((current.factor * 100).rounded()))%"))
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            .controlSize(.small)
            HStack(spacing: 4) {
                ForEach(CustomDrinks.symbols, id: \.self) { symbol in
                    let selected = current.symbol == symbol
                    Button {
                        draft?.symbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(selected ? 0.18 : 0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(selected ? 0.45 : 0), lineWidth: 1))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("图标"))
                }
            }
            if let error = current.error ?? (tooLong ? tr("名字最多 \(CustomDrinks.maxNameLength) 个字") : nil) {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: PaletteColor.red.hex))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let id = current.id {
                    Button("删除", role: .destructive) { removeDrink(id) }
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(Color(hex: PaletteColor.red.hex))
                }
                Spacer()
                Button("取消") { draft = nil }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.7))
                Button("保存", action: saveDraft)
                    .buttonStyle(.plain)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(canSave ? 1 : 0.35))
                    .disabled(!canSave)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private func saveDraft() {
        guard !context.isPreview, let current = draft else { return }
        guard current.name.count <= CustomDrinks.maxNameLength else { return }
        let drinks = CustomDrinks.all(instance.config)
        let newID = CustomDrinks.newID(among: drinks)
        let result = current.id.map {
            CustomDrinks.updating(id: $0, name: current.name, factor: current.factor, symbol: current.symbol, in: drinks)
        } ?? CustomDrinks.adding(name: current.name, factor: current.factor, symbol: current.symbol,
                                 id: newID, to: drinks)
        switch result {
        case .success(let list):
            WaterLog.editDrinks(instance) { _, _ in list }
            drink = .mine(current.id ?? newID)
            draft = nil
        case .failure(let error):
            let message: String
            switch error {
            case .emptyName: message = tr("先起个名字")
            case .duplicateName: message = tr("已经有同名的饮料了")
            case .tooMany: message = tr("最多 \(CustomDrinks.maxCount) 种自定义饮料")
            case .notFound: message = tr("这个饮料已经删除了")
            }
            draft?.error = message
        }
    }

    private func removeDrink(_ id: String) {
        guard !context.isPreview else { return }
        WaterLog.editDrinks(instance) { drinks, days in CustomDrinks.removing(id: id, in: drinks, days: days) }
        if drink == .mine(id) { drink = .builtIn(.water) }
        if draft?.id == id { draft = nil }
    }

    // MARK: A character just earned

    /// The characters the log has just earned, each until its banner is closed.
    private var earnedNotices: [WaterCharacter] {
        guard !context.isPreview else { return [] }
        return WaterCharacter.notices(instance.config.string(WaterLog.earnedNoticeKey))
    }

    private func dropNotice(_ character: WaterCharacter, in config: inout WidgetConfig) {
        let rest = WaterCharacter.removingNotice(character, from: config.string(WaterLog.earnedNoticeKey))
        config.set(WaterLog.earnedNoticeKey, rest.map(WidgetConfig.Value.string))
    }

    private func earnedBanner(_ character: WaterCharacter) -> some View {
        HStack(spacing: 8) {
            WaterPanda(character: character, mood: .cheer, level: 1, height: 22)
                .frame(height: 24)
            Text(character.earnedLine)
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("换上") {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    WidgetWriter.write(instance) { config in
                        config.set("character", .string(character.rawValue))
                        dropNotice(character, in: &config)
                    }
                }
            }
            .buttonStyle(.plain)
            .font(WidgetStyle.label(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.18)))
            Button {
                WidgetWriter.write(instance) { config in dropNotice(character, in: &config) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassPane(cornerRadius: 10)
    }

    private var amounts: some View {
        HStack(spacing: 6) {
            if editingCustom {
                HStack(spacing: 6) {
                    TextField("", text: $customAmount, prompt: Text("毫升"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .focused($focus, equals: .amount)
                        .onSubmit(addCustom)
                    Button("添加", action: addCustom)
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white)
                        .disabled(Int(customAmount) == nil)
                    Button {
                        editingCustom = false
                        customAmount = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消")
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .glassPane(cornerRadius: 10)
            } else {
                // 小杯、一杯、大杯：一杯是设置里的一杯容量，另外两只跟着让开。
                ForEach(WaterCupPage.cupButtons(cup: WaterIntake.cupSize(instance.config)), id: \.size) { button in
                    cupButton(button)
                }
                amountTile(symbol: "pencil", title: tr("自定义"), subtitle: nil, highlighted: false) {
                    editingCustom = true
                    focus = .amount
                }
                .help(tr("自定义"))
            }
        }
    }

    private func cupButton(_ button: WaterCupPage.CupButton) -> some View {
        let amount = WaterIntake.amount(button.amount, ounces: ounces)
        return amountTile(symbol: nil, cup: button.size, title: "+\(WaterIntake.figure(button.amount, ounces: ounces))",
                          subtitle: button.size.title, highlighted: button.size == .cup) {
            log(button.amount)
        }
        .help(tr("记录\(button.size.title)，\(amount)"))
        .accessibilityLabel(tr("记录\(button.size.title)，\(amount)"))
    }

    /// 一只按钮：左边一个小杯（按杯量画大小）或图标，右边量和名字。默认那只
    /// 只多一圈淡白描边，不用大块的蓝。
    private func amountTile(symbol: String?, cup: WaterCupPage.CupSize? = nil, title: String, subtitle: String?,
                            highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let cup {
                    let scale: CGFloat = cup == .small ? 0.7 : cup == .cup ? 0.85 : 1
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(WaterStyle.water.opacity(0.75))
                                .frame(height: 18 * scale * 0.6)
                        }
                        .clipShape(SmallCupShape())
                        .frame(width: 13 * scale, height: 18 * scale)
                    .frame(width: 13, height: 18, alignment: .bottom)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 13)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(highlighted ? 0.16 : 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(highlighted ? 0.35 : 0), lineWidth: 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }

    private func log(_ amount: Int) {
        guard !context.isPreview else { return }
        let choice = picked
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
            WaterLog.drink(choice.type, amount: amount, factor: choice.factor, drinkID: choice.id, in: instance)
        }
    }

    private func addCustom() {
        let typed = Int(customAmount.trimmingCharacters(in: .whitespaces)) ?? 0
        guard typed > 0 else { return }
        // Typed in the unit on show.
        let millilitres = ounces ? Int((Double(typed) * WaterIntake.millilitresPerOunce).rounded()) : typed
        log(min(5000, millilitres))
        customAmount = ""
        editingCustom = false
    }

    // MARK: 今天的时间轴和记录

    private func entries(_ today: WaterDay, all: [WaterDay], now: Date) -> some View {
        let count = today.entries.count
        let shown = WaterCupPage.shownRows(count: count, expanded: showsAllEntries)
        let rows = Array(today.entries.enumerated().reversed().prefix(shown))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("今天")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.9))
                Text(tr("\(count) 杯 · 计入 \(WaterIntake.amount(today.total, ounces: ounces))"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button {
                    guard !context.isPreview else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { WaterLog.undo(instance) }
                } label: {
                    Label("撤销上一杯", systemImage: "arrow.uturn.backward")
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(.white.opacity(today.entries.isEmpty ? 0.3 : 0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(today.entries.isEmpty ? 0.05 : 0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(today.entries.isEmpty || context.isPreview)
            }
            timeline(today, now: now)
            if today.entries.isEmpty {
                Text("今天还没喝水。点上面的按钮记一杯，小熊猫就开始装水了。")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            } else {
                // 一杯一行的记录是次要内容：面板统一限高后默认收起，时间轴上
                // 每一杯照样看得到；展开状态记住。
                DetailFold(key: DetailPanelSections.foldKey(.water, "entries")) {
                    Text(tr("每一杯的记录"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                } content: {
                    entryRows(rows, count: count)
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    /// 今天的记录，最新的在上；多了先露几条，点“展开全部”。
    @ViewBuilder
    private func entryRows(_ rows: [(offset: Int, element: WaterEntry)], count: Int) -> some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.offset) { index, entry in
                entryRow(entry, index: index)
            }
        }
        if WaterCupPage.canExpand(count: count) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { showsAllEntries.toggle() }
            } label: {
                Label(showsAllEntries ? tr("收起") : tr("展开全部 \(count) 条"),
                      systemImage: showsAllEntries ? "chevron.up" : "chevron.down")
                    .font(WidgetStyle.label(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// 提醒时段的一根横轴：每一杯一个小图标，现在一道竖线，今天还有的下次
    /// 提醒一个淡淡的铃铛，下面是整点。
    private func timeline(_ today: WaterDay, now: Date) -> some View {
        let calendar = WaterIntake.calendar
        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var nextMinute: Int?
        if !context.isPreview, case .upcoming(let at) = WaterReminder.due(instance.config, now: now),
           calendar.isDate(at, inSameDayAs: now) {
            nextMinute = calendar.component(.hour, from: at) * 60 + calendar.component(.minute, from: at)
        }
        let axis = WaterCupPage.axis(window: WaterReminder(config: instance.config),
                                     entries: today.entries.map(\.minute),
                                     now: context.isPreview ? nil : nowMinute, next: nextMinute)
        let lineY: CGFloat = 18
        return GeometryReader { proxy in
            let width = proxy.size.width
            let inset: CGFloat = 8
            let usable = max(1, width - inset * 2)
            let x: (Int) -> CGFloat = { minute in inset + usable * CGFloat(axis.fraction(minute)) }
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: usable, height: 2)
                    .position(x: inset + usable / 2, y: lineY)
                if let nextMinute {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.55))
                        .position(x: x(nextMinute), y: lineY)
                        .help(tr("下次提醒 \(PostureSchedule.clock(nextMinute))"))
                }
                if !context.isPreview, nowMinute >= axis.start, nowMinute <= axis.end {
                    Capsule()
                        .fill(.white.opacity(0.8))
                        .frame(width: 1.5, height: 14)
                        .position(x: x(nowMinute), y: lineY)
                    Text("现在")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize()
                        .position(x: x(nowMinute), y: 4)
                }
                ForEach(Array(today.entries.enumerated()), id: \.offset) { _, entry in
                    Image(systemName: CustomDrinks.symbol(of: entry, in: namedDrinks))
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(entry.type == .water ? WaterStyle.water.opacity(0.85)
                                                  : Color.white.opacity(0.28)))
                        .position(x: x(entry.minute), y: lineY)
                        .help("\(entry.clock) \(CustomDrinks.title(of: entry, in: namedDrinks)) \(WaterIntake.amount(entry.amount, ounces: ounces))")
                }
                ForEach(axis.ticks, id: \.self) { tick in
                    Text(verbatim: WaterCupPage.tickLabel(tick))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: x(tick), y: 34)
                }
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }

    private static func clock(_ date: Date) -> String {
        PostureSchedule.clock(WaterIntake.calendar.component(.hour, from: date) * 60
                              + WaterIntake.calendar.component(.minute, from: date))
    }

    private func lastDrinkLine(_ all: [WaterDay], now: Date) -> String {
        if context.isPreview { return tr("14:20，40 分钟前") }
        guard let last = WaterIntake.lastDrink(all),
              WaterIntake.calendar.isDate(last, inSameDayAs: now) else { return tr("今天还没喝") }
        let since = max(0, now.timeIntervalSince(last))
        return since < 60 ? tr("\(Self.clock(last))，刚刚") : tr("\(Self.clock(last))，\(Self.spelled(since))前")
    }

    private func dueLine(now: Date) -> String {
        if context.isPreview { return "15:20" }
        switch WaterReminder.due(instance.config, now: now) {
        case .off: return tr("已关闭")
        case .met(let next): return tr("达标啦，明天 \(Self.clock(next))")
        case .upcoming(let at):
            let day = WaterIntake.calendar.isDate(at, inSameDayAs: now) ? "" : tr("明天 ")
            return "\(day)\(Self.clock(at))"
        case .overdue(let seconds):
            return seconds >= 60 ? tr("已超时 \(Self.spelled(seconds))") : tr("该喝水了")
        }
    }

    /// "45 分钟", "1 小时 30 分钟": a span, not a ticking countdown.
    private static func spelled(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return tr("\(max(1, minutes)) 分钟") }
        return minutes % 60 == 0 ? tr("\(minutes / 60) 小时") : tr("\(minutes / 60) 小时 \(minutes % 60) 分钟")
    }

    /// Every drink the user named, removed ones too, for the rows' names.
    private var namedDrinks: [CustomDrink] { CustomDrinks.all(instance.config) }

    private func entryRow(_ entry: WaterEntry, index: Int) -> some View {
        let name = CustomDrinks.title(of: entry, in: namedDrinks)
        return HStack(spacing: 8) {
            Text(entry.clock)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
            Image(systemName: CustomDrinks.symbol(of: entry, in: namedDrinks))
                .font(.system(size: 11))
                .foregroundStyle(accent.mix(with: .white, by: 0.35))
                .frame(width: 16)
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(WaterIntake.amount(entry.amount, ounces: ounces))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
            if entry.effective != entry.amount {
                Text(tr("计 \(WaterIntake.figure(entry.effective, ounces: ounces))"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }
            Button {
                guard !context.isPreview else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { WaterLog.remove(at: index, in: instance) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help("删除这一杯")
            .accessibilityLabel(tr("删除 \(entry.clock) 的\(name)"))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassPane(cornerRadius: 9)
    }

    // MARK: 统计

    private func history(_ all: [WaterDay], goal: Int, now: Date, streak: Int) -> some View {
        let week = WaterIntake.lastDays(all, goal: goal, today: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatChip(label: tr("连续达标"), value: tr("\(streak) 天"))
                StatChip(label: tr("本月达标"), value: tr("\(WaterIntake.metCount(all, goal: goal, month: now, today: now)) 天"))
                StatChip(label: tr("7 天平均"), value: WaterIntake.amount(week.reduce(0) { $0 + $1.total } / max(1, week.count), ounces: ounces))
            }
            bars(week)
            month(all, goal: goal, now: now)
        }
    }

    /// The last seven days as bars, today last, with the goal as a line.
    private func bars(_ week: [WaterDayReading]) -> some View {
        let height: CGFloat = 70
        return VStack(spacing: 4) {
            ZStack(alignment: .top) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(week, id: \.key) { day in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.isMet ? accent.opacity(0.9) : Color.white.opacity(day.total > 0 ? 0.35 : 0.1))
                            .frame(height: max(3, height * day.fraction))
                            .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
                            .overlay(alignment: .top) {
                                if day.isToday {
                                    Circle().fill(.white).frame(width: 4, height: 4).offset(y: -7)
                                        .opacity(day.fraction > 0.9 ? 0 : 1)
                                }
                            }
                            .help("\(day.date.formatted(.dateTime.month().day()))：\(WaterIntake.amount(day.total, ounces: ounces))")
                    }
                }
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(height: 0.5)
                    .overlay(alignment: .trailing) {
                        Text("目标")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .offset(y: -7)
                    }
            }
            .frame(height: height)
            HStack(spacing: 8) {
                ForEach(week, id: \.key) { day in
                    Text(day.isToday ? tr("今") : Self.weekdays[weekdayIndex(day.date)])
                        .font(.system(size: 9, weight: day.isToday ? .bold : .semibold))
                        .foregroundStyle(.white.opacity(day.isToday ? 0.9 : 0.5))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    /// 0 for Monday through 6 for Sunday.
    private func weekdayIndex(_ date: Date) -> Int {
        let calendar = WaterIntake.calendar
        return (calendar.component(.weekday, from: date) - 2 + 7) % 7
    }

    /// This month, a dot per day: filled where the goal was met, a ring
    /// filled partway where some water went in.
    private func month(_ all: [WaterDay], goal: Int, now: Date) -> some View {
        let weeks = WaterIntake.monthGrid(all, goal: goal, month: now, today: now)
        let cell: CGFloat = 16
        return VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.year().month(.wide)))
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        Group {
                            if let day = weeks[row][column] {
                                dot(day, size: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func dot(_ day: WaterDayReading, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(day.isMet ? accent.opacity(0.9) : Color.white.opacity(day.isFuture ? 0.03 : 0.08))
            if !day.isMet, day.total > 0 {
                Circle()
                    .trim(from: 0, to: day.fraction)
                    .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1)
            }
            if day.isToday {
                Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1)
            }
            Text("\(day.day)")
                .font(.system(size: 7.5, weight: day.isToday ? .bold : .medium))
                .foregroundStyle(.white.opacity(day.isMet ? 1 : (day.isFuture ? 0.25 : 0.6)))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .help(day.isFuture ? "" : WaterIntake.amount(day.total, ounces: ounces))
    }

    // MARK: 设置

    private func goalSettings() -> some View {
        let reminder = WaterReminder(config: instance.config)
        return VStack(alignment: .leading, spacing: 10) {
            characterPicker

            reminderSettings(reminder)

            Button {
                confirmReset = true
            } label: {
                Label("复位喝水设置", systemImage: "arrow.counterclockwise")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .glassPane(cornerRadius: 10)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .confirmationDialog("复位喝水设置？", isPresented: $confirmReset) {
                Button("复位", role: .destructive) {
                    WaterLog.resetSettings(in: instance)
                    weightText = ""
                    ageText = ""
                    heightText = ""
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("手动目标、体重、性别、年龄、身高、活动量、今日运动、气候、特殊状态、提醒间隔、时段和下次提醒恢复默认，每日目标回到推荐值，喝水记录、角色和单位保留。")
            }

            Text("达标后当天不再提醒，刚喝过水也会顺延。一杯的容量和单位可以在设置的小组件页里改。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 提醒

    private func reminderSettings(_ reminder: WaterReminder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            settingRow(tr("提醒")) {
                Picker("", selection: Binding(
                    get: { reminder.every },
                    set: { value in
                        guard !context.isPreview else { return }
                        WaterLog.set("remindEvery", .string(String(value)), in: instance)
                    })) {
                        ForEach(WaterIntake.reminderChoices, id: \.self) { value in
                            Text(value == 0 ? tr("关闭") : tr("每 \(value) 分钟")).tag(value)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
            }
            // 交给到点弹出卡片时不走系统通知，不用提示。
            NotificationsOffNote(active: NotificationAccess.waterUsesNotifications(
                every: reminder.every, popupShows: ReminderPopupCenter.shared.shows(.water)),
                                 preview: context.isPreview)
            settingRow(tr("时段")) {
                HStack(spacing: 4) {
                    timePicker(reminder.start, key: "start")
                    Text("到").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    timePicker(reminder.end % 1440, key: "end")
                }
            }
            if reminder.every > 0 {
                nextReminderRow
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private var nextReminderRow: some View {
        let now = Date.now
        let picked = WaterReminder.override(instance.config, now: now)
        let shown = WaterReminder.next(instance.config, now: now) ?? now
        let calendar = WaterIntake.calendar
        let minutes = calendar.component(.hour, from: shown) * 60 + calendar.component(.minute, from: shown)
        return VStack(alignment: .leading, spacing: 6) {
            settingRow(tr("下次提醒")) {
                HStack(spacing: 6) {
                    if !calendar.isDate(shown, inSameDayAs: now) {
                        Text("明天").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    DatePicker("", selection: Binding(
                        get: { Self.date(minutes: minutes) },
                        set: { date in
                            let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
                            pickNext(WaterReminder.pickedTime(minutes: m, now: .now))
                        }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                }
            }
            HStack(spacing: 6) {
                ForEach([15, 30, 60], id: \.self) { delay in
                    chip(delay == 60 ? tr("1 小时后") : tr("\(delay) 分钟后")) {
                        pickNext(Date.now.addingTimeInterval(TimeInterval(delay * 60)))
                    }
                }
                Spacer(minLength: 0)
                if picked != nil {
                    chip(tr("恢复自动")) {
                        guard !context.isPreview else { return }
                        WaterLog.set(WaterReminder.overrideKey, nil, in: instance)
                    }
                }
            }
        }
    }

    private func pickNext(_ date: Date) {
        guard !context.isPreview else { return }
        WaterLog.set(WaterReminder.overrideKey, .number(date.timeIntervalSince1970), in: instance)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            content()
        }
        .controlSize(.small)
    }

    private func timePicker(_ minutes: Int, key: String) -> some View {
        DatePicker("", selection: Binding(
            get: { Self.date(minutes: minutes) },
            set: { date in
                guard !context.isPreview else { return }
                let calendar = WaterIntake.calendar
                let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
                WaterLog.set(key, .string(PostureSchedule.clock(m)), in: instance)
            }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .fixedSize()
            .disabled(context.isPreview)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WidgetStyle.label(11))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
    }

    /// Today at `minutes` after midnight, for a time-only picker.
    private static func date(minutes: Int) -> Date {
        WaterIntake.calendar.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Six faces in a row; the chosen one sits on the accent. A Pro one that
    /// is locked opens the paywall; a shiba or cat still to be earned only
    /// says how many more days it takes.
    private var characterPicker: some View {
        let pro = ProAccess.isUnlocked || context.isPreview
        let chosen = WaterCharacter.shown(instance.config, unlocked: pro)
        let access = Dictionary(uniqueKeysWithValues: WaterCharacter.allCases.map {
            ($0, WaterCharacter.access($0, config: instance.config, pro: pro))
        })
        let waiting: [(WaterCharacter, Int)] = WaterCharacter.allCases.compactMap { character in
            guard let left = access[character]?.daysLeft else { return nil }
            return (character, left)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("角色")
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 4) {
                ForEach(WaterCharacter.allCases) { character in
                    let selected = character == chosen
                    let state = access[character] ?? .free
                    let proLocked = state == .pro(unlocked: false)
                    let earnLocked = state.daysLeft
                    let locked = proLocked || earnLocked != nil
                    Button {
                        guard !context.isPreview else { return }
                        if proLocked { PaywallWindow.shared.show(); return }
                        if earnLocked != nil { return }
                        withAnimation(.snappy(duration: 0.25)) {
                            WaterLog.set("character", .string(character.rawValue), in: instance)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            WaterPanda(character: character, mood: .idle, level: 1, height: 26)
                                .frame(height: 28)
                                .opacity(locked ? 0.55 : 1)
                                .overlay(alignment: .topTrailing) {
                                    if locked {
                                        // Orange is Pro's; a lock that only
                                        // needs more days is plain white.
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(2.5)
                                            .background(Circle().fill(proLocked ? Color(hex: ShelfColor.redPanda.hex)
                                                                                : Color.white.opacity(0.3)))
                                    }
                                }
                            Text(character.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(selected ? 0.18 : 0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(selected ? 0.45 : 0), lineWidth: 1))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(context.isPreview)
                    .help(earnLocked.map { tr("\(character.title)：\(WaterCharacter.unlockHint(daysLeft: $0))") }
                          ?? (proLocked ? "\(character.title)：\(ProFeatures.help)" : character.title))
                    .accessibilityLabel(earnLocked.map { tr("角色：\(character.title)，\(WaterCharacter.unlockHint(daysLeft: $0))") }
                                        ?? (proLocked ? tr("角色：\(character.title)，Pro 专属") : tr("角色：\(character.title)")))
                }
            }
            if !waiting.isEmpty {
                Text(waiting.map { tr("\($0.0.title)：\(WaterCharacter.unlockHint(daysLeft: $0.1))") }
                    .joined(separator: tr("；")))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    // MARK: Saving the details

    private static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "，", with: ".")
            .trimmingCharacters(in: .whitespaces))
    }

    /// Empty clears the value; anything outside the range is put back.
    private func saveNumber(_ text: String, key: String, range: ClosedRange<Double>, reload: () -> Void) {
        guard !context.isPreview else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if instance.config[key] != nil { WaterLog.profile(instance) { config, _ in config.set(key, nil) } }
            return
        }
        guard let value = Self.parse(trimmed), value.isFinite, range.contains(value) else { reload(); return }
        let stored = (value * 10).rounded() / 10
        guard instance.config.double(key) != stored else { return }
        WaterLog.profile(instance) { config, _ in config.set(key, .number(stored)) }
    }

    private func saveWeight() {
        saveNumber(weightText, key: WaterGoal.Key.weight, range: WaterGoal.weightRange, reload: loadProfileText)
    }

    private func saveAge() {
        // Whole years; anything outside the range goes through as typed and
        // is put back by saveNumber.
        let range = Double(WaterGoal.ageRange.lowerBound)...Double(WaterGoal.ageRange.upperBound)
        var text = ageText
        if let value = Self.parse(ageText), value.isFinite, range.contains(value) {
            text = "\(Int(value.rounded(.down)))"
        }
        saveNumber(text, key: WaterGoal.Key.age, range: range, reload: loadProfileText)
    }

    private func saveHeight() {
        saveNumber(heightText, key: WaterGoal.Key.height, range: WaterGoal.heightRange, reload: loadProfileText)
    }

    private func setProfile(_ key: String, _ value: WidgetConfig.Value?) {
        guard !context.isPreview else { return }
        WaterLog.profile(instance) { config, _ in config.set(key, value) }
    }

}

// MARK: - 目标

/// The personal goal: what it comes to and why, a goal set by hand on top
/// with a way back, and the details the recommendation is worked out from.
/// All in one scrolling page so the panel keeps its height.
extension WaterDetail {
    private var currentProfile: WaterProfile { WaterProfile(config: instance.config) }

    func target(_ result: WaterGoalResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                goalSummary(result)
                breakdown(result)
                bodyDetails
                todayDetails
                Text("推荐量只是日常参考，不是医疗建议。心脏、肾脏疾病需要限水的人请遵医嘱。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: 340)
        .scrollIndicators(.never)
    }

    /// The goal in use, the stepper that sets one by hand, and 恢复推荐.
    private func goalSummary(_ result: WaterGoalResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(
                get: { result.goal },
                set: { value in
                    guard !context.isPreview else { return }
                    WaterLog.setGoal(value, in: instance)
                }), in: WaterIntake.goalRange, step: 50) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("每日目标")
                                .font(WidgetStyle.label(12))
                                .foregroundStyle(.white.opacity(0.85))
                            Text(result.isManual ? tr("已手动设置") : tr("按个人情况推荐"))
                                .font(.system(size: 10))
                                .foregroundStyle(result.isManual ? Color(hex: PaletteColor.orange.hex) : .white.opacity(0.55))
                        }
                        Spacer()
                        Text(WaterIntake.amount(result.goal, ounces: ounces))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                }
                .controlSize(.small)
            if result.isManual {
                HStack(spacing: 6) {
                    Text(tr("推荐目标 \(WaterIntake.amount(result.recommended, ounces: ounces))"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Button {
                        guard !context.isPreview else { return }
                        WaterLog.useRecommended(in: instance)
                    } label: {
                        Label("恢复推荐", systemImage: "arrow.uturn.backward")
                            .font(WidgetStyle.label(11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(accent.opacity(0.7)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(context.isPreview)
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    /// 基数 + 各项加减 = 推荐目标, always in millilitres: the rules are.
    private func breakdown(_ result: WaterGoalResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("计算明细")
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            ForEach(result.lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                        if !line.detail.isEmpty {
                            Text(line.detail)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    Spacer(minLength: 4)
                    Text(WaterGoal.signed(line))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            Rectangle().fill(.white.opacity(0.2)).frame(height: 0.5)
            HStack {
                Text("推荐目标")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(tr("\(result.recommended) 毫升"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            if let manual = result.manual {
                HStack {
                    Text("已手动设置")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                    Spacer()
                    Text(tr("\(manual) 毫升"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                        .monospacedDigit()
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    /// Who is drinking: changes rarely.
    private var bodyDetails: some View {
        let profile = currentProfile
        return VStack(alignment: .leading, spacing: 8) {
            Text("个人情况")
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            numberField(tr("体重"), text: $weightText, unit: tr("公斤"), prompt: "60", field: .weight, save: saveWeight)
            optionRow(tr("性别")) {
                Picker("", selection: Binding(
                    get: { profile.sex },
                    set: { setProfile(WaterGoal.Key.sex, $0 == .unset ? nil : .string($0.rawValue)) })) {
                        ForEach(WaterSex.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .tint(panelTint.control)
                    .labelsHidden()
                    .fixedSize()
            }
            numberField(tr("年龄"), text: $ageText, unit: tr("岁"), prompt: "30", field: .age, save: saveAge)
            numberField(tr("身高"), text: $heightText, unit: tr("厘米"), prompt: "170", field: .height, save: saveHeight)
            optionRow(tr("日常活动量")) {
                Picker("", selection: Binding(
                    get: { profile.activity },
                    set: { setProfile(WaterGoal.Key.activity, $0 == .sedentary ? nil : .string($0.rawValue)) })) {
                        ForEach(WaterActivity.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .tint(panelTint.control)
                    .labelsHidden()
                    .fixedSize()
            }
            optionRow(tr("气候")) {
                Picker("", selection: Binding(
                    get: { profile.climate },
                    set: { setProfile(WaterGoal.Key.climate, $0 == .mild ? nil : .string($0.rawValue)) })) {
                        ForEach(WaterClimate.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
            }
            optionRow(tr("特殊状态")) {
                Picker("", selection: Binding(
                    get: { profile.condition },
                    set: { setProfile(WaterGoal.Key.condition, $0 == .none ? nil : .string($0.rawValue)) })) {
                        ForEach(WaterCondition.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .tint(panelTint.control)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(profile.sex == .male || context.isPreview)
            }
            if profile.sex == .male, profile.condition != .none {
                Text("性别为男时不计特殊状态。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text("都可以不填：没填体重时按膳食指南（2022）的成人基准估算。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    /// Today only: cleared on its own tomorrow.
    private var todayDetails: some View {
        let profile = currentProfile
        return VStack(alignment: .leading, spacing: 8) {
            Text("今天")
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            Stepper(value: Binding(
                get: { profile.exerciseMinutes },
                set: { value in
                    guard !context.isPreview else { return }
                    WaterLog.profile(instance) { config, now in
                        WaterGoal.settingExercise(value, in: &config, now: now)
                    }
                }), in: 0...WaterGoal.maxExerciseMinutes, step: 10) {
                    HStack {
                        Text("今日运动")
                            .font(WidgetStyle.label(12))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text(profile.exerciseMinutes == 0 ? tr("没有", context: "amount") : tr("\(profile.exerciseMinutes) 分钟"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                }
                .controlSize(.small)
            Toggle(isOn: Binding(
                get: { profile.unwell },
                set: { on in
                    guard !context.isPreview else { return }
                    WaterLog.profile(instance) { config, now in
                        WaterGoal.settingUnwell(on, in: &config, now: now)
                    }
                })) {
                    Text("发烧或腹泻")
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(panelTint.control)
                .disabled(context.isPreview)
            Text("今日运动和发烧或腹泻只算今天，明天自动清零。")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        let control = content()
        // 标题和分段同一行放不下（英文 "Daily activity" 加三格
        // "Sedentary / Moderate / Heavy labor"）就把分段放到标题下面，
        // 不再把整块撑宽、在滚动区里被裁掉两边。
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                optionTitle(title)
                Spacer(minLength: 4)
                control
            }
            VStack(alignment: .leading, spacing: 6) {
                optionTitle(title)
                control
            }
        }
        .controlSize(.small)
        .disabled(context.isPreview)
    }

    private func optionTitle(_ title: String) -> some View {
        Text(title)
            .font(WidgetStyle.label(12))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .fixedSize()
    }

    fileprivate func numberField(_ title: String, text: Binding<String>, unit: String, prompt: String,
                             field: Field, save: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 4)
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .focused($focus, equals: field)
                .onSubmit(save)
                .disabled(context.isPreview)
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 28, alignment: .leading)
        }
    }
}

/// Chips left to right at their own width, wrapping onto a new row when the
/// next would not fit, so a long drink name is never cut short. Each row is
/// stretched to the full width so the chips still read as one block.
private struct DrinkChipFlow: Layout {
    var spacing: CGFloat

    private func rows(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let needed = rows[rows.count - 1].isEmpty ? size.width : used + spacing + size.width
            if needed > width, !rows[rows.count - 1].isEmpty {
                rows.append([index])
                used = size.width
            } else {
                rows[rows.count - 1].append(index)
                used = needed
            }
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? sizes.reduce(0) { $0 + $1.width + spacing }
        let lines = rows(sizes, width: width)
        let height = lines.reduce(0) { total, line in
            total + (line.map { sizes[$0].height }.max() ?? 0)
        } + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for line in rows(sizes, width: bounds.width) {
            let natural = line.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(0, line.count - 1))
            // Spare room is shared out so a row fills the width, as the old
            // equal-width chips did.
            let extra = line.isEmpty ? 0 : max(0, bounds.width - natural) / CGFloat(line.count)
            let height = line.map { sizes[$0].height }.max() ?? 0
            var x = bounds.minX
            for index in line {
                let width = sizes[index].width + extra
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: width, height: sizes[index].height))
                x += width + spacing
            }
            y += height + spacing
        }
    }
}
