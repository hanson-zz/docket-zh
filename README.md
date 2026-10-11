<div align="center">

<img src="https://github.com/nparashar150/dockset/raw/main/docs/images/icon.png" alt="Docket 图标" width="128">

# Docket 中文版

### 免费、开源的 macOS 程序坞扩展栏，简体中文界面。

在系统程序坞旁边放一条扩展栏，摆上实时小组件、应用分组和文件夹，
也可以直接用它替代程序坞。

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](#从源码构建)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](project.yml)
[![许可证: MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<br>

<img src="https://github.com/nparashar150/dockset/raw/main/docs/images/shelf.png" alt="Docket 扩展栏运行在屏幕底部：系统活动、逐小时天气、便签，然后是一排应用图标" width="100%">

<sub>截图来自上游英文版，界面布局与中文版一致。</sub>

</div>

---

## 这是什么

本仓库是 [Docket](https://github.com/nparashar150/dockset) 的**非官方简体中文本地化分支**。
上游 Docket 是一个 MIT 许可的开源 macOS 应用，本分支做了这些改动：

- 把所有用户可见的界面文字翻译成简体中文：菜单栏菜单、设置面板、小组件库、
  小组件卡片与详情面板、提示文字、弹窗、权限说明、空状态等；
- 调整构建配置，让任何人 clone 后都能直接构建（ad-hoc 签名、独立的 bundle ID
  `com.docket-zh.app`，可与上游英文版同时安装）；
- 新增三种切换布局的方式，见下方“新增功能”。

其余功能与上游保持一致：

- **跟随真实的程序坞**：大小、所在边缘、放大效果和自动隐藏都实时读取系统设置。
- **二十种可用的小组件**：时钟、世界时钟、秒表、专注计时、时间进度、倒计时、闹钟、
  喝水提醒、便签、日历、提醒事项、电池、系统活动、网络活动、隔空投送、股票、自选股、
  天气、快捷指令、正在播放。点按小组件会打开详情面板。
- **应用分组**：把一个图标拖到另一个图标上并停留，即可像 iOS 一样建立分组。
- **布局**：可保存多套布局，并可写回系统程序坞（只改动 `persistent-apps`，带校验和回滚）。

### 新增功能

- **快捷键切换布局**：在 **设置 > 布局** 中，点按某个布局右侧的“录制快捷键”按钮，
  然后按下组合键（例如 `⌃⌥1`）即可为它设定全局快捷键；组合键须包含 ⌃、⌥ 或 ⌘ 之一，
  按 Esc 取消，按删除键清除。之后在任何应用中按下该组合键，都会切换到对应的布局
  （系统程序坞布局会同时写入程序坞）。快捷键不会自动分配，也不需要辅助功能权限。
  同一组合键只能属于一个布局，录给新布局时会从原布局上移除。
- **随专注模式自动切换**：打开 **系统设置 > 专注模式**，选择一个专注模式，在
  “专注模式过滤条件”中点按“添加过滤条件”，选择 Docket 并挑选一个布局。
  该专注模式开启时 Docket 会切换到这个布局，结束时恢复开启前的布局。
  Docket 未运行时，macOS 一般会在后台启动它来完成切换。
- **⌘ + 滚轮 / 双指轻扫切换**：指针位于扩展栏上时，按住 ⌘ 滚动滚轮，或在触控板上
  双指左右轻扫，即可在扩展栏布局之间循环切换，并短暂显示新布局的名称。
  一次手势只切换一步。扩展栏内容超出屏幕时，左右轻扫仍用于滚动扩展栏，
  不按 ⌘ 的普通滚动行为不变。可在 **设置 > 布局 > 切换布局** 中关闭。

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="https://github.com/nparashar150/dockset/raw/main/docs/images/shelf-showcase.png" alt="扩展栏近景" width="100%">
    </td>
    <td width="50%" valign="top">
      <img src="https://github.com/nparashar150/dockset/raw/main/docs/images/settings-shelf.png" alt="扩展栏设置面板" width="100%">
    </td>
  </tr>
</table>

---

## 安装

1. 从本仓库的 [Releases 页面](../../releases) 下载最新的 `.dmg` 或 `.zip`，
   把 `Docket.app` 移到“应用程序”文件夹。
2. **构建未签名、未经公证**，首次打开时 macOS 26 会提示无法验证该应用。处理方法：
   - 双击打开，出现拒绝提示后关闭它；
   - 打开 **系统设置 > 隐私与安全性**，在“安全性”部分点按 Docket 旁边的 **仍要打开**；
   - 验证身份后再次打开并确认。

   或者在终端中移除隔离属性：

   ```sh
   xattr -dr com.apple.quarantine /Applications/Docket.app
   ```

3. **首次运行请看菜单栏。** Docket 是辅助型应用：没有程序坞图标，也没有主窗口，
   设置、小组件库和布局切换都在菜单栏图标里。

### 已知限制

- ad-hoc 签名的辅助型应用收不到 macOS 的定位授权弹窗，天气小组件请在
  **设置 > 小组件** 中手动输入城市。
- “正在播放”需要在 **隐私与安全性 > 自动化** 中允许 Docket；读取浏览器标签页还需要在
  浏览器的“开发”菜单中开启“允许来自 Apple 事件的 JavaScript”。
- 天气数据来自 [MET Norway](https://api.met.no/)。城市名称通过 Apple 地图（MapKit）解析，
  一般可以直接输入中文城市名；如果识别不到，可改用英文名（如 `Beijing`）。

---

## 从源码构建

需要 macOS 26 和 Xcode。Xcode 工程由 `project.yml` 生成，不在仓库中：

```sh
brew install xcodegen
xcodegen generate
xcodebuild -scheme Docket -configuration Release build
```

运行测试：

```sh
xcodebuild -scheme DocketTests -configuration Debug test
```

`project.yml` 默认使用 ad-hoc 签名（`CODE_SIGN_IDENTITY: "-"`），不需要开发者证书。
如果希望系统能弹出定位授权，可以把 `CODE_SIGN_IDENTITY` 换成你自己的 Apple Development
证书，并加上 `DEVELOPMENT_TEAM`。

发布自己的构建前，请把 `Sources/Services/UpdateService.swift` 中的
`releasesRepository` 改成你的仓库路径，这样“检查更新”才会指向本分支的 Releases。

---

## 致谢

- **[Docket](https://github.com/nparashar150/dockset)**：本分支的上游项目，MIT 许可，
  版权归其原作者所有。所有功能和代码都来自上游，本分支只负责中文本地化。
- **[Dockset](https://dockset.app)**：Docket 的灵感来源，是由独立开发者打造的**原创付费应用**。
  如果你喜欢这个想法，想要打磨更完善、有售后支持的正式产品，请购买 Dockset，支持独立开发者。
- 天气数据来自 **[MET Norway](https://api.met.no/)**，依 CC BY 4.0 许可使用。
- 工程由 **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** 生成。

本分支与 Dockset、Docket 上游及其作者均**无任何关联**，也未获得其认可或赞助。
完整的署名与商标说明见 [NOTICE.md](NOTICE.md)。

## 许可证

[MIT](LICENSE)。第三方署名与商标说明见 [NOTICE.md](NOTICE.md)。
