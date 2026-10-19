import XCTest

/// 全局视觉规矩：尺寸常量、状态先后、减少动态效果、缺权限的那句话、空状态的小熊猫。
final class DockStyleTests: XCTestCase {

    // MARK: 常量

    func testMetricsKeepTheCurrentLook() {
        // 换成常量后外观不变：这些是原来卡片里最常见的写法。
        XCTAssertEqual(DockMetrics.cardCorner, 18)
        XCTAssertEqual(DockMetrics.cardInset, 10)
        XCTAssertEqual(DockMetrics.badge, 40)
        XCTAssertEqual(DockMetrics.badgeCompact, 34)
        XCTAssertEqual(DockMetrics.badgeColumn, 32)
        XCTAssertEqual(DockMetrics.badgeCorner(40), 10.4, accuracy: 0.0001)
        XCTAssertEqual(DockMetrics.rowSpacing, 10)
    }

    func testTypeScaleHasThreeLevels() {
        XCTAssertEqual(DockMetrics.figureSize, 24)
        XCTAssertEqual(DockMetrics.titleSize, 13)
        XCTAssertEqual(DockMetrics.captionSize, 11)
        XCTAssertGreaterThan(DockMetrics.figureSize, DockMetrics.titleSize)
        XCTAssertGreaterThan(DockMetrics.titleSize, DockMetrics.captionSize)
    }

    func testBadgesFitInsideTheSmallestCardHeight() {
        // 方底不能比卡片还高，否则会顶出卡片。
        XCTAssertLessThan(DockMetrics.badge, DockMetrics.cardCorner * 4)
        XCTAssertLessThanOrEqual(DockMetrics.badgeColumn, DockMetrics.badgeCompact)
        XCTAssertLessThanOrEqual(DockMetrics.badgeCompact, DockMetrics.badge)
    }

    // MARK: 状态

    func testStatePriority() {
        XCTAssertEqual(TileState.resolve(hovered: false), .normal)
        XCTAssertEqual(TileState.resolve(hovered: true), .hovered)
        XCTAssertEqual(TileState.resolve(hovered: true, targeted: true), .targeted)
        XCTAssertEqual(TileState.resolve(hovered: true, targeted: true, disabled: true), .disabled)
        XCTAssertEqual(TileState.resolve(hovered: true, targeted: true, disabled: true, locked: true), .locked)
    }

    func testOpacity() {
        XCTAssertEqual(TileState.normal.contentOpacity, 1)
        XCTAssertEqual(TileState.hovered.contentOpacity, 1)
        XCTAssertEqual(TileState.targeted.contentOpacity, 1)
        XCTAssertEqual(TileState.disabled.contentOpacity, DockMetrics.disabledOpacity)
        XCTAssertLessThan(TileState.disabled.contentOpacity, TileState.locked.contentOpacity)
        XCTAssertLessThan(TileState.locked.contentOpacity, 1)
    }

    func testHoverIsSubtle() {
        // 悬停只是轻微提亮，放大不超过 2%。
        XCTAssertLessThanOrEqual(TileState.hovered.scale(reduceMotion: false), 1.02)
        XCTAssertGreaterThan(TileState.hovered.scale(reduceMotion: false), 1)
        XCTAssertGreaterThan(TileState.hovered.hoverLift(dark: true), 0)
        XCTAssertGreaterThan(TileState.hovered.hoverLift(dark: false), 0)
        XCTAssertEqual(TileState.normal.hoverLift(dark: true), 0)
        XCTAssertEqual(TileState.targeted.scale(reduceMotion: false), 1)
    }

    func testReduceMotionDropsScaling() {
        XCTAssertEqual(TileState.hovered.scale(reduceMotion: true), 1)
        XCTAssertEqual(TileState.targeted.badgeScale(reduceMotion: true), 1)
        XCTAssertGreaterThan(TileState.targeted.badgeScale(reduceMotion: false), 1)
        XCTAssertEqual(TileState.hovered.badgeScale(reduceMotion: false), 1)
        // 提亮照旧：减少动态效果不等于没有反馈。
        XCTAssertGreaterThan(TileState.hovered.hoverLift(dark: true), 0)
        XCTAssertLessThan(TileState.transitionDuration(reduceMotion: true),
                          TileState.transitionDuration(reduceMotion: false))
    }

    func testDropOutlineOnlyWhenTargeted() {
        XCTAssertTrue(TileState.targeted.showsDropOutline)
        for state in [TileState.normal, .hovered, .disabled, .locked] {
            XCTAssertFalse(state.showsDropOutline)
        }
        XCTAssertEqual(DockMetrics.dropDash.count, 2)
        XCTAssertNotEqual(DockMetrics.dropBlueDark, DockMetrics.dropBlueLight)
    }

    func testAirDropStatesMapOntoSharedStates() {
        // 隔空投送的拖入态就是共用的拖入态，灰掉就是共用的禁用。
        let targeted = AirDropDrop.state(available: true, dragging: true, files: 2)
        XCTAssertEqual(TileState.resolve(hovered: true, targeted: targeted.highlighted,
                                         disabled: targeted.disabled), .targeted)
        let unavailable = AirDropDrop.state(available: false, dragging: true, files: 2)
        XCTAssertEqual(TileState.resolve(hovered: true, targeted: unavailable.highlighted,
                                         disabled: unavailable.disabled), .disabled)
    }

    // MARK: 缺权限

    func testPermissionPrompt() {
        XCTAssertEqual(TilePermission.prompt("日历"), "需要日历权限 · 去开启")
        XCTAssertEqual(TilePermission.prompt("提醒事项"), "需要提醒事项权限 · 去开启")
        XCTAssertEqual(TilePermission.prompt("完全磁盘访问权限"), "需要完全磁盘访问权限 · 去开启")
        XCTAssertEqual(TilePermission.prompt("自动化（邮件）"), "需要自动化权限（邮件） · 去开启")
        XCTAssertEqual(TilePermission.prompt("日历", compact: true), "需要权限")
    }

    func testEveryKnownPermissionReadsWell() {
        for (kind, name) in WidgetSearch.permissions {
            XCTAssertEqual(TilePermission.name(for: kind), name)
            let text = TilePermission.prompt(name)
            XCTAssertTrue(text.hasPrefix("需要"), text)
            XCTAssertTrue(text.hasSuffix(" · 去开启"), text)
            XCTAssertFalse(text.contains("权限权限"), text)
            XCTAssertEqual(text.components(separatedBy: "权限").count - 1, 1, text)
            XCTAssertFalse(TilePermission.accessibilityLabel(name).isEmpty)
        }
        XCTAssertNil(TilePermission.name(for: "clock"))
    }

    func testPermissionTilesUseTheSharedNames() {
        XCTAssertEqual(TilePermission.name(for: "calendar"), "日历")
        XCTAssertEqual(TilePermission.name(for: "week"), "日历")
        XCTAssertEqual(TilePermission.name(for: "reminders"), "提醒事项")
        XCTAssertEqual(TilePermission.name(for: "trash"), "完全磁盘访问权限")
        XCTAssertNotNil(TilePermission.name(for: "mail"))
    }

    // MARK: 空状态的小熊猫

    func testEmptyStatesUseRedPandaArtOnly() {
        for empty in PandaEmpty.allCases {
            XCTAssertTrue(empty.imageName.hasPrefix("pet-panda-"), empty.imageName)
            XCTAssertTrue(PandaEmpty.allowedImages.contains(empty.imageName), empty.imageName)
            XCTAssertFalse(empty.line().isEmpty)
            XCTAssertFalse(empty.line(compact: true).isEmpty)
            XCTAssertLessThanOrEqual(empty.line(compact: true).count, 3, "竖排货架放不下")
            XCTAssertLessThanOrEqual(empty.line().count, 10, "卡片上一行放得下")
        }
    }

    func testPandaArtExistsInResources() throws {
        // 素材就是 Resources/Pet 里现成的小熊猫，不新增、不用大熊猫。
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        for name in PandaEmpty.allowedImages {
            let url = root.appendingPathComponent("Resources/Pet/\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), name)
        }
    }

    func testNewEmptyStatesHaveDistinctCaptionsAndExistingArtwork() {
        let states: [PandaEmpty] = [.habit, .anniversary, .alarm, .radio, .podcast,
                                   .bookmarks, .screenshots, .photos, .basket]
        XCTAssertEqual(Set(states.map { $0.line() }).count, states.count)
        // 九格的（图，镜像）组合各不相同。
        let looks = Set(states.map { "\($0.imageName)|\($0.mirrored)" })
        XCTAssertEqual(looks.count, states.count)
        XCTAssertEqual(PandaEmpty.habit.imageName, "pet-panda-cheer")
        XCTAssertEqual(PandaEmpty.podcast.imageName, "pet-panda-hungry")
        XCTAssertEqual(PandaEmpty.basket.imageName, "pet-panda-eat")
        XCTAssertTrue(PandaEmpty.radio.mirrored)
        XCTAssertFalse(PandaEmpty.bookmarks.mirrored)
    }

    func testThemedEmptyStatesHaveColorPropAndHint() {
        let states: [PandaEmpty] = [.habit, .anniversary, .alarm, .radio, .podcast,
                                   .bookmarks, .screenshots, .photos, .basket]
        for state in states {
            XCTAssertNotNil(state.theme, state.rawValue)
            XCTAssertEqual(state.theme?.hex, state.themeHex, state.rawValue)
            XCTAssertFalse(state.propSymbol?.isEmpty ?? true, state.rawValue)
            let hint = state.hint ?? ""
            XCTAssertFalse(hint.isEmpty, state.rawValue)
            XCTAssertFalse(hint.contains("\u{2014}"))
        }
        XCTAssertEqual(Set(states.compactMap(\.hint)).count, states.count)
        XCTAssertEqual(PandaEmpty.photos.themeHex, "#FFD60A")
        XCTAssertEqual(PandaEmpty.alarm.propSymbol, "bell.fill")
        // 原有几格保持现状。
        for state in [PandaEmpty.todo, .todoDone, .clipboard, .downloads, .fileShelf] {
            XCTAssertNil(state.theme)
            XCTAssertNil(state.propSymbol)
            XCTAssertNil(state.hint)
            XCTAssertFalse(state.mirrored)
        }
        XCTAssertEqual(PandaEmpty.todo.imageName, "pet-panda-idle")
        XCTAssertEqual(PandaEmpty.clipboard.imageName, "pet-panda-rest")
    }

    func testOnlyBrightThemesUseDarkButtonLabel() {
        let dark = Set(PandaEmpty.allCases.filter(\.usesDarkLabel))
        XCTAssertEqual(dark, [.photos, .screenshots])
    }

    func testBreathStaysBetweenOneAndPeak() {
        XCTAssertEqual(PandaEmpty.breath(at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(PandaEmpty.breath(at: PandaEmpty.breathPeriod / 2), PandaEmpty.breathScale, accuracy: 1e-9)
        XCTAssertEqual(PandaEmpty.breath(at: PandaEmpty.breathPeriod), 1, accuracy: 1e-9)
        for i in 0..<60 {
            let s = PandaEmpty.breath(at: Double(i) * 0.1)
            XCTAssertGreaterThanOrEqual(s, 1 - 1e-9)
            XCTAssertLessThanOrEqual(s, PandaEmpty.breathScale + 1e-9)
        }
        XCTAssertEqual(PandaEmpty.breath(at: .nan), 1)
    }

    func testTodoEmptyAndDoneAreDifferent() {
        XCTAssertNotEqual(PandaEmpty.todo.line(), PandaEmpty.todoDone.line())
        XCTAssertNotEqual(PandaEmpty.todo.imageName, PandaEmpty.todoDone.imageName)
    }
}
