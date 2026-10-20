import XCTest

/// 系统活动面板：环形缓冲、24 小时、每分钟汇总、进程排名、超阈值提醒、卡片读数。
final class SystemActivityTests: XCTestCase {

    // MARK: 环形缓冲

    func testRingBufferKeepsTheNewestInOrder() {
        var ring = RingBuffer<Int>(capacity: 3)
        XCTAssertTrue(ring.isEmpty)
        XCTAssertNil(ring.last)
        ring.append(1)
        ring.append(2)
        XCTAssertEqual(ring.elements, [1, 2])
        XCTAssertEqual(ring.last, 2)
        ring.append(3)
        ring.append(4)
        ring.append(5)
        XCTAssertEqual(ring.elements, [3, 4, 5])
        XCTAssertEqual(ring.count, 3)
        XCTAssertEqual(ring.last, 5)
        ring.append(6)
        ring.append(7)
        XCTAssertEqual(ring.elements, [5, 6, 7])
        ring.removeAll()
        XCTAssertEqual(ring.elements, [])
    }

    func testRingBufferRoundTripsAndTrimsToCapacity() throws {
        var ring = RingBuffer<Int>(capacity: 4)
        for i in 1...10 { ring.append(i) }
        let data = try JSONEncoder().encode(ring)
        let back = try JSONDecoder().decode(RingBuffer<Int>.self, from: data)
        XCTAssertEqual(back, ring)
        XCTAssertEqual(back.elements, [7, 8, 9, 10])

        let odd = Data(#"{"capacity":2,"items":[1,2,3]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RingBuffer<Int>.self, from: odd).elements, [2, 3])
        XCTAssertEqual(RingBuffer<Int>(capacity: 0).capacity, 1)
    }

    // MARK: 24 小时

    private func sample(_ minute: Int, cpu: Double = 0.2, net: Double = 1_000, disk: Double = 200e9) -> SystemMinuteSample {
        SystemMinuteSample(minute: minute, cpu: cpu, memory: 0.5, network: net, diskFree: disk)
    }

    func testHistoryKeepsOneDayAndIgnoresGoingBack() {
        var history = SystemActivityHistory()
        XCTAssertTrue(history.record(sample(100)))
        XCTAssertFalse(history.record(sample(100)))
        XCTAssertFalse(history.record(sample(99)))
        for m in 101...(100 + 1500) { history.record(sample(m)) }
        XCTAssertEqual(history.samples.count, SystemActivityHistory.minutes)
        let now = SystemActivityHistory.date(ofMinute: 1600)
        let window = history.window(now: now)
        XCTAssertEqual(window.first?.minute, 1600 - 1439)
        XCTAssertEqual(window.last?.minute, 1600)
        // 两小时后再看，前两小时已经出了窗口。
        XCTAssertEqual(history.window(now: now + 7200).count, SystemActivityHistory.minutes - 120)
    }

    func testPeakIsHighestOrLeastFreeDisk() {
        var history = SystemActivityHistory()
        history.record(sample(10, cpu: 0.3, disk: 210e9))
        history.record(sample(11, cpu: 0.94, disk: 205e9))
        history.record(sample(12, cpu: 0.4, disk: 212e9))
        let now = SystemActivityHistory.date(ofMinute: 12)
        XCTAssertEqual(history.peak(.cpu, now: now)?.minute, 11)
        XCTAssertEqual(history.peak(.disk, now: now)?.minute, 11)
        XCTAssertNil(SystemActivityHistory().peak(.cpu, now: now))
    }

    func testSegmentsBreakAtGapsAndScale() {
        var history = SystemActivityHistory()
        let end = 10_000
        history.record(sample(end - 30, cpu: 0))
        history.record(sample(end - 29, cpu: 0.5))
        history.record(sample(end - 1, cpu: 1))
        history.record(sample(end, cpu: 1))
        let parts = history.segments(.cpu, now: SystemActivityHistory.date(ofMinute: end))
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].map(\.y), [0, 0.5])
        XCTAssertEqual(parts[1].last?.x ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(parts[1].last?.y ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(SystemActivityHistory.range(.network, values: [10]).upperBound, 64 * 1024)
        let disk = SystemActivityHistory.range(.disk, values: [200e9, 200e9])
        XCTAssertTrue(disk.contains(200e9))
        XCTAssertGreaterThan(disk.upperBound - disk.lowerBound, 0)
    }

    func testAccumulatorAveragesEachMinute() {
        var acc = SystemMinuteAccumulator()
        let base = Date(timeIntervalSince1970: 600)  // 第 10 分钟开头
        XCTAssertNil(acc.add(cpu: 0.2, memory: 0.5, network: 100, diskFree: 50e9, at: base))
        XCTAssertNil(acc.add(cpu: 0.4, memory: 0.7, network: 300, diskFree: 0, at: base + 30))
        let done = acc.add(cpu: 0.9, memory: 0.1, network: 0, diskFree: 0, at: base + 61)
        XCTAssertEqual(done?.minute, 10)
        XCTAssertEqual(done?.cpu ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(done?.memory ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertEqual(done?.network ?? 0, 200, accuracy: 1e-9)
        // 没读到磁盘的一秒（0）不把可用空间拉低。
        XCTAssertEqual(done?.diskFree, 50e9)
        // 休眠十分钟后醒来，交出的是睡前那一分钟。
        let late = acc.add(cpu: 0.1, memory: 0.1, network: 0, diskFree: 0, at: base + 61 + 600)
        XCTAssertEqual(late?.minute, 11)
        XCTAssertEqual(late?.diskFree, 50e9)
    }

    // MARK: 文字

    func testReadouts() {
        XCTAssertEqual(SystemReadout.rate(2_400_000).value, "2.4")
        XCTAssertEqual(SystemReadout.rate(2_400_000).unit, "MB/s")
        XCTAssertEqual(SystemReadout.rate(860_000).value, "860")
        XCTAssertEqual(SystemReadout.rate(860_000).unit, "KB/s")
        XCTAssertEqual(SystemReadout.rate(12).unit, "B/s")
        XCTAssertEqual(SystemReadout.shortRate(2_400_000), "2.4M")
        XCTAssertEqual(SystemReadout.shortRate(500), "0K")
        XCTAssertEqual(SystemReadout.gigabytes(212e9), "212")
        XCTAssertEqual(SystemReadout.gigabytes(3.1e9), "3.1")
        XCTAssertEqual(SystemReadout.percent(0.234), 23)
        XCTAssertEqual(SystemReadout.percent(1.4), 100)
        XCTAssertEqual(SystemReadout.uptime(3 * 86_400 + 4 * 3_600 + 59), "已运行 3 天 4 小时")
        XCTAssertEqual(SystemReadout.uptime(4 * 3_600 + 12 * 60), "已运行 4 小时 12 分钟")
        XCTAssertEqual(SystemReadout.uptime(30), "已运行 0 分钟")
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(SystemReadout.clock(minute: 14 * 60 + 20, timeZone: utc), "14:20")
        let peak = SystemMinuteSample(minute: 14 * 60 + 20, cpu: 0.94, memory: 0.5, network: 2_400_000, diskFree: 205e9)
        XCTAssertEqual(SystemReadout.peakLabel(.cpu, sample: peak, timeZone: utc), "峰值 94% · 14:20")
        XCTAssertEqual(SystemReadout.peakLabel(.network, sample: peak, timeZone: utc), "峰值 2.4 MB/s · 14:20")
        XCTAssertEqual(SystemReadout.peakLabel(.disk, sample: peak, timeZone: utc), "最少可用 205 GB · 14:20")
    }

    // MARK: 进程

    func testAppBundleIsTheOutermostApp() {
        XCTAssertEqual(ProcessRanking.appBundle(fromPath: "/Applications/Browser.app/Contents/Frameworks/X.framework/Helpers/Browser Helper.app/Contents/MacOS/Browser Helper"),
                       "/Applications/Browser.app")
        XCTAssertEqual(ProcessRanking.appBundle(fromPath: "/Applications/Editor.app"), "/Applications/Editor.app")
        XCTAssertNil(ProcessRanking.appBundle(fromPath: "/usr/sbin/mds"))
        XCTAssertEqual(ProcessRanking.bundleName("/Applications/视频剪辑.app"), "视频剪辑")
    }

    func testTopGroupsHelpersAndSorts() {
        let previous: [Int32: UInt64] = [1: 0, 2: 0, 3: 0, 4: 500]
        let second: UInt64 = 1_000_000_000
        let current = [
            ProcessReading(pid: 1, group: "/A.app", name: "A", cpuNanos: 400_000_000, memory: 1_000),
            ProcessReading(pid: 2, group: "/A.app", name: "A", cpuNanos: 220_000_000, memory: 2_000),
            ProcessReading(pid: 3, group: "pid:3", name: "mds", cpuNanos: 900_000_000, memory: 10),
            // pid 被复用：计数比上次小，记 0。
            ProcessReading(pid: 4, group: "pid:4", name: "new", cpuNanos: 100, memory: 9_000),
            // 刚启动，上次没有。
            ProcessReading(pid: 5, group: "pid:5", name: "fresh", cpuNanos: 5_000_000_000, memory: 5),
        ]
        let byCPU = ProcessRanking.top(previous: previous, current: current, elapsedNanos: second, sort: .cpu)
        XCTAssertEqual(byCPU.map(\.name), ["mds", "A", "new", "fresh"])
        XCTAssertEqual(byCPU[1].cpuPercent, 62, accuracy: 1e-9)
        XCTAssertEqual(byCPU[1].pids, [1, 2])
        XCTAssertEqual(byCPU[1].memory, 3_000)
        XCTAssertEqual(byCPU[2].cpuPercent, 0)
        let byMemory = ProcessRanking.top(previous: previous, current: current, elapsedNanos: second, sort: .memory, limit: 2)
        XCTAssertEqual(byMemory.map(\.name), ["new", "A"])
        XCTAssertEqual(ProcessRanking.top(previous: [:], current: [], elapsedNanos: 0, sort: .cpu), [])
    }

    func testProcessTexts() {
        XCTAssertEqual(ProcessRanking.cpuText(62.4), "62%")
        XCTAssertEqual(ProcessRanking.cpuText(2.04), "2.0%")
        XCTAssertEqual(ProcessRanking.memoryText(3_100_000_000), "3.1 GB")
        XCTAssertEqual(ProcessRanking.memoryText(420_000_000), "420 MB")
    }

    // MARK: 规则

    func testRulesDefaultOffAndRoundTrip() {
        let empty = WidgetConfig()
        let defaults = SystemAlertRules.rules(empty)
        XCTAssertEqual(defaults.map(\.metric), [.cpu, .memory, .disk])
        XCTAssertTrue(defaults.allSatisfy { !$0.enabled })

        var config = WidgetConfig()
        var rules = defaults
        rules[0].enabled = true
        rules[1].threshold = 87  // 对齐到 5 的步长
        rules.append(SystemAlertRule(id: "net", metric: .network, threshold: 999, minutes: 0, enabled: true))
        SystemAlertRules.store(rules, in: &config)
        let back = SystemAlertRules.rules(config)
        XCTAssertEqual(back.count, 4)
        XCTAssertTrue(back[0].enabled)
        XCTAssertEqual(back[1].threshold, 85)
        XCTAssertEqual(back[3].threshold, 200)
        XCTAssertEqual(back[3].minutes, 1)

        var broken = WidgetConfig()
        broken.set(SystemAlertRules.key, .string("not json"))
        XCTAssertEqual(SystemAlertRules.rules(broken), defaults)
        var cleared = WidgetConfig()
        SystemAlertRules.store([], in: &cleared)
        XCTAssertEqual(SystemAlertRules.rules(cleared), [])
    }

    func testRuleWordingAndNewRule() {
        let cpu = SystemAlertRule(id: "a", metric: .cpu, threshold: 90, minutes: 5, enabled: true)
        XCTAssertEqual(cpu.summary, "CPU > 90% 持续 5 分钟")
        let disk = SystemAlertRule(id: "b", metric: .disk, threshold: 20, minutes: 5, enabled: true)
        XCTAssertEqual(disk.summary, "磁盘可用 < 20 GB 持续 5 分钟")
        XCTAssertEqual(cpu.switching(to: .network).threshold, 50)
        XCTAssertEqual(cpu.switching(to: .cpu), cpu)
        let next = SystemAlertRules.newRule(after: [cpu, disk], id: "n")
        XCTAssertEqual(next.metric, .memory)
        XCTAssertTrue(next.enabled)
        let all = SystemMetricKind.allCases.map { SystemAlertRule(metric: $0, threshold: 50, minutes: 1, enabled: true) }
        XCTAssertEqual(SystemAlertRules.newRule(after: all).metric, .cpu)
    }

    func testTrackerFiresOnceAfterTheDurationAndRearms() {
        var tracker = SystemAlertTracker()
        let rule = SystemAlertRule(id: "cpu", metric: .cpu, threshold: 90, minutes: 5, enabled: true)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let hot = SystemAlertReading(cpu: 0.95)
        XCTAssertEqual(tracker.check(hot, rules: [rule], unlocked: true, now: t0).alerts, [])
        let early = tracker.check(hot, rules: [rule], unlocked: true, now: t0 + 299)
        XCTAssertEqual(early.alerts, [])
        XCTAssertEqual(early.firing, [])
        let due = tracker.check(hot, rules: [rule], unlocked: true, now: t0 + 300)
        XCTAssertEqual(due.alerts.map(\.ruleID), ["cpu"])
        XCTAssertEqual(due.alerts.first?.title, "CPU 占用已持续 5 分钟超过 90%")
        XCTAssertEqual(due.firing, [.cpu])
        // 一直超着不再响，卡片保持红色。
        let still = tracker.check(hot, rules: [rule], unlocked: true, now: t0 + 900)
        XCTAssertEqual(still.alerts, [])
        XCTAssertEqual(still.firing, [.cpu])
        // 回落后重新计时。
        XCTAssertEqual(tracker.check(SystemAlertReading(cpu: 0.5), rules: [rule], unlocked: true, now: t0 + 901).firing, [])
        XCTAssertEqual(tracker.check(hot, rules: [rule], unlocked: true, now: t0 + 1_000).alerts, [])
        XCTAssertEqual(tracker.check(hot, rules: [rule], unlocked: true, now: t0 + 1_300).alerts.count, 1)
    }

    func testTrackerDipResetsTheClock() {
        var tracker = SystemAlertTracker()
        let rule = SystemAlertRule(id: "m", metric: .memory, threshold: 85, minutes: 10, enabled: true)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = tracker.check(SystemAlertReading(memory: 0.9), rules: [rule], unlocked: true, now: t0)
        _ = tracker.check(SystemAlertReading(memory: 0.8), rules: [rule], unlocked: true, now: t0 + 400)
        _ = tracker.check(SystemAlertReading(memory: 0.9), rules: [rule], unlocked: true, now: t0 + 401)
        XCTAssertEqual(tracker.check(SystemAlertReading(memory: 0.9), rules: [rule], unlocked: true, now: t0 + 700).alerts, [])
        XCTAssertEqual(tracker.check(SystemAlertReading(memory: 0.9), rules: [rule], unlocked: true, now: t0 + 1_001).alerts.count, 1)
    }

    func testTrackerDiskNetworkAndMissingReadings() {
        var tracker = SystemAlertTracker()
        let disk = SystemAlertRule(id: "d", metric: .disk, threshold: 20, minutes: 1, enabled: true)
        let net = SystemAlertRule(id: "n", metric: .network, threshold: 10, minutes: 1, enabled: true)
        let off = SystemAlertRule(id: "o", metric: .cpu, threshold: 50, minutes: 1, enabled: false)
        let t0 = Date(timeIntervalSince1970: 0)
        let reading = SystemAlertReading(cpu: 1, network: 12_000_000, diskFree: 15e9)
        _ = tracker.check(reading, rules: [disk, net, off], unlocked: true, now: t0)
        let due = tracker.check(reading, rules: [disk, net, off], unlocked: true, now: t0 + 60)
        XCTAssertEqual(Set(due.alerts.map(\.ruleID)), ["d", "n"])
        XCTAssertEqual(due.firing, [.disk, .network])
        XCTAssertEqual(due.alerts.first { $0.ruleID == "d" }?.title, "磁盘可用空间不到 20 GB")
        // 没读到磁盘（0 或 nil）不算回落，红色保持。
        let missing = tracker.check(SystemAlertReading(network: 12_000_000), rules: [disk, net], unlocked: true, now: t0 + 61)
        XCTAssertEqual(missing.firing, [.disk, .network])
        XCTAssertEqual(missing.alerts, [])
    }

    func testLockedProDoesNothingAndForgets() {
        var tracker = SystemAlertTracker()
        let rule = SystemAlertRule(id: "cpu", metric: .cpu, threshold: 90, minutes: 1, enabled: true)
        let t0 = Date(timeIntervalSince1970: 0)
        let hot = SystemAlertReading(cpu: 0.99)
        XCTAssertFalse(ProLicenseGate.systemAlertsActive(unlocked: false))
        XCTAssertTrue(ProLicenseGate.systemAlertsActive(unlocked: true))
        _ = tracker.check(hot, rules: [rule], unlocked: true, now: t0)
        let locked = tracker.check(hot, rules: [rule], unlocked: false, now: t0 + 120)
        XCTAssertEqual(locked.alerts, [])
        XCTAssertEqual(locked.firing, [])
        // 解锁后从头计时。
        XCTAssertEqual(tracker.check(hot, rules: [rule], unlocked: true, now: t0 + 121).alerts, [])
        XCTAssertEqual(tracker.check(hot, rules: [rule], unlocked: true, now: t0 + 181).alerts.count, 1)
    }

    func testRemovedRuleStopsFiring() {
        var tracker = SystemAlertTracker()
        let rule = SystemAlertRule(id: "cpu", metric: .cpu, threshold: 90, minutes: 1, enabled: true)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = tracker.check(SystemAlertReading(cpu: 1), rules: [rule], unlocked: true, now: t0)
        XCTAssertEqual(tracker.check(SystemAlertReading(cpu: 1), rules: [rule], unlocked: true, now: t0 + 60).firing, [.cpu])
        var off = rule
        off.enabled = false
        XCTAssertEqual(tracker.check(SystemAlertReading(cpu: 1), rules: [off], unlocked: true, now: t0 + 61).firing, [])
    }

    // MARK: 卡片读数

    func testCardMetricsToggleKeepsOrderAndOne() {
        XCTAssertEqual(SystemCardMetrics.shown(WidgetConfig()), ["cpu", "memory"])
        XCTAssertEqual(SystemCardMetrics.toggling("network", in: ["cpu", "memory"]), ["cpu", "memory", "network"])
        XCTAssertEqual(SystemCardMetrics.toggling("cpu", in: ["disk", "cpu"]), ["disk"])
        XCTAssertEqual(SystemCardMetrics.toggling("disk", in: ["disk"]), ["disk"])
        XCTAssertEqual(SystemCardMetrics.toggling("nope", in: ["cpu"]), ["cpu"])
        XCTAssertEqual(SystemCardMetrics.toggling("cpu", in: ["disk", "memory"]), ["disk", "memory", "cpu"],
                       "拖好的顺序不被打乱，新勾的接在最后")
        var config = WidgetConfig()
        config.set("metrics", .list([.string("bogus")]))
        XCTAssertEqual(SystemCardMetrics.shown(config), ["cpu", "memory"])
    }

    func testNetworkFractionIsLogScaled() {
        XCTAssertEqual(SystemCardMetrics.networkFraction(0), 0)
        XCTAssertEqual(SystemCardMetrics.networkFraction(10_000), 0)
        XCTAssertEqual(SystemCardMetrics.networkFraction(100_000_000), 1, accuracy: 1e-9)
        XCTAssertEqual(SystemCardMetrics.networkFraction(1e12), 1)
        XCTAssertEqual(SystemCardMetrics.networkFraction(1_000_000), 0.5, accuracy: 1e-9)
    }
}
