import Foundation

// 桌面宠物：贴在程序坞（系统程序坞或码头扩展栏）上沿的小熊猫。
//
// 这里只有纯逻辑：设置、动作帧、走路发呆睡觉的状态机、废纸篓救回挑哪几项、
// 程序坞上沿的可走范围。窗口、计时器、读程序坞位置和放回原处在 App 和 Services 里，
// 见 `DesktopPetController`。

// MARK: - 设置

/// 设置 ▸ 小组件 ▸ 桌面宠物。两个开关都默认关。
public struct DesktopPetSettings: Codable, Hashable, Sendable {
    /// 总开关：小熊猫贴在程序坞上沿散步。
    public var enabled: Bool = false
    /// 废纸篓救回：刚拖进废纸篓的文件，小熊猫跑过去叼回来放回原处。单独默认关，
    /// 第一次打开时先说明要的权限。
    public var trashRescue: Bool = false

    public init(enabled: Bool = false, trashRescue: Bool = false) {
        self.enabled = enabled
        self.trashRescue = trashRescue
    }

    /// 救回真正在不在工作：总开关和子开关都开着。
    public var rescueActive: Bool { enabled && trashRescue }

    private enum CodingKeys: String, CodingKey { case enabled, trashRescue }

    /// 宽松解码：老状态文件没有这一组，或以后多了认不出的键，都照常读。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        trashRescue = (try? c.decodeIfPresent(Bool.self, forKey: .trashRescue)) ?? false
    }
}

// MARK: - 动作帧

/// 一套动作帧：Resources/Pet/sprites/pet-sprite-<动作>-<1…n>.png，同一只小熊猫、
/// 同一个比例（@2x，走路那张约 105px 高），都朝右；往左走时整张左右翻过来。
public enum DesktopPetStrip: String, CaseIterable, Sendable {
    case walk, run, jump, carry, sleep

    public var frameCount: Int { self == .carry ? 4 : 3 }

    /// 第几帧（从 0 数，超出时绕回）对应的图片名，不带扩展名。
    public func imageName(_ frame: Int) -> String {
        let count = frameCount
        let index = ((frame % count) + count) % count
        return "pet-sprite-\(rawValue)-\(index + 1)"
    }
}

/// 某一刻画哪张图、往上抬多少、要不要翻过来。
public struct DesktopPetPose: Equatable, Sendable {
    /// 图片名（不带扩展名）：动作帧，或 Resources/Pet 里现成的 pet-panda-idle / cheer。
    public var image: String
    /// 脚离程序坞上沿多高（跳起来时大于 0），点。
    public var lift: Double
    /// 朝左：图左右翻过来。
    public var facingLeft: Bool
    /// 显示高度，点。动作帧按图片自己的大小（像素 / 2），静态图给一个固定高度。
    public var height: Double?

    public init(image: String, lift: Double = 0, facingLeft: Bool = false, height: Double? = nil) {
        self.image = image
        self.lift = lift
        self.facingLeft = facingLeft
        self.height = height
    }
}

// MARK: - 状态机

/// 小熊猫在做什么。时间都是绝对时刻，所以帧号和位置都能从“现在”算出来。
public enum DesktopPetActivity: Equatable, Sendable {
    /// 停下发呆，到点再走。
    case idle(until: Date)
    /// 散步到某个横坐标。
    case walk(to: Double)
    /// 睡觉（先打哈欠，再趴下，再团成一团）。
    case sleep(since: Date)
    /// 被点了一下：原地跳，之后回去发呆。
    case jump(since: Date)
    /// 专注计时进行中：坐着陪，不乱跑。
    case sit
    /// 欢呼（专注完成一轮、救回了文件）。
    case cheer(until: Date)
    /// 废纸篓救回的一整段。
    case rescue(DesktopPetRescueStep)
}

/// 救回的几步：跑到废纸篓、叼起来、叼着跑回原来的地方、放下。
public enum DesktopPetRescueStep: Equatable, Sendable {
    case toTrash(trashX: Double, homeX: Double)
    case pickUp(since: Date, homeX: Double)
    case back(homeX: Double)
    /// 到家了，等放回原处的结果。
    case arrived(since: Date)
}

public struct DesktopPetState: Equatable, Sendable {
    /// 小熊猫中心的横坐标（屏幕坐标，点）。
    public var x: Double
    public var facingLeft: Bool
    public var activity: DesktopPetActivity
    /// 这个动作从什么时候开始，算帧号用。
    public var since: Date

    public init(x: Double, facingLeft: Bool = false, activity: DesktopPetActivity, since: Date) {
        self.x = x
        self.facingLeft = facingLeft
        self.activity = activity
        self.since = since
    }
}

/// 散步、发呆、睡觉、跳、坐、欢呼、救回的规则。所有随机都从外面传进来，测试可以定住。
public enum DesktopPetBrain {
    /// 动作帧率：每秒 8 帧，低一点省电，也更像手翻的小动画。
    public static let fps: Double = 8
    /// 睡着以后计时器放慢到每秒 2 次。
    public static let sleepingFPS: Double = 2
    /// 用户多久没碰键盘鼠标就睡觉。
    public static let sleepAfter: TimeInterval = 180
    /// 散步、跑、叼着跑的速度（点 / 秒）。
    public static let walkSpeed: Double = 28
    public static let runSpeed: Double = 190
    public static let carrySpeed: Double = 120
    /// 跑去废纸篓最多花几秒：程序坞很长时跑快一点。
    public static let maxRunTime: TimeInterval = 2.6
    /// 跳一下多久、多高。
    public static let jumpDuration: TimeInterval = 0.75
    public static let jumpHeight: Double = 26
    /// 叼起来那几帧多久。
    public static let pickUpDuration: TimeInterval = 0.9
    /// 欢呼多久。
    public static let cheerDuration: TimeInterval = 2.5
    /// 发呆几秒（下限、上限）。
    public static let idleRange: ClosedRange<Double> = 3...9
    /// 一次散步最远走多远。
    public static let strollRange: ClosedRange<Double> = 40...220
    /// 静态图（发呆、坐、欢呼）显示多高。
    public static let sittingHeight: Double = 62

    /// 刚出现：在可走范围中间偏左一点发呆。
    public static func initial(lane: ClosedRange<Double>, now: Date) -> DesktopPetState {
        let x = lane.lowerBound + (lane.upperBound - lane.lowerBound) * 0.35
        return DesktopPetState(x: x, activity: .idle(until: now.addingTimeInterval(4)), since: now)
    }

    /// 往前走一步。`dt` 是距上一步的秒数；`userIdle` 是用户多久没操作；
    /// `focusing` 是专注计时正在走（而且能用专注陪伴）；`random` 是 0…1 的随机数来源。
    public static func step(_ state: DesktopPetState, dt: TimeInterval, now: Date,
                            lane: ClosedRange<Double>, userIdle: TimeInterval, focusing: Bool,
                            random: () -> Double) -> DesktopPetState {
        var next = state
        next.x = clamp(state.x, lane)
        let dt = max(0, min(dt, 1))

        // 救回、跳、欢呼正在演的，演完再说；其余的按专注和睡觉打断。
        switch state.activity {
        case .rescue(let step):
            return rescueStep(next, step: step, dt: dt, now: now, lane: lane)
        case .jump(let since):
            if now.timeIntervalSince(since) < jumpDuration { return next }
            return settle(next, now: now, focusing: focusing, random: random)
        case .cheer(let until):
            if now < until { return next }
            return settle(next, now: now, focusing: focusing, random: random)
        default:
            break
        }

        if focusing {
            if next.activity != .sit { next.activity = .sit; next.since = now }
            return next
        }
        if userIdle >= sleepAfter {
            if case .sleep = next.activity { return next }
            next.activity = .sleep(since: now)
            next.since = now
            return next
        }

        switch next.activity {
        case .sit, .sleep:
            // 专注结束、或用户回来了：醒过来发呆一会儿。
            next.activity = .idle(until: now.addingTimeInterval(lerp(idleRange, random())))
            next.since = now
        case .idle(let until):
            guard now >= until else { return next }
            let target = strollTarget(from: next.x, lane: lane, random: random)
            if abs(target - next.x) < 4 {
                next.activity = .idle(until: now.addingTimeInterval(lerp(idleRange, random())))
            } else {
                next.activity = .walk(to: target)
                next.facingLeft = target < next.x
            }
            next.since = now
        case .walk(let target):
            let target = clamp(target, lane)
            let moved = move(next.x, toward: target, by: walkSpeed * dt)
            next.x = moved
            next.facingLeft = target < state.x
            if moved == target {
                next.activity = .idle(until: now.addingTimeInterval(lerp(idleRange, random())))
                next.since = now
            }
        default:
            break
        }
        return next
    }

    /// 被点了一下：跳起来（睡着的也醒过来跳）。救回途中不理会。
    public static func poked(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        if case .rescue = state.activity { return state }
        if case .jump = state.activity { return state }
        var next = state
        next.activity = .jump(since: now)
        next.since = now
        return next
    }

    /// 欢呼（专注完成一轮）。救回途中不打断。
    public static func cheer(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        if case .rescue = state.activity { return state }
        var next = state
        next.activity = .cheer(until: now.addingTimeInterval(cheerDuration))
        next.since = now
        return next
    }

    /// 开始救回：从现在的位置跑去废纸篓。
    public static func startRescue(_ state: DesktopPetState, trashX: Double, lane: ClosedRange<Double>,
                                   now: Date) -> DesktopPetState {
        var next = state
        let trash = clamp(trashX, lane)
        next.activity = .rescue(.toTrash(trashX: trash, homeX: clamp(state.x, lane)))
        next.facingLeft = trash < state.x
        next.since = now
        return next
    }

    /// 放回原处有了结果：成功就欢呼，失败就回去发呆（气泡由外面另外弹）。
    public static func finishRescue(_ state: DesktopPetState, succeeded: Bool, now: Date) -> DesktopPetState {
        var next = state
        next.facingLeft = false
        next.since = now
        next.activity = succeeded
            ? .cheer(until: now.addingTimeInterval(cheerDuration))
            : .idle(until: now.addingTimeInterval(idleRange.upperBound))
        return next
    }

    /// 救回走到了“到家”这一步、正等着放回原处。
    public static func awaitingPutBack(_ state: DesktopPetState) -> Bool {
        if case .rescue(.arrived) = state.activity { return true }
        return false
    }

    /// 这一刻画什么。
    public static func pose(_ state: DesktopPetState, now: Date) -> DesktopPetPose {
        let elapsed = max(0, now.timeIntervalSince(state.since))
        let frame = Int(elapsed * fps)
        let left = state.facingLeft
        switch state.activity {
        case .idle:
            return DesktopPetPose(image: "pet-panda-idle", height: sittingHeight)
        case .sit:
            return DesktopPetPose(image: "pet-panda-idle", height: sittingHeight)
        case .cheer:
            return DesktopPetPose(image: "pet-panda-cheer", height: sittingHeight + 4)
        case .walk:
            return DesktopPetPose(image: DesktopPetStrip.walk.imageName(frame), facingLeft: left)
        case .jump:
            let t = min(1, elapsed / jumpDuration)
            let index = t < 0.2 ? 0 : (t < 0.8 ? 1 : 2)
            return DesktopPetPose(image: DesktopPetStrip.jump.imageName(index),
                                  lift: jumpLift(t), facingLeft: left)
        case .sleep(let since):
            let asleep = now.timeIntervalSince(since)
            let index = asleep < 1.6 ? 0 : (asleep < 4 ? 1 : 2)
            return DesktopPetPose(image: DesktopPetStrip.sleep.imageName(index))
        case .rescue(let step):
            switch step {
            case .toTrash:
                return DesktopPetPose(image: DesktopPetStrip.run.imageName(frame), facingLeft: left)
            case .pickUp(let since, _):
                let t = min(1, now.timeIntervalSince(since) / pickUpDuration)
                let index = t < 0.4 ? 0 : (t < 0.75 ? 1 : 2)
                return DesktopPetPose(image: DesktopPetStrip.carry.imageName(index), facingLeft: left)
            case .back:
                // 叼着跑：第 4 帧加一点上下颠，看着在跑。
                return DesktopPetPose(image: DesktopPetStrip.carry.imageName(3),
                                      lift: frame % 2 == 0 ? 0 : 3, facingLeft: left)
            case .arrived:
                return DesktopPetPose(image: DesktopPetStrip.carry.imageName(2))
            }
        }
    }

    /// 睡着时计时器放慢。
    public static func tickRate(_ state: DesktopPetState) -> Double {
        if case .sleep = state.activity { return sleepingFPS }
        return fps
    }

    // MARK: 内部

    static func jumpLift(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return 4 * jumpHeight * t * (1 - t)
    }

    private static func settle(_ state: DesktopPetState, now: Date, focusing: Bool,
                               random: () -> Double) -> DesktopPetState {
        var next = state
        next.since = now
        next.activity = focusing ? .sit : .idle(until: now.addingTimeInterval(lerp(idleRange, random())))
        return next
    }

    private static func rescueStep(_ state: DesktopPetState, step: DesktopPetRescueStep, dt: TimeInterval,
                                   now: Date, lane: ClosedRange<Double>) -> DesktopPetState {
        var next = state
        switch step {
        case .toTrash(let trashX, let homeX):
            let distance = abs(trashX - homeX)
            let speed = max(runSpeed, distance / maxRunTime)
            next.x = move(state.x, toward: trashX, by: speed * dt)
            next.facingLeft = trashX < state.x
            if next.x == trashX {
                next.activity = .rescue(.pickUp(since: now, homeX: homeX))
                next.since = now
            }
        case .pickUp(let since, let homeX):
            if now.timeIntervalSince(since) >= pickUpDuration {
                next.activity = .rescue(.back(homeX: clamp(homeX, lane)))
                next.facingLeft = homeX < state.x
                next.since = now
            }
        case .back(let homeX):
            next.x = move(state.x, toward: homeX, by: carrySpeed * dt)
            next.facingLeft = homeX < state.x
            if next.x == homeX {
                next.activity = .rescue(.arrived(since: now))
                next.since = now
            }
        case .arrived:
            break
        }
        return next
    }

    static func strollTarget(from x: Double, lane: ClosedRange<Double>, random: () -> Double) -> Double {
        let distance = lerp(strollRange, random())
        let goLeft = random() < 0.5
        var target = goLeft ? x - distance : x + distance
        // 走不出去就掉头。
        if target < lane.lowerBound || target > lane.upperBound {
            target = goLeft ? x + distance : x - distance
        }
        return clamp(target, lane)
    }

    static func move(_ x: Double, toward target: Double, by step: Double) -> Double {
        if abs(target - x) <= step { return target }
        return x + (target > x ? step : -step)
    }

    static func clamp(_ x: Double, _ lane: ClosedRange<Double>) -> Double {
        min(lane.upperBound, max(lane.lowerBound, x))
    }

    static func lerp(_ range: ClosedRange<Double>, _ t: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * min(1, max(0, t))
    }
}

// MARK: - 站在哪

/// 小熊猫站的那条程序坞：屏幕坐标（左下原点）里的矩形，废纸篓在哪。
public struct DesktopPetPerch: Equatable, Sendable {
    public var frame: CGRect
    /// 废纸篓图标中心的横坐标；拿不到时是 nil，用程序坞最右端。
    public var trashX: Double?

    public init(frame: CGRect, trashX: Double? = nil) {
        self.frame = frame
        self.trashX = trashX
    }

    /// 小熊猫中心能走到的范围：两头各留半只小熊猫。
    public var lane: ClosedRange<Double> {
        let inset = min(36, frame.width / 4)
        let low = Double(frame.minX) + inset
        let high = max(low, Double(frame.maxX) - inset)
        return low...high
    }

    /// 跑去哪：废纸篓，没有时程序坞最右端。
    public var rescueX: Double {
        DesktopPetBrain.clamp(trashX ?? lane.upperBound, lane)
    }
}

/// 跟系统程序坞还是码头扩展栏，以及什么时候不显示。
public enum DesktopPetPlacement {
    /// 系统程序坞的读数。
    public struct SystemDock: Equatable, Sendable {
        public var frame: CGRect?
        public var trashX: Double?
        public var atBottom: Bool
        public var autoHide: Bool

        public init(frame: CGRect?, trashX: Double? = nil, atBottom: Bool, autoHide: Bool) {
            self.frame = frame
            self.trashX = trashX
            self.atBottom = atBottom
            self.autoHide = autoHide
        }
    }

    /// 码头扩展栏的读数。
    public struct Shelf: Equatable, Sendable {
        public var frame: CGRect?
        public var atBottom: Bool
        /// 自动隐藏滑到屏幕外。
        public var tucked: Bool

        public init(frame: CGRect?, atBottom: Bool, tucked: Bool) {
            self.frame = frame
            self.atBottom = atBottom
            self.tucked = tucked
        }
    }

    /// 站在哪条程序坞上，nil 是这会儿不显示：全屏 App 在前、程序坞自动隐藏、
    /// 两条都不在底边。系统程序坞在底边、看得见时跟它；否则跟在底边、没收起来的扩展栏。
    public static func perch(system: SystemDock, shelf: Shelf, fullScreen: Bool) -> DesktopPetPerch? {
        guard !fullScreen else { return nil }
        if system.atBottom, !system.autoHide, let frame = system.frame, usable(frame) {
            return DesktopPetPerch(frame: frame, trashX: system.trashX)
        }
        if shelf.atBottom, !shelf.tucked, let frame = shelf.frame, usable(frame) {
            return DesktopPetPerch(frame: frame, trashX: nil)
        }
        return nil
    }

    /// 读不到程序坞的位置（没有辅助功能权限）时按屏幕估一个：可见区域底下空出来的
    /// 就是程序坞的高度，宽度按图标个数估，居中。
    public static func estimatedDock(screen: CGRect, visible: CGRect, tileSize: Double, tiles: Int) -> CGRect? {
        let height = visible.minY - screen.minY
        guard height > 8 else { return nil }
        let width = min(screen.width * 0.9, max(160, (Double(tiles) + 2) * (tileSize + 4) + 24))
        return CGRect(x: screen.midX - width / 2, y: screen.minY, width: width, height: height)
    }

    /// 一个窗口算不算铺满了这块屏幕（全屏 App）：差几个点也算。
    public static func coversScreen(_ window: CGRect, screen: CGRect) -> Bool {
        abs(window.minX - screen.minX) <= 2 && abs(window.minY - screen.minY) <= 2
            && abs(window.width - screen.width) <= 2 && abs(window.height - screen.height) <= 2
    }

    private static func usable(_ frame: CGRect) -> Bool {
        frame.width >= 80 && frame.height >= 20
    }
}

// MARK: - 废纸篓救回

public enum DesktopPetRescue {
    /// 只认这么多秒内拖进去的。
    public static let freshWindow: TimeInterval = 10
    /// 一次最多叼回几个；多了不自动放回，只弹气泡让人自己点。
    public static let maxItems = 3

    /// 刚扔进来、还没处理过的几项。`seen` 是打开开关时已经在废纸篓里的和处理过的；
    /// 清空废纸篓、放回原处只会让项目变少，不会出现在这里。
    public static func fresh(_ items: [TrashedItem], seen: Set<String>, now: Date) -> [TrashedItem] {
        items.filter { item in
            !seen.contains(item.trashName)
                && item.date <= now.addingTimeInterval(2)
                && now.timeIntervalSince(item.date) <= freshWindow
        }
    }

    /// 自动放回原处，还是只给一个气泡按钮：项目太多、或这一下扔进去的比列出来的多
    /// （废纸篓面板只列最近几个，后面的看不到）时只给按钮。
    public static func autoPutBack(fresh: Int, added: Int) -> Bool {
        fresh > 0 && fresh <= maxItems && added <= fresh
    }

    /// 气泡上的字。
    public static func bubbleTitle(count: Int) -> String {
        count > 1 ? tr("放回原处（\(count) 项）") : tr("放回原处")
    }

    /// 交给访达的 AppleScript：把废纸篓里的这一项移回原来的文件夹，名字改回原名。
    /// 路径和名字从参数传进去，不拼进脚本。
    public static let finderScript = """
        on run argv
            set src to (POSIX file (item 1 of argv)) as alias
            set dest to (POSIX file (item 2 of argv)) as alias
            set wanted to item 3 of argv
            tell application "Finder"
                set moved to move src to dest
                if name of moved is not wanted then set name of moved to wanted
            end tell
        end run
        """
}

// MARK: - 专注陪伴（码头 Pro）

/// 专注计时面板里顺着竹竿往上爬的小熊猫，和桌面宠物专注时坐着陪、结束时欢呼。
public enum FocusPandaClimb {
    /// 中途手动结束或重置：滑下来；完成一轮：到顶欢呼。
    public enum Event: Equatable, Sendable {
        case slide, cheer
    }

    /// 专注环节开始了（走着或暂停着）。
    public static func isActive(_ state: TimerState) -> Bool {
        state.phase == .focus && (state.deadline != nil || state.paused != nil)
    }

    /// 专注进度 0…1：0 在竹竿底，1 到顶。没开始时是 0。
    public static func progress(_ state: TimerState, now: Date) -> Double {
        guard state.phase == .focus else { return 0 }
        let total = max(1, state.duration ?? Double(max(1, state.minutes) * 60))
        let left: TimeInterval
        if let paused = state.paused {
            left = paused
        } else if let deadline = state.deadline {
            left = deadline.timeIntervalSince(now)
        } else {
            return 0
        }
        return min(1, max(0, 1 - left / total))
    }

    /// 两次读数之间发生了什么。`now` 用来分辨“合盖很久回来、计时器自己回到开头”，
    /// 那不是手动结束，不滑。
    public static func event(from old: TimerState, to new: TimerState, now: Date) -> Event? {
        guard isActive(old) else { return nil }
        if new.phase != .focus, new.completed != old.completed {
            if let deadline = old.deadline, now.timeIntervalSince(deadline) > FocusCycle.staleAfter { return nil }
            return .cheer
        }
        if new.phase == .focus, !isActive(new) {
            if let deadline = old.deadline, deadline <= now { return nil }
            return .slide
        }
        return nil
    }

    /// 小熊猫离竹竿底多高：`travel` 是能爬的高度（竹竿高减去小熊猫高）。
    public static func climbOffset(progress: Double, travel: Double) -> Double {
        max(0, travel) * min(1, max(0, progress))
    }
}

/// 专注陪伴是码头 Pro：免费用户在竹竿旁看到一只静态的小熊猫。
public extension ProLicenseGate {
    static func canUseFocusPanda(unlocked: Bool) -> Bool {
        canUse(.focusPanda, unlocked: unlocked)
    }
}
