import SwiftUI

/// 设置 ▸ 小组件 ▸ 卜卦：每日一签按星座或属相定签（免费），签筒和铜钱皮肤（Pro）。
///
/// 星座 / 属相三选一：不选（按日期加卡片定签，和原来一样）、星座 12 个、属相 12 个，
/// 存在卡片配置的 `sign`。皮肤存在 `tubeSkin`、`coinSkin`；没解锁时选 Pro 款弹付费墙，
/// 已经选好的照旧存着，面板和桌面卡片画默认款（见 Divination.tubeSkin / coinSkin）。
struct DivinationSettingsSection: View {
    var instance: WidgetInstance
    var write: ((inout WidgetConfig) -> Void) -> Void

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool { licenseUnlocked || supporter }
    private var config: WidgetConfig { instance.config }
    private var sign: DivinationSign? { Divination.sign(config) }
    private var kind: DivinationSign.Kind { sign?.kind ?? .none }

    var body: some View {
        Section(tr("每日一签")) {
            Picker(tr("按星座或属相"), selection: Binding(
                get: { kind },
                set: { newKind in
                    guard newKind != kind else { return }
                    setSign(newKind.signs.first)
                })) {
                    ForEach(DivinationSign.Kind.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
            if kind != .none {
                Picker(kind.title, selection: Binding(
                    get: { sign ?? kind.signs[0] },
                    set: { setSign($0) })) {
                        ForEach(kind.signs, id: \.self) { item in
                            Text(verbatim: item.name).tag(item)
                        }
                    }
            }
            Text(tr("选了以后，同一天同一个星座或属相抽到的是同一支签，签上多一个小徽章和今日幸运色、幸运数字。不选时每张卡片各抽各的。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            skinPicker(tr("签筒"), stored: Divination.storedTubeSkin(config), all: TubeSkin.allCases,
                       title: \.title, isPro: \.isPro, key: Divination.tubeSkinKey)
            skinPicker(tr("铜钱"), stored: Divination.storedCoinSkin(config), all: CoinSkin.allCases,
                       title: \.title, isPro: \.isPro, key: Divination.coinSkinKey)
        }
    }

    private func setSign(_ sign: DivinationSign?) {
        let salt = instance.id.uuidString
        write { Divination.setSign(sign, in: &$0, now: Date(), cardSalt: salt) }
    }

    /// 菜单项里放不下胶囊，Pro 款在名字后标「（Pro 专属）」；选中的是 Pro 款时标题旁显示 Pro 标识。
    private func skinPicker<Skin: RawRepresentable & Hashable>(
        _ label: String, stored: Skin, all: [Skin], title: KeyPath<Skin, String>, isPro: KeyPath<Skin, Bool>,
        key: String
    ) -> some View where Skin.RawValue == String {
        Picker(selection: Binding(
            get: { stored },
            set: { skin in
                guard ProLicenseGate.canChooseDivinationSkin(isPro: skin[keyPath: isPro], unlocked: unlocked) else {
                    PaywallWindow.shared.show()
                    return
                }
                write { $0.set(key, .string(skin.rawValue)) }
            })) {
                ForEach(all, id: \.self) { skin in
                    Text(ProFeatures.menuTitle(skin[keyPath: title], isPro: skin[keyPath: isPro])).tag(skin)
                }
            } label: {
                ProLabel(title: label, isPro: stored[keyPath: isPro] || !unlocked)
            }
    }
}
