import XCTest

/// Which payment tab the sponsor window opens on.
final class SponsorMethodTests: XCTestCase {
    func testChineseSystemOpensWeChat() {
        XCTAssertEqual(SponsorMethod.pick(languages: ["zh-Hans-CN", "en"], region: "CN"), .wechat)
        XCTAssertEqual(SponsorMethod.pick(languages: ["zh-Hant-TW"], region: "TW"), .wechat)
    }

    func testChinaRegionOpensWeChatEvenInEnglish() {
        XCTAssertEqual(SponsorMethod.pick(languages: ["en-CN"], region: "CN"), .wechat)
    }

    func testEveryoneElseOpensKofi() {
        XCTAssertEqual(SponsorMethod.pick(languages: ["en-US"], region: "US"), .kofi)
        XCTAssertEqual(SponsorMethod.pick(languages: [], region: nil), .kofi)
    }

    func testEveryMethodHasItsCode() {
        XCTAssertEqual(SponsorMethod.allCases.map(\.imageName), ["SponsorWeChat", "SponsorAlipay", "SponsorKofi"])
    }
}
