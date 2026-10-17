#!/usr/bin/env python3
"""Writes one language of a String Catalog out as a plain .strings file.

The Shots tool is a bare executable rather than an app bundle, so the catalog
the app ships compiled into its Resources is not next to it. capture-shots.sh
runs this to put an en.lproj beside the tool, which is where Bundle.main looks
for one when the executable is not inside a bundle.

    strings-from-catalog.py Localizable.xcstrings en out/Localizable.strings
"""

import json
import sys


def escape(text):
    return (text.replace("\\", "\\\\").replace('"', '\\"')
                .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t"))


def value(localization):
    unit = localization.get("stringUnit")
    if unit and unit.get("value") is not None:
        return unit["value"]
    # A plural or device variation: the "other" form is the general one.
    for forms in localization.get("variations", {}).values():
        other = forms.get("other", {}).get("stringUnit", {})
        if other.get("value") is not None:
            return other["value"]
    return None


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    catalog_path, language, out_path = sys.argv[1:]
    with open(catalog_path, encoding="utf-8") as handle:
        catalog = json.load(handle)
    lines = []
    for key, entry in catalog.get("strings", {}).items():
        text = value(entry.get("localizations", {}).get(language, {}))
        if text is not None:
            lines.append('"%s" = "%s";' % (escape(key), escape(text)))
    with open(out_path, "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")
    print("strings-from-catalog: %d %s strings" % (len(lines), language))


if __name__ == "__main__":
    main()
