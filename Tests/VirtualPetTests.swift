import Foundation
import XCTest

final class VirtualPetTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    // MARK: Time passing

    func testNeedsRunDownByTheHour() {
        let start = at(2026, 10, 14, 8)
        let pet = PetState(food: 80, mood: 80, energy: 80, clean: 80, at: start)
        let later = VirtualPet.advanced(pet, to: start.addingTimeInterval(4 * 3600), calendar: calendar)
        XCTAssertEqual(later.food, 60, accuracy: 0.001)
        XCTAssertEqual(later.mood, 64, accuracy: 0.001)
        XCTAssertEqual(later.energy, 68, accuracy: 0.001)
        XCTAssertEqual(later.clean, 72, accuracy: 0.001)
        XCTAssertEqual(later.at, start.addingTimeInterval(4 * 3600))

        let month = VirtualPet.advanced(pet, to: start.addingTimeInterval(90 * 86_400), calendar: calendar)
        XCTAssertEqual(month.food, VirtualPet.awayFloor, "a long time away leaves it hungry, not sick")
        XCTAssertEqual(VirtualPet.advanced(pet, to: start.addingTimeInterval(-3600), calendar: calendar).food, 80,
                       "a clock set back changes nothing")
    }

    func testSleepFillsEnergyThenWakesByItself() {
        let start = at(2026, 10, 14, 10)
        let pet = PetState(food: 80, mood: 80, energy: 40, clean: 80, at: start, sleepSince: start)
        let oneHour = VirtualPet.advanced(pet, to: start.addingTimeInterval(3600), calendar: calendar)
        XCTAssertTrue(oneHour.isSleeping)
        XCTAssertEqual(oneHour.energy, 60, accuracy: 0.001)
        XCTAssertEqual(oneHour.food, 77.5, accuracy: 0.001, "half speed asleep")
        XCTAssertEqual(oneHour.mood, 78, accuracy: 0.001)

        // Full after three hours, then two more awake.
        let fiveHours = VirtualPet.advanced(pet, to: start.addingTimeInterval(5 * 3600), calendar: calendar)
        XCTAssertFalse(fiveHours.isSleeping)
        XCTAssertEqual(fiveHours.energy, 94, accuracy: 0.001)
        XCTAssertEqual(fiveHours.food, 80 - 7.5 - 10, accuracy: 0.001)
    }

    // MARK: Care

    func testActions() {
        let now = at(2026, 10, 14, 9)
        let pet = PetState(food: 20, mood: 50, energy: 50, clean: 20, at: now)
        let fed = VirtualPet.performing(.feed, on: pet, now: now, calendar: calendar)
        XCTAssertEqual(fed.food, 50)
        XCTAssertEqual(fed.lastAction, .feed)
        XCTAssertEqual(fed.cared, ["20261014"])

        let played = VirtualPet.performing(.play, on: pet, now: now, calendar: calendar)
        XCTAssertEqual(played.mood, 75)
        XCTAssertEqual(played.energy, 40)

        XCTAssertEqual(VirtualPet.performing(.wash, on: pet, now: now, calendar: calendar).clean, 60)
        XCTAssertEqual(VirtualPet.performing(.feed, on: PetState(food: 90, at: now), now: now, calendar: calendar).food, 100,
                       "never above full")

        let asleep = VirtualPet.performing(.sleep, on: pet, now: now, calendar: calendar)
        XCTAssertTrue(asleep.isSleeping)
        XCTAssertNil(asleep.lastAction, "going to bed is not acted out")
        XCTAssertFalse(VirtualPet.performing(.sleep, on: asleep, now: now, calendar: calendar).isSleeping, "the same button wakes it")
        XCTAssertFalse(VirtualPet.performing(.feed, on: asleep, now: now, calendar: calendar).isSleeping, "food wakes it too")
    }

    func testTreatsAreCappedAndCountAsCare() {
        let now = at(2026, 10, 14, 9)
        let pet = PetState(food: 0, mood: 0, energy: 50, clean: 50, at: now)
        let two = VirtualPet.treating(2, on: pet, now: now, calendar: calendar)
        XCTAssertEqual(two.food, 2 * VirtualPet.treatFood)
        XCTAssertEqual(two.mood, 2 * VirtualPet.treatMood)
        XCTAssertEqual(two.cared, ["20261014"])
        XCTAssertEqual(VirtualPet.treating(0, on: pet, now: now), pet)
        XCTAssertEqual(VirtualPet.treating(500, on: pet, now: now).food, 100)
    }

    // MARK: Looks

    func testLookPriority() {
        let now = at(2026, 10, 14, 15)
        var pet = PetState(food: 50, mood: 50, energy: 50, clean: 50, at: now)
        XCTAssertEqual(VirtualPet.look(pet, now: now), .idle)
        pet.food = 20
        XCTAssertEqual(VirtualPet.look(pet, now: now), .hungry)
        pet.clean = 10
        XCTAssertEqual(VirtualPet.look(pet, now: now), .sick, "sick beats hungry")
        pet.sleepSince = now
        XCTAssertEqual(VirtualPet.look(pet, now: now), .rest)
        pet.lastAction = .feed
        pet.lastActionAt = now.addingTimeInterval(-1)
        XCTAssertEqual(VirtualPet.look(pet, now: now), .eat, "acting out beats everything")
        XCTAssertEqual(VirtualPet.look(pet, now: now.addingTimeInterval(10)), .rest, "for a few seconds")

        let happy = PetState(food: 90, mood: 90, energy: 80, clean: 76, at: now)
        XCTAssertEqual(VirtualPet.look(happy, now: now), .cheer)
        XCTAssertEqual(VirtualPet.statusLine(PetState(food: 60, mood: 60, energy: 60, clean: 20, at: now), now: now),
                       "有点脏了")
    }

    func testWashShowsBubblesAndDirtShowsSmudges() {
        let start = at(2026, 10, 14, 8)
        let dirty = PetState(food: 90, mood: 90, energy: 90, clean: 20, at: start)
        XCTAssertEqual(VirtualPet.effect(dirty, now: start), .dirty)

        let washed = VirtualPet.performing(.wash, on: dirty, now: start, calendar: calendar)
        XCTAssertEqual(VirtualPet.effect(washed, now: start.addingTimeInterval(1)),
                       .bubbles(until: start.addingTimeInterval(VirtualPet.actSeconds)))
        XCTAssertEqual(VirtualPet.statusLine(washed, now: start.addingTimeInterval(1)), "洗得香喷喷")
        XCTAssertEqual(VirtualPet.effect(washed, now: start.addingTimeInterval(VirtualPet.actSeconds + 1)), .none,
                       "60 is clean enough for no smudges once the bubbles are gone")

        // Already clean and happy: the bubbles are the only thing that shows it was washed.
        let happy = PetState(food: 95, mood: 95, energy: 95, clean: 90, at: start)
        let again = VirtualPet.performing(.wash, on: happy, now: start, calendar: calendar)
        if case .bubbles = VirtualPet.effect(again, now: start) {} else { XCTFail("no bubbles") }
    }

    func testGoesToBedAtNightAndStaysUpWhenWoken() {
        let evening = at(2026, 10, 14, 22)
        let pet = PetState(food: 80, mood: 80, energy: 40, clean: 80, at: evening)
        let midnight = VirtualPet.advanced(pet, to: at(2026, 10, 15, 0), calendar: calendar)
        XCTAssertTrue(midnight.isSleeping, "asleep by itself after 23:00")
        XCTAssertTrue(midnight.sleepNightly)
        XCTAssertEqual(midnight.energy, 40 - 3 + 20, accuracy: 0.001, "an hour awake, an hour asleep")

        let morning = VirtualPet.advanced(pet, to: at(2026, 10, 15, 8), calendar: calendar)
        XCTAssertFalse(morning.isSleeping, "up at 7:00")
        XCTAssertEqual(morning.energy, 100 - 3, accuracy: 0.001)
        XCTAssertEqual(morning.food, 80 - 5 - 8 * 2.5 - 5, accuracy: 0.001)

        // Woken at midnight, it stays up for the rest of that night.
        let woken = VirtualPet.performing(.sleep, on: midnight, now: at(2026, 10, 15, 0), calendar: calendar)
        XCTAssertFalse(woken.isSleeping)
        XCTAssertFalse(VirtualPet.advanced(woken, to: at(2026, 10, 15, 2), calendar: calendar).isSleeping)
        XCTAssertTrue(VirtualPet.advanced(woken, to: at(2026, 10, 15, 23, 30), calendar: calendar).isSleeping,
                      "and goes to bed again the next night")

        // Fed at night, it wakes up too.
        XCTAssertFalse(VirtualPet.performing(.feed, on: midnight, now: at(2026, 10, 15, 0), calendar: calendar)
            .isSleeping)
    }

    func testAWeekendAwayLeavesItHungryNotSick() {
        let friday = at(2026, 10, 16, 18)
        let pet = PetState(food: 80, mood: 80, energy: 80, clean: 80, at: friday)
        let monday = VirtualPet.advanced(pet, to: at(2026, 10, 19, 9), calendar: calendar)
        for need in PetNeed.allCases {
            XCTAssertGreaterThanOrEqual(monday[need], VirtualPet.awayFloor, need.title)
        }
        XCTAssertNotEqual(VirtualPet.look(monday, now: monday.at), .sick)
        XCTAssertEqual(VirtualPet.look(monday, now: monday.at), .hungry)
    }

    func testFullPetTurnsThingsDown() {
        let now = at(2026, 10, 14, 9)
        let full = PetState(food: 98, mood: 98, energy: 50, clean: 98, at: now)
        let fed = VirtualPet.performing(.feed, on: full, now: now, calendar: calendar)
        XCTAssertEqual(fed.food, 98)
        XCTAssertEqual(fed.mood, 98, "no mood for food it did not eat")
        XCTAssertEqual(VirtualPet.statusLine(fed, now: now.addingTimeInterval(1)), "吃不下了")
        XCTAssertNotEqual(VirtualPet.look(fed, now: now.addingTimeInterval(1)), .eat)
        XCTAssertTrue(fed.cared.isEmpty, "turning food down is not looking after it")

        let played = VirtualPet.performing(.play, on: full, now: now, calendar: calendar)
        XCTAssertEqual(played.energy, 50, "a game it did not want costs nothing")
        XCTAssertEqual(VirtualPet.statusLine(played, now: now), "已经很开心了")
        XCTAssertEqual(VirtualPet.effect(played, now: now), .none)
        XCTAssertEqual(VirtualPet.statusLine(VirtualPet.performing(.wash, on: full, now: now, calendar: calendar),
                                             now: now), "已经很干净了")

        // Played with when it wanted a game: hearts.
        let bored = PetState(food: 60, mood: 40, energy: 60, clean: 60, at: now)
        let game = VirtualPet.performing(.play, on: bored, now: now, calendar: calendar)
        XCTAssertEqual(VirtualPet.effect(game, now: now), .hearts(until: now.addingTimeInterval(VirtualPet.actSeconds)))
        XCTAssertEqual(VirtualPet.statusLine(game, now: now), "玩得真开心")
    }

    func testSeeingTheDoctorOnlyWhenSick() {
        let now = at(2026, 10, 14, 15)
        let sick = PetState(food: 10, mood: 60, energy: 5, clean: 50, at: now)
        XCTAssertTrue(VirtualPet.isSick(sick))
        let healed = VirtualPet.performing(.heal, on: sick, now: now, calendar: calendar)
        XCTAssertFalse(VirtualPet.isSick(healed))
        XCTAssertEqual(healed.food, VirtualPet.healTo)
        XCTAssertEqual(healed.energy, VirtualPet.healTo)
        XCTAssertEqual(healed.mood, 60, "what was fine stays as it was")
        XCTAssertEqual(VirtualPet.effect(healed, now: now), .healing(until: now.addingTimeInterval(VirtualPet.actSeconds)))
        XCTAssertEqual(VirtualPet.statusLine(healed, now: now), "好多了")

        let well = PetState(food: 60, mood: 60, energy: 60, clean: 60, at: now)
        let turned = VirtualPet.performing(.heal, on: well, now: now, calendar: calendar)
        XCTAssertEqual(turned.food, 60)
        XCTAssertEqual(VirtualPet.statusLine(turned, now: now), "没有生病")
    }

    func testNextAlert() {
        let noon = at(2026, 10, 14, 12)
        // Food 60 reaches 35 in five hours, at 17:00.
        let pet = PetState(food: 60, mood: 90, energy: 90, clean: 90, at: noon)
        let alert = VirtualPet.nextAlert(pet, after: noon, calendar: calendar)
        XCTAssertEqual(alert?.sick, false)
        XCTAssertEqual(alert?.line, "饿了")
        XCTAssertEqual(alert.map { $0.date.timeIntervalSince(noon) / 3600 } ?? 0, 5, accuracy: 0.2)
        XCTAssertEqual(alert?.message(name: "小熊猫").title, "小熊猫需要照顾")

        // Already hungry: the next one is for falling sick (food 30 to 15, three hours).
        let hungry = PetState(food: 30, mood: 90, energy: 90, clean: 90, at: noon)
        let sick = VirtualPet.nextAlert(hungry, after: noon, calendar: calendar)
        XCTAssertEqual(sick?.sick, true)
        XCTAssertEqual(sick.map { $0.date.timeIntervalSince(noon) / 3600 } ?? 0, 3, accuracy: 0.2)

        // Due in the night: waits for 7:00.
        let evening = at(2026, 10, 14, 21)
        let late = VirtualPet.nextAlert(PetState(food: 45, mood: 90, energy: 90, clean: 90, at: evening),
                                        after: evening, calendar: calendar)
        XCTAssertEqual(late?.date, at(2026, 10, 15, 7))

        XCTAssertNil(VirtualPet.nextAlert(PetState(food: 5, at: noon), after: noon, calendar: calendar),
                     "already sick")
    }

    func testPictures() {
        XCTAssertEqual(VirtualPet.imageName(.redPanda, .idle), "pet-panda-idle")
        XCTAssertEqual(VirtualPet.imageName(.redPanda, .rest), "pet-panda-rest")
        XCTAssertEqual(VirtualPet.imageName(.shiba, .cheer), "water-shiba-cheer", "reuses 喝水's")
        XCTAssertEqual(VirtualPet.imageName(.otter, .sick), "pet-otter-sick")
        XCTAssertEqual(VirtualPet.imageName(.octopus, .hungry), "pet-octopus-hungry")
    }

    // MARK: Streak and storage

    func testStreak() {
        let today = at(2026, 10, 14, 10)
        var pet = PetState(at: today, cared: ["20261011", "20261012", "20261013"])
        XCTAssertEqual(VirtualPet.streak(pet, today: today, calendar: calendar), 3, "today not done yet keeps it")
        pet.cared.insert("20261014")
        XCTAssertEqual(VirtualPet.streak(pet, today: today, calendar: calendar), 4)
        pet.cared = ["20261010"]
        XCTAssertEqual(VirtualPet.streak(pet, today: today, calendar: calendar), 0)
    }

    func testRoundTripsThroughTheConfig() {
        let now = at(2026, 10, 14, 10)
        let pet = PetState(food: 12.34, mood: 56, energy: 78, clean: 90, at: now, sleepSince: now,
                           lastAction: .wash, lastActionAt: now, cared: ["20261014", "20260101"],
                           focusCredited: now)
        var config = WidgetConfig()
        VirtualPet.store(pet, in: &config, now: now, calendar: calendar)
        let back = VirtualPet.state(config, now: now)
        XCTAssertEqual(back.food, 12.3, accuracy: 0.001)
        XCTAssertEqual(back.mood, 56)
        XCTAssertEqual(back.sleepSince, now)
        XCTAssertEqual(back.lastAction, .wash)
        XCTAssertEqual(back.focusCredited, now)
        XCTAssertEqual(back.cared, ["20261014"], "older than four months is dropped")

        let fresh = VirtualPet.state(WidgetConfig(), now: now)
        XCTAssertEqual(fresh.food, 80)
        XCTAssertEqual(fresh.at, now)
        XCTAssertFalse(fresh.needsCare)
    }

    func testFinishedFocusIsCreditedOnce() {
        let now = at(2026, 10, 14, 10)
        var timer = TimerState()
        timer.phase = .focus
        timer.deadline = now.addingTimeInterval(-60)
        XCTAssertEqual(VirtualPet.finishedFocus(timer, credited: nil, now: now), timer.deadline)
        XCTAssertNil(VirtualPet.finishedFocus(timer, credited: timer.deadline, now: now), "once")
        timer.paused = 30
        XCTAssertNil(VirtualPet.finishedFocus(timer, credited: nil, now: now), "paused is not finished")
        timer.paused = nil
        timer.phase = .rest
        XCTAssertNil(VirtualPet.finishedFocus(timer, credited: nil, now: now), "a break is not focus")
        timer.phase = .focus
        timer.deadline = now.addingTimeInterval(60)
        XCTAssertNil(VirtualPet.finishedFocus(timer, credited: nil, now: now), "still running")
        timer.deadline = now.addingTimeInterval(-2 * 86_400)
        XCTAssertNil(VirtualPet.finishedFocus(timer, credited: nil, now: now), "a stale leftover")
    }

    // MARK: Wiring

    func testPetIsWiredIntoTheCatalogAndVisibility() {
        let entry = WidgetCatalog.entry(.pet)
        XCTAssertEqual(entry?.name, "电子宠物")
        XCTAssertEqual(entry?.category, .reminders)
        XCTAssertTrue(WidgetVisibility.supportsCondition(.pet))
        var widget = WidgetCatalog.make(.pet)!
        XCTAssertEqual(WidgetVisibility.conditionTitle(.pet, config: widget.config), "需要照顾时显示")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: widget.config, kind: .pet), "小熊猫")
        XCTAssertTrue(WidgetCatalog.isSupporterOnly(["character": .string("shiba")]))
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(["character": .string("panda")]))

        widget.config.set(WidgetVisibility.modeKey, .string("conditional"))
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown), false, "a new pet is fine")
        VirtualPet.store(PetState(food: 10, at: .now), in: &widget.config)
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown), true, "hungry shows it")
    }
}
