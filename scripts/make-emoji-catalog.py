#!/usr/bin/env python3
"""生成 Sources/Core/EmojiCatalogData.swift（表情符号面板的内置表情表）。

    python3 scripts/make-emoji-catalog.py

下载 Unicode emoji-test.txt（15.1）和 CLDR 中英文表情注释（annotations +
annotationsDerived），只取 Emoji 15.0 及以前的完全限定表情，去掉肤色变体和
“组件”组。能换肤色的标准：5 种肤色按“第一个字后面加肤色、去掉紧跟的 FE0F”
算出来的写法都在 emoji-test 里。数据是 Unicode License v3，见 NOTICE.md。
"""

import json
import os
import re
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Sources/Core/EmojiCatalogData.swift")
TEST = "https://unicode.org/Public/emoji/15.1/emoji-test.txt"
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json"
MAX_VERSION = 15.0
MODS = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]


def get(url):
    with urllib.request.urlopen(url) as r:
        return r.read().decode("utf-8")


def annotations(lang):
    full = json.loads(get(f"{CLDR}/cldr-annotations-full/annotations/{lang}/annotations.json"))
    derived = json.loads(get(f"{CLDR}/cldr-annotations-derived-full/annotationsDerived/{lang}/annotations.json"))
    table = dict(derived["annotationsDerived"]["annotations"])
    table.update(full["annotations"]["annotations"])
    return table


def keywords(table, emoji):
    entry = table.get(emoji) or table.get(emoji.replace("\ufe0f", ""))
    if not entry:
        return []
    out = []
    for k in entry.get("tts", []) + entry.get("default", []):
        k = k.strip().replace("|", "/").replace("\t", " ")
        if k and k not in out:
            out.append(k)
    return out


def toned(emoji, mod):
    rest = list(emoji[1:])
    if rest and rest[0] == "\ufe0f":
        rest = rest[1:]
    return emoji[0] + chr(mod) + "".join(rest)


def main():
    zh, en = annotations("zh"), annotations("en")
    qualified, entries, group = set(), [], None
    for line in get(TEST).splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
        if not line or line.startswith("#"):
            continue
        cps, rest = line.split(";", 1)
        status = rest.split("#")[0].strip()
        emoji = "".join(chr(int(c, 16)) for c in cps.split())
        if status != "fully-qualified":
            continue
        qualified.add(emoji)
        if group == "Component" or any(ord(c) in MODS for c in emoji):
            continue
        version = float(re.search(r"E(\d+\.\d+)", rest).group(1))
        if version <= MAX_VERSION:
            entries.append(emoji)
    rows = []
    for emoji in entries:
        modifiable = all(toned(emoji, m) in qualified for m in MODS)
        z = keywords(zh, emoji)
        e = [k.lower() for k in keywords(en, emoji)]
        rows.append("\t".join([emoji, "1" if modifiable else "0", "|".join(z), "|".join(e)]))
    body = "\n".join(rows).replace("\u2014", "-").replace("\u2013", "-")
    assert "\\" not in body and '"""' not in body
    header = (
        "// 由 Unicode emoji-test.txt（15.1，只取 15.0 及以前的完全限定表情，不含肤色变体和组件）\n"
        "// 和 CLDR 中英文注释（annotations + annotationsDerived，Unicode License v3）生成。\n"
        "// 一行一个：表情、能否换肤色（1/0）、中文关键词（| 分隔）、英文关键词（小写，| 分隔）。\n"
        "// 顺序是 Unicode 的官方排序，搜索结果同分时按它排。不要手改，用\n"
        "// scripts/make-emoji-catalog.py 重新生成。\n\n"
        "enum EmojiCatalogData {\n"
        '    static let table = """\n'
    )
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(header + body + '\n"""\n}\n')
    print(f"{len(rows)} emoji -> {OUT}")


if __name__ == "__main__":
    main()
