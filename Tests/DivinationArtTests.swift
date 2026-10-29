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
        XCTAssertLessThanOrEqual(total, 1_000_000, "卜卦素材合计不超过 1MB")
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
            XCTAssertLessThan(pose.aspect, 0.86, "姿势层留的宽度放得下：\(pose.imageName)")
        }
        let dome = try pngSize(folder.appendingPathComponent("\(DivinationArt.shellDome).png"))
        XCTAssertEqual(Double(dome.width) / Double(dome.height), DivinationArt.shellDomeAspect, accuracy: 0.01)
        // 签筒着色层和「摇一摇」图一样大，才叠得严。
        let shake = DivinationPose.qianShake.pixelSize
        for skin in TubeSkin.allCases {
            guard let overlay = DivinationArt.tubeOverlay(skin) else { continue }
            let size = try pngSize(folder.appendingPathComponent("\(overlay).png"))
            XCTAssertEqual(size.width, shake.width, overlay)
            XCTAssertEqual(size.height, shake.height, overlay)
        }
    }

    func testResourcesAreBundled() throws {
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(yml.contains("- path: Resources/Divination\n        buildPhase: resources"))
    }

    func testSkinsPickTheirOwnArt() {
        XCTAssertNil(DivinationArt.tubeOverlay(.bamboo), "默认竹签筒就是原图")
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

    func testStickShakeOrder() {
        let s = StickShake.normal
        XCTAssertEqual([0, s.flyStart, s.readStart, s.total], [0, s.flyStart, s.readStart, s.total].sorted())
        XCTAssertEqual(s.phase(at: 0.01), .shake)
        XCTAssertEqual(s.phase(at: s.flyStart + 0.01), .fly)
        XCTAssertEqual(s.phase(at: s.readStart + 0.01), .read)
        XCTAssertEqual(s.phase(at: s.total), .rest)
        XCTAssertEqual(s.phase(at: 99), .rest)
        XCTAssertEqual(s.pose(at: 0.1, drawn: false), .qianShake)
        XCTAssertEqual(s.pose(at: s.flyStart + 0.1, drawn: false), .qianDraw)
        XCTAssertEqual(s.pose(at: s.readStart + 0.1, drawn: true), .qianRead)
        XCTAssertEqual(s.pose(at: 99, drawn: true), .qianRead)
        XCTAssertEqual(s.pose(at: 99, drawn: false), .qianShake)
        XCTAssertLessThan(s.total, 1.6)
        // 摇摆 ±8° 以内，最后回正。
        XCTAssertEqual(StickShake.swayAngles.map(abs).max(), 8)
        XCTAssertEqual(StickShake.swayAngles.last, 0)
    }

    func testShellTossPoses() {
        for toss in [ShellToss.normal, ShellToss.fast] {
            XCTAssertEqual(toss.pose(at: 0.01, tossed: false), .castHold)
            XCTAssertEqual(toss.pose(at: toss.liftStart + 0.01, tossed: false), .castRaise)
            XCTAssertNil(toss.pose(at: toss.impact, tossed: false), "一摔那下只有扣地龟甲")
            XCTAssertNil(toss.pose(at: toss.landing(2), tossed: false))
            XCTAssertEqual(toss.pose(at: toss.pickupStart + 0.01, tossed: true), .castPickup)
            XCTAssertEqual(toss.pose(at: 99, tossed: true), .castPickup)
            XCTAssertEqual(toss.pose(at: 99, tossed: false), .castHold)
            XCTAssertEqual(toss.phase(at: toss.fallStart), .thrown)
            XCTAssertLessThan(toss.crouch, toss.lift, "起跳前蹲在举高那段里面")
            // 铜钱都在熊猫回来之前落定。
            XCTAssertLessThan(toss.settled, toss.pickupStart)
        }
    }

    func testWorryBookPoses() {
        XCTAssertEqual(WorryBook.pose(at: 0.01, answered: true, dark: false), .bookWish)
        XCTAssertEqual(WorryBook.pose(at: WorryBook.wishHold + 0.01, answered: true, dark: false), .bookOpenRed)
        XCTAssertEqual(WorryBook.pose(at: WorryBook.flipSwap + 0.01, answered: true, dark: true), .bookAnswerNavy)
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

    func testDesktopLargeLeavesRoom() {
        // 大号 340：签那行 72 高的小熊猫加起卦块，底下还有余量给「仅供娱乐」。
        XCTAssertLessThanOrEqual(DesktopCardsDivinationPlan.largePoseHeight, 76)
        XCTAssertLessThanOrEqual(DesktopCardsDivinationPlan.largeSpacing, 8)
    }
}
