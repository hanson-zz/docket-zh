# 时间洞察 Pro · Chrome 与 Edge 真机验收

## 安装测试版

1. 在 macOS 26 安装本 PR 的 Debug 构建，或运行 `xcodegen generate`、`xcodebuild -scheme Docket -configuration Debug build`。启动 Dockling，在扩展栏布局中放置时间洞察，确认 Pro 已解锁并单独开启网站域名统计。
2. 在稳定版 Chrome 的 `chrome://extensions` 或稳定版 Edge 的 `edge://extensions` 打开开发者模式。加载仓库中的 `Extensions/TimeInsightsChromium` 作为解压缩扩展，抄下该浏览器显示的扩展 ID。
3. 在扩展详情保留所有网站的访问权限，并开启「允许在无痕模式下运行」或「允许 InPrivate」。这项权限只用于识别私密窗口，扩展检测到私密窗口后不会查询其标签页。
4. 从仓库根目录运行以下命令。分别填写安装路径和各浏览器的扩展 ID，完成后在浏览器扩展页重新加载扩展。

   ```sh
   bash Extensions/TimeInsightsChromium/install-host.sh chrome CHROME_EXTENSION_ID /Applications/Dockling.app
   bash Extensions/TimeInsightsChromium/install-host.sh edge EDGE_EXTENSION_ID /Applications/Dockling.app
   ```

每个浏览器的 Native Messaging 配置只授权上述扩展 ID。连接在当前 macOS 用户的私有 Unix 套接字内进行，无需 Apple Events、辅助功能权限或网络服务。扩展检查焦点、无痕标记、网址和安全表单特征，仅传域名。无法检查的跨源子框架会使整页退回应用级统计。对不断变化的页面，敏感检测使用网址和 DOM 启发式规则。测试分发使用解压缩安装，商店分发是后续工作。

## 验收步骤

| 场景 | 操作与预期 |
| --- | --- |
| 双浏览器和多标签页 | 使用正常窗口访问 `example.com` 和 `example.org`，每页停留至少 10 秒并间歇操作。切换活动标签页、切换同浏览器两个窗口、切换 Chrome 与 Edge。只有前台窗口的活动标签页增加域名用时。后台标签页刷新或跳转时，原前台域名保持不变。 |
| 前台与焦点 | 切到 Finder，分别在全屏、其它空间和多个浏览器配置文件重复。网站榜单在离开浏览器后停止增长。 |
| 锁屏、睡眠和 AFK | 将空闲门槛调到最短值。在活跃网站上锁屏、睡眠或静置超过门槛。AFK 场景在静置期间触发自动跳转，检查最后一次输入后的站点切片被归为无操作停留。解锁并恢复输入后，从新样本继续。 |
| 无痕与敏感页面 | 从普通页切到无痕或 InPrivate 窗口，打开测试域名、登录路径、含密码框或支付字段的测试页。再切回普通页。私密和敏感期间只增加应用总时长。用测试页面和虚构输入。 |
| 断线与撤权 | 禁用扩展，等待约 3 秒，设置显示断开。重新启用后连接恢复。撤销网站访问或无痕识别权限，设置显示缺少权限。两种情况均退回应用级统计。未安装新扩展时显示未连接。 |
| 同意与权限 | 关闭网站授权、暂停、排除浏览器或移除组件，确认网站时长不再增长。关闭 Pro 后检查基础记录、暂停、排除、清空与基础 CSV；CSV 不含域名或标题。 |
| 日周月与 SQLite | 对比完整统计中的当日、当周、当月榜单。网站用时包含在浏览器活跃时间中。按会话检查域名字段、无重叠、无完整网址、路径、查询或标题，并验证旧记录仍可读取。 |
| 重启恢复 | 采集时退出 Chrome 或 Edge 并重新打开，再强制退出 Dockling。重启后检查历史时段没有重复，Dockling 未运行期间没有补记。 |

验收截图在真机打开「时间洞察 › 完整统计」，截取有真实域名和时长的榜单，再截取「设置 › 时间洞察」的连接与撤权状态。截图使用公开测试站点，避免暴露个人浏览历史。Safari Web Extension 单独交付。
