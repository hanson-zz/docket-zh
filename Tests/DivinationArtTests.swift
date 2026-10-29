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
        let scenes: [(width: Double, pose: Double)] = [
            (Divination.panelContentWidth, 184), (140, 70),
            (DesktopCardsDivinationPlan.mediumStickWidth, 64), (72, DesktopCardsDivinationPlan.largePoseHeight),
        ]
        for scene in scenes {
            let height = scene.pose + 4
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
        for i in 0..<3 {
            let spot = l.landing(i)
            XCTAssertGreaterThan(spot.y - l.coin / 2, l.footY + 2, "铜钱顶边在脚底下面")
            XCTAssertLessThanOrEqual(spot.y + l.coin / 2, l.sceneHeight, "不被场景底边裁掉")
            XCTAssertLessThanOrEqual(abs(spot.x) + l.coin / 2, half)
        }
        // 跳到最高处（14pt）举着龟甲的那张图顶边也在场景里。
        XCTAssertGreaterThanOrEqual(l.footY - l.poseHeight * DivinationPose.castRaise.heightScale - 14, 0)
        // 壳口在一摔图里靠下、在小熊猫前面偏右，铜钱从那里往下往前落。
        let mouth = DivinationPose.castSlam.scenePoint(DivinationArt.slamMouth.x, DivinationArt.slamMouth.y,
                                                       poseHeight: l.poseHeight, centerX: half, bottom: l.footY)
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

    func testDesktopLargeLeavesRoom() {
        // 大号 340：签那行 72 高的小熊猫加起卦块，底下还有余量给「仅供娱乐」。
        XCTAssertLessThanOrEqual(DesktopCardsDivinationPlan.largePoseHeight, 76)
        XCTAssertLessThanOrEqual(DesktopCardsDivinationPlan.largeSpacing, 8)
    }
}
