import XCTest

/// 码头 Pro 授权的纯逻辑：状态机、试用天数、离线宽限、响应解析、兑换码、打码和文案。
final class ProLicenseTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 配置

    func testConfigPointsAtDockling() {
        XCTAssertEqual(ProLicenseConfig.productID, "prod_XYf9P2X55fvYZQOLhs3Lr")
        XCTAssertEqual(ProLicenseConfig.buyURL.absoluteString,
                       "https://www.creem.io/payment/prod_XYf9P2X55fvYZQOLhs3Lr")
        XCTAssertTrue(ProLicenseConfig.apiBase.hasPrefix("https://dockling-license."))
        XCTAssertTrue(ProLicenseConfig.apiBase.hasSuffix("/v1/licenses/"))
        XCTAssertFalse(ProLicenseConfig.apiBase.contains("shiduo"))
        XCTAssertNotNil(URL(string: ProLicenseConfig.apiBase + "activate"))
        XCTAssertEqual(ProLicenseConfig.trialDays, 7)
        XCTAssertEqual(ProLicenseConfig.giftPrefix, "DKG")
    }

    // MARK: 状态机

    func testFreshInstallIsFreeAndCanStartTrial() {
        let snapshot = ProLicenseSnapshot()
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now), .free)
        XCTAssertTrue(ProLicenseLogic.canStartTrial(snapshot))
        XCTAssertFalse(ProLicenseState.free.isUnlocked)
    }

    func testTrialCountsDownSevenDays() {
        var snapshot = ProLicenseSnapshot(trialStart: now)
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now), .trial(daysLeft: 7))
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now + day * 0.9), .trial(daysLeft: 7))
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now + day), .trial(daysLeft: 6))
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now + day * 6.5), .trial(daysLeft: 1))
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now + day * 7), .expiredTrial)
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now + day * 100), .expiredTrial)
        XCTAssertFalse(ProLicenseLogic.canStartTrial(snapshot), "试用开始过就不能再开始")
        snapshot.trialStart = now + day * 3
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now), .trial(daysLeft: 7), "时钟往回拨不会多给")
        XCTAssertTrue(ProLicenseState.trial(daysLeft: 3).isUnlocked)
        XCTAssertFalse(ProLicenseState.expiredTrial.isUnlocked)
    }

    func testTrialEndDate() {
        XCTAssertEqual(ProLicenseLogic.trialEndDate(trialStart: now), now + day * 7)
    }

    func testActivatedIsProWithinGrace() {
        let snapshot = ProLicenseSnapshot(licenseKey: "ABCD-1234", instanceID: "inst_1",
                                          lastValidated: now - day * 29, trialStart: now - day * 40)
        XCTAssertTrue(snapshot.isActivated)
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now), .pro)
        XCTAssertTrue(ProLicenseState.pro.isUnlocked)
        XCTAssertFalse(ProLicenseLogic.canStartTrial(snapshot))
    }

    func testGraceRunsOutAfterThirtyDaysOffline() {
        let snapshot = ProLicenseSnapshot(licenseKey: "ABCD-1234", instanceID: "inst_1",
                                          lastValidated: now - day * 30, trialStart: now - day * 40)
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now), .expiredTrial)
        let noTrial = ProLicenseSnapshot(licenseKey: "ABCD-1234", instanceID: "inst_1", lastValidated: now - day * 31)
        XCTAssertEqual(ProLicenseLogic.state(noTrial, now: now), .free)
        XCTAssertTrue(ProLicenseLogic.withinGrace(lastValidated: now - day * 29.9, now: now))
        XCTAssertFalse(ProLicenseLogic.withinGrace(lastValidated: now - day * 30, now: now))
    }

    func testKeyWithoutInstanceIsNotActivated() {
        let snapshot = ProLicenseSnapshot(licenseKey: "ABCD-1234", instanceID: nil, lastValidated: now)
        XCTAssertFalse(snapshot.isActivated)
        XCTAssertEqual(ProLicenseLogic.state(snapshot, now: now), .free)
        XCTAssertFalse(ProLicenseSnapshot(licenseKey: "", instanceID: "x", lastValidated: now).isActivated)
    }

    func testRevalidationOncePerDay() {
        var snapshot = ProLicenseSnapshot(licenseKey: "K", instanceID: "I", lastValidated: now - 3600)
        XCTAssertFalse(ProLicenseLogic.needsRevalidation(snapshot, now: now))
        snapshot.lastValidated = now - day
        XCTAssertTrue(ProLicenseLogic.needsRevalidation(snapshot, now: now))
        snapshot.lastValidated = now + day
        XCTAssertTrue(ProLicenseLogic.needsRevalidation(snapshot, now: now), "上次校验在将来说明时钟被拨过")
        snapshot.lastValidated = nil
        XCTAssertTrue(ProLicenseLogic.needsRevalidation(snapshot, now: now))
        XCTAssertFalse(ProLicenseLogic.needsRevalidation(ProLicenseSnapshot(trialStart: now), now: now))
    }

    func testStatusTexts() {
        XCTAssertEqual(ProLicenseState.free.statusText, "免费版")
        XCTAssertEqual(ProLicenseState.trial(daysLeft: 3).statusText, "Pro 试用中，还剩 3 天")
        XCTAssertEqual(ProLicenseState.pro.statusText, "码头 Pro 已激活")
        XCTAssertEqual(ProLicenseState.expiredTrial.statusText, "试用已结束")
    }

    // MARK: 响应

    private func parse(_ json: String) -> ProLicenseResponse? {
        ProLicenseResponse.parse(Data(json.utf8))
    }

    func testParsesRelayResponse() throws {
        let r = try XCTUnwrap(parse("""
            {"activated":true,"instance":{"id":"inst_9"},"license_key":{"status":"active"},
             "meta":{"product_id":"prod_XYf9P2X55fvYZQOLhs3Lr"}}
            """))
        XCTAssertEqual(r.activated, true)
        XCTAssertEqual(r.instanceID, "inst_9")
        XCTAssertEqual(r.status, "active")
        XCTAssertTrue(r.matchesProduct)
        XCTAssertEqual(ProLicenseLogic.activation(r), .success(instanceID: "inst_9"))
        XCTAssertNil(parse("not json"))
        XCTAssertNil(parse("[1,2]"))
    }

    func testSiblingProductIsRejected() throws {
        let r = try XCTUnwrap(parse("""
            {"activated":true,"instance":{"id":"inst_9"},"license_key":{"status":"active"},
             "meta":{"product_id":"prod_632G8EgQJWLL6m9M5JaBXv"}}
            """))
        XCTAssertFalse(r.matchesProduct)
        XCTAssertEqual(ProLicenseLogic.activation(r), .wrongProduct(instanceID: "inst_9"))
        let missing = ProLicenseResponse(activated: true, instanceID: "x", status: "active", productID: nil)
        XCTAssertFalse(missing.matchesProduct, "没有产品 ID 也不认")
        var valid = r
        valid.activated = nil
        valid.valid = true
        XCTAssertEqual(ProLicenseLogic.revalidation(valid), .revoked(message: ProLicenseText.wrongProduct))
    }

    func testActivationFailureMessages() {
        let limit = ProLicenseResponse(activated: false, error: "activation limit reached")
        guard case .failure(let message) = ProLicenseLogic.activation(limit) else { return XCTFail() }
        XCTAssertTrue(message.contains("解绑本机"))
        let expired = ProLicenseResponse(activated: true, instanceID: "i", status: "expired",
                                         productID: ProLicenseConfig.productID)
        XCTAssertEqual(ProLicenseLogic.activation(expired), .failure(message: "这个许可证已过期。"))
    }

    func testRevalidationOutcomes() {
        XCTAssertEqual(ProLicenseLogic.revalidation(nil), .keep, "没网时保持")
        let ok = ProLicenseResponse(valid: true, status: "active", productID: ProLicenseConfig.productID)
        XCTAssertEqual(ProLicenseLogic.revalidation(ok), .confirmed)
        let gone = ProLicenseResponse(valid: false, error: "instance not found.", status: "active",
                                      productID: ProLicenseConfig.productID)
        guard case .revoked = ProLicenseLogic.revalidation(gone) else { return XCTFail() }
        let disabled = ProLicenseResponse(valid: false, error: "license disabled")
        XCTAssertEqual(ProLicenseLogic.revalidation(disabled), .revoked(message: "这个许可证已被停用。"))
        XCTAssertEqual(ProLicenseLogic.revalidation(ProLicenseResponse(error: "upstream unavailable")), .keep,
                       "服务器出错不算吊销")
    }

    func testDeactivation() {
        XCTAssertTrue(ProLicenseLogic.deactivationSucceeded(ProLicenseResponse(deactivated: true)))
        XCTAssertTrue(ProLicenseLogic.deactivationSucceeded(ProLicenseResponse(deactivated: false, error: "instance not found.")))
        XCTAssertFalse(ProLicenseLogic.deactivationSucceeded(ProLicenseResponse(deactivated: false, error: "too many requests")))
    }

    // MARK: 输入和兑换码

    func testGiftCodeFormat() {
        XCTAssertEqual(ProLicenseInput.classify("DKG-ABCD-2345-WXYZ"), .gift("DKG-ABCD-2345-WXYZ"))
        XCTAssertEqual(ProLicenseInput.classify("  dkg-abcd-2345-wxyz \n"), .gift("DKG-ABCD-2345-WXYZ"))
        XCTAssertEqual(ProLicenseInput.classify("DKGABCD2345WXYZ"), .gift("DKG-ABCD-2345-WXYZ"))
        XCTAssertEqual(ProLicenseInput.classify("dkg abcd 2345 wxyz"), .gift("DKG-ABCD-2345-WXYZ"))
        XCTAssertEqual(ProLicenseInput.classify("DKG-ABCD-2345"), .malformedGift)
        XCTAssertEqual(ProLicenseInput.classify("DKG-ABC0-2345-WXYZ"), .malformedGift, "0 不在字符表里")
        XCTAssertEqual(ProLicenseInput.classify("DKG-ABCI-2345-WXYZ"), .malformedGift, "I 不在字符表里")
        XCTAssertEqual(ProLicenseInput.classify("SDG-ABCD-2345-WXYZ"), .siblingGift)
        XCTAssertEqual(ProLicenseInput.classify("   "), .empty)
        XCTAssertEqual(ProLicenseInput.classify(" 3f2a-ff19-abcd "), .licenseKey("3f2a-ff19-abcd"),
                       "许可证密钥原样提交，不改大小写")
        XCTAssertTrue(ProLicenseInput.isGiftCode("DKG-ABCD-2345-WXYZ"))
        XCTAssertFalse(ProLicenseInput.isGiftCode("dkg-abcd-2345-wxyz"))
        XCTAssertEqual(ProLicenseInput.giftAlphabet.count, 32)
    }

    func testInputProblems() {
        XCTAssertEqual(ProLicenseText.inputProblem(.empty), ProLicenseText.emptyInput)
        XCTAssertEqual(ProLicenseText.inputProblem(.malformedGift), ProLicenseText.malformedGift)
        XCTAssertEqual(ProLicenseText.inputProblem(.siblingGift), ProLicenseText.siblingGift)
        XCTAssertNil(ProLicenseText.inputProblem(.gift("DKG-ABCD-2345-WXYZ")))
        XCTAssertNil(ProLicenseText.inputProblem(.licenseKey("abc")))
    }

    // MARK: 打码和文案

    func testMasking() {
        XCTAssertEqual(ProLicenseText.mask("ABCD-EFGH-IJKL-MNOP"), "ABCD••••••••MNOP")
        XCTAssertEqual(ProLicenseText.mask("DKG-ABCD-2345-WXYZ"), "DKG-••••-••••-WXYZ")
        XCTAssertEqual(ProLicenseText.mask("short"), "•••••")
        XCTAssertFalse(ProLicenseText.mask("ABCD-EFGH-IJKL-MNOP").contains("EFGH"))
    }

    func testErrorMessagesAreChinese() {
        XCTAssertEqual(ProLicenseText.message(error: "license_key not found.", status: nil),
                       "许可证密钥或兑换码不正确，请检查是否完整复制。")
        XCTAssertEqual(ProLicenseText.message(error: nil, status: "disabled"), "这个许可证已被停用。")
        XCTAssertEqual(ProLicenseText.message(error: "too many requests", status: nil), "请求太频繁，请稍后再试。")
        XCTAssertEqual(ProLicenseText.message(error: "server misconfigured", status: nil), "授权服务器暂时不可用，请稍后再试。")
        XCTAssertEqual(ProLicenseText.message(error: nil, status: nil), "授权失败，请稍后再试。")
        XCTAssertEqual(ProLicenseText.message(error: "weird", status: nil), "授权失败：weird")
        XCTAssertTrue(ProLicenseText.priceLine.contains("$9.90"))
        XCTAssertTrue(ProLicenseText.priceLine.contains("$6.90"))
        XCTAssertTrue(ProLicenseText.priceLine.contains("$15.90"))
        XCTAssertTrue(ProLicenseText.priceLine.contains("20"))
    }

    // MARK: 锁

    func testSupporterAndTrialUnlock() {
        XCTAssertFalse(ProLicenseGate.isUnlocked(.free, supporter: false))
        XCTAssertFalse(ProLicenseGate.isUnlocked(.expiredTrial, supporter: false))
        XCTAssertTrue(ProLicenseGate.isUnlocked(.expiredTrial, supporter: true), "老赞助者不被锁")
        XCTAssertTrue(ProLicenseGate.isUnlocked(.trial(daysLeft: 1), supporter: false))
        XCTAssertTrue(ProLicenseGate.isUnlocked(.pro, supporter: false))
    }

    func testAddingAndChoosing() {
        XCTAssertFalse(ProLicenseGate.canAdd(.pet, overrides: [:], unlocked: false))
        XCTAssertTrue(ProLicenseGate.canAdd(.pet, overrides: [:], unlocked: true))
        XCTAssertTrue(ProLicenseGate.canAdd(.clock, overrides: [:], unlocked: false))
        XCTAssertFalse(ProLicenseGate.canAdd(.clock, overrides: ["layout": .string("neon")], unlocked: false))
        XCTAssertFalse(ProLicenseGate.canChoose(["look": .string("liquid")], unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChoose(["look": .string("classic")], unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChoose(["layout": .string("liquid")], unlocked: true))
    }

    func testLockOverlay() {
        let pet = WidgetInstance(kind: .pet, config: WidgetConfig())
        XCTAssertTrue(ProLicenseGate.needsLockOverlay(pet, unlocked: false))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(pet, unlocked: true))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(pet, unlocked: false, isPreview: true))

        let liquidClock = WidgetInstance(kind: .clock, config: WidgetConfig(["layout": .string("liquid")]))
        XCTAssertTrue(ProLicenseGate.needsLockOverlay(liquidClock, unlocked: false))

        // 电池的液态和赞助者外观退回经典，不盖遮罩。
        let liquidBattery = WidgetInstance(kind: .battery, config: WidgetConfig([BatteryLook.key: .string("liquid")]))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(liquidBattery, unlocked: false))
        let neon = WidgetInstance(kind: .clock, config: WidgetConfig(["layout": .string("neon")]))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(neon, unlocked: false))
        let plain = WidgetInstance(kind: .clock, config: WidgetConfig())
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(plain, unlocked: false))
    }

    func testBatteryFallsBackToClassic() {
        let liquid = WidgetConfig([BatteryLook.key: .string("liquid")])
        XCTAssertEqual(ProLicenseGate.batteryLook(config: liquid, unlocked: false), .classic)
        XCTAssertEqual(ProLicenseGate.batteryLook(config: liquid, unlocked: true), .liquid)
        let panda = WidgetConfig([BatteryLook.key: .string("panda")])
        XCTAssertEqual(ProLicenseGate.batteryLook(config: panda, unlocked: false), .classic)
        XCTAssertEqual(ProLicenseGate.batteryLook(config: panda, unlocked: true), .panda)
        XCTAssertEqual(ProLicenseGate.batteryLook(config: WidgetConfig(), unlocked: false), .classic)
        for look in BatteryLook.allCases {
            XCTAssertFalse(ProFeatures.isProStyle([BatteryLook.key: .string(ProLicenseGate.batteryLook(
                config: WidgetConfig([BatteryLook.key: .string(look.rawValue)]), unlocked: false).rawValue)]),
                "锁着时显示的电池外观都是免费的")
        }
    }
}
