#!/usr/bin/env python3
# 收音机「世界」页的点阵地图资源：把 Natural Earth 110m 国家面（公有领域，
# https://www.naturalearthdata.com/downloads/110m-cultural-vectors/ 的
# ne_110m_admin_0_countries，转成 GeoJSON）栅格化成 4° 经纬点阵，每个陆地点记它落在哪个国家
# （ISO 3166-1 两位码，认不出的记空）。只记点和国家码，不画、不存国界线。
# 结果写到 Resources/Radio/radio-world-dots.json，App 直接读这个小 JSON，运行时不解析 geojson。
#
# 用法：python3 scripts/make-radio-world-dots.py <ne_110m_countries.geojson>
# 依赖 Pillow。南极洲不画；纬度只取北纬 82° 到南纬 56°。
import json, os, re, sys
from PIL import Image, ImageDraw

LON0, LON1, LAT0, LAT1 = -180, 180, 82, -56
STEP = 4
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources/Radio/radio-world-dots.json")


def code_of(props):
    iso = props.get("ISO_A2_EH") or props.get("ISO_A2") or ""
    name = props.get("NAME")
    if name == "France":
        iso = "FR"
    if name == "Norway":
        iso = "NO"
    return iso if re.fullmatch(r"[A-Z]{2}", iso or "") else ""


def main(src):
    gj = json.load(open(src))
    rw, rh = 1440, 552   # 0.25° 一个像素
    im = Image.new("I", (rw, rh), 0)
    dr = ImageDraw.Draw(im)
    codes = [None]
    # 西撒哈拉在 110m 数据里和摩洛哥的面重叠，放最后画。
    feats = sorted(gj["features"], key=lambda f: f["properties"].get("ISO_A2_EH") == "EH")
    for f in feats:
        p = f["properties"]
        if p.get("CONTINENT") == "Antarctica":
            continue
        codes.append(code_of(p))
        idx = len(codes) - 1
        geom = f["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        for poly in polys:
            pts = [((lo - LON0) / (LON1 - LON0) * rw, (LAT0 - la) / (LAT0 - LAT1) * rh) for lo, la in poly[0]]
            dr.polygon(pts, fill=idx)

    def px(lo, la):
        x = int((lo - LON0) / (LON1 - LON0) * rw)
        y = int((LAT0 - la) / (LAT0 - LAT1) * rh)
        return x, y

    cols = int((LON1 - LON0) / STEP)
    rows = int((LAT0 - LAT1) / STEP)
    table = [""]
    dots = []
    for r in range(rows):
        for c in range(cols):
            lo = LON0 + (c + 0.5) * STEP
            la = LAT0 - (r + 0.5) * STEP
            votes = {}
            for dx, dy in [(0, 0), (-1.2, -1.2), (1.2, -1.2), (-1.2, 1.2), (1.2, 1.2)]:
                x, y = px(lo + dx, la + dy)
                if 0 <= x < rw and 0 <= y < rh:
                    v = im.getpixel((x, y))
                    if v:
                        votes[v] = votes.get(v, 0) + (2 if (dx, dy) == (0, 0) else 1)
            if not votes:
                continue
            cx, cy = px(lo, la)
            centre = im.getpixel((cx, cy))
            code = codes[centre] if centre else codes[max(votes, key=votes.get)]
            if "EH" in codes:
                eh = codes.index("EH")
                hits = sum(1 for i in range(9) for j in range(9)
                           if im.getpixel((min(rw - 1, cx - 8 + i * 2), min(rh - 1, cy - 8 + j * 2))) == eh)
                if hits >= 16:
                    code = "EH"
            if code not in table:
                table.append(code)
            dots.append([c, r, table.index(code)])
    out = {
        "source": "Natural Earth 110m admin 0 countries (public domain)",
        "step": STEP, "lon0": LON0, "lat0": LAT0,
        "cols": cols, "rows": rows,
        "codes": table, "dots": dots,
    }
    with open(OUT, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print(OUT, cols, rows, len(dots), "dots,", len(table) - 1, "countries")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "../../design/assets/geo/ne_110m_countries.geojson"))
