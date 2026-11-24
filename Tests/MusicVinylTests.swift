import XCTest

/// 正在播放的黑胶模式：样式开关、唱台布局、唱臂按进度落针、唱片转速和水波纹。
final class MusicVinylTests: XCTestCase {

    // MARK: 样式

    func testStyleDefaultsToStandard() {
        XCTAssertEqual(MusicPanelStyle.of(WidgetConfig()), .standard, "没选过的卡片外观不变")
        var config = WidgetConfig()
        config.set(MusicPanelStyle.key, .string("唱片机"))
        XCTAssertEqual(MusicPanelStyle.of(config), .standard, "认不得的值按标准")
    }

    func testChoosingVinylAndBack() {
        let vinyl = MusicPanelStyle.choosing(.vinyl, in: WidgetConfig())
        XCTAssertEqual(MusicPanelStyle.of(vinyl), .vinyl)
        let back = MusicPanelStyle.choosing(.standard, in: vinyl)
        XCTAssertEqual(MusicPanelStyle.of(back), .standard)
        XCTAssertEqual(ProLicenseGate.musicPanelStyle(config: back, unlocked: true), .standard,
                       "选了精简要记住，不被 Pro 默认黑胶盖掉")
        XCTAssertEqual(ProLicenseGate.musicPanelStyle(config: WidgetConfig(), unlocked: false), .vinyl,
                       "没选过的卡片默认黑胶，免费也是")
    }

    func testSummaryMentionsVinylOnlyForMusic() {
        let vinyl = MusicPanelStyle.choosing(.vinyl, in: WidgetConfig())
        XCTAssertEqual(WidgetAppearance.summary(vinyl, kind: .music), "黑胶模式")
        XCTAssertTrue(WidgetAppearance.isCustomized(vinyl, kind: .music))
        XCTAssertEqual(WidgetAppearance.summary(vinyl, kind: .battery), "默认", "别的卡片不认这个键")
        XCTAssertEqual(WidgetAppearance.summary(WidgetConfig(), kind: .music), "默认")
    }

    // MARK: 唱台布局

    func testStageFitsWidth() {
        for width in [308.0, 288, 270, 250, 400] {
            let stage = MusicVinyl.stage(width: width)
            XCTAssertLessThanOrEqual(stage.width, width + 0.001)
            XCTAssertLessThanOrEqual(stage.height, 260)
            // 唱盘（含金属边和厚度）轮廓完整，不被唱台裁掉。
            XCTAssertGreaterThanOrEqual(stage.center.x - stage.platter, 0)
            XCTAssertLessThanOrEqual(stage.center.x + stage.platter, stage.width)
            XCTAssertGreaterThanOrEqual(stage.center.y - stage.platter, 0)
            XCTAssertLessThanOrEqual(stage.platterBottom, stage.height)
            // 唱臂底座在唱台里。
            XCTAssertLessThanOrEqual(stage.pivot.x + stage.pivotBase * 1.15, stage.width)
            XCTAssertGreaterThanOrEqual(stage.pivot.y - stage.pivotBase * 1.15, 0)
            // 小熊猫贴纸在唱台里。
            XCTAssertGreaterThanOrEqual(stage.sticker.x, 0)
            XCTAssertLessThanOrEqual(stage.sticker.maxY, stage.height)
        }
        XCTAssertEqual(MusicVinyl.stage(width: 400).scale, 1, "宽了不放大")
        XCTAssertEqual(MusicVinyl.stage(width: .nan).scale, 1)
        let full = MusicVinyl.stage(width: MusicVinyl.designWidth)
        XCTAssertGreaterThanOrEqual(full.height, 240, "唱台约 240 到 260 高")
        XCTAssertLessThanOrEqual(full.height, 260)
        XCTAssertGreaterThanOrEqual(full.radius, 100, "唱片放大")
        XCTAssertEqual(MusicVinyl.panelWidth, 320)
        XCTAssertGreaterThanOrEqual(MusicVinyl.stage(width: MusicVinyl.panelWidth - 32).scale, 0.9,
                                    "320 面板里唱片不缩太小")
    }

    func testStickerStaysClearOfTheStylusPath() {
        let stage = MusicVinyl.stage(width: MusicVinyl.designWidth)
        for step in 0...20 {
            let angle = MusicVinyl.armAngle(stage, progress: Double(step) / 20, playing: true)
            XCTAssertGreaterThan(MusicVinyl.stylus(stage, angle: angle).x, stage.sticker.maxX,
                                 "小熊猫不挡唱针走的音轨")
        }
    }

    func testRippleStaysInsideStage() {
        let stage = MusicVinyl.stage(width: MusicVinyl.designWidth)
        let widest = stage.radius * (1 + MusicVinyl.rippleReach)
        XCTAssertLessThanOrEqual(stage.center.x + widest, stage.width + 0.001)
        XCTAssertGreaterThanOrEqual(stage.center.x - widest, 0)
        let water = stage.center.y + stage.radius * MusicVinyl.waterDrop
        XCTAssertLessThanOrEqual(water + widest * MusicVinyl.waterFlatness, stage.height)
        XCTAssertGreaterThan(widest, stage.platter, "两侧露得出一点水面")
    }

    // MARK: 唱臂

    func testArmRestsOffTheRecord() {
        let stage = MusicVinyl.stage(width: 288)
        XCTAssertEqual(MusicVinyl.armAngle(stage, progress: 0.5, playing: false), MusicVinyl.restAngle)
        XCTAssertGreaterThan(MusicVinyl.stylusDistance(stage, angle: MusicVinyl.restAngle), stage.platter,
                             "收起时唱针在唱盘外面")
    }

    func testArmFollowsProgressFromOuterToInner() {
        for width in [288.0, 260] {
            let stage = MusicVinyl.stage(width: width)
            let start = MusicVinyl.armAngle(stage, progress: 0, playing: true)
            let end = MusicVinyl.armAngle(stage, progress: 1, playing: true)
            XCTAssertEqual(MusicVinyl.stylusDistance(stage, angle: start), stage.outerGroove, accuracy: 0.01)
            XCTAssertEqual(MusicVinyl.stylusDistance(stage, angle: end), stage.innerGroove, accuracy: 0.01)
            XCTAssertGreaterThan(start, MusicVinyl.restAngle, "落针要从支架转过来")
            var last = start
            for step in 1...20 {
                let angle = MusicVinyl.armAngle(stage, progress: Double(step) / 20, playing: true)
                XCTAssertGreaterThan(angle, last, "进度越往后唱臂越往里")
                XCTAssertGreaterThan(MusicVinyl.stylusDistance(stage, angle: angle), stage.label,
                                     "唱针不压到中心标签")
                last = angle
            }
        }
    }

    func testArmClampsAndHandlesUnknownProgress() {
        let stage = MusicVinyl.stage(width: 288)
        let outer = MusicVinyl.armAngle(stage, progress: 0, playing: true)
        XCTAssertEqual(MusicVinyl.armAngle(stage, progress: nil, playing: true), outer, "读不到进度停在外圈")
        XCTAssertEqual(MusicVinyl.armAngle(stage, progress: .nan, playing: true), outer)
        XCTAssertEqual(MusicVinyl.armAngle(stage, progress: -1, playing: true), outer)
        XCTAssertEqual(MusicVinyl.armAngle(stage, progress: 3, playing: true),
                       MusicVinyl.armAngle(stage, progress: 1, playing: true))
    }

    // MARK: 转动

    func testDiscSpinsAtSteadyRate() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertEqual(MusicVinyl.discAngle(base: 10, since: start, now: start.addingTimeInterval(1)),
                       10 + MusicVinyl.degreesPerSecond, accuracy: 1e-9)
        XCTAssertEqual(MusicVinyl.discAngle(base: 10, since: nil, now: start.addingTimeInterval(99)), 10,
                       "暂停停在原角度")
        let wrapped = MusicVinyl.discAngle(base: 350, since: start, now: start.addingTimeInterval(1))
        XCTAssertGreaterThanOrEqual(wrapped, 0)
        XCTAssertLessThan(wrapped, 360)
        XCTAssertEqual(MusicVinyl.discAngle(base: 5, since: start, now: start.addingTimeInterval(-3)), 5,
                       "时钟往回拨不倒转")
        XCTAssertLessThan(MusicVinyl.degreesPerSecond, 200, "比真唱片 33 转慢")
    }

    func testFramesOnlyWhenPlayingVisibleAndMotionAllowed() {
        XCTAssertEqual(MusicVinyl.framesPerSecond(playing: true, visible: true, reduceMotion: false), MusicVinyl.fps)
        XCTAssertNil(MusicVinyl.framesPerSecond(playing: false, visible: true, reduceMotion: false))
        XCTAssertNil(MusicVinyl.framesPerSecond(playing: true, visible: false, reduceMotion: false))
        XCTAssertNil(MusicVinyl.framesPerSecond(playing: true, visible: true, reduceMotion: true))
    }

    // MARK: 水波纹

    func testRipplesStayFaintAndExpand() {
        for step in 0..<200 {
            let rings = MusicVinyl.ripples(t: Double(step) * 0.11)
            XCTAssertEqual(rings.count, MusicVinyl.rippleCount)
            for ring in rings {
                XCTAssertGreaterThanOrEqual(ring.scale, 1)
                XCTAssertLessThanOrEqual(ring.scale, 1 + MusicVinyl.rippleReach)
                XCTAssertGreaterThanOrEqual(ring.opacity, 0)
                XCTAssertLessThanOrEqual(ring.opacity, MusicVinyl.rippleOpacity, "低透明度，不大面积发光")
            }
        }
        let a = MusicVinyl.ripples(t: 1)[0].scale
        XCTAssertGreaterThan(MusicVinyl.ripples(t: 2)[0].scale, a, "播放时一圈圈往外扩")
    }

    func testStillRipplesAreStableAndVisible() {
        XCTAssertEqual(MusicVinyl.ripples(t: nil), MusicVinyl.ripples(t: nil))
        XCTAssertTrue(MusicVinyl.ripples(t: nil).allSatisfy { $0.opacity > 0 }, "静帧几圈都看得见")
        XCTAssertEqual(MusicVinyl.ripples(t: .nan), MusicVinyl.ripples(t: nil))
    }
}
