import Foundation
import XCTest

/// 电子宠物的积灰和化成一滩：什么时候出现、谁先谁后、用哪张图。
final class PetDustMeltTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func at(_ d: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    // MARK: 积灰

    func testDustAfterADayWithoutBeingTouched() {
        // 吃饱玩好地走开一天：十二小时后的离开保底让它不至于生病。
        let played = VirtualPet.performing(.play, on: PetState(food: 100, mood: 80, energy: 100, clean: 100, at: at(14)),
                                           now: at(14), calendar: calendar)
        XCTAssertEqual(played.touchedAt, at(14))
        XCTAssertFalse(VirtualPet.isDusty(played, now: at(15, 11)))
        XCTAssertTrue(VirtualPet.isDusty(played, now: at(15, 12)))
        let later = VirtualPet.advanced(played, to: at(15, 13), calendar: calendar)
        XCTAssertEqual(VirtualPet.look(later, now: later.at), .dusty, "积灰比饿了先出来")
        XCTAssertEqual(VirtualPet.statusLine(later, now: later.at), "积灰了，摸摸它")
    }

    func testTreatsDoNotBrushTheDustOff() {
        let washed = VirtualPet.performing(.wash, on: PetState(clean: 40, at: at(14)), now: at(14), calendar: calendar)
        let treated = VirtualPet.performing(.treat, on: washed, now: at(15, 13), calendar: calendar)
        XCTAssertEqual(treated.touchedAt, at(14))
        XCTAssertTrue(VirtualPet.isDusty(treated, now: at(15, 14)))
        let fed = VirtualPet.performing(.feed, on: treated, now: at(15, 14), calendar: calendar)
        XCTAssertFalse(VirtualPet.isDusty(fed, now: at(15, 15)), "亲手喂一顿就干净了")
        // 吃不下也算摸过它。
        let full = VirtualPet.performing(.feed, on: PetState(food: 99, at: at(14)), now: at(14), calendar: calendar)
        XCTAssertEqual(full.touchedAt, at(14))
    }

    func testOldPetsFallBackToTheirLastActionAndNewOnesAreClean() {
        XCTAssertFalse(VirtualPet.isDusty(PetState(at: at(1)), now: at(20)), "从没碰过的不算积灰")
        let old = PetState(at: at(10), lastAction: .wash, lastActionAt: at(10))
        XCTAssertTrue(VirtualPet.isDusty(old, now: at(12)))
        let treatedOnly = PetState(at: at(10), lastAction: .treat, lastActionAt: at(10))
        XCTAssertFalse(VirtualPet.isDusty(treatedOnly, now: at(12)))
    }

    func testTouchedAtRoundTrips() {
        let pet = PetState(at: at(14), touchedAt: at(14))
        var config = WidgetConfig()
        VirtualPet.store(pet, in: &config, now: at(14), calendar: calendar)
        XCTAssertEqual(VirtualPet.state(config, now: at(14)).touchedAt, at(14))
        XCTAssertNil(VirtualPet.state(WidgetConfig(["at": .number(1)]), now: at(14)).touchedAt)
    }

    func testSleepAndSickBeatDust() {
        var pet = PetState(food: 60, mood: 60, energy: 60, clean: 60, at: at(14), touchedAt: at(10))
        XCTAssertEqual(VirtualPet.look(pet, now: at(14)), .dusty)
        pet.clean = 10
        XCTAssertEqual(VirtualPet.look(pet, now: at(14)), .sick)
        pet.sleepSince = at(14)
        XCTAssertEqual(VirtualPet.look(pet, now: at(14)), .rest)
    }

    // MARK: 化成一滩

    func testMeltsWhenTheMacOrTheWeatherIsHot() {
        XCTAssertFalse(PetHeat.isMelting(thermal: 0, cpuHistory: [], outdoorCelsius: nil))
        XCTAssertFalse(PetHeat.isMelting(thermal: 1, cpuHistory: [], outdoorCelsius: 34.9))
        XCTAssertTrue(PetHeat.isMelting(thermal: 2, cpuHistory: [], outdoorCelsius: nil))
        XCTAssertTrue(PetHeat.isMelting(thermal: 3, cpuHistory: [], outdoorCelsius: nil))
        XCTAssertTrue(PetHeat.isMelting(thermal: 0, cpuHistory: [], outdoorCelsius: 35))
        XCTAssertFalse(PetHeat.isMelting(thermal: 0, cpuHistory: [], outdoorCelsius: .nan))
    }

    func testOnlyASustainedBusyCPUMelts() {
        XCTAssertFalse(PetHeat.cpuBusy(Array(repeating: 1, count: 29)), "读数不够 30 秒")
        XCTAssertTrue(PetHeat.cpuBusy(Array(repeating: 0.95, count: 30)))
        XCTAssertFalse(PetHeat.cpuBusy(Array(repeating: 0.95, count: 20) + Array(repeating: 0.5, count: 10)))
        // 只看最近 30 秒：之前闲着不拖后腿。
        XCTAssertTrue(PetHeat.cpuBusy(Array(repeating: 0, count: 30) + Array(repeating: 0.92, count: 30)))
        XCTAssertTrue(PetHeat.isMelting(thermal: 0, cpuHistory: Array(repeating: 1, count: 60), outdoorCelsius: nil))
    }

    func testMeltPriorityAndLine() {
        let pet = PetState(food: 60, mood: 60, energy: 60, clean: 60, at: at(14))
        XCTAssertEqual(VirtualPet.look(pet, now: at(14), melted: true), .melted)
        XCTAssertEqual(VirtualPet.look(pet, now: at(14), dried: true, melted: true), .dried, "骷髅最先")
        var asleep = pet
        asleep.sleepSince = at(14)
        XCTAssertEqual(VirtualPet.look(asleep, now: at(14), melted: true), .melted, "睡着也会化")
        XCTAssertEqual(VirtualPet.statusLine(pet, now: at(14), melted: true), "热化了，歇一歇")
        let fed = VirtualPet.performing(.feed, on: pet, now: at(14), calendar: calendar)
        XCTAssertEqual(VirtualPet.look(fed, now: at(14), melted: true), .eat, "喂的那几秒照样吃")
    }

    // MARK: 图

    func testEveryCharacterHasDustAndMeltPictures() {
        XCTAssertEqual(VirtualPet.imageName(.redPanda, .dusty), "pet-panda-dusty")
        XCTAssertEqual(VirtualPet.imageName(.redPanda, .melted), "pet-panda-melt")
        XCTAssertEqual(VirtualPet.imageName(.shiba, .dusty), "pet-shiba-dusty")
        XCTAssertEqual(VirtualPet.imageName(.octopus, .melted), "pet-octopus-melt")
        for character in WaterCharacter.allCases {
            for look in PetLook.allCases {
                XCTAssertFalse(VirtualPet.imageName(character, look).isEmpty)
            }
        }
    }
}
