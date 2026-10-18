import Foundation

/// 喝水和电子宠物分工：喝水看“今天喝了多少”，杯子和水位是主角；电子宠物看
/// “它过得怎么样”，角色是主角，四个需求一眼看完。两张卡片不再长得一样。
///
/// 两种小组件的六只角色都不再作为样式列在添加小组件面板里：喝水只列
/// “角色”“圆环”“液态”三张，电子宠物只列一张，角色在面板或 设置 ▸ 小组件
/// 里选（键 `character`，Pro 角色照旧是 Pro，见 `ProFeatures`）。
///
/// 原来的六张角色卡片本来就存成 `layout` = character 加 `character` = 角色
/// （电子宠物只存 `character`），所以已经放好的卡片读取时不用改写：读出来
/// 就是“角色”样式加原来的角色选项，样子和 Pro 判定都不变。没存 `layout`
/// 的老卡片照旧由目录默认值补成角色样式。
public enum WaterPetCards {

    /// 喝水的角色样式存在 `layout` 里的值。
    public static let characterLayout = "character"

    // MARK: 喝水：八个小杯

    /// 卡片上一排几个小杯。
    public static let cupSlots = 8

    /// 满了几个小杯：按进度四舍五入，没达标时最多 7 个，达标才 8 个全满，
    /// 免得看起来已经喝够了其实还差一口。
    public static func filledCups(total: Int, goal: Int, slots: Int = cupSlots) -> Int {
        guard slots > 0, goal > 0, total > 0 else { return 0 }
        if total >= goal { return slots }
        let share = WaterIntake.progress(total: total, goal: goal)
        return min(slots - 1, max(0, Int((share * Double(slots)).rounded())))
    }

    // MARK: 电子宠物：四个需求小格

    /// 点一格做什么：饱食是喂、心情是玩、精力是睡（睡着时叫醒）、清洁是洗。
    public static func action(for need: PetNeed) -> PetAction {
        switch need {
        case .food: .feed
        case .mood: .play
        case .energy: .sleep
        case .clean: .wash
        }
    }

    /// 现在最要紧的那一格：低于 `VirtualPet.lowLine` 的里面最低的一项，
    /// 都还好时为 nil。卡片上把它标红。
    public static func mostNeeded(_ state: PetState) -> PetNeed? {
        let low = PetNeed.allCases.filter { state[$0] < VirtualPet.lowLine }
        return low.min { state[$0] < state[$1] }
    }

    /// 一格的名字、数值和点一下做什么，给悬停提示和旁白用。
    public static func cellHelp(_ need: PetNeed, state: PetState) -> String {
        let action = action(for: need)
        let title = action == .sleep && state.isSleeping ? tr("叫醒") : action.title
        return tr("\(need.title) \(Int(state[need].rounded()))，点一下\(title)")
    }

    /// 宠物卡片的宽度（和原来一样）。
    public static let petTileWidth: Double = 196
    /// 竖排：角色、一行字、四个小格两两一排。
    public static let petColumnHeight: Double = 118
}
