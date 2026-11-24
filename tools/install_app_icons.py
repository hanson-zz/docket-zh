#!/usr/bin/env python3
"""给码头 Dockling 的 设置 → 通用 → 应用图标 导入本包中的 12 款图标。

用法（在解压包目录中执行）:
    python3 tools/install_app_icons.py /path/to/docket-zh

不会修改默认 AppIcon.icon；新增图标沿用原项目“Pro 隐藏系列”逻辑。
脚本可重复执行：已存在的 id 不会重复加入。
"""
from pathlib import Path
import re
import shutil
import sys

ITEMS = [
    ("VioletShadow", "紫影行者"),
    ("ShieldGuardian", "星盾守卫"),
    ("AstralMage", "星环法师"),
    ("StormWielder", "雷霆勇士"),
    ("SkylineAcrobat", "飞跃小熊"),
    ("SkyGuardian", "晴空守护"),
    ("CrimsonArmor", "赤甲小熊"),
    ("EmeraldGiant", "绿能巨熊"),
    ("NightSentinel", "暗夜披风"),
    ("SpeedRunner", "疾风跑者"),
    ("AmberClaws", "金蓝爪卫"),
    ("RedMischief", "红黑机灵"),
]

def main():
    if len(sys.argv) != 2:
        sys.exit("用法: python3 tools/install_app_icons.py /path/to/docket-zh")
    repo = Path(sys.argv[1]).expanduser().resolve()
    target = repo / "Sources/Core/AppIconChoice.swift"
    destination = repo / "Resources/AppIcons"
    here = Path(__file__).resolve().parent.parent
    src = here / "Resources/AppIcons"
    if not target.is_file() or not (repo / "project.yml").is_file():
        sys.exit("未找到码头仓库目录（需要 Sources/Core/AppIconChoice.swift 和 project.yml）")
    source_text = target.read_text(encoding="utf-8")
    if "public static let hidden: [AppIconOption]" not in source_text:
        sys.exit("未找到 AppIconCatalog.hidden；当前仓库结构可能已变，请交给 Hark 人工合并。")
    if "public static let heroNinja" not in source_text:
        sys.exit("未找到现有 Hero 图标定义；不自动修改，避免覆盖后续新版本。")
    for stem, _ in ITEMS:
        for suffix in ("", "-512", "-256"):
            file = src / f"AppIcon-{stem}{suffix}.png"
            if not file.is_file():
                sys.exit(f"缺少素材: {file.name}")

    lines = []
    added_ids = []
    for stem, title in ITEMS:
        name = "hero" + stem
        if f'id: "{name}"' in source_text:
            continue
        lines += [
            f'    public static let {name} = AppIconOption(',
            f'        id: "{name}", title: tr("{title}"), resourceName: "AppIcon-{stem}", isSupporterOnly: true)',
            "",
        ]
        added_ids.append(name)

    if added_ids:
        marker = '    /// 隐藏系列，按这个顺序排在 `all` 后面。'
        if source_text.count(marker) != 1:
            sys.exit("无法定位隐藏系列注册位置，请让 Hark 手动检查。")
        source_text = source_text.replace(marker, "\n".join(lines) + marker, 1)
        m = re.search(
            r'(    public static let hidden: \[AppIconOption\] = \[\n)(.*?)(    \])',
            source_text, flags=re.S)
        if not m:
            sys.exit("无法定位 hidden 列表，未写入任何修改。")
        replacement = m.group(1) + m.group(2).rstrip() + "\n" + \
            "        " + ", ".join(added_ids) + ",\n" + m.group(3)
        source_text = source_text[:m.start()] + replacement + source_text[m.end():]

    destination.mkdir(parents=True, exist_ok=True)
    copied = 0
    for stem, _ in ITEMS:
        for suffix in ("", "-512", "-256"):
            file = f"AppIcon-{stem}{suffix}.png"
            shutil.copy2(src / file, destination / file)
            copied += 1
    if added_ids:
        target.write_text(source_text, encoding="utf-8")
    print(f"已复制 {copied} 张 PNG 至 {destination}")
    print(f"新注册的图标：{len(added_ids)} 款。现有注册项不重复添加。")
    print("新图沿用 Pro 隐藏系列逻辑。请使用 Xcode/XcodeGen 构建并在“设置→通用→应用图标”检查。")
    print("注意：这些图片中有明显借鉴知名角色的设计，上架或公开销售前应进行 IP 合规评估。")

if __name__ == "__main__":
    main()
