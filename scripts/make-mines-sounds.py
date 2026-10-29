#!/usr/bin/env python3
"""合成扫雷小组件的音效，写到 Resources/Mines/。

    make-mines-sounds.py           重新生成全部音效
    make-mines-sounds.py --check   只检查已有文件（大小、峰值）

全部用正弦、噪声和包络现场算出来，是原创音效，不取任何采样，也不模仿任何系统
扫雷的声音，可以商用。只用标准库，随机数固定种子，每次生成的文件逐字节相同。

规格：单声道 22050 Hz 16 位 WAV，每个小于 40 KB。揭开格子最常响，峰值压得最低。

| 文件              | 什么时候     | 声音                               | 峰值      |
| ----------------- | ------------ | ---------------------------------- | --------- |
| mines-reveal.wav  | 揭开格子     | 很短的木质轻“嗒”                   | -18 dBFS  |
| mines-flag.wav    | 插旗 / 拔旗  | 往上挑的两声“哔啵”                 | -14 dBFS  |
| mines-boom.wav    | 踩雷         | 闷闷的“噗”：低频下滑加滤过的噪声   | -8 dBFS   |
| mines-win.wav     | 赢了         | 钟琴琶音 C5 E5 G5 C6               | -9 dBFS   |
"""

import math
import os
import random
import struct
import sys
import wave

RATE = 22050
MAX_BYTES = 40 * 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Mines")


def seconds(n):
    return int(n * RATE)


def one_pole_lowpass(samples, cutoff):
    out, y = [], 0.0
    alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    for x in samples:
        y += alpha * (x - y)
        out.append(y)
    return out


def reveal():
    """木质轻“嗒”：1.6 kHz 和 2.9 kHz 两个正弦，几毫秒内衰减完，加一点点噪声起音。"""
    rng = random.Random(3)
    n = seconds(0.06)
    out = []
    for i in range(n):
        t = i / RATE
        body = 0.7 * math.sin(2 * math.pi * 1600 * t) + 0.3 * math.sin(2 * math.pi * 2900 * t)
        click = rng.uniform(-1, 1) * max(0.0, 1 - i / 40) * 0.5
        out.append((body * math.exp(-t * 90)) + click)
    return out


def flag():
    """两声往上挑的“哔啵”：E6 再 A6，各 45 毫秒，圆润的正弦。"""
    out = []
    for freq, length in ((1318.51, 0.05), (1760.0, 0.07)):
        n = seconds(length)
        for i in range(n):
            t = i / RATE
            a = min(1.0, t / 0.002)
            out.append(a * math.sin(2 * math.pi * freq * t) * math.exp(-t * 38))
    return out


def boom():
    """闷闷的“噗”：从 140 Hz 掉到 45 Hz 的正弦，叠一段低通噪声，尾巴淡出。卡通，不刺耳。"""
    rng = random.Random(7)
    n = seconds(0.55)
    noise = one_pole_lowpass([rng.uniform(-1, 1) for _ in range(n)], 600)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 45 + 95 * math.exp(-t * 9)
        phase += 2 * math.pi * f / RATE
        tone = math.sin(phase) * math.exp(-t * 6)
        hiss = 3.0 * noise[i] * math.exp(-t * 7)
        a = min(1.0, t / 0.004)
        out.append(a * (tone + hiss))
    fade = seconds(0.06)
    for m in range(fade):
        out[n - fade + m] *= 1 - m / fade
    return out


def win():
    """钟琴琶音 C5 E5 G5 C6：每个音基频加一点二次泛音，指数衰减，依次进来。"""
    notes = [523.25, 659.25, 783.99, 1046.50]
    step = seconds(0.09)
    total = step * (len(notes) - 1) + seconds(0.6)
    out = [0.0] * total
    for k, freq in enumerate(notes):
        start = step * k
        for i in range(total - start):
            t = i / RATE
            a = min(1.0, t / 0.003)
            v = (math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(2 * math.pi * freq * 2.01 * t)
                 * math.exp(-t * 6))
            out[start + i] += 0.6 * a * v * math.exp(-t * 5.5)
    fade = seconds(0.08)
    for m in range(fade):
        out[total - fade + m] *= 1 - m / fade
    return out


SOUNDS = {
    "mines-reveal": (reveal, -18.0),
    "mines-flag": (flag, -14.0),
    "mines-boom": (boom, -8.0),
    "mines-win": (win, -9.0),
}


def write(name, samples, peak_dbfs):
    peak = max(abs(x) for x in samples) or 1.0
    gain = (10 ** (peak_dbfs / 20)) / peak
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x * gain)) * 32767)) for x in samples)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)
    return path


def check():
    ok = True
    for name, (_, peak_dbfs) in SOUNDS.items():
        path = os.path.join(OUT, name + ".wav")
        if not os.path.exists(path):
            print(f"缺少 {path}")
            ok = False
            continue
        size = os.path.getsize(path)
        with wave.open(path, "rb") as handle:
            data = handle.readframes(handle.getnframes())
            rate = handle.getframerate()
        values = struct.unpack(f"<{len(data) // 2}h", data)
        peak = max(abs(v) for v in values) / 32767
        db = 20 * math.log10(peak) if peak > 0 else -120
        print(f"{name}.wav  {size} 字节  {rate} Hz  峰值 {db:.1f} dBFS")
        if size > MAX_BYTES or rate != RATE or abs(db - peak_dbfs) > 0.5:
            ok = False
    return ok


def main():
    if "--check" in sys.argv:
        sys.exit(0 if check() else 1)
    os.makedirs(OUT, exist_ok=True)
    for name, (make, peak_dbfs) in SOUNDS.items():
        write(name, make(), peak_dbfs)
    sys.exit(0 if check() else 1)


if __name__ == "__main__":
    main()
