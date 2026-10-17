import Foundation

/// 关于页里“开源致谢与许可”和“最终用户协议”两个窗口显示的文字。
///
/// 放在 Core 而不是从仓库文件读，是因为安装包里没有 LICENSE、NOTICE.md
/// 和 EULA.md 这些文件。和仓库文件的一致由 LicensingTests 检查：改了
/// LICENSE 或 EULA.md，测试会提醒这里也要跟着改。
public enum Licensing {
    /// 一条需要随安装包保留的版权和许可声明。
    public struct Credit: Identifiable, Hashable, Sendable {
        public let id: String
        /// 项目名，显示成小标题。
        public let project: String
        /// 用到了什么，一句中文说明。
        public let usage: String
        public let link: String
        /// 许可原文，照抄不翻译。
        public let text: String
    }

    /// 原作 Docket 的 MIT 许可原文，与仓库根目录的 LICENSE 一字不差。
    public static let upstreamMIT = """
        MIT License

        Copyright (c) 2026 Naman Parashar

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """

    /// 码头自己的版权说明，显示在致谢窗口最上面。
    public static let ownNotice = """
        码头 Dockling 基于 Naman Parashar 的开源项目 Docket（MIT 许可）开发。原作部分按下面的 MIT 许可提供，版权归原作者所有。

        码头在原作之外新增和修改的代码、图片、角色形象和文字，版权所有 © 2026 Hanson，保留所有权利。安装和使用码头适用《最终用户许可协议》。
        """

    /// 需要保留声明的全部来源，原作排在第一个。
    public static let credits: [Credit] = [
        Credit(id: "docket", project: "Docket",
               usage: "码头的原作，扩展栏、小组件和应用分组的基础代码。",
               link: "https://github.com/nparashar150/dockset",
               text: upstreamMIT),
        Credit(id: "codenotch", project: "Codenotch",
               usage: "Codex 用量小组件参考了它的接口和会话日志格式。",
               link: "https://github.com/vinzdg/codenotch",
               text: """
        MIT License

        Copyright (c) 2026 Vinz

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """),
        Credit(id: "onlyswitch", project: "OnlySwitch",
               usage: "快速开关小组件参考了它用到的系统命令。",
               link: "https://github.com/jacklandrin/OnlySwitch",
               text: """
        MIT License

        Copyright (c) 2021 jack

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """),
        Credit(id: "meowradio", project: "阿喵收音机 meowRadio",
               usage: "收音机小组件的图标和弧光调谐的样式。",
               link: "https://github.com/ca-x/meowRadio",
               text: """
        MIT License

        Copyright (c) 2026 ca-x

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """),
        Credit(id: "audiocap", project: "AudioCap",
               usage: "应用音量小组件的声音接入流程参考了它。",
               link: "https://github.com/insidegui/AudioCap",
               text: """
        Copyright (c) 2024 Guilherme Rambo

        Redistribution and use in source and binary forms, with or without
        modification, are permitted provided that the following conditions are met:

        - Redistributions of source code must retain the above copyright notice, this
          list of conditions and the following disclaimer.

        - Redistributions in binary form must reproduce the above copyright notice,
          this list of conditions and the following disclaimer in the documentation
          and/or other materials provided with the distribution.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
        AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
        IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
        FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
        DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
        SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
        CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
        OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
        OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """),
    ]

    /// 数据来源的署名，许可要求在显示数据的地方注明，这里再列一次。
    public static let dataSources = """
        天气数据来自 MET Norway 和 Open-Meteo（CC BY 4.0），加密货币行情来自 CoinGecko，电台目录来自 Radio Browser，节假日数据来自 holiday-cn（MIT）。
        """

    /// 最终用户许可协议，与仓库根目录的 EULA.md 一字不差。
    public static let eula = """
        # 码头 Dockling 最终用户许可协议

        版本：2026 年 10 月

        安装或使用码头（Dockling，以下称“本软件”），即表示你同意本协议。不同意的话，请不要安装或使用，已安装的请删除。

        ## 1. 免费使用

        本软件的作者 Hanson（以下称“作者”）授予你一项免费、非独占、不可转让的许可：你可以在自己的 Mac 上安装和使用本软件，个人和工作中使用都可以。

        ## 2. 不允许的事

        - 不得反编译、反汇编或以其他方式逆向工程本软件，适用法律明确允许的除外。
        - 不得二次分发本软件：不得出售、出租、转授权，也不得在其他网站、网盘、应用商店或渠道重新打包或提供下载。想推荐给别人，请分享官方下载地址（GitHub 上 hanson-zz/docket-release 的 Releases，或 docket.shiduo.app）。
        - 不得移除、遮盖或修改本软件中的版权声明、许可声明和本协议，不得绕过或去除本软件的授权相关内容。

        ## 3. 开源部分

        本软件基于 Naman Parashar 的开源项目 Docket（MIT 许可），也包含按其他开源许可使用的内容。这些部分按各自的许可执行，本协议不限制你依据那些许可享有的权利。完整的版权声明和许可原文见本软件“设置 ▸ 通用 ▸ 开源致谢与许可”。

        ## 4. 不提供担保

        本软件按“现状”免费提供，不附带任何明示或暗示的担保。在适用法律允许的最大范围内，作者不对因使用或无法使用本软件造成的任何损失承担责任。

        ## 5. 终止

        你违反本协议时，本许可自动终止，你应停止使用并删除本软件。

        ## 6. 联系

        对本协议有疑问，请发邮件到 694561981@qq.com。
        """
}
