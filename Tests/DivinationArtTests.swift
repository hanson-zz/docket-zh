import XCTest

/// 卜卦小熊猫姿势图：素材都在包里、尺寸和代码里写的一样、包体积守住，
/// 以及三种玩法「什么时候换哪张图」的顺序。
final class DivinationArtTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func pngSize(_ url: URL) throws -> (width: Int, height: Int) {
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 24)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], url.lastPathComponent)
        func int(_ offset: Int) -> Int {
            data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        return (int(16), int(20))
    }

    // MARK: 素材

    func testEveryImageIsInResources() throws {
        let folder = root.appendingPathComponent("Resources/Divination")
        var total = 0
        for name in DivinationArt.allImageNames {
            let url = folder.appendingPathComponent("\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertLessThan(bytes, 100_000, "每张压到 100KB 以内：\(name)")
            total += bytes
        }
        XCTAssertLessThanOrEqual(total, 1_300_000, "卜卦素材合计不超过 1.3MB")
        XCTAssertEqual(Set(DivinationArt.allImageNames).count, DivinationArt.allImageNames.count)
        // 文件夹里没有用不到的图（绿壳之类没选中的不进包）。
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(Set(files.map { String($0.dropLast(4)) }), Set(DivinationArt.allImageNames))
    }

    func testPoseSizesMatchTheFiles() throws {
        let folder = root.appendingPathComponent("Resources/Divination")
        for pose in DivinationPose.allCases {
            let size = try pngSize(folder.appendingPathComponent("\(pose.imageName).png"))
            XCTAssertEqual(size.width, pose.pixelSize.width, pose.imageName)
            XCTAssertEqual(size.height, pose.pixelSize.height, pose.imageName)
            // @2x、高 480：面板里最大显示约 220pt，够清楚。
            XCTAssertEqual(size.height, 480, pose.imageName)
            XCTAssertGreaterThan(pose.aspect, 0.6)
            XCTAssertLessThan(pose.aspect * pose.heightScale, 0.86, "姿势层留的宽度放得下：\(pose.imageName)")
            XCTAssertGreaterThan(pose.anchorX, 0.35)
            XCTAssertLessThan(pose.anchorX, 0.65)
        }
        // 签筒着色层和抱签筒的两张图各自一样大，才叠得严。
        for pose in DivinationArt.tubePoses {
            for skin in TubeSkin.allCases {
                guard let overlay = DivinationArt.tubeOverlay(skin, pose: pose) else { continue }
                let size = try pngSize(folder.appendingPathComponent("\(overlay).png"))
                XCTAssertEqual(size.width, pose.pixelSize.width, overlay)
                XCTAssertEqual(size.height, pose.pixelSize.height, overlay)
            }
        }
    }

    /// 这一轮照分解图补的两张姿势（仰头看签、一摔）在包里、在 allImageNames 里；不再用的举签图、
    /// 扣地龟甲已经拿掉。
    func testNewBeatPosesAreBundled() throws {
        let folder = root.appendingPathComponent("Resources/Divination")
        let names = Set(DivinationArt.allImageNames)
        for name in ["div-qian-2-look", "div-cast-3-slam", "div-qian-2-tube-lacquer", "div-qian-2-tube-jade"] {
            XCTAssertTrue(names.contains(name), name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name).png").path), name)
        }
        for gone in ["div-qian-2-draw", "div-shell-dome"] {
            XCTAssertFalse(names.contains(gone), gone)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(gone).png").path), gone)
        }
        XCTAssertEqual(DivinationArt.tubeOverlay(.jade, pose: .qianLook), "div-qian-2-tube-jade")
        XCTAssertNil(DivinationArt.tubeOverlay(.jade, pose: .qianRead), "展签图上没有签筒")
    }

    func testResourcesAreBundled() throws {
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(yml.contains("- path: Resources/Divination\n        buildPhase: resources"))
    }

    func testSkinsPickTheirOwnArt() {
        XCTAssertNil(DivinationArt.tubeOverlay(.bamboo), "默认竹签筒就是原图")
        XCTAssertNil(DivinationArt.tubeOverlay(.bamboo, pose: .qianLook))
        XCTAssertNotNil(DivinationArt.tubeOverlay(.lacquer))
        XCTAssertNotNil(DivinationArt.tubeOverlay(.jade))
        var coins = Set<String>()
        for skin in CoinSkin.allCases {
            XCTAssertNotEqual(DivinationArt.coin(back: true, skin: skin), DivinationArt.coin(back: false, skin: skin))
            coins.insert(DivinationArt.coin(back: true, skin: skin))
            coins.insert(DivinationArt.coin(back: false, skin: skin))
        }
        XCTAssertEqual(coins.count, CoinSkin.allCases.count * 2)
        XCTAssertEqual(DivinationArt.coin(back: false, skin: .classic), "div-coin-front")
    }

    func testBookCoverFollowsAppearance() {
        XCTAssertEqual(DivinationPose.bookOpen(dark: true), .bookOpenNavy)
        XCTAssertEqual(DivinationPose.bookOpen(dark: false), .bookOpenRed)
        XCTAssertEqual(DivinationPose.bookAnswer(dark: true), .bookAnswerNavy)
        XCTAssertEqual(DivinationPose.bookAnswer(dark: false), .bookAnswerRed)
    }

    /// 签纸上的字：纸够大才写，写就不小于 13pt；面板那么大写得下。
    func testSlipFontNeverBelowMinimum() {
        XCTAssertNil(DivinationArt.slipFont(slipHeight: 13), "桌面小卡片的签纸不写字")
        for height in stride(from: 10.0, through: 60.0, by: 0.5) {
            if let font = DivinationArt.slipFont(slipHeight: height) {
                XCTAssertGreaterThanOrEqual(font, Divination.minimumFont)
                XCTAssertLessThanOrEqual(font, 22)
                XCTAssertLessThanOrEqual(font, height)
            }
        }
        let panel = 184 * DivinationArt.slipRect.height
        XCTAssertNotNil(DivinationArt.slipFont(slipHeight: panel))
        // 「上上签」三个字放得进签纸宽。
        let width = 184 * DivinationPose.qianRead.aspect * DivinationArt.slipRect.width
        XCTAssertLessThanOrEqual((DivinationArt.slipFont(slipHeight: panel) ?? 0) * 3, width)
    }

    // MARK: 节奏

    /// 几拍首尾相接、从 0 开始、合计就是总时长，每拍中间显示的就是这一拍的姿势。
    private func checkBeats(_ beats: [DivinationBeat], total: Double, pose: (Double) -> DivinationPose,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(beats.first?.start ?? -1, 0, accuracy: 0.0001, file: file, line: line)
        for i in 1..<beats.count {
            XCTAssertEqual(beats[i].start, beats[i - 1].end, accuracy: 0.0001, file: file, line: line)
        }
        XCTAssertEqual(beats.last?.end ?? -1, total, accuracy: 0.0001, file: file, line: line)
        for beat in beats {
            XCTAssertEqual(pose(beat.start + beat.duration / 2), beat.pose, file: file, line: line)
            // 每拍都比交叉淡入长，换完图还停得住。
            XCTAssertGreaterThan(beat.duration, DivinationArt.crossFade, file: file, line: line)
        }
    }

    /// 每日一签照分解图三拍：摇一摇 → 仰头看签 → 展签；每拍 0.35～0.6 秒，合计和原来（声音）一样 1.29。
    func testStickShakeBeats() {
        let s = StickShake.normal
        XCTAssertEqual(s.beats.map(\.pose), [.qianShake, .qianLook, .qianRead])
        checkBeats(s.beats, total: s.total) { s.pose(at: $0, drawn: true) }
        for beat in s.beats {
            XCTAssertGreaterThanOrEqual(beat.duration, 0.35)
            XCTAssertLessThanOrEqual(beat.duration, 0.6)
        }
        XCTAssertEqual(s.total, 1.29, accuracy: 0.0001)
        XCTAssertEqual(s.phase(at: s.total), .rest)
        XCTAssertEqual(s.pose(at: 99, drawn: true), .qianRead)
        XCTAssertEqual(s.pose(at: 99, drawn: false), .qianShake)
        // 摇摆 ±8° 以内，最后回正。
        XCTAssertEqual(StickShake.swayAngles.map(abs).max(), 8)
        XCTAssertEqual(StickShake.swayAngles.last, 0)
    }

    /// 签条：蹦出来 → 停在半空 → 落进手里展开，落定以后纸上的字才出来；不在动时没有签条。
    func testSlipLandsInTheHands() {
        let s = StickShake.normal
        XCTAssertNil(s.slipStage(at: s.flyStart - 0.01), "摇的时候签还在筒里")
        guard case .pop = s.slipStage(at: s.flyStart + 0.01) else { return XCTFail("先蹦出来") }
        guard case .hover = s.slipStage(at: s.readStart - 0.01) else { return XCTFail("再停在半空") }
        guard case .land(let q) = s.slipStage(at: s.readStart + StickShake.catchDuration / 2) else {
            return XCTFail("落进手里")
        }
        XCTAssertEqual(q, 0.5, accuracy: 0.01)
        XCTAssertNil(s.slipStage(at: s.caught), "落定以后签条就是图里那张签纸")
        XCTAssertNil(s.slipStage(at: 99))
        // 停在半空那段够看清（第二拍的一半以上）。
        XCTAssertGreaterThan(s.fly * (1 - StickShake.popFraction), 0.2)
        XCTAssertLessThan(StickShake.catchDuration, s.reveal / 2, "落定后还停得住")
        XCTAssertEqual(s.slipTextOpacity(at: s.caught - 0.01), 0)
        XCTAssertEqual(s.slipTextOpacity(at: s.caught + 0.2), 1)
        XCTAssertEqual(s.slipTextOpacity(at: 99), 1)
    }

    /// 签条停在半空的位置收在场景里：面板、桌面小 / 中 / 大卡片都不被裁。
    func testSlipHoverStaysInsideEveryScene() {
        let scenes: [(width: Double, height: Double, pose: Double)] = [
            (Divination.panelContentWidth, 188, 184),
            (140, DesktopCardsDivinationPlan.smallPoseHeight + 4, DesktopCardsDivinationPlan.smallPoseHeight),
            (DesktopCardsDivinationPlan.mediumStickWidth, DesktopCardsDivinationPlan.mediumStickSceneHeight,
             DesktopCardsDivinationPlan.mediumStickPoseHeight),
            (72, DesktopCardsDivinationPlan.largePoseHeight + 4, DesktopCardsDivinationPlan.largePoseHeight),
        ]
        for scene in scenes {
            let height = scene.height
            let c = DivinationArt.hoverCenter(sceneWidth: scene.width, sceneHeight: height, poseHeight: scene.pose)
            let h = DivinationArt.flyingSlipHeight(poseHeight: scene.pose)
            let w = h * DivinationArt.flyingSlipAspect
            XCTAssertGreaterThanOrEqual(c.x - w / 2, 0, "\(scene)")
            XCTAssertLessThanOrEqual(c.x + w / 2, scene.width, "\(scene)")
            XCTAssertGreaterThanOrEqual(c.y - h / 2, 0, "\(scene)")
            XCTAssertLessThanOrEqual(c.y + h / 2, height, "\(scene)")
        }
        // 面板里签停在小熊猫头的右上方（比签筒口高、在中线右边）。
        let panel = DivinationArt.hoverCenter(sceneWidth: Divination.panelContentWidth, sceneHeight: 194, poseHeight: 184)
        let mouth = DivinationPose.qianLook.scenePoint(DivinationArt.tubeMouth.x, DivinationArt.tubeMouth.y,
                                                       poseHeight: 184, centerX: Divination.panelContentWidth / 2,
                                                       bottom: 190)
        XCTAssertLessThan(panel.y, mouth.y)
        XCTAssertGreaterThan(panel.x, Divination.panelContentWidth / 2)
    }

    /// 起卦照分解图：捧 → 摇 → 举高 → 一摔（熊猫在画面里，铜钱同时蹦出）→ 捡回；合计和原来一样。
    func testShellTossBeats() {
        for toss in [ShellToss.normal, ShellToss.fast] {
            XCTAssertEqual(toss.beats.map(\.pose), [.castHold, .castHold, .castRaise, .castSlam, .castPickup])
            checkBeats(toss.beats, total: toss.total) { toss.pose(at: $0, tossed: true) }
            XCTAssertEqual(toss.phase(at: 0.01), .hold)
            XCTAssertEqual(toss.phase(at: toss.shakeStart + 0.01), .shake)
            XCTAssertEqual(toss.phase(at: toss.liftStart + 0.01), .raise)
            XCTAssertEqual(toss.phase(at: toss.fallStart), .slam)
            // 一摔那拍熊猫在画面里，铜钱蹦出、落地都在这一拍里。
            for i in 0..<3 {
                XCTAssertEqual(toss.pose(at: toss.popStart(i), tossed: false), .castSlam)
                XCTAssertEqual(toss.pose(at: toss.landing(i), tossed: false), .castSlam)
            }
            XCTAssertEqual(toss.pose(at: toss.pickupStart + 0.01, tossed: true), .castPickup)
            XCTAssertEqual(toss.pose(at: 99, tossed: true), .castPickup)
            XCTAssertEqual(toss.pose(at: 99, tossed: false), .castHold)
            XCTAssertLessThanOrEqual(toss.crouch + toss.rise, toss.lift + 1e-9, "跳上去在举高那拍里")
            XCTAssertLessThan(toss.crouch + toss.rise, ShellToss.normal.lift, "平常节奏跳到最高处还停一下")
            XCTAssertLessThan(toss.settled, toss.pickupStart, "铜钱都在捡龟甲之前落定")
        }
        let n = ShellToss.normal
        for (i, beat) in n.beats.enumerated() {
            XCTAssertGreaterThanOrEqual(beat.duration, 0.35, "第 \(i + 1) 拍")
            // 一摔那拍里铜钱要蹦出来、落地、弹两下（时间跟着落地声），长一点。
            XCTAssertLessThanOrEqual(beat.duration, beat.pose == .castSlam ? 0.75 : 0.6, "第 \(i + 1) 拍")
        }
        XCTAssertEqual(n.total, 2.28, accuracy: 0.0001, "合计和原来一样")
        XCTAssertEqual(ShellToss.fast.total, 1.61, accuracy: 0.0001)
    }

    /// 铜钱落在小熊猫前面那排：和脚隔开、不压在脚上，也都在场景里。
    func testCoinsLandInFrontOfThePanda() {
        let l = ShellToss.panelLayout
        let half = Divination.panelContentWidth / 2
        XCTAssertEqual(l.sceneWidth, Divination.panelContentWidth)
        XCTAssertEqual(l.pandaX, half, "面板小熊猫在中线上")
        XCTAssertFalse(l.coinsInRow)
        XCTAssertEqual(l.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(l.jumpHeight, 14, accuracy: 0.0001, "面板跳起高度和原来一样")
        XCTAssertEqual(l.coinArc(0), 40, accuracy: 0.0001)
        for i in 0..<3 {
            let spot = l.landing(i)
            XCTAssertGreaterThan(spot.y - l.coin / 2, l.footY + 2, "铜钱顶边在脚底下面")
            XCTAssertLessThanOrEqual(spot.y + l.coin / 2, l.sceneHeight, "不被场景底边裁掉")
            XCTAssertGreaterThanOrEqual(spot.x - l.coin / 2, 0)
            XCTAssertLessThanOrEqual(spot.x + l.coin / 2, l.sceneWidth)
            XCTAssertEqual(spot.x, half + ShellToss.landings[i].x * l.coin, accuracy: 0.0001, "面板落点和原来一样")
        }
        // 跳到最高处（14pt）举着龟甲的那张图顶边也在场景里。
        XCTAssertGreaterThanOrEqual(l.footY - l.poseHeight * DivinationPose.castRaise.heightScale - l.jumpHeight, 0)
        // 壳口在一摔图里靠下、在小熊猫前面偏右，铜钱从那里往下往前落。
        let mouth = DivinationPose.castSlam.scenePoint(DivinationArt.slamMouth.x, DivinationArt.slamMouth.y,
                                                       poseHeight: l.poseHeight, centerX: l.pandaX, bottom: l.footY)
        XCTAssertGreaterThan(mouth.x, half)
        XCTAssertLessThan(mouth.y, l.footY)
        XCTAssertGreaterThan(mouth.y, l.footY - l.poseHeight * 0.3)
    }

    /// 解忧书三拍：默想 → 翻开 → 答案；每拍 0.35～0.6 秒，合计和原来一样 1.23。
    func testWorryBookBeats() {
        for dark in [false, true] {
            let beats = WorryBook.beats(dark: dark)
            XCTAssertEqual(beats.map(\.pose), [.bookWish, .bookOpen(dark: dark), .bookAnswer(dark: dark)])
            checkBeats(beats, total: WorryBook.flipDuration) { WorryBook.pose(at: $0, answered: true, dark: dark) }
            for beat in beats {
                XCTAssertGreaterThanOrEqual(beat.duration, 0.35)
                XCTAssertLessThanOrEqual(beat.duration, 0.6)
            }
        }
        XCTAssertEqual(WorryBook.flipDuration, 1.23, accuracy: 0.0001)
        XCTAssertEqual(WorryBook.pose(at: 99, answered: false, dark: true), .bookWish)
        XCTAssertEqual(WorryBook.pose(at: 99, answered: true, dark: false), .bookAnswerRed)
        // 换页前旧答案藏着，换页后逐行出来，不在动时都看得见。
        XCTAssertEqual(WorryBook.lineOpacity(0, at: 0.1), 0)
        XCTAssertEqual(WorryBook.lineOpacity(0, at: WorryBook.flipSwap), 0)
        XCTAssertGreaterThan(WorryBook.lineOpacity(0, at: WorryBook.flipSwap + 0.2), WorryBook.lineOpacity(1, at: WorryBook.flipSwap + 0.2))
        XCTAssertEqual(WorryBook.lineOpacity(1, at: WorryBook.flipDuration - 0.001), 1, accuracy: 0.05)
        XCTAssertEqual(WorryBook.lineOpacity(0, at: 99), 1)
        XCTAssertEqual(WorryBook.lineOpacity(1, at: 99), 1)
    }

    /// 书页上的淡墨字从右往左一列列出来，翻完时都写好了；书页位置在答案图的书上。
    func testBookInkRunsRightToLeft() {
        let count = DivinationArt.bookInkColumns * 2
        let mid = WorryBook.flipSwap + 0.2
        XCTAssertEqual(WorryBook.inkOpacity(count - 1, of: count, at: WorryBook.flipSwap), 0)
        XCTAssertGreaterThan(WorryBook.inkOpacity(count - 1, of: count, at: mid), WorryBook.inkOpacity(0, of: count, at: mid))
        for k in 0..<count {
            XCTAssertEqual(WorryBook.inkOpacity(k, of: count, at: WorryBook.flipDuration - 0.001), 1, accuracy: 0.05)
            XCTAssertEqual(WorryBook.inkOpacity(k, of: count, at: 99), 1)
        }
        let r = DivinationArt.bookPageRect
        XCTAssertGreaterThan(DivinationArt.bookSpineX, r.x)
        XCTAssertLessThan(DivinationArt.bookSpineX, r.x + r.width)
        XCTAssertLessThanOrEqual(r.x + r.width, 1)
        XCTAssertLessThanOrEqual(r.y + r.height, 1)
    }

    /// 场景坐标：图的身子（anchorX）对在中线、底边贴着 bottom。
    func testScenePointAnchorsTheBody() {
        let pose = DivinationPose.castSlam
        let p = pose.scenePoint(pose.anchorX, 1, poseHeight: 136, centerX: 133, bottom: 152)
        XCTAssertEqual(p.x, 133, accuracy: 0.0001)
        XCTAssertEqual(p.y, 152, accuracy: 0.0001)
        let top = pose.scenePoint(0.5, 0, poseHeight: 136, centerX: 133, bottom: 152)
        XCTAssertEqual(top.y, 152 - 136 * pose.heightScale, accuracy: 0.0001)
        XCTAssertEqual(top.x - 133, pose.centerOffset(poseHeight: 136), accuracy: 0.0001)
    }

    // MARK: 桌面卡片起卦

    /// 桌面卡片中号、大号的起卦和面板「一次起完」同一套五拍、同样的时长：捧 → 摇 → 跳起举高 →
    /// 一摔（铜钱蹦出、落地）→ 捡回；界面用面板同一个场景和同一个声音入口，不再是只摇一下的图。
    func testDesktopCastUsesThePanelBeats() throws {
        XCTAssertNil(DesktopCardsDivinationPlan.castLayout(.small), "小号只放今日签")
        let toss = ShellToss.timing(fast: true)
        XCTAssertEqual(toss.beats.map(\.pose), [.castHold, .castHold, .castRaise, .castSlam, .castPickup])
        XCTAssertEqual(toss.total, 1.61, accuracy: 0.0001)
        for size in [DesktopPinSize.medium, .large] {
            XCTAssertNotNil(DesktopCardsDivinationPlan.castLayout(size), "\(size)")
            XCTAssertTrue(DesktopCardsDivinationPlan.canCast(size))
        }
        let card = try String(contentsOf: root.appendingPathComponent(
            "Sources/Widgets/DesktopCards/DesktopCardsGamesDivination.swift"), encoding: .utf8)
        XCTAssertTrue(card.contains("ShellTossScene(layout: layout"), "桌面卡片用面板同一个起卦场景")
        XCTAssertTrue(card.contains("throwCount: tossCount, fast: true"), "按一次起完的节奏")
        XCTAssertTrue(card.contains("DivinationPlay.performToss(in: widget"), "声音和写回跟面板同一套时间")
        XCTAssertTrue(card.contains("question: \"\", all: true, fresh: true"),
                      "桌面卡片起卦总是丢掉半截、重新一次起完")
        XCTAssertTrue(card.contains("DivinationPlay.castFresh(in: widget"), "减少动态效果时也重新起一卦")
        XCTAssertFalse(card.contains("DivinationPlay.toss(in: widget"), "桌面卡片不续面板的半截卦")
        XCTAssertFalse(card.contains("DivinationShellSway"), "不再只是抱着龟甲摇一下")
        let panel = try String(contentsOf: root.appendingPathComponent(
            "Sources/Widgets/Details/DivinationDetail.swift"), encoding: .utf8)
        XCTAssertTrue(panel.contains("DivinationPlay.performToss(in: instance, question: asked, all: all)"),
                      "面板自己照旧逐次摇、续自己的半截卦")
    }

    /// 桌面卡片起卦小场景不裁切：每一拍的姿势图（连同摇摆、压扁、起跳）、三枚铜钱（连影子、
    /// 抛起来的最高点）、光点都在场景里；铜钱排成一排、不压小熊猫；场景加卦画放得进那一行，
    /// 整块放得进卡片。
    func testDesktopCastSceneFits() throws {
        for size in [DesktopPinSize.medium, .large] {
            let l = try XCTUnwrap(DesktopCardsDivinationPlan.castLayout(size))
            let tag = "\(size)"
            XCTAssertTrue(l.coinsInRow, tag)
            XCTAssertGreaterThanOrEqual(l.coin, 12, "铜钱小号也看得清：\(tag)")
            XCTAssertEqual(l.coinRowY + l.coin / 2, l.footY, accuracy: 0.0001, "铜钱躺在脚底那条线上：\(tag)")
            for pose in [DivinationPose.castHold, .castRaise, .castSlam, .castPickup] {
                let extent = poseExtent(pose, l)
                XCTAssertGreaterThanOrEqual(extent.left, 0, "\(tag) \(pose)")
                XCTAssertLessThanOrEqual(extent.right, l.sceneWidth, "\(tag) \(pose)")
                XCTAssertGreaterThanOrEqual(extent.top, 0, "\(tag) \(pose) 顶边")
            }
            XCTAssertLessThanOrEqual(l.footY + 2, l.sceneHeight, "脚下阴影：\(tag)")
            let slam = DivinationPose.castSlam.displaySize(poseHeight: l.poseHeight).width
            let slamRight = l.pandaX + slam * (1 - DivinationPose.castSlam.anchorX) * ShellToss.Layout.squashWidth
            let mouth = DivinationPose.castSlam.scenePoint(DivinationArt.slamMouth.x, DivinationArt.slamMouth.y,
                                                           poseHeight: l.poseHeight, centerX: l.pandaX, bottom: l.footY)
            for i in 0..<3 {
                let spot = l.landing(i)
                XCTAssertEqual(spot.y, l.coinRowY, "一排：\(tag)")
                XCTAssertGreaterThan(spot.x - l.coin / 2, slamRight, "铜钱在小熊猫右边、不压着：\(tag)")
                XCTAssertLessThanOrEqual(spot.x + l.coin / 2, l.sceneWidth, "\(tag)")
                XCTAssertLessThanOrEqual(spot.y + l.coin * 0.42 + l.coin / 12, l.sceneHeight, "铜钱影子：\(tag)")
                if i > 0 { XCTAssertGreaterThanOrEqual(spot.x - l.landing(i - 1).x, l.coin, "互不压着：\(tag)") }
                // 抛物线最高点（t = 0.5）也在场景里。
                let peak = (mouth.y + spot.y) / 2 - l.coinArc(i)
                XCTAssertGreaterThanOrEqual(peak - l.coin / 2, 0, "\(tag) 第 \(i + 1) 枚抛高")
            }
            let c = l.coinsCenter
            let center = (x: c.x, y: c.y - l.coin * 0.4)
            let r = DivinationArt.sparkleRadius(center: center, preferred: l.coin * 2.6,
                                                width: l.sceneWidth, height: l.sceneHeight)
            XCTAssertGreaterThan(r, l.coin * 0.5, "光点还看得见：\(tag)")
            for star in DivinationArt.sparkleStars {
                let x = center.x + star.x * r, y = center.y + star.y * r
                XCTAssertGreaterThanOrEqual(x - star.size / 2, -0.001, tag)
                XCTAssertLessThanOrEqual(x + star.size / 2, l.sceneWidth + 0.001, tag)
                XCTAssertGreaterThanOrEqual(y - star.size / 2, -0.001, tag)
                XCTAssertLessThanOrEqual(y + star.size / 2, l.sceneHeight + 0.001, tag)
            }
            if DesktopCardsDivinationPlan.figuresOverScene(size) == nil {
                // 大号那一行：场景 + 间距 + 本卦 → 变卦，放得进起卦块的宽；卦画连卦名不比场景高。
                let row = l.sceneWidth + DesktopCardsDivinationPlan.castRowSpacing(size)
                    + DesktopCardsDivinationPlan.figuresWidth(size)
                XCTAssertLessThanOrEqual(row, DesktopCardsDivinationPlan.castBlockWidth(size), tag)
                let beside = DesktopCardsDivinationPlan.figureHeight(size)
                    + (DesktopCardsDivinationPlan.nameBesideFigures(size) ? 4 + 19 : 0)
                XCTAssertLessThanOrEqual(beside, l.sceneHeight, tag)
            } else {
                XCTAssertLessThanOrEqual(l.sceneWidth, DesktopCardsDivinationPlan.castBlockWidth(size), tag)
            }
        }
        XCTAssertEqual(DesktopCardsDivinationPlan.castBlockWidth(.medium), 176)
        XCTAssertEqual(DesktopCardsDivinationPlan.castBlockWidth(.large), 316)
        // 竖着放得下（15pt 一行约 19、13pt 约 17、宋体 13pt 约 19，按钮 28）：
        // 中号 160 高去掉边距 136：场景（卦画叠在右上角）、卦名（没起过是一行提示）、按钮；不写白话。
        let m = try XCTUnwrap(DesktopCardsDivinationPlan.castLayout(.medium))
        let gm = DesktopCardsDivinationPlan.castSpacing(.medium)
        XCTAssertFalse(DesktopCardsDivinationPlan.showsPlain(.medium))
        XCTAssertLessThanOrEqual(m.sceneHeight + gm + 19 + gm + 28, 136)
        // 大号起卦块约 198 高（340 去掉边距、签那行 76、分隔线、「仅供娱乐」和间距）：
        // 场景一行（卦名在里面）、两行卦辞、两行白话、按钮。
        let lg = try XCTUnwrap(DesktopCardsDivinationPlan.castLayout(.large))
        let gl = DesktopCardsDivinationPlan.castSpacing(.large)
        let available = 340 - DesktopCardsDivinationPlan.inset(.large) * 2 - 76 - 1
            - DesktopCardsDivinationPlan.largeSpacing * 3 - 17
        XCTAssertLessThanOrEqual(lg.sceneHeight + gl + 19 * 2 + gl + 17 * 2 + gl + 28, available)
    }

    /// 光点半径：地方够时就是想要的半径，不够时缩到每颗星都在场景里。
    func testSparkleRadiusFits() {
        XCTAssertEqual(DivinationArt.sparkleRadius(center: (133, 100), preferred: 30, width: 266, height: 198), 30)
        let r = DivinationArt.sparkleRadius(center: (80, 40), preferred: 40, width: 92, height: 56)
        XCTAssertLessThan(r, 40)
        XCTAssertGreaterThanOrEqual(r, 0)
    }

    /// 每日一签第三拍签条走低路线落进手里：先在小熊猫右边竖着往下落、再横着滑进手里，
    /// 一路不挡脸、不出场景，最后正好是图里那张签纸；面板和桌面小 / 中 / 大卡片都一样。
    func testSlipLandingAvoidsTheFace() {
        let scenes: [(width: Double, height: Double, pose: Double)] = [
            (Divination.panelContentWidth, 194, 184), (140, 74, 70),
            (DesktopCardsDivinationPlan.mediumStickWidth, DesktopCardsDivinationPlan.mediumStickSceneHeight,
             DesktopCardsDivinationPlan.mediumStickPoseHeight),
            (72, DesktopCardsDivinationPlan.largePoseHeight + 4, DesktopCardsDivinationPlan.largePoseHeight),
        ]
        for scene in scenes {
            let face = StickShake.faceBox(sceneWidth: scene.width, sceneHeight: scene.height, poseHeight: scene.pose)
            let hover = DivinationArt.hoverCenter(sceneWidth: scene.width, sceneHeight: scene.height, poseHeight: scene.pose)
            for k in 0...200 {
                let q = Double(k) / 200
                let f = StickShake.landFrame(q, sceneWidth: scene.width, sceneHeight: scene.height, poseHeight: scene.pose)
                let overlaps = f.minX < face.maxX && f.maxX > face.minX && f.minY < face.maxY && f.maxY > face.minY
                XCTAssertFalse(overlaps, "\(scene) q=\(q) 挡脸")
                XCTAssertGreaterThanOrEqual(f.minX, 0, "\(scene) q=\(q)")
                XCTAssertLessThanOrEqual(f.maxX, scene.width, "\(scene) q=\(q)")
                XCTAssertGreaterThanOrEqual(f.minY, 0, "\(scene) q=\(q)")
                XCTAssertLessThanOrEqual(f.maxY, scene.height, "\(scene) q=\(q)")
                if q < StickShake.dropFraction { XCTAssertEqual(f.x, hover.x, accuracy: 0.0001, "先竖着往下落") }
            }
            let start = StickShake.landFrame(0, sceneWidth: scene.width, sceneHeight: scene.height, poseHeight: scene.pose)
            XCTAssertEqual(start.x, hover.x, accuracy: 0.0001)
            XCTAssertEqual(start.y, hover.y, accuracy: 0.0001, "从半空接着落，不跳")
            let end = StickShake.landFrame(1, sceneWidth: scene.width, sceneHeight: scene.height, poseHeight: scene.pose)
            let caught = StickShake.caughtFrame(sceneWidth: scene.width, sceneHeight: scene.height, poseHeight: scene.pose)
            XCTAssertEqual(end.x, caught.x, accuracy: 0.0001, "\(scene)")
            XCTAssertEqual(end.y, caught.y, accuracy: 0.0001, "\(scene)")
            XCTAssertEqual(end.width, caught.width, accuracy: 0.0001, "\(scene)")
            XCTAssertEqual(end.height, caught.height, accuracy: 0.0001, "\(scene)")
            // 落到的那么低：签条顶边在脸下面。
            let low = StickShake.landFrame(StickShake.dropFraction, sceneWidth: scene.width, sceneHeight: scene.height,
                                           poseHeight: scene.pose)
            XCTAssertGreaterThanOrEqual(low.minY, face.maxY, "\(scene)")
        }
        XCTAssertLessThan(StickShake.catchDuration, StickShake.normal.reveal / 2)
    }

    // MARK: 解忧书第 ② 拍

    /// 解忧书第 ② 拍换成书页朝外、刚翻开的新图（朱红、藏蓝各一张）：在包里、尺寸和第 ③ 拍答案图
    /// 一样、身子对在同一处（换图时小熊猫不动，只看见书页翻平、亮起来）。
    func testBookOpenFacesOut() throws {
        let folder = root.appendingPathComponent("Resources/Divination")
        for dark in [false, true] {
            let open = DivinationPose.bookOpen(dark: dark), answer = DivinationPose.bookAnswer(dark: dark)
            XCTAssertTrue(DivinationArt.allImageNames.contains(open.imageName))
            let size = try pngSize(folder.appendingPathComponent("\(open.imageName).png"))
            XCTAssertEqual(size.width, 355, open.imageName)
            XCTAssertEqual(size.height, 480, open.imageName)
            XCTAssertEqual(open.pixelSize.width, answer.pixelSize.width)
            XCTAssertEqual(open.anchorX, answer.anchorX)
            XCTAssertEqual(open.heightScale, answer.heightScale)
        }
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(yml.contains("Resources/Divination"), "整个文件夹打进包")
    }

    func testDesktopLargeLeavesRoom() {
        // 大号 340：签那行 72 高的小熊猫加起卦块，底下还有余量给「仅供娱乐」。
        XCTAssertLessThanOrEqual(DesktopCardsDivinationPlan.largePoseHeight, 76)
        XCTAssertLessThanOrEqual(DesktopCardsDivinationPlan.largeSpacing, 8)
    }

    /// 起卦场景里一张姿势图最多伸到哪（场景坐标）：② 摇的时候不压扁、绕脚底转 ±8°（转出去的是
    /// 上面的角）；一摔触地、捡回落地时最多横着胖 6%；跳起、托一下时竖着高 6% 再往上抬。
    private func poseExtent(_ pose: DivinationPose, _ l: ShellToss.Layout)
        -> (left: Double, right: Double, top: Double) {
        let size = pose.displaySize(poseHeight: l.poseHeight)
        let left = size.width * pose.anchorX, right = size.width * (1 - pose.anchorX)
        var l0 = left * 1.06, r0 = right * 1.06
        if pose == .castHold {
            let a = StickShake.swayAngles.map { abs($0) }.max()! * Double.pi / 180
            l0 = max(l0, left * cos(a) + size.height * sin(a))
            r0 = max(r0, right * cos(a) + size.height * sin(a))
        }
        let lift = pose == .castRaise ? l.jumpHeight : l.holdLift
        return (l.pandaX - l0, l.pandaX + r0, l.footY - size.height * 1.06 - lift)
    }

    /// 中号起卦区收起白话那一行，腾出的高度给场景：小熊猫接近左边签那只（64），铜钱 14 以上，
    /// 仍一排在小熊猫右边脚底那条线上；大号不变。
    func testDesktopMediumCastIsBigger() throws {
        let m = try XCTUnwrap(DesktopCardsDivinationPlan.castLayout(.medium))
        XCTAssertGreaterThanOrEqual(m.poseHeight, 58)
        XCTAssertLessThanOrEqual(m.poseHeight, 64, "不比左边签那只大")
        XCTAssertGreaterThanOrEqual(m.coin, 14)
        XCTAssertTrue(m.coinsInRow)
        XCTAssertGreaterThan(m.landing(0).x, m.pandaX, "铜钱在小熊猫右边")
        let lg = try XCTUnwrap(DesktopCardsDivinationPlan.castLayout(.large))
        XCTAssertEqual(lg, ShellToss.Layout(sceneWidth: 120, sceneHeight: 70, poseHeight: 57, footY: 67, coin: 15,
                                            coinRowY: 59.5, pandaX: 34, coinsInRow: true), "大号不变")
        XCTAssertTrue(DesktopCardsDivinationPlan.showsPlain(.large))
        XCTAssertNil(DesktopCardsDivinationPlan.figuresOverScene(.large))
    }

    /// 中号卦画叠在场景右上角：卦画在起卦块里；小熊猫每一拍、抛起来的铜钱一路、落地的铜钱、
    /// 光点都碰不到卦画；按钮和卦名放得进卡片。
    func testDesktopMediumFiguresStayClear() throws {
        let size = DesktopPinSize.medium
        let l = try XCTUnwrap(DesktopCardsDivinationPlan.castLayout(size))
        let f = try XCTUnwrap(DesktopCardsDivinationPlan.figuresOverScene(size))
        let block = DesktopCardsDivinationPlan.castBlockWidth(size)
        XCTAssertGreaterThanOrEqual(f.x, 0)
        XCTAssertLessThanOrEqual(f.x + f.width, block, "卦画在起卦块里")
        XCTAssertGreaterThanOrEqual(f.y, 0)
        XCTAssertLessThanOrEqual(f.y + f.height, l.sceneHeight)
        XCTAssertEqual(f.width, DesktopCardsDivinationPlan.figuresWidth(size), accuracy: 0.0001)
        XCTAssertEqual(DesktopCardsDivinationPlan.figureHeight(.large), 45, accuracy: 0.0001, "大号卦画不变")
        XCTAssertGreaterThanOrEqual(DesktopCardsDivinationPlan.figureLineHeight(size), 4, "爻还看得清")
        func inFigures(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
            x1 > f.x && x0 < f.x + f.width && y1 > f.y && y0 < f.y + f.height
        }
        for pose in [DivinationPose.castHold, .castRaise, .castSlam, .castPickup] {
            let e = poseExtent(pose, l)
            XCTAssertFalse(inFigures(e.left, e.top, e.right, l.footY), "小熊猫碰到卦画：\(pose)")
        }
        let mouth = DivinationPose.castSlam.scenePoint(DivinationArt.slamMouth.x, DivinationArt.slamMouth.y,
                                                       poseHeight: l.poseHeight, centerX: l.pandaX, bottom: l.footY)
        for i in 0..<3 {
            let land = l.landing(i)
            let start = (x: mouth.x + Double(i - 1) * l.mouthSpread, y: mouth.y)
            for k in 0...40 {
                let t = Double(k) / 40
                let x = start.x + (land.x - start.x) * t
                let y = start.y + (land.y - start.y) * t - l.coinArc(i) * 4 * t * (1 - t)
                XCTAssertFalse(inFigures(x - l.coin / 2, y - l.coin / 2, x + l.coin / 2, y + l.coin / 2),
                               "第 \(i + 1) 枚铜钱飞过卦画（t = \(t)）")
            }
            // 落地以后弹两下，最高弹起 0.3 枚。
            XCTAssertGreaterThan(land.y - l.coin * 0.8, f.y + f.height, "第 \(i + 1) 枚落地在卦画下面")
        }
        let c = l.coinsCenter
        let center = (x: c.x, y: c.y - l.coin * 0.4)
        let r = DivinationArt.sparkleRadius(center: center, preferred: l.coin * 2.6,
                                            width: l.sceneWidth, height: l.sceneHeight)
        for star in DivinationArt.sparkleStars {
            let x = center.x + star.x * r, y = center.y + star.y * r, h = star.size / 2
            XCTAssertFalse(inFigures(x - h, y - h, x + h, y + h), "光点盖住卦画")
        }
    }

    /// 中号卡片：白话不写在卡片上但没丢，鼠标停在卦名那一行时卡片自己画浮层写完整白话（桌面卡片窗口
    /// 不激活，系统 `.help` 可能不弹，所以卡片上不再用 `.help`）；没起过卦是一行短提示、完整的在浮层里；
    /// 卡片上的字都不小于 13pt（箭头图标、「仅供娱乐」法律小字除外）。
    func testDesktopMediumPlainMovesToHoverNote() throws {
        let card = try String(contentsOf: root.appendingPathComponent(
            "Sources/Widgets/DesktopCards/DesktopCardsGamesDivination.swift"), encoding: .utf8)
        XCTAssertFalse(card.contains(".help("), "桌面卡片不靠系统悬停提示")
        XCTAssertTrue(card.contains(".deskHoverNote(hoverNote(casting), width: blockWidth, enabled: !castBusy)"))
        XCTAssertTrue(card.contains(".deskHoverNote(hoverNote(nil), width: blockWidth, enabled: !castBusy)"))
        XCTAssertTrue(card.contains("return \"\\(title)：\\(primary.plain)\""), "浮层里是完整白话")
        XCTAssertTrue(card.contains(".onHover { hovering = $0 }"))
        XCTAssertTrue(card.contains("if DesktopCardsDivinationPlan.showsPlain(size) {\n                            Text(verbatim: primary.plain)"),
                      "卡片上只有大号写白话")
        XCTAssertTrue(card.contains("tr(\"想好问题再起卦\")"))
        let lines = card.components(separatedBy: "\n")
        let pattern = try NSRegularExpression(pattern: #"size: (\d+(?:\.\d+)?)[,)]"#)
        for (n, line) in lines.enumerated() where line.contains(".font(") {
            if n > 0, lines[n - 1].contains("Image(systemName:") { continue }
            let range = NSRange(line.startIndex..., in: line)
            for match in pattern.matches(in: line, range: range) {
                let value = Double(line[Range(match.range(at: 1), in: line)!])!
                XCTAssertGreaterThanOrEqual(value, Divination.minimumFont, "第 \(n + 1) 行字号")
            }
        }
    }

    // MARK: 中号两只小熊猫脚底对齐

    /// 中号左边签、右边起卦两只小熊猫的脚底在卡片里同一条线上（误差 1pt 以内）：签那块按起卦场景的
    /// 脚底线加高。每一拍的姿势图（摇一摇、仰头看、展签；捧、摇、举高、一摔、捡回）和不动时的姿势
    /// （没抽 / 抽过、没起过 / 起过）都是底边贴着脚底线画的，所以每拍都对齐（起跳、托一下是动作本身）。
    func testDesktopMediumPandasStandOnOneLine() throws {
        let plan = DesktopCardsDivinationPlan.self
        let cast = try XCTUnwrap(plan.castLayout(.medium))
        XCTAssertEqual(plan.mediumStickFootY, plan.mediumCastFootY, accuracy: 1, "两只小熊猫脚底对齐")
        XCTAssertEqual(plan.mediumCastFootY, 88, accuracy: 0.0001)
        XCTAssertEqual(plan.mediumStickPoseHeight, cast.poseHeight, "两只一样大")
        let stickBottom = plan.mediumStickSceneHeight - plan.stickFootMargin
        let shake = StickShake.normal
        var stickPoses = shake.beats.map(\.pose)
        stickPoses += [shake.pose(at: 99, drawn: false), shake.pose(at: 99, drawn: true)]
        for pose in stickPoses {
            let foot = pose.scenePoint(pose.anchorX, 1, poseHeight: plan.mediumStickPoseHeight,
                                       centerX: plan.mediumStickWidth / 2, bottom: stickBottom)
            XCTAssertEqual(plan.inset(.medium) + foot.y, plan.mediumCastFootY, accuracy: 1, "\(pose)")
        }
        let toss = ShellToss.timing(fast: true)
        var castPoses = toss.beats.map(\.pose)
        castPoses += [toss.pose(at: 99, tossed: false), toss.pose(at: 99, tossed: true)]
        for pose in castPoses {
            let foot = pose.scenePoint(pose.anchorX, 1, poseHeight: cast.poseHeight, centerX: cast.pandaX,
                                       bottom: cast.footY)
            XCTAssertEqual(plan.inset(.medium) + foot.y, plan.mediumStickFootY, accuracy: 1, "\(pose)")
        }
        // 签那只每一拍都在签场景里：最高那张图加上签蹦出来时小熊猫轻轻一跳（4pt），摇的时候左右摆 8° 不出列宽。
        let hop = 4.0
        for pose in stickPoses {
            let size = pose.displaySize(poseHeight: plan.mediumStickPoseHeight)
            XCTAssertGreaterThanOrEqual(stickBottom - size.height - hop, 0, "\(pose) 头顶出了场景")
            let a = StickShake.swayAngles.map { abs($0) }.max()! * Double.pi / 180
            let half = max(size.width * pose.anchorX, size.width * (1 - pose.anchorX))
            XCTAssertLessThanOrEqual(half * cos(a) + size.height * sin(a), plan.mediumStickWidth / 2, "\(pose)")
        }
    }

    /// 签那块加高以后字不挤出卡片：左边抽过（签级签号、一句话白话、一行宜忌）、没抽（宜忌加「摇一摇」）两种，
    /// 右边起卦（场景、卦名或提示、按钮）都放得进中号 136 的内高。
    func testDesktopMediumColumnsFit() {
        let plan = DesktopCardsDivinationPlan.self
        XCTAssertEqual(plan.mediumInnerHeight, 136, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(plan.mediumStickColumnHeight(drawn: true), plan.mediumInnerHeight)
        XCTAssertLessThanOrEqual(plan.mediumStickColumnHeight(drawn: false), plan.mediumInnerHeight)
        XCTAssertLessThanOrEqual(plan.mediumCastColumnHeight, plan.mediumInnerHeight)
        // 小号（160×160）：小熊猫、签级签号、一句话白话、农历（没抽：提示、摇一摇、农历）放得进 140 的内高；
        // 大号：签那一行多了签题、一句话白话、农历宜忌以后，整列仍放得进 316 的内高。
        XCTAssertEqual(plan.smallInnerHeight, 140, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(plan.smallColumnHeight(drawn: true), plan.smallInnerHeight)
        XCTAssertLessThanOrEqual(plan.smallColumnHeight(drawn: false), plan.smallInnerHeight)
        XCTAssertLessThanOrEqual(plan.largeColumnHeight, DesktopPinSize.large.height - plan.inset(.large) * 2)
        // 签场景只往下加高，不比起卦场景高（两边顶上对齐、底下都留得出字的地方）。
        XCTAssertEqual(plan.mediumStickSceneHeight, plan.castLayout(.medium)!.sceneHeight, accuracy: 0.0001)
    }

    /// 卦名那一行的悬停浮层：最长的一条（卦名 → 变卦名加最长的白话）在最多几行里写得下，浮层从卦名那一行
    /// 底边往上长、不出起卦块的顶，也不出起卦块的宽。
    func testDesktopMediumHoverNoteFits() throws {
        let plan = DesktopCardsDivinationPlan.self
        let cast = try XCTUnwrap(plan.castLayout(.medium))
        let width = plan.castBlockWidth(.medium)
        let perLine = Int((width - plan.hoverNotePadding * 2) / Divination.minimumFont)
        let longestName = Hexagram.all.map(\.name.count).max()!
        for hexagram in Hexagram.all {
            // 变卦写法「乾 → 坤」按每个字符一格从宽算；不变卦是全名。
            let title = max(hexagram.fullName.count, longestName * 2 + 3)
            let chars = title + 1 + hexagram.plain.count
            let lines = (chars + perLine - 1) / perLine
            XCTAssertLessThanOrEqual(lines, plan.hoverNoteMaxLines, hexagram.name)
        }
        let blank = tr("想好问题，摇六次成一卦").count
        XCTAssertLessThanOrEqual((blank + perLine - 1) / perLine, plan.hoverNoteMaxLines)
        let room = cast.sceneHeight + plan.castSpacing(.medium) + plan.nameLineHeight
        XCTAssertLessThanOrEqual(plan.hoverNoteHeight, room, "浮层不出起卦块的顶")
    }

    // MARK: 字号

    /// 卜卦的界面（面板、签历、签卡、扩展栏卡片、场景、桌面卡片）里，会缩的字缩完也不小于 13pt：
    /// 每个 `.minimumScaleFactor` 往上找最近的字号，字号乘缩放比不小于 13。原来面板顶上三段切换
    /// 13pt 配 0.8，英文「Worry Book」放不下时缩到 10pt 多。
    func testScaledDivinationTextStaysReadable() throws {
        let files = [
            "Sources/Widgets/Details/DivinationDetail.swift", "Sources/Widgets/Details/DivinationArchive.swift",
            "Sources/Widgets/Details/DivinationDailyExtras.swift", "Sources/Widgets/Details/DivinationShareCard.swift",
            "Sources/Widgets/Kinds/DivinationTile.swift", "Sources/Widgets/Kinds/DivinationScenes.swift",
            "Sources/Widgets/DesktopCards/DesktopCardsGamesDivination.swift",
        ]
        let size = try NSRegularExpression(pattern: #"\.font\(\.system\(size: (\d+(?:\.\d+)?)"#)
        let scale = try NSRegularExpression(pattern: #"\.minimumScaleFactor\((\d+(?:\.\d+)?)\)"#)
        func number(_ re: NSRegularExpression, _ line: String) -> Double? {
            guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let r = Range(m.range(at: 1), in: line) else { return nil }
            return Double(line[r])
        }
        var checked = 0
        for file in files {
            let lines = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                .components(separatedBy: "\n")
            for (n, line) in lines.enumerated() {
                guard let factor = number(scale, line) else { continue }
                // 往上找最近的字号（同一个 Text 或它所在的那一组）。
                var font: Double?
                for k in stride(from: n, through: max(0, n - 12), by: -1) {
                    if let value = number(size, lines[k]) { font = max(font ?? 0, value); break }
                }
                let base = try XCTUnwrap(font, "\(file):\(n + 1) 找不到字号")
                XCTAssertGreaterThanOrEqual(base * factor, Divination.minimumFont - 0.1, "\(file):\(n + 1)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 5)
    }

    /// 设置里选铜钱皮肤那一行的标题和皮肤名「铜钱」分开两个键：皮肤名英文是 Bronze，标题英文是 Coins
    /// （原来共用一个键，英文设置里标题也写成 Bronze）。
    func testCoinSkinPickerTitleHasItsOwnKey() throws {
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/MenuBar/DivinationSettings.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(settings.contains("skinPicker(tr(\"铜钱\", context: \"coins\")"))
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Localization/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        func english(_ key: String) -> String? {
            let entry = strings[key] as? [String: Any]
            let loc = entry?["localizations"] as? [String: Any]
            let en = loc?["en"] as? [String: Any]
            return (en?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        XCTAssertEqual(english("铜钱 (coins)"), "Coins")
        XCTAssertEqual(english("铜钱"), "Bronze", "皮肤名不动")
    }
}
