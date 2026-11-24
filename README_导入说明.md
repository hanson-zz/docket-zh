# 码头 Dockling · 通用应用图标追加包

适用项目：https://github.com/hanson-zz/docket-zh

本包内有 12 款用户上传的图标，文件名为 `Resources/AppIcons/AppIcon-*.png`。
每款含 1024、512、256 三档，共 36 张。图片均为 RGBA 透明 PNG，
1024 图四边各保留至少 100px 完全透明边距，中心圆角图标本体为 824×824。

## 安装方式

1. 解压 ZIP。
2. 先备份或提交仓库未保存的改动（建议在独立分支安装）。
3. 在 Mac 终端执行：`python3 tools/install_app_icons.py /你的/docket-zh/仓库/路径`
   （这里的 `tools` 是本压缩包中的 tools 目录，不是仓库中的 tools）。
4. 对比 `git diff -- Sources/Core/AppIconChoice.swift`，检查新增条目与命名。
5. `xcodegen generate` 后编译测试（依照项目自己的构建流程）。
6. 在 Pro 解锁状态下进入 **设置 → 通用 → 应用图标** 逐一切换图标，检查
   Dock、应用切换器、“关于”和 Finder 的图标更换。
7. 检查 64px 缩略图、深浅色桌面、退出重启后的选择持久性与 Pro 状态变化。

## 实现说明

- 原项目 `AppIconCatalog.hidden` 已有 8 款 Pro 隐藏小熊猫，且未解锁时整组不可见。
- 本脚本保留这一逻辑，把新 12 款追加进 `hidden`，不修改 `all` 中已有的免费款。
- 图片存在 `Resources/AppIcons`，现有 `project.yml` 已将该目录打包，原 AppIcon 不替换。
- `AppIconSwitcher` 的图片载入命名规则是原名、`-512`、`-256`；本包按现有规则命名。
- 安装脚本不修改任何其他资源、播放逻辑、授权存储或默认图标。
- 新上传的前 8 张实际不带透明角（原像素是实底），已经统一遮罩裁切并置入透明边距；
  后 4 张保留原有透明通道后重新统一尺寸。
- 这些素材中的部分造型高度接近知名超级英雄。接入用于本地测试没有问题，
  但公开销售、推广和分发前应做版权/商标/角色形象相似性审查，必要时替换为原创设计。
- 图标文件较大，正式发版前建议确认二进制大小和构建包增长。

## 本次图标名

- 紫影行者 → `AppIcon-VioletShadow` → `heroVioletShadow`
- 星盾守卫 → `AppIcon-ShieldGuardian` → `heroShieldGuardian`
- 星环法师 → `AppIcon-AstralMage` → `heroAstralMage`
- 雷霆勇士 → `AppIcon-StormWielder` → `heroStormWielder`
- 飞跃小熊 → `AppIcon-SkylineAcrobat` → `heroSkylineAcrobat`
- 晴空守护 → `AppIcon-SkyGuardian` → `heroSkyGuardian`
- 赤甲小熊 → `AppIcon-CrimsonArmor` → `heroCrimsonArmor`
- 绿能巨熊 → `AppIcon-EmeraldGiant` → `heroEmeraldGiant`
- 暗夜披风 → `AppIcon-NightSentinel` → `heroNightSentinel`
- 疾风跑者 → `AppIcon-SpeedRunner` → `heroSpeedRunner`
- 金蓝爪卫 → `AppIcon-AmberClaws` → `heroAmberClaws`
- 红黑机灵 → `AppIcon-RedMischief` → `heroRedMischief`
