import Foundation
import XCTest

/// 屏幕下边缘藏在草里、点一下冒头、睡着趴进草里；程序坞上待着脚边一小丛草。
final class DesktopPetGrassTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testBottomEdgeHidesInTallGrass() {
        let state = DesktopPetState(x: 300, activity: .curl(until: t0.addingTimeInterval(10)), since: t0)
        let pose = DesktopPetBrain.pose(state, now: t0.addingTimeInterval(2), style: .curl, edge: .bottom)
        XCTAssertEqual(pose.grass, .tall, "歇着藏在高草里")
        XCTAssertTrue(pose.image.hasPrefix("pet-sprite-front-sit-"), "正面坐着只露耳朵")
        XCTAssertEqual(pose.lift, -DesktopPetGrass.hiddenSink, accuracy: 0.001)
    }

    func testClickPopsHeadOut() {
        let state = DesktopPetState(x: 300, activity: .peek(until: t0.addingTimeInterval(3)), since: t0)
        let start = DesktopPetBrain.pose(state, now: t0, style: .curl, edge: .bottom)
        let up = DesktopPetBrain.pose(state, now: t0.addingTimeInterval(1), style: .curl, edge: .bottom)
        XCTAssertEqual(start.lift, -DesktopPetGrass.hiddenSink, accuracy: 0.001, "从草里冒出来")
        XCTAssertEqual(up.lift, -DesktopPetGrass.peekSink, accuracy: 0.001)
        XCTAssertEqual(up.grass, .low, "冒头时前景草压矮")
        XCTAssertTrue(up.image.hasPrefix("pet-sprite-front-wave-"), "挥爪")
    }

    func testSleepCurlsUpInGrass() {
        let state = DesktopPetState(x: 300, activity: .sleep(since: t0), since: t0)
        let pose = DesktopPetBrain.pose(state, now: t0.addingTimeInterval(5), style: .curl, edge: .bottom)
        XCTAssertEqual(pose.grass, .low)
        XCTAssertTrue(pose.image.hasPrefix("pet-sprite-front-sleep-"))
        XCTAssertEqual(pose.lift, 0, "趴着不沉")
    }

    func testWalkingHasNoGrass() {
        let state = DesktopPetState(x: 300, activity: .walk(to: 400), since: t0)
        XCTAssertNil(DesktopPetBrain.pose(state, now: t0, style: .curl, edge: .bottom).grass)
        XCTAssertNil(DesktopPetBrain.pose(state, now: t0, style: .stroll).grass)
    }

    func testDockRestHasMiniGrass() {
        let state = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(5)), since: t0)
        XCTAssertEqual(DesktopPetBrain.pose(state, now: t0, style: .stroll).grass, .mini)
        XCTAssertNil(DesktopPetBrain.pose(state, now: t0, style: .sit).grass, "随意放的不长草")
    }

    func testGrassSwaysAndImagesExist() {
        let frames = Set((0..<8).map { DesktopPetGrass.tall.frontImage(time: Double($0) * DesktopPetGrass.swayPeriod / 4) })
        XCTAssertEqual(frames.count, 3, "前景草三张轮着摆")
        XCTAssertNil(DesktopPetGrass.mini.backImage)
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Pet/sprites")
        for name in DesktopPetGrass.allImages {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".png").path), name)
        }
    }
}
