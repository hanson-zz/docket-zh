#!/usr/bin/env python3
"""合成码头 Pro 解锁动画的音效，写到 Resources/Unlock/。

    make-unlock-sounds.py           重新生成全部音效
    make-unlock-sounds.py --check   只检查已有文件（大小、峰值）

全部用正弦、噪声和包络现场算出来，是原创音效，不取任何采样。只用标准库，
随机数固定种子，每次生成的文件逐字节相同。

规格：单声道 22050 Hz 16 位 WAV，每个小于 60 KB，峰值归一到约 -6 dBFS。
左右声像不写进文件，由 AVAudioPlayer.pan 在播放时设置。

| 文件                     | 时刻        | 声音                         |
| ------------------------ | ----------- | ---------------------------- |
| unlock-whoosh.wav        | 0s          | 登场的“嗖”                   |
| unlock-pop.wav           | 约 0.9s     | 皇冠落到头上的“啵”           |
| unlock-firework.wav      | 1.0s、1.3s  | 烟花：上升哨音 + 噼啪        |
| unlock-ding-0..5.wav     | 每个标签    | 轻“叮”，音高逐个升高         |
| unlock-success.wav       | 约 2.4s     | 暖色的成功和弦               |
"""

import math
import os
import random
import struct
import sys
import wave

RATE = 22050
PEAK_DBFS = -6.0
MAX_BYTES = 60 * 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Unlock")

# 标签的“叮”：五声音阶 C6 D6 E6 G6 A6 C7，一个比一个高。
DING_NOTES = [1046.50, 1174.66, 1318.51, 1567.98, 1760.00, 2093.00]


def seconds(n):
    return int(n * RATE)


def envelope(i, total, attack, release_curve=4.0):
    """线性起音，指数衰减。"""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-release_curve * t / (total / RATE))


def one_pole_lowpass(samples, cutoff):
    out, y = [], 0.0
    for x in samples:
        alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        y += alpha * (x - y)
        out.append(y)
    return out


def whoosh():
    """带通滤波的噪声，中心频率从低扫到高再回落，像东西从下方飞上来。"""
    rng = random.Random(11)
    n = seconds(0.48)
    low = high = 0.0
    out = []
    for i in range(n):
        p = i / n
        centre = 300 + 2600 * math.sin(math.pi * min(1.0, p * 1.15)) ** 1.5
        x = rng.uniform(-1, 1)
        a_hi = 1 - math.exp(-2 * math.pi * centre * 1.6 / RATE)
        a_lo = 1 - math.exp(-2 * math.pi * centre * 0.6 / RATE)
        high += a_hi * (x - high)
        low += a_lo * (x - low)
        band = high - low
        env = math.sin(math.pi * p) ** 1.6
        out.append(band * env)
    return out


def pop():
    """短促下滑的正弦加一点点击声。"""
    n = seconds(0.2)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 320 + 700 * math.exp(-t * 38)
        phase += 2 * math.pi * f / RATE
        body = math.sin(phase) * math.exp(-t * 26)
        click = (1 if i < 30 else 0) * (1 - i / 30) * 0.6
        out.append(body + click)
    return out


def firework():
    """上升的哨音（带颤音），然后低沉的一声和渐稀的噼啪。"""
    rng = random.Random(23)
    whistle_n = seconds(0.36)
    total = seconds(1.15)
    out = [0.0] * total
    phase = 0.0
    for i in range(whistle_n):
        t = i / RATE
        p = i / whistle_n
        f = 1300 + 1500 * p + 40 * math.sin(2 * math.pi * 22 * t)
        phase += 2 * math.pi * f / RATE
        env = min(1.0, p * 6) * (1 - p) ** 0.4
        out[i] += 0.45 * math.sin(phase) * env
    # 爆开：低频噪声。
    boom_start = whistle_n
    noise = [rng.uniform(-1, 1) for _ in range(seconds(0.5))]
    noise = one_pole_lowpass(noise, 420)
    for j, x in enumerate(noise):
        k = boom_start + j
        if k >= total:
            break
        out[k] += 2.4 * x * math.exp(-(j / RATE) * 9)
    # 噼啪：随机的小脉冲，越来越稀、越来越轻。
    t0 = boom_start + seconds(0.05)
    for _ in range(170):
        when = t0 + int(rng.expovariate(1 / seconds(0.22)))
        if when >= total - 60:
            continue
        amp = rng.uniform(0.25, 0.75) * math.exp(-((when - t0) / RATE) * 2.4)
        length = rng.randint(18, 60)
        tone = rng.uniform(2500, 6000)
        for m in range(length):
            out[when + m] += amp * math.sin(2 * math.pi * tone * m / RATE) * (1 - m / length)
    # 结尾淡出，避免截断噪声。
    fade = seconds(0.08)
    for m in range(fade):
        out[total - fade + m] *= 1 - m / fade
    return out


def ding(freq):
    """钟琴一样的轻“叮”：基频加不谐和的高次泛音，指数衰减。"""
    n = seconds(0.42)
    out = []
    for i in range(n):
        t = i / RATE
        a = min(1.0, t / 0.003)
        v = (math.sin(2 * math.pi * freq * t) * math.exp(-t * 9)
             + 0.35 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-t * 18)
             + 0.12 * math.sin(2 * math.pi * freq * 5.4 * t) * math.exp(-t * 30))
        out.append(a * v)
    return out


def success():
    """C 大调琶音（C5 E5 G5 C6）叠成一个暖和弦，柔和的三角波。"""
    n = seconds(1.25)
    notes = [(523.25, 0.00), (659.25, 0.09), (783.99, 0.18), (1046.50, 0.27)]
    out = [0.0] * n
    for freq, start in notes:
        s = seconds(start)
        for i in range(n - s):
            t = i / RATE
            a = min(1.0, t / 0.012)
            decay = math.exp(-t * 2.6)
            # 前三个奇次谐波近似三角波，听起来比正弦暖。
            v = (math.sin(2 * math.pi * freq * t)
                 - math.sin(2 * math.pi * 3 * freq * t) / 9
                 + math.sin(2 * math.pi * 5 * freq * t) / 25)
            vibrato = 1 + 0.004 * math.sin(2 * math.pi * 5 * t)
            out[s + i] += a * decay * v * vibrato
    fade = seconds(0.12)
    for m in range(fade):
        out[n - fade + m] *= 1 - m / fade
    return out


def normalise(samples):
    peak = max(abs(x) for x in samples) or 1.0
    target = 10 ** (PEAK_DBFS / 20)
    return [x / peak * target for x in samples]


def write(name, samples):
    path = os.path.join(OUT, name)
    data = b"".join(struct.pack("<h", int(round(max(-1, min(1, x)) * 32767))) for x in normalise(samples))
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data)
    return path


def sounds():
    yield "unlock-whoosh.wav", whoosh()
    yield "unlock-pop.wav", pop()
    yield "unlock-firework.wav", firework()
    for index, freq in enumerate(DING_NOTES):
        yield f"unlock-ding-{index}.wav", ding(freq)
    yield "unlock-success.wav", success()


NAMES = (["unlock-whoosh.wav", "unlock-pop.wav", "unlock-firework.wav"]
         + [f"unlock-ding-{index}.wav" for index in range(len(DING_NOTES))]
         + ["unlock-success.wav"])


def check(path):
    size = os.path.getsize(path)
    with wave.open(path, "rb") as handle:
        frames = handle.readframes(handle.getnframes())
        rate, width, channels = handle.getframerate(), handle.getsampwidth(), handle.getnchannels()
    values = struct.unpack("<%dh" % (len(frames) // 2), frames)
    peak = max(abs(v) for v in values) / 32767
    dbfs = 20 * math.log10(peak) if peak > 0 else -120
    problems = []
    if size >= MAX_BYTES:
        problems.append(f"{size} 字节，超过 60 KB")
    if not -6.5 <= dbfs <= -5.5:
        problems.append(f"峰值 {dbfs:.2f} dBFS，不在 -6 dBFS 附近")
    if (rate, width, channels) != (RATE, 2, 1):
        problems.append(f"格式 {rate} Hz / {width * 8} 位 / {channels} 声道")
    print(f"{os.path.basename(path):24} {size:6d} B  {len(values) / rate:4.2f}s  峰值 {dbfs:6.2f} dBFS"
          + ("  " + "；".join(problems) if problems else ""))
    return not problems


def main():
    names = NAMES if "--check" in sys.argv else None
    ok = True
    if names is None:
        os.makedirs(OUT, exist_ok=True)
        for name, samples in sounds():
            ok &= check(write(name, samples))
    else:
        for name in names:
            ok &= check(os.path.join(OUT, name))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
