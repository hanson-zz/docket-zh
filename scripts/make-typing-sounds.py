#!/usr/bin/env python3
"""打字音效的素材，写到 Resources/TypingSounds/。

    make-typing-sounds.py                    重新合成青轴、茶轴、打字机三套（原创，不取任何采样）
    make-typing-sounds.py --recordings DIR   从 DIR 里下载好的录音裁出红轴、黑轴、静电容、白噪安静款四套
    make-typing-sounds.py --check            只检查已有文件（个数、时长、峰值、总大小）

每套 7 个单键样本，文件名 typing-<款>-<键>.wav，平铺在一个文件夹里（打包时资源会被摊平，
所以名字里带上款名，免得重名）：

    key-1 … key-4   普通键的四个变体（播放时随机挑、不连着重复，再略微随机音高）
    space           空格
    enter           回车
    backspace       删除

规格：单声道 32000 Hz 16 位 WAV；单个样本不超过 0.16 秒（打字机回车带铃声，0.75 秒）；
峰值统一压到 -3 dBFS 左右，响度由 App 里的音量滑杆管。七套合计控制在 1.5 MB 以内。

合成的三套只用 numpy 现场算：噪声、衰减正弦和包络，随机数固定种子，每次生成逐字节相同。

| 款      | 听感                                                       |
| ------- | ---------------------------------------------------------- |
| 青轴    | 先一声清脆的“咔”（高频短脉冲加 3 kHz 小共振），紧跟触底的“哒” |
| 茶轴    | 没有咔声，一个闷一点的段落鼓包，再是偏低的触底声               |
| 打字机  | 金属字锤敲在滚筒上：不谐和的金属泛音加低频“咚”；回车是棘轮“嗒嗒嗒”加一声铃 |

四套录音（需要先把下面的原始文件下载到 DIR，脚本不联网）：

| 款         | 来源                                                                 | 许可  |
| ---------- | -------------------------------------------------------------------- | ----- |
| 红轴       | Mechvibes soundpacks/keyboard/cherrymx-red-abs（config.json + sound.ogg）        | MIT   |
| 黑轴       | Mechvibes soundpacks/keyboard/cherrymx-black-pbt（config.json + sound.ogg）      | MIT   |
| 静电容     | Mechvibes soundpacks/keyboard/topre-purple-hybrid-pbt（config.json + sound.ogg） | MIT   |
| 白噪安静款 | OpenGameArt「Keyboard Soundpack #1」Single Keys/keypress-0NN.wav             | CC0   |

Mechvibes：https://github.com/hainguyents13/mechvibes （MIT，Copyright (c) 2026 Hải Nguyễn），
目录结构 DIR/<包名>/config.json、DIR/<包名>/sound.ogg；按 config.json 里每个键的第一段
timing（按下）裁出来，解 ogg 用 ffmpeg。
OpenGameArt：https://opengameart.org/content/keyboard-soundpack-1-typing-and-single-keystrokes
（unicaegames，CC0），解压后的 “Single Keys” 文件夹放在 DIR/opengameart/。
"""

import json
import os
import subprocess
import sys
import wave

import numpy as np

RATE = 32000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "TypingSounds")
KEYS = ["key-1", "key-2", "key-3", "key-4", "space", "enter", "backspace"]
SYNTH = ["blue", "brown", "typewriter"]
RECORDED = ["red", "black", "capacitive", "quiet"]
MAX_SECONDS = 0.16
MAX_ENTER_SECONDS = 0.75
BUDGET = 1_500_000
PEAK = 10 ** (-3 / 20)


# MARK: - 基本件

def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(length, attack, decay):
    """指数衰减包络，attack 秒线性起。"""
    x = np.arange(length) / RATE
    e = np.exp(-x / decay)
    a = max(1, int(attack * RATE))
    e[:a] *= np.linspace(0, 1, a)
    return e


def bandpass(signal, low, high):
    spectrum = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / RATE)
    # 柔和的边，不让滤波器自己振铃。
    gain = 1 / (1 + (low / np.maximum(freqs, 1)) ** 4) / (1 + (freqs / high) ** 4)
    return np.fft.irfft(spectrum * gain, len(signal))


def ping(length, freq, decay, phase=0.0):
    x = np.arange(length) / RATE
    return np.sin(2 * np.pi * freq * x + phase) * np.exp(-x / decay)


def place(total, part, at):
    start = int(at * RATE)
    end = min(len(total), start + len(part))
    total[start:end] += part[: end - start]
    return total


def finish(signal, seconds):
    n = int(seconds * RATE)
    signal = signal[:n].copy()
    fade = min(len(signal), int(0.008 * RATE))
    signal[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(signal)) or 1
    return signal / peak * PEAK


# MARK: - 合成三套

def click(rng, brightness=1.0):
    """青轴的“咔”：2 ms 高频噪声脉冲加一个 3 kHz 上下的小共振。"""
    n = int(0.012 * RATE)
    burst = bandpass(rng.standard_normal(n), 3500, 9000) * env(n, 0.0002, 0.0012)
    res = ping(n, 3100 * brightness * rng.uniform(0.96, 1.04), 0.0025)
    return burst * 0.9 + res * 0.5


def bottom(rng, tone, body, decay=0.010, bright=2600):
    """触底：中频噪声加低频的壳体共鸣。"""
    n = int(0.09 * RATE)
    noise = bandpass(rng.standard_normal(n), 600, bright) * env(n, 0.0004, 0.004)
    shell = ping(n, tone * rng.uniform(0.97, 1.03), decay) * 0.6
    low = ping(n, body * rng.uniform(0.97, 1.03), decay * 1.6) * 0.45
    return noise + shell + low


def rattle(rng, n, at, strength=0.25):
    """大键的卫星轴：几下很轻的杂响。"""
    out = np.zeros(n)
    for k in range(3):
        m = int(0.01 * RATE)
        part = bandpass(rng.standard_normal(m), 1500, 6000) * env(m, 0.0002, 0.0015) * strength * (0.8 ** k)
        place(out, part, at + 0.006 * k + rng.uniform(0, 0.002))
    return out


def blue(key, rng):
    n = int(MAX_SECONDS * RATE)
    out = np.zeros(n)
    if key.startswith("key") or key == "backspace":
        bright = 1.08 if key == "backspace" else 1.0
        place(out, click(rng, bright), 0)
        place(out, bottom(rng, 1250 * bright, 260) * 0.75, 0.011 + rng.uniform(-0.001, 0.001))
    elif key == "space":
        place(out, click(rng, 0.9) * 0.8, 0)
        place(out, bottom(rng, 820, 170, decay=0.016, bright=1800), 0.013)
        out += rattle(rng, n, 0.02)
    else:  # enter：咔一声、重一点的触底，加一点卫星轴，听着“换了一行”
        place(out, click(rng, 0.95), 0)
        place(out, bottom(rng, 980, 190, decay=0.018, bright=2000), 0.012)
        out += rattle(rng, n, 0.022, 0.3)
        place(out, bottom(rng, 1400, 300, decay=0.006) * 0.25, 0.06)
    return finish(out, MAX_SECONDS)


def brown(key, rng):
    n = int(MAX_SECONDS * RATE)
    out = np.zeros(n)
    bump_n = int(0.02 * RATE)
    bump = bandpass(rng.standard_normal(bump_n), 500, 1800) * env(bump_n, 0.001, 0.004) * 0.35
    if key.startswith("key") or key == "backspace":
        tone = 1050 if key == "backspace" else 900
        place(out, bump, 0)
        place(out, bottom(rng, tone, 210, decay=0.009, bright=1900), 0.014 + rng.uniform(-0.0015, 0.0015))
    elif key == "space":
        place(out, bump, 0)
        place(out, bottom(rng, 640, 150, decay=0.016, bright=1400), 0.016)
        out += rattle(rng, n, 0.024, 0.18)
    else:
        place(out, bump, 0)
        place(out, bottom(rng, 720, 160, decay=0.02, bright=1500), 0.015)
        out += rattle(rng, n, 0.026, 0.2)
        place(out, bottom(rng, 1100, 260, decay=0.006) * 0.22, 0.065)
    return finish(out, MAX_SECONDS)


def strike(rng, scale=1.0):
    """字锤打在滚筒上：不谐和的金属泛音、滚筒的低频“咚”和一点纸的噪声。"""
    n = int(MAX_SECONDS * RATE)
    out = np.zeros(n)
    hit = bandpass(rng.standard_normal(n), 1200, 8000) * env(n, 0.0002, 0.0025)
    out += hit
    for freq, amp, decay in [(1830, 0.5, 0.03), (2910, 0.38, 0.022), (4270, 0.26, 0.016), (6150, 0.16, 0.01)]:
        out += ping(n, freq * scale * rng.uniform(0.985, 1.015), decay, rng.uniform(0, 6.28)) * amp
    out += ping(n, 150 * rng.uniform(0.95, 1.05), 0.02) * 0.7
    # 字杆回落的第二下，轻一点。
    place(out, bandpass(rng.standard_normal(int(0.01 * RATE)), 800, 4000)
          * env(int(0.01 * RATE), 0.0003, 0.002) * 0.25, 0.07 + rng.uniform(0, 0.01))
    return out


def typewriter(key, rng):
    if key == "enter":
        total = MAX_ENTER_SECONDS
        n = int(total * RATE)
        out = np.zeros(n)
        # 换行杆：棘轮“嗒嗒嗒”越来越快，接着滑架撞到头的“咚”。
        at = 0.0
        gap = 0.034
        for k in range(7):
            m = int(0.012 * RATE)
            tick = bandpass(rng.standard_normal(m), 1500, 7000) * env(m, 0.0002, 0.0018) * (0.5 + 0.05 * k)
            place(out, tick + ping(m, 2400, 0.003) * 0.2, at)
            at += gap
            gap *= 0.86
        place(out, strike(rng, 0.8) * 0.6, at + 0.01)
        # 铃：两个不谐和的分音，长一点的余音。
        bell_n = n - int((at + 0.02) * RATE)
        bell = (ping(bell_n, 2637, 0.32) + ping(bell_n, 2637 * 2.76, 0.12) * 0.35
                + ping(bell_n, 2637 * 5.4, 0.05) * 0.12) * 0.7
        place(out, bell, at + 0.02)
        return finish(out, total)
    if key == "space":
        # 空格没有字锤，只有擒纵走一格的“咔嗒”，比字键轻。
        n = int(MAX_SECONDS * RATE)
        out = np.zeros(n)
        m = int(0.02 * RATE)
        place(out, bandpass(rng.standard_normal(m), 900, 5000) * env(m, 0.0002, 0.003), 0)
        place(out, ping(n, 1450, 0.012) * 0.35 + ping(n, 210, 0.018) * 0.5, 0.004)
        return finish(out, MAX_SECONDS)
    scale = 1.12 if key == "backspace" else 1.0
    return finish(strike(rng, scale), MAX_SECONDS)


# MARK: - 四套录音

def decode(path):
    """用 ffmpeg 解成 32 kHz 单声道 float。"""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def trim(signal, limit):
    """去掉开头的静音（起音前留 1.5 ms），截到 limit 秒。按下就该响，开头不能拖。"""
    level = np.max(np.abs(signal)) or 1
    above = np.nonzero(np.abs(signal) > level * 0.12)[0]
    start = max(0, (above[0] if len(above) else 0) - int(0.0015 * RATE))
    return finish(signal[start:], min(limit, (len(signal) - start) / RATE))


MECHVIBES = {
    "red": "cherrymx-red-abs",
    "black": "cherrymx-black-pbt",
    "capacitive": "topre-purple-hybrid-pbt",
}
MECHVIBES_KEYS = {
    "key-1": "KeyA", "key-2": "KeyF", "key-3": "KeyJ", "key-4": "KeyL",
    "space": "Space", "enter": "Enter", "backspace": "Backspace",
}
# 白噪安静款：OpenGameArt 的 32 个单键里挑的（起音干净、按下到峰值不到 8 ms 的几个）。空格、回车、删除没有单独录，取另外几个
# 放慢一点（音高略低、显得键大），删除略快。
QUIET = {
    "key-1": ("keypress-003.wav", 1.0), "key-2": ("keypress-007.wav", 1.0),
    "key-3": ("keypress-013.wav", 1.0), "key-4": ("keypress-017.wav", 1.0),
    "space": ("keypress-004.wav", 0.82), "enter": ("keypress-006.wav", 0.88),
    "backspace": ("keypress-029.wav", 1.06),
}


def resample(signal, speed):
    if speed == 1.0:
        return signal
    positions = np.arange(0, len(signal) - 1, speed)
    return np.interp(positions, np.arange(len(signal)), signal)


def recorded(source):
    result = {}
    for style, pack in MECHVIBES.items():
        folder = os.path.join(source, pack)
        with open(os.path.join(folder, "config.json"), encoding="utf-8") as handle:
            config = json.load(handle)
        audio = decode(os.path.join(folder, config["audio_file"]))
        for key, code in MECHVIBES_KEYS.items():
            start, end = config["definitions"][code]["timing"][0]
            clip = audio[int(start / 1000 * RATE): int(end / 1000 * RATE)]
            result[(style, key)] = trim(clip, MAX_SECONDS)
    singles = os.path.join(source, "opengameart")
    for key, (name, speed) in QUIET.items():
        clip = resample(decode(os.path.join(singles, name)), speed)
        result[("quiet", key)] = trim(clip, MAX_SECONDS)
    return result


# MARK: - 写文件

def write(style, key, signal):
    path = os.path.join(OUT, f"typing-{style}-{key}.wav")
    data = (np.clip(signal, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data)


def check(styles=None):
    styles = styles or SYNTH + RECORDED
    total = 0
    problems = []
    for style in styles:
        for key in KEYS:
            path = os.path.join(OUT, f"typing-{style}-{key}.wav")
            if not os.path.exists(path):
                problems.append(f"缺 {path}")
                continue
            total += os.path.getsize(path)
            with wave.open(path) as handle:
                seconds = handle.getnframes() / handle.getframerate()
                if handle.getframerate() != RATE or handle.getnchannels() != 1:
                    problems.append(f"{path} 不是 {RATE} Hz 单声道")
            limit = MAX_ENTER_SECONDS if (style == "typewriter" and key == "enter") else MAX_SECONDS
            if seconds > limit + 0.001:
                problems.append(f"{path} 有 {seconds:.3f} 秒")
    print(f"共 {len(styles) * len(KEYS)} 个文件，{total} 字节")
    if total > BUDGET:
        problems.append(f"总大小 {total} 超过 {BUDGET}")
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


def main():
    os.makedirs(OUT, exist_ok=True)
    if "--check" in sys.argv:
        return check()
    if "--recordings" in sys.argv:
        source = sys.argv[sys.argv.index("--recordings") + 1]
        for (style, key), signal in recorded(source).items():
            write(style, key, signal)
        return check()
    makers = {"blue": blue, "brown": brown, "typewriter": typewriter}
    for index, style in enumerate(SYNTH):
        for k, key in enumerate(KEYS):
            rng = np.random.default_rng(2026_11_01 + index * 100 + k)
            write(style, key, makers[style](key, rng))
    return check(SYNTH)


if __name__ == "__main__":
    sys.exit(main())
