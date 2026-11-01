#!/usr/bin/env python3
"""压 Resources 下的 PNG，给安装包减体积（2026-11 第一次跑，Resources 里的 PNG 合计15,710,177 字节降到 8,400,028 字节）。

用法（在仓库根目录）：
    pip install pyoxipng imagequant pillow numpy
    python3 scripts/optimize-pngs.py --dry                      # 只看结果不写
    python3 scripts/optimize-pngs.py "Resources/Pet/*.png"       # 压某一组
    python3 scripts/optimize-pngs.py --near "Resources/AppIcons/*.png"  # 应用图标只用近无损

规则：
- 每张先做无损重压（oxipng level 4，只去不影响显示的块，保留 iCCP 颜色描述）。
- 真彩色图（小熊猫姿势图等）再试 libimagequant 量化到 256 色（抖动 0.5），按透明度预乘后
  PSNR >= 40 dB、99.9% 像素误差 <= 32 才用，肉眼看不出来。
- 过不了门槛的、以及带 --near 的（应用图标会在访达简介、程序坞放大里被放大看，256 色的抖动颗粒
  放大后看得出），RGB 各通道就近取 4 的倍数（每通道误差最多 2/255，透明度不动），仍是真彩色。
- 收款码（Sponsor）、菜单栏模板图（MenuBar）只做无损；Resources/AppIcon.icon（Icon Composer）不动。
- 结果不比原图小就保留原图，所以重复跑是安全的（已压过的图基本不再变）。
"""
import glob, io, sys
import numpy as np
import oxipng
from PIL import Image
import imagequant
def metrics(a, b):
    a=np.asarray(a.convert('RGBA'),dtype=np.float64); b=np.asarray(b.convert('RGBA'),dtype=np.float64)
    # premultiply onto alpha
    pa=a[...,:3]*a[...,3:]/255; pb=b[...,:3]*b[...,3:]/255
    d=np.concatenate([pa-pb,(a[...,3:]-b[...,3:])],-1)
    mse=(d**2).mean(); psnr=99 if mse==0 else 10*np.log10(255**2/mse)
    return psnr, np.abs(d).max(), np.percentile(np.abs(d).max(-1),99.9)
def quant(im, dither=1.0, minq=0, maxq=100):
    q=imagequant.quantize_pil_image(im.convert('RGBA'), dithering_level=dither, max_colors=256, min_quality=minq, max_quality=maxq)
    return q
def encode(im, **kw):
    b=io.BytesIO(); im.save(b,'PNG',**kw); return oxipng.optimize_from_memory(b.getvalue(), level=4, strip=oxipng.StripChunks.safe())

PSNR_MIN, P999_MAX = 40.0, 32
LOSSLESS_ONLY = ('Resources/Sponsor/', 'Resources/MenuBar/', 'Resources/AppIcon.icon/')
dry = '--dry' in sys.argv
# 应用图标会被放大看（访达简介、程序坞放大），256 色抖动的颗粒放大后看得出，只用近无损。
force_near = '--near' in sys.argv
rep = []
pats = [a for a in sys.argv[1:] if not a.startswith('--')] or ['Resources/**/*.png']
files = sorted({f for p in pats for f in glob.glob(p, recursive=True)})
for f in files:
    if f.startswith('Resources/AppIcon.icon/'): continue  # Icon Composer 资源不动
    orig = open(f, 'rb').read(); im = Image.open(f); im.load()
    lossless = oxipng.optimize_from_memory(orig, level=4, strip=oxipng.StripChunks.safe())
    best, how = lossless, 'lossless'
    if im.mode in ('RGBA', 'RGB') and not f.startswith(LOSSLESS_ONLY):
        p = p999 = 0
        qd = encode(quant(im, 0.5))
        p, mx, p999 = metrics(im, Image.open(io.BytesIO(qd)))
        if not force_near and p >= PSNR_MIN and p999 <= P999_MAX and len(qd) < len(best):
            best, how = qd, f'quant psnr={p:.1f} p999={p999:.0f}'
        else:
            # 量化过不了门槛（渐变多的经典图标等）：RGB 各通道就近取 4 的倍数（误差最多 2/255），
            # 透明度不动，仍是真彩色 PNG。
            a = np.asarray(im.convert('RGBA')).astype(np.int32)
            a[..., :3] = np.clip(((a[..., :3] + 2) // 4) * 4, 0, 255)
            pd = encode(Image.fromarray(a.astype(np.uint8), 'RGBA'))
            p2, _, _ = metrics(im, Image.open(io.BytesIO(pd)))
            if len(pd) < len(best):
                best, how = pd, f'near-lossless step4 psnr={p2:.1f} (quant rejected psnr={p:.1f})'
    if len(best) >= len(orig): best, how = orig, 'unchanged'
    rep.append((f, len(orig), len(best), how))
    if not dry and best is not orig: open(f, 'wb').write(best)
    print(f, len(orig), len(best), how, flush=True)
a = sum(r[1] for r in rep); b = sum(r[2] for r in rep)
print('TOTAL', a, b)
