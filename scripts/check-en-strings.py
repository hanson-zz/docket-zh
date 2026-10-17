#!/usr/bin/env python3
"""检查 Localizable.xcstrings 的英文译文。

    check-en-strings.py [Resources/Localization/Localizable.xcstrings]

三条规则，CI 的 House rules 里跑：

1. 英文译文里不能有汉字，也不能有中文标点（、，。：；！？（）「」『』【】《》
   和全角引号）。机翻常把“、”原样留下，付费墙的功能清单就出过这种事。
2. 带说明的键（`间隔 (interval)` 这种，给 `tr(_:context:)` 用）必须带简体、繁体
   和香港中文的值，否则中文界面会把“ (interval)”一起显示出来。
3. 键和英文译文里的占位符（%@、%d）个数一致。

确实要留中文的地方列在下面：提示词里的 `{文本}` 是占位符，原样保留；两条
说明是在举中文的例子。
"""

import json
import re
import sys

# 刻意保留的中文：整条键白名单，以及任何译文里都可以出现的片段。
ALLOWED_KEYS = {
    # 搜索框说明：用户可以直接输入中文“天气”。
    "也可以试试拼音、首字母或英文，比如 tianqi、tq、weather",
    # 录音文件名本身就以“录音”开头。
    "还没有录音。录音以 .m4a 格式保存，文件名以“录音”开头。",
}
ALLOWED_FRAGMENTS = ("{文本}",)

HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
CJK_PUNCT = re.compile(r"[\u3000-\u303f\uff01-\uff0f\uff1a-\uff20\uff3b-\uff40\uff5b-\uff65\u201c\u201d\u2018\u2019]")
CONTEXT_KEY = re.compile(r".+ \([a-z]+\)")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:@|0?\d*l{0,2}d)")


def values(localization):
    unit = localization.get("stringUnit")
    if unit and unit.get("value") is not None:
        yield unit["value"]
    for forms in localization.get("variations", {}).values():
        for form in forms.values():
            value = form.get("stringUnit", {}).get("value")
            if value is not None:
                yield value


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "Resources/Localization/Localizable.xcstrings"
    with open(path, encoding="utf-8") as handle:
        catalog = json.load(handle)

    problems = []
    for key, entry in catalog.get("strings", {}).items():
        localizations = entry.get("localizations", {})
        english = localizations.get("en")
        if english is None:
            continue
        for value in values(english):
            checked = value
            for fragment in ALLOWED_FRAGMENTS:
                checked = checked.replace(fragment, "")
            if key not in ALLOWED_KEYS:
                han = sorted(set(HAN.findall(checked)))
                punct = sorted(set(CJK_PUNCT.findall(checked)))
                if han:
                    problems.append((key, value, "汉字 " + "".join(han)))
                if punct:
                    problems.append((key, value, "中文标点 " + " ".join(punct)))
            if len(PLACEHOLDER.findall(key)) != len(PLACEHOLDER.findall(value)):
                problems.append((key, value, "占位符个数和键不一致"))
        if CONTEXT_KEY.fullmatch(key):
            for lang in ("zh-Hans", "zh-Hant", "zh-HK"):
                if not any(True for _ in values(localizations.get(lang, {}))):
                    problems.append((key, "", f"带说明的键缺少 {lang} 的值"))

    if problems:
        for key, value, why in problems:
            print(f"::error title=English string::{why}: {key!r} => {value!r}")
        print(f"\n{len(problems)} 处问题。英文译文改用英文标点；确实要保留中文的，"
              "加到 scripts/check-en-strings.py 的白名单里。")
        return 1
    print("English strings: clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
