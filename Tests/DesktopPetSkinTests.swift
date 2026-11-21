import XCTest

final class DesktopPetSkinTests: XCTestCase {
    func testMapsPandaFrames() {
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-walk-1"), .walk1)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-walk-9"), .walk2)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-fallasleep-3"), .sleep)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-hang-sleep-1"), .hangSleep)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-hang-3"), .hang)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-hug-climb-r-2"), .hugR)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-hug-out-1"), .hug)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-drag-4"), .drag)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-cheer-2"), .cheer)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-peek-4"), .peek)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-sprite-front-sit-2"), .sit)
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: "pet-panda-idle"), .sit)
    }

    func testPandaUnchangedOthersSwapped() {
        let pose = DesktopPetPose(image: "pet-sprite-walk-9", lift: 0, facingLeft: true, height: 40)
        XCTAssertEqual(DesktopPetSkin.apply(pose, mascot: .panda), pose)
        let shiba = DesktopPetSkin.apply(pose, mascot: .shiba)
        XCTAssertEqual(shiba.image, "pet-sprite-shiba-walk2")
        XCTAssertEqual(shiba.lift, DesktopPetSkin.walkBob)
        XCTAssertNil(shiba.height)
        XCTAssertTrue(shiba.facingLeft)
    }
}
