<div align="center">

<img src="docs/images/icon.png" alt="Docket 图标" width="128">

# Docket 中文版

### 免费、开源的 macOS 程序坞扩展栏，简体中文界面。

在系统程序坞旁边放一条扩展栏，摆上实时小组件、应用分组和文件夹，
也可以直接用它替代程序坞。

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](#从源码构建)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](project.yml)
[![许可证: MIT](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<br>

<img src="docs/images/zh/shelf-showcase.png" alt="Docket 中文版扩展栏：时钟、世界时钟、系统活动、便签，然后是一排应用图标" width="100%">

<sub>所有截图都是应用自己的界面，由仓库中的截图工具在 macOS 上实际拍摄（见文末“截图是怎么来的”）。</sub>

</div>

---

## 这是什么

本仓库是 [Docket](https://github.com/nparashar150/dockset) 的**非官方简体中文本地化分支**。
上游 Docket 是一个 MIT 许可的开源 macOS 应用，本分支做了这些改动：

- 把所有用户可见的界面文字翻译成简体中文：菜单栏菜单、设置面板、小组件库、
  小组件卡片与详情面板、提示文字、弹窗、权限说明、空状态等；
- 调整构建配置，让任何人 clone 后都能直接构建（ad-hoc 签名、独立的 bundle ID
  `com.docket-zh.app`，可与上游英文版同时安装）；
- 新增二十多种小组件（相册、最近截图、下载、文件暂存、剪贴板、取色器、单位换算、
  截图工具、表情符号、搜索、音量、快速开关；v0.4.0 又加入壁纸切换、应用切换器、书签、录音、
  邮件、计算器、汇率换算、GitHub；v0.4.1 加入麦克风、圆环仪表、久坐提醒），时钟样式与天气扩展，
  扩展栏外观预设、单个小组件的条件显示与背景开关、放不下时自动缩小，
  以及三种切换布局的方式，见下方“新增功能：更快地切换布局”。

与上游一致的基础能力：

- **跟随真实的程序坞**：大小、所在边缘、放大效果和自动隐藏都实时读取系统设置。
- **应用分组**：把一个图标拖到另一个图标上并停留，即可像 iOS 一样建立分组。
- **布局**：可保存多套布局，并可写回系统程序坞（只改动 `persistent-apps`，带校验和回滚）。
- **点按小组件会打开详情面板**，显示更多内容和操作。

---

## 小组件一览

四十多种小组件，按用途分成五类，最后两节集中展示 v0.4.0 与 v0.4.1 新增的内容。每一类都可以自由组合，放在同一条扩展栏上。

<sub>下面每类第一张图是放着该类小组件的真实扩展栏，小组件显示的是小组件库自带的示例数据
（日历、提醒事项、音乐等需要授权的内容不会读取拍摄机器上的真实数据）；详情面板截图中
标注“示例数据”的同理，其余为拍摄时的实时读数。</sub>

### 应用、文件和快速访问

把常用应用、刚下载的文件和要来回拖动的文件都放在手边，不用再打开访达翻找。

**包含：** 应用图标与分组、应用切换器、书签、下载、文件暂存、搜索（网页搜索或查找文件）、隔空投送、快捷指令

- **应用切换器**：正在运行的应用图标（与 ⌘Tab 的范围相同），当前应用排在最前，点按即切换；
  放不下时最后一格显示“+n”，详情中列出全部应用，可隐藏或退出。
- **书签**：多个常用网址，点按用默认浏览器打开。在 **设置 > 小组件** 中编辑，每项写成
  “标题 网址”（例如 `必应 cn.bing.com`），用逗号分隔。不抓取网站图标，用标题首字代替。

<img src="docs/images/zh/shelf-files.png" alt="扩展栏：下载、最近截图、文件暂存、搜索、隔空投送和应用图标" width="100%">

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/zh/downloads.png" alt="下载详情面板：最近下载的五个文件" width="100%">
      <p align="center"><sub>下载：最近下载的文件，点按打开，拖出即用</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/zh/file-shelf.png" alt="文件暂存详情面板：暂存的三个文件" width="100%">
      <p align="center"><sub>文件暂存：先把文件拖进来，稍后再拖出去</sub></p>
    </td>
  </tr>
</table>

### 生产力和日常专注

把今天的日程、待办和专注节奏放在眼前，一眼就知道接下来要做什么。

**包含：** 日历、提醒事项、邮件、专注计时（番茄钟）、喝水提醒、久坐提醒、便签、时钟、世界时钟、秒表、倒计时、闹钟、时间进度

- **时钟样式**：标准、模拟表盘（带秒针）、翻页、像素，在 **设置 > 小组件** 的“样式”中选择。
- **邮件**：“邮件”App 收件箱的未读数量，点按打开“邮件”。通过 AppleScript 读取，只在“邮件”已运行时读取，
  首次使用会请求“自动化”权限；被拒绝时小组件会提示，并可一键打开对应的设置。

<img src="docs/images/zh/shelf-productivity.png" alt="扩展栏：日历、提醒事项、专注计时、喝水提醒和便签" width="100%">

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/zh/focus-timer.png" alt="专注计时详情面板：正在进行的专注时段" width="100%">
      <p align="center"><sub>专注计时：专注、休息、长休息交替进行</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/zh/time-progress.png" alt="时间进度详情面板：今天、本月和今年已过去的比例" width="100%">
      <p align="center"><sub>时间进度：今天、本月、今年过去了多少</sub></p>
    </td>
  </tr>
</table>

### Mac 控制和系统工具

不用打开控制中心或活动监视器，常用的开关和系统状态就在扩展栏上。

**包含：** 正在播放（音乐）、音量、快速开关（暗色模式、锁屏、屏幕保护程序、清空废纸篓）、壁纸切换、录音、麦克风、系统活动、网络活动、电池、圆环仪表

- **壁纸切换**：选择一个文件夹（默认“图片”），上一张 / 下一张 / 随机切换桌面壁纸，卡片显示当前壁纸；
  详情中点按任意图片即设为壁纸。可选择应用到所有显示器或仅主显示器，只改变当前空间的壁纸。
- **录音**：一键开始 / 停止，显示录音时长，保存为 .m4a（默认“下载”文件夹，可在详情中更换），
  详情中列出最近的录音，可播放、拖出或删除。首次使用会请求麦克风权限。

<img src="docs/images/zh/shelf-system.png" alt="扩展栏：正在播放、音量、快速开关、系统活动和电池" width="100%">

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/zh/system-activity.png" alt="系统活动详情面板：CPU、内存和磁盘的最近一分钟曲线" width="100%">
      <p align="center"><sub>系统活动：CPU、内存、磁盘的最近一分钟</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/zh/battery.png" alt="电池详情面板：Mac 和配件的电量（示例数据）" width="100%">
      <p align="center"><sub>电池：Mac 和配件的电量（示例数据）</sub></p>
    </td>
  </tr>
</table>

### 实用小工具

一些随手就要用的小工具：找回刚才拷贝的内容、换算单位、插入表情、看看天气。

**包含：** 剪贴板、单位换算、计算器、汇率换算、表情符号、天气、GitHub、股票、自选股

- **计算器**：离线计算，详情中有键盘也可直接输入，支持 + − × ÷、乘方 ^、百分号和括号，
  中文输入法的全角符号也能识别。输入有误时只提示，不会出错退出。
- **汇率换算**：默认美元换人民币，可选二十种常用币种。汇率来自
  [ExchangeRate-API](https://www.exchangerate-api.com)（open.er-api.com，免费、无需密钥，每日更新），
  保存在本地，离线时使用最近一次的汇率并标明日期。
- **天气**：新增风向与风力等级、湿度，以及按城市坐标在本地计算的日出日落；新样式“风与日出日落”。
- **GitHub**：公开仓库的星标、议题、拉取请求等，默认显示本仓库。在详情中可填入个人访问令牌（可选），
  令牌只保存在钥匙串中，用于提高请求上限并显示未读通知数。

<img src="docs/images/zh/shelf-tools.png" alt="扩展栏：剪贴板、单位换算、表情符号、天气和世界时钟" width="100%">

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/zh/clipboard.png" alt="剪贴板详情面板：最近拷贝的四条内容" width="100%">
      <p align="center"><sub>剪贴板：最近拷贝的内容，点按即可重新拷贝</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/zh/converter.png" alt="单位换算详情面板：1 英里换算成各种长度单位" width="100%">
      <p align="center"><sub>单位换算：长度、重量、温度</sub></p>
    </td>
  </tr>
</table>

### 图片与截图

看看喜欢的图片，随时截图，最近的截图和取到的颜色都能直接拖走或拷贝。

**包含：** 相册、最近截图、截图工具、取色器

<img src="docs/images/zh/shelf-images.png" alt="扩展栏：相册、最近截图、截图工具、取色器和应用图标" width="100%">

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/zh/photos.png" alt="相册详情面板：文件夹中的六张图片" width="100%">
      <p align="center"><sub>相册：轮播一个文件夹里的图片</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/zh/screenshots.png" alt="最近截图详情面板：最新一张截图和更早的几张" width="100%">
      <p align="center"><sub>最近截图：拷贝、显示、删除，或直接拖进聊天窗口</sub></p>
    </td>
  </tr>
</table>

### v0.4.0 新增

效率工具、桌面与应用，以及新的外观预设。

<img src="docs/images/zh/shelf-utilities.png" alt="扩展栏：计算器、汇率换算、书签、GitHub 和邮件" width="100%">

<img src="docs/images/zh/shelf-desktop.png" alt="扩展栏：翻页时钟、壁纸切换、应用切换器、录音和像素时钟" width="100%">

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/zh/calculator.png" alt="计算器详情面板：算式、结果和键盘" width="100%">
      <p align="center"><sub>计算器：键盘与直接输入</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/zh/currency.png" alt="汇率换算详情面板：美元换人民币及其他常用币种" width="100%">
      <p align="center"><sub>汇率换算：每日汇率，离线可用</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/images/zh/github.png" alt="GitHub 详情面板：本仓库的星标、复刻、议题和拉取请求" width="100%">
      <p align="center"><sub>GitHub：公开仓库的数据，令牌可选</sub></p>
    </td>
    <td width="50%" valign="top">
      <img src="docs/images/zh/bookmarks.png" alt="书签详情面板：四个常用网址" width="100%">
      <p align="center"><sub>书签：点按用默认浏览器打开</sub></p>
    </td>
  </tr>
</table>

**外观预设**（**设置 > 扩展栏 > 外观**）：玻璃、清透玻璃、浅色玻璃、深色玻璃、磨砂、白色、黑色、透明
（透明即不绘制底板，每个小组件保留自己的卡片）。另有“小组件颜色：原色 / 单色”和“降低透明度”开关；
macOS 开启“降低透明度”时会自动使用不透明底板。下图是深色玻璃加单色，配模拟表盘时钟和“风与日出日落”天气：

<img src="docs/images/zh/shelf-styles.png" alt="深色玻璃、单色模式的扩展栏：模拟表盘时钟、天气（风与日出日落）、世界时钟和计算器" width="100%">

### v0.4.1 新增

三种小组件，以及每个小组件自己的显示设置。

<img src="docs/images/zh/shelf-v041.png" alt="扩展栏：圆环仪表（存储空间与电池）、麦克风、久坐提醒、隐藏了背景和边框的翻页时钟、电池圆环" width="100%">

- **麦克风**：通过 Core Audio 读取默认输入设备是否正被某个应用使用，显示设备名称；设备支持时可一键输入静音。
  只读取状态，不录音，不需要麦克风权限。
- **圆环仪表**：存储空间（启动磁盘的可用 / 总容量，与访达的算法一致）和电池的圆环，可在设置中只保留其中一个。
  CPU 温度没有公开接口，因此不提供。
- **久坐提醒**：与喝水提醒相同的形式，可设提醒间隔和提醒时段（默认 09:00 到 18:00），到时发送系统通知，
  并记录今天起身了几次。首次提醒时会请求通知权限。
- **条件显示**：右键小组件选择“显示条件”：始终显示、满足条件时显示或隐藏。目前支持条件的有：
  正在播放（仅播放时）、电池（仅使用电池时，可加电量阈值）、麦克风（仅使用中）、邮件（仅有未读时）。
  被隐藏的小组件列在扩展栏右键菜单和菜单栏的“已隐藏的小组件”中，点按即可恢复。
- **隐藏背景和边框**：右键小组件选择“隐藏背景和边框”，或在 **设置 > 小组件** 的“显示”中打开，
  只去掉这个小组件自己的卡片，便签纸色、封面等内容保留。
- **放不下时自动缩小**：**设置 > 扩展栏 > 行为** 中“放不下时”可选“横向滚动”（原有行为）或“自动缩小”。
  自动缩小最多缩到所选大小的一半，仍放不下时再滚动。

开启“自动缩小”后，比屏幕还长的一排小组件整体缩小，放在同一条扩展栏上：

<img src="docs/images/zh/shelf-shrink.png" alt="开启自动缩小后，十五个小组件缩小后放在同一条扩展栏上" width="100%">

<p align="center">
  <img src="docs/images/zh/posture.png" alt="久坐提醒详情面板：下次起身时间、今日起身次数、提醒时段和间隔（示例数据）" width="50%"><br>
  <sub>久坐提醒：下次起身时间与今日次数（示例数据）</sub>
</p>

以上 v0.4.1 功能已通过自动化构建和单元测试，但尚未在真机上逐项验证，见
[路线图](ROADMAP-zh.md)中的“需要在真机上验证”。

---

## 新增功能：更快地切换布局

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
- “录音”需要麦克风权限，“邮件”需要对“邮件”的“自动化”权限；ad-hoc 签名的版本更新后可能需要重新授权。
- “壁纸切换”通过系统接口只设置当前空间的壁纸，其他空间不受影响。
- “久坐提醒”的系统通知需要在首次提醒时允许；ad-hoc 签名的版本能否正常收到通知需要在真机上确认。
- CPU 温度没有公开 API，圆环仪表不提供。
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

## 截图是怎么来的

README 里的图片都由仓库自带的截图工具拍摄：`Tools/Shots` 把应用真实的扩展栏和详情面板
放进屏幕上的真实窗口，`scripts/capture-shots.sh` 再用 `screencapture` 拍下来。
不是设计稿，也没有手工修改过数字。每张图都会标明是实时读数（live）、
小组件库的示例数据（sample）还是空状态（empty）。

- 相册、文件暂存展示的图片和文件由截图工具当场生成，不会读取你自己的照片或文件；
- 下载、最近截图、剪贴板只有在设置了 `SHOTS_DISPOSABLE=1` 的一次性机器上
  （例如 GitHub Actions）才会写入示例文件并以实时状态拍摄，在你自己的 Mac 上会改用示例数据，
  不会往你的“下载”、桌面或剪贴板里写任何东西。

**在自己的 Mac 上重新拍摄：**

1. 安装 Xcode 和 XcodeGen（`brew install xcodegen`），在仓库目录运行 `xcodegen generate`。
2. 在 **系统设置 > 隐私与安全性 > 录屏与系统录音** 中允许你使用的终端应用（例如“终端”），
   然后重新打开终端。
3. 运行 `SHOTS_OUT=docs/images/zh scripts/capture-shots.sh`。拍摄需要几分钟，
   期间屏幕会被一张背景盖住，请不要操作电脑，等它打印出汇总。
4. 只想重拍其中几张时，可以加上 `SHOTS_ONLY=photos,shelf-files`。

也可以在本仓库的 **Actions > Screenshots** 中手动运行工作流，在 GitHub 的 macOS
虚拟机上拍摄，拍好的图片会作为构件（artifact）上传，下载后检查再提交。

---

## 致谢

- **[Docket](https://github.com/nparashar150/dockset)**：本分支的上游项目，MIT 许可，
  版权归其原作者所有。扩展栏、小组件框架和大部分小组件都来自上游；本分支负责中文本地化，
  并新增了上文列出的小组件和布局切换功能。
- **[Dockset](https://dockset.app)**：Docket 的灵感来源，是由独立开发者打造的**原创付费应用**。
  如果你喜欢这个想法，想要打磨更完善、有售后支持的正式产品，请购买 Dockset，支持独立开发者。
- 天气数据来自 **[MET Norway](https://api.met.no/)**，依 CC BY 4.0 许可使用。
- 工程由 **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** 生成。

本分支与 Dockset、CoolDock、Docket 上游及其作者均**无任何关联**，也未获得其认可或赞助。
README 的分类介绍方式参考了同类应用的常见写法，所有截图均为本应用自己的界面。
完整的署名与商标说明见 [NOTICE.md](NOTICE.md)。

## 许可证

[MIT](LICENSE)。第三方署名与商标说明见 [NOTICE.md](NOTICE.md)。
