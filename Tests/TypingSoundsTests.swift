import XCTest
@testable import Docket

final class TypingSoundsTests: XCTestCase {

    // MARK: 键码归类

    func testKeyCategories() {
        XCTAssertEqual(TypingSoundKey.of(keyCode: 36), .enter, "Return")
        XCTAssertEqual(TypingSoundKey.of(keyCode: 76), .enter, "小键盘 Enter")
        XCTAssertEqual(TypingSoundKey.of(keyCode: 49), .space)
        XCTAssertEqual(TypingSoundKey.of(keyCode: 51), .backspace, "Delete")
        XCTAssertEqual(TypingSoundKey.of(keyCode: 117), .backspace, "向前删除")
        XCTAssertEqual(TypingSoundKey.of(keyCode: 0), .key, "A")
        XCTAssertEqual(TypingSoundKey.of(keyCode: 123), .key, "方向键也算普通键")
        for modifier in 54...63 { XCTAssertNil(TypingSoundKey.of(keyCode: modifier), "修饰键 \(modifier) 不响") }
        XCTAssertNil(TypingSoundKey.of(keyCode: 72), "音量键不响")
        XCTAssertNil(TypingSoundKey.of(keyCode: -1))
        XCTAssertNil(TypingSoundKey.of(keyCode: 400))
        XCTAssertEqual(TypingSoundKey.key.fileKeys, ["key-1", "key-2", "key-3", "key-4"])
        XCTAssertEqual(TypingSoundKey.enter.fileKeys, ["enter"])
    }

    // MARK: 七款和 Pro

    func testStylesAndProSplit() {
        XCTAssertEqual(TypingSoundStyle.allCases.count, 7)
        XCTAssertEqual(TypingSoundStyle.allCases.filter { !$0.isPro }, [.blue], "免费只有青轴")
        XCTAssertEqual(TypingSoundStyle.allCases.filter(\.isRecording), [.red, .black, .capacitive, .quiet])
        XCTAssertEqual(TypingSoundStyle.allCases.map(\.title),
                       ["青轴", "茶轴", "打字机", "红轴", "黑轴", "静电容", "白噪安静款"])
        // 界面不出现品牌名。
        let brands = ["cherry", "topre", "hhkb", "gateron", "kailh", "mechvibes"]
        for style in TypingSoundStyle.allCases {
            let text = (style.title + style.caption).lowercased()
            for brand in brands { XCTAssertFalse(text.contains(brand), "\(style) 出现了 \(brand)") }
        }
        XCTAssertEqual(TypingSoundStyle.blue.fileName("key-2"), "typing-blue-key-2")
        XCTAssertEqual(TypingSoundStyle.quiet.fileNames.count, 7)
    }

    func testProGate() {
        var settings = TypingSoundSettings()
        XCTAssertEqual(TypingSoundGate.effectiveChoice(settings, unlocked: false), .style(.blue))
        settings.choice = TypingSoundStyle.typewriter.rawValue
        XCTAssertEqual(TypingSoundGate.effectiveChoice(settings, unlocked: false), .style(.blue), "没解锁按青轴响")
        XCTAssertEqual(settings.choice, "typewriter", "选择不改写")
        XCTAssertEqual(TypingSoundGate.effectiveChoice(settings, unlocked: true), .style(.typewriter))
        XCTAssertFalse(TypingSoundGate.canChoose(.style(.red), unlocked: false))
        XCTAssertTrue(TypingSoundGate.canChoose(.style(.blue), unlocked: false))
        XCTAssertFalse(TypingSoundGate.canImport(unlocked: false))
        XCTAssertTrue(TypingSoundGate.canImport(unlocked: true))
        XCTAssertFalse(TypingSoundGate.canChoose(.pack("x"), unlocked: false), "导入的包是 Pro")

        settings.packs = [TypingSoundPackRecord(id: "abc", name: "Pack", method: "single", keyCount: 3)]
        settings.choice = TypingSoundChoice.pack("abc").raw
        XCTAssertEqual(TypingSoundGate.effectiveChoice(settings, unlocked: true), .pack("abc"))
        XCTAssertEqual(TypingSoundGate.effectiveChoice(settings, unlocked: false), .style(.blue))
        settings.choice = TypingSoundChoice.pack("gone").raw
        XCTAssertEqual(TypingSoundGate.effectiveChoice(settings, unlocked: true), .style(.blue), "删掉的包按青轴")

        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.typingSounds))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.typingSounds)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.typingSounds)), "打字音效")
        XCTAssertFalse(ProLicenseGate.typingSoundsProActive(unlocked: false))
        XCTAssertTrue(ProLicenseGate.typingSoundsProActive(unlocked: true))
    }

    func testChoiceRawValues() {
        XCTAssertEqual(TypingSoundChoice(raw: "brown"), .style(.brown))
        XCTAssertEqual(TypingSoundChoice(raw: "nonsense"), .style(.blue))
        XCTAssertEqual(TypingSoundChoice(raw: "pack:12-ab"), .pack("12-ab"))
        XCTAssertEqual(TypingSoundChoice(raw: "pack:"), .style(.blue))
        XCTAssertEqual(TypingSoundChoice.pack("x").raw, "pack:x")
        XCTAssertTrue(TypingSoundChoice.pack("x").isPro)
        XCTAssertFalse(TypingSoundChoice.style(.blue).isPro)
    }

    // MARK: 设置

    func testSettingsDefaultsAndLenientDecoding() throws {
        let value = TypingSoundSettings()
        XCTAssertFalse(value.enabled, "默认关")
        XCTAssertEqual(value.selected, .style(.blue))
        XCTAssertEqual(value.clampedVolume, TypingSoundSettings.defaultVolume)
        XCTAssertEqual(PersistedState().typingSounds, value)

        var state = PersistedState()
        state.typingSounds.enabled = true
        state.typingSounds.choice = "red"
        state.typingSounds.volume = 0.3
        state.typingSounds.packs = [TypingSoundPackRecord(id: "a-1", name: "A", author: "me", method: "multi", keyCount: 9)]
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.typingSounds, state.typingSounds)

        let legacy = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.typingSounds, TypingSoundSettings())

        let odd = Data(#"{"enabled":"yes","choice":"","volume":7,"packs":[{"id":"x","name":"X","author":"","method":"single","keyCount":1},{"id":"x","name":"Y","author":"","method":"single","keyCount":1}]}"#.utf8)
        let decoded = try JSONDecoder().decode(TypingSoundSettings.self, from: odd)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.choice, "blue")
        XCTAssertEqual(decoded.clampedVolume, 1, "音量夹到 0…1")
        XCTAssertEqual(decoded.packs.map(\.name), ["X"], "重复 id 只留第一个")
    }

    func testRemovingSelectedPackFallsBackToBlue() {
        var settings = TypingSoundSettings()
        settings.packs = [TypingSoundPackRecord(id: "p", name: "P", method: "single", keyCount: 1)]
        settings.choice = "pack:p"
        settings.removePack("p")
        XCTAssertTrue(settings.packs.isEmpty)
        XCTAssertEqual(settings.selected, .style(.blue))
    }

    func testListenOnlyWhenEnabledAndPermitted() {
        var settings = TypingSoundSettings()
        XCTAssertFalse(TypingSoundGate.shouldListen(settings, permitted: true))
        settings.enabled = true
        XCTAssertFalse(TypingSoundGate.shouldListen(settings, permitted: false), "没权限不装监听")
        XCTAssertTrue(TypingSoundGate.shouldListen(settings, permitted: true))
    }

    // MARK: 连发和安全输入

    func testSecureInputIsSilent() {
        var throttle = TypingSoundThrottle()
        XCTAssertFalse(throttle.admit(isRepeat: false, secureInput: true, now: 10))
        XCTAssertTrue(throttle.admit(isRepeat: false, secureInput: false, now: 10), "密码框里那一下不算数")
    }

    func testAutorepeatIsRateLimited() {
        var throttle = TypingSoundThrottle()
        XCTAssertTrue(throttle.admit(isRepeat: false, secureInput: false, now: 0))
        // 系统连发大约每 0.03 秒一下：0.15 秒里只响一次。
        var played = 0
        var t = 0.4
        while t < 1.4 {
            if throttle.admit(isRepeat: true, secureInput: false, now: t) { played += 1 }
            t += 0.03
        }
        XCTAssertLessThanOrEqual(played, Int(1.0 / TypingSoundThrottle.repeatInterval) + 1)
        XCTAssertGreaterThan(played, 0, "按住删除时还是有节奏地响")
        // 正常打字不受连发间隔影响。
        var typing = TypingSoundThrottle()
        XCTAssertTrue(typing.admit(isRepeat: false, secureInput: false, now: 0))
        XCTAssertTrue(typing.admit(isRepeat: false, secureInput: false, now: 0.05))
        XCTAssertTrue(typing.admit(isRepeat: false, secureInput: false, now: 0.1))
        XCTAssertFalse(typing.admit(isRepeat: false, secureInput: false, now: 0.105), "两声至少隔 12 ms")
    }

    func testRepeatRightAfterPressWaitsAFullInterval() {
        var throttle = TypingSoundThrottle()
        XCTAssertTrue(throttle.admit(isRepeat: false, secureInput: false, now: 1))
        XCTAssertFalse(throttle.admit(isRepeat: true, secureInput: false, now: 1.1))
        XCTAssertTrue(throttle.admit(isRepeat: true, secureInput: false, now: 1.16))
    }

    // MARK: 变体和音高

    func testVariantsNeverRepeatBackToBack() {
        var picker = TypingSoundVariantPicker()
        var last = -1
        var seen = Set<Int>()
        for i in 0..<200 {
            let r = Double((i * 7919) % 1000) / 1000
            let index = picker.next("key", count: 4, random: r)
            XCTAssertTrue((0..<4).contains(index))
            XCTAssertNotEqual(index, last, "第 \(i) 次和上一次一样")
            seen.insert(index)
            last = index
        }
        XCTAssertEqual(seen.count, 4, "四个变体都用得到")
        XCTAssertEqual(picker.next("space", count: 1, random: 0.9), 0)
        XCTAssertEqual(picker.next("space", count: 1, random: 0.1), 0, "只有一个时就用它")
        XCTAssertTrue((0..<4).contains(picker.next("key", count: 4, random: 1.5)), "越界的随机数也夹住")
    }

    func testPitchAndGainStayInRange() {
        XCTAssertEqual(TypingSoundVariantPicker.rate(spread: 50, random: 0.5), 1, accuracy: 0.0001)
        let low = TypingSoundVariantPicker.rate(spread: 50, random: 0)
        let high = TypingSoundVariantPicker.rate(spread: 50, random: 1)
        XCTAssertEqual(low, Float(pow(2, -50.0 / 1200)), accuracy: 0.0001)
        XCTAssertEqual(high, Float(pow(2, 50.0 / 1200)), accuracy: 0.0001)
        XCTAssertGreaterThan(high, 1)
        XCTAssertLessThan(high, 1.03, "音高起伏不超过约半个半音")
        XCTAssertEqual(TypingSoundVariantPicker.gain(random: 0), 0.85, accuracy: 0.0001)
        XCTAssertEqual(TypingSoundVariantPicker.gain(random: 9), 1, accuracy: 0.0001)
    }

    // MARK: 键码对照

    func testMacKeyCodesMapToWebCodes() {
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 0), "KeyA")
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 38), "KeyJ")
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 36), "Enter")
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 49), "Space")
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 51), "Backspace")
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 117), "Delete")
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 126), "ArrowUp")
        XCTAssertEqual(TypingKeyCodes.web(keyCode: 18), "Digit1")
        XCTAssertNil(TypingKeyCodes.web(keyCode: 52))
        // 26 个字母都有。
        let letters = Set(TypingKeyCodes.macToWeb.values.filter { $0.hasPrefix("Key") })
        XCTAssertEqual(letters, Set(TypingKeyCodes.letters))
        XCTAssertEqual(TypingKeyCodes.letters.count, 26)
        XCTAssertEqual(Set(TypingKeyCodes.macToWeb.values).count, TypingKeyCodes.macToWeb.count, "不重名")
    }

    func testIohookCodesForVersionOnePacks() {
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "30"), "KeyA")
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "57"), "Space")
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "28"), "Enter")
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "14"), "Backspace")
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "3612"), "NumpadEnter")
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "3667"), "Delete")
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "57416"), "ArrowUp")
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "57424"), "ArrowDown")
        XCTAssertNil(TypingKeyCodes.web(v1Key: "99999"))
        XCTAssertEqual(TypingKeyCodes.web(v1Key: "KeyQ"), "KeyQ", "已经是名字的原样用")
    }

    // MARK: Mechvibes config.json

    func testParsesVersionTwoSinglePack() throws {
        let json = #"""
        {"config_version":"2","name":"Test Pack","author":"Someone","definition_method":"single",
         "audio_file":"./sound.ogg",
         "definitions":{"KeyA":{"timing":[[100,175],[175,250]]},"Space":{"timing":[[300,400]]},
                        "Enter":{"timing":[[500,600]]},"KeyB":{"timing":[[700,650]]},"Weird":{"timing":[[1,2,3]]}}}
        """#
        let pack = try MechvibesPack.parse(Data(json.utf8))
        XCTAssertEqual(pack.name, "Test Pack")
        XCTAssertEqual(pack.author, "Someone")
        XCTAssertEqual(pack.method, .single)
        XCTAssertEqual(pack.files, ["sound.ogg"], "去掉 ./")
        XCTAssertEqual(pack.definitions["KeyA"], .init(file: "sound.ogg", start: 100, end: 175), "只用按下那一段")
        XCTAssertNil(pack.definitions["KeyB"], "结束早于开始的丢掉")
        XCTAssertNil(pack.definitions["Weird"], "不是两个数的丢掉")
        XCTAssertEqual(pack.segment(keyCode: 0, random: 0), pack.definitions["KeyA"])
        XCTAssertEqual(pack.segment(keyCode: 49, random: 0), pack.definitions["Space"])
        XCTAssertEqual(pack.segment(keyCode: 76, random: 0), pack.definitions["Enter"], "小键盘 Enter 借回车")
        // 没定义的 J：从定义了的字母键里借。
        XCTAssertEqual(pack.segment(keyCode: 38, random: 0.5), pack.definitions["KeyA"])
        XCTAssertNil(pack.segment(keyCode: 56, random: 0), "修饰键不借")
    }

    func testParsesVersionTwoMultiPack() throws {
        let json = #"""
        {"name":"Multi","author":"x","definition_method":"multi","audio_file":"default.wav",
         "definitions":{"KeyA":{"audio_file":"a.wav","timing":[[0,50]]},"KeyS":{"audio_file":"sub/s.mp3"},
                        "Space":{"timing":[[0,80]]}}}
        """#
        let pack = try MechvibesPack.parse(Data(json.utf8))
        XCTAssertEqual(pack.method, .multi)
        XCTAssertEqual(pack.definitions["KeyS"], .init(file: "sub/s.mp3"), "没有 timing 时放整个文件")
        XCTAssertEqual(pack.definitions["Space"]?.file, "default.wav", "没写自己的文件时用包的")
        XCTAssertEqual(pack.files, ["a.wav", "default.wav", "sub/s.mp3"])
    }

    func testParsesVersionOnePacks() throws {
        let single = #"{"id":"old","name":"Old","key_define_type":"single","sound":"sound.ogg","defines":{"30":[1000,120],"57":[2000,150],"28":null,"3667":[3000,90]}}"#
        let pack = try MechvibesPack.parse(Data(single.utf8))
        XCTAssertEqual(pack.method, .single)
        XCTAssertEqual(pack.definitions["KeyA"], .init(file: "sound.ogg", start: 1000, end: 1120), "第 1 版是开始加时长")
        XCTAssertEqual(pack.definitions["Space"]?.end, 2150)
        XCTAssertEqual(pack.definitions["Delete"]?.start, 3000)
        XCTAssertNil(pack.definitions["Enter"], "null 的键丢掉")
        XCTAssertEqual(pack.segment(keyCode: 117, random: 0), pack.definitions["Delete"])
        XCTAssertEqual(pack.segment(keyCode: 51, random: 0), pack.definitions["Delete"], "删除借向前删除")

        let multi = #"{"name":"M","key_define_type":"multi","defines":{"30":"a.wav","57":"space.wav","1":null,"14":"null"}}"#
        let m = try MechvibesPack.parse(Data(multi.utf8))
        XCTAssertEqual(m.method, .multi)
        XCTAssertEqual(m.definitions["KeyA"], .init(file: "a.wav"))
        XCTAssertEqual(m.definitions.count, 2)
    }

    func testRejectsBadPacks() {
        XCTAssertThrowsError(try MechvibesPack.parse(Data("not json".utf8))) {
            XCTAssertEqual($0 as? MechvibesPack.ParseError, .invalidJSON)
        }
        XCTAssertThrowsError(try MechvibesPack.parse(Data(#"{"name":"x"}"#.utf8))) {
            XCTAssertEqual($0 as? MechvibesPack.ParseError, .noDefinitions)
        }
        XCTAssertThrowsError(try MechvibesPack.parse(Data(#"{"defines":{"30":[0,10]}}"#.utf8))) {
            XCTAssertEqual($0 as? MechvibesPack.ParseError, .missingAudioFile)
        }
        XCTAssertThrowsError(try MechvibesPack.parse(Data(#"{"config_version":3,"definitions":{}}"#.utf8))) {
            XCTAssertEqual($0 as? MechvibesPack.ParseError, .tooNewVersion)
        }
        XCTAssertThrowsError(try MechvibesPack.parse(Data(#"{"audio_file":"../../etc/x.wav","definitions":{"KeyA":{"timing":[[0,10]]}}}"#.utf8))) {
            XCTAssertEqual($0 as? MechvibesPack.ParseError, .unsafePath("../../etc/x.wav"))
        }
        XCTAssertThrowsError(try MechvibesPack.parse(Data(#"{"audio_file":"/tmp/x.wav","definitions":{"KeyA":{"timing":[[0,10]]}}}"#.utf8)))
        XCTAssertThrowsError(try MechvibesPack.parse(Data(#"{"audio_file":"sound.opus","definitions":{"KeyA":{"timing":[[0,10]]}}}"#.utf8))) {
            XCTAssertEqual($0 as? MechvibesPack.ParseError, .unsupportedFormat("opus"))
        }
        XCTAssertTrue(MechvibesPack.ParseError.unsupportedFormat("opus").message.contains("opus"))
    }

    func testCleanPath() throws {
        XCTAssertEqual(try MechvibesPack.cleanPath("./a/b.wav"), "a/b.wav")
        XCTAssertEqual(try MechvibesPack.cleanPath("a\\b.wav"), "a/b.wav")
        XCTAssertEqual(try MechvibesPack.cleanPath("a//b.wav"), "a/b.wav")
        XCTAssertThrowsError(try MechvibesPack.cleanPath("a/../../b.wav"))
        XCTAssertThrowsError(try MechvibesPack.cleanPath(""))
        XCTAssertThrowsError(try MechvibesPack.cleanPath("/abs.wav"))
    }

    func testPackIDsAndNames() {
        XCTAssertTrue(TypingSoundPacks.isValidID("0f3c-12ab"))
        XCTAssertFalse(TypingSoundPacks.isValidID("../x"))
        XCTAssertFalse(TypingSoundPacks.isValidID(""))
        XCTAssertFalse(TypingSoundPacks.isValidID("a/b"))
        let unnamed = MechvibesPack(name: "", author: "", method: .single, definitions: [:])
        XCTAssertEqual(TypingSoundPacks.displayName(unnamed, fallback: "my-pack"), "my-pack")
    }

    // MARK: 素材

    /// 49 个 wav 都在、格式对、总大小不超预算（合成三套 < 0.5 MB，七套 < 1.5 MB）。
    func testBundledSoundFiles() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/TypingSounds")
        var total = 0
        var synthesized = 0
        for style in TypingSoundStyle.allCases {
            for name in style.fileNames {
                let url = folder.appending(path: name + ".wav")
                let data = try Data(contentsOf: url)
                XCTAssertEqual(data.prefix(4), Data("RIFF".utf8), name)
                XCTAssertEqual(data.subdata(in: 8..<12), Data("WAVE".utf8), name)
                total += data.count
                if !style.isRecording { synthesized += data.count }
            }
        }
        XCTAssertLessThan(synthesized, 500_000)
        XCTAssertLessThan(total, 1_500_000)
    }
}
