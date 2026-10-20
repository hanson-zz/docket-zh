import Foundation

/// The sounds the ambient widget can mix.
///
/// Every one is synthesised from noise rather than played from a recording:
/// nothing to license, nothing to download, nothing that loops audibly every
/// thirty seconds, and the whole set costs no space in the app.
public enum AmbientSound: String, CaseIterable, Sendable, Identifiable {
    case rain, waves, wind, fire, white, pink, brown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rain: tr("雨声")
        case .waves: tr("海浪")
        case .wind: tr("风声")
        case .fire: tr("篝火")
        case .white: tr("白噪音")
        case .pink: tr("粉红噪音")
        case .brown: tr("棕色噪音")
        }
    }

    public var symbol: String {
        switch self {
        case .rain: "cloud.rain.fill"
        case .waves: "water.waves"
        case .wind: "wind"
        case .fire: "flame.fill"
        case .white: "waveform"
        case .pink: "waveform.path"
        case .brown: "waveform.circle.fill"
        }
    }

    /// The stored list, in saved order, unknown names and repeats dropped.
    public static func parse(_ names: [String]) -> [AmbientSound] {
        // 按存的先后（设置里能拖动排序），卡片上画第一种的图标。
        OrderedChecklist.ordered(names, all: allCases.map(\.rawValue)).compactMap(AmbientSound.init(rawValue:))
    }

    /// "雨声 + 海浪", or the first two and a count when there are more.
    public static func summary(_ sounds: [AmbientSound]) -> String {
        switch sounds.count {
        case 0: tr("未选择声音")
        case 1, 2: sounds.map(\.title).joined(separator: " + ")
        default: tr("\(sounds[0].title) 等 \(sounds.count) 种")
        }
    }
}

/// The sleep timer's choices, in minutes. Zero is off.
public enum AmbientTimer {
    /// 面板上的固定几档；别的时长走「自定义」（见 `AmbientCustomTimer`）。
    public static let choices: [Int] = [0, 15, 30, 60]

    public static func title(_ minutes: Int) -> String {
        minutes == 0 ? tr("不定时") : (minutes >= 60 && minutes % 60 == 0 ? tr("\(minutes / 60) 小时") : tr("\(minutes) 分钟"))
    }

    /// "12:05" left, rounded up so it never reads 0:00 while still playing.
    public static func remaining(until end: Date, now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
                     : "\(m):\(String(format: "%02d", s))"
    }
}

/// A mono noise synthesiser, one sample at a time.
///
/// Pure arithmetic with its own seeded generator, so it runs on the audio
/// thread without allocating or locking anything of its own, and the tests
/// can render it on Linux and check what comes out.
public struct AmbientSynth: Sendable {
    public let sampleRate: Double

    /// What each sound is fading towards, 0...1.
    private var targets = [Float](repeating: 0, count: AmbientSound.allCases.count)
    /// What each sound is actually at; follows `targets` smoothly so a sound
    /// switched on or off fades instead of clicking.
    private var gains = [Float](repeating: 0, count: AmbientSound.allCases.count)
    private var masterTarget: Float = 0.5
    private var master: Float = 0.5
    private let glide: Float

    private var seed: UInt64

    // Pink noise (Paul Kellett's refined filter).
    private var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0
    private var p4: Float = 0, p5: Float = 0, p6: Float = 0
    // Brown noise: leaky integrated white.
    private var brownState: Float = 0

    // Rain: a hiss above a few hundred hertz and drops on top.
    private var rainLow: Float = 0
    private var dropEnv: Float = 0
    private var dropTone: Float = 0
    private let dropDecay: Float
    private let rainCut: Float
    private let windFloorCut: Float

    // Waves: a slow swell opening a low-pass filter.
    private var wavePhase: Double = 0
    private var waveRate: Double = 0.085
    private var waveLow: Float = 0
    private var waveLow2: Float = 0

    // Wind: band-limited noise under a wandering gust.
    private var windLow: Float = 0
    private var windLow2: Float = 0
    private var windFloor: Float = 0
    private var gust: Float = 0.5
    private var gustTarget: Float = 0.5
    private var gustCountdown = 0

    // Fire: a low roar and crackles.
    private var fireLow: Float = 0
    private var crackleEnv: Float = 0
    private let crackleDecay: Float

    public init(sampleRate: Double = 48_000, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.sampleRate = max(8_000, sampleRate)
        self.seed = seed == 0 ? 0x2545_F491_4F6C_DD1D : seed
        // About a third of a second to reach a new level.
        glide = Float(1 - exp(-1 / (self.sampleRate * 0.12)))
        dropDecay = Float(exp(-1 / (self.sampleRate * 0.006)))
        crackleDecay = Float(exp(-1 / (self.sampleRate * 0.0025)))
        rainCut = Self.coefficient(450, self.sampleRate)
        windFloorCut = Self.coefficient(90, self.sampleRate)
    }

    /// One-pole low-pass coefficient for a cutoff in hertz.
    static func coefficient(_ hertz: Double, _ rate: Double) -> Float {
        Float(1 - exp(-2 * Double.pi * hertz / rate))
    }

    // MARK: Controls

    /// Which sounds play, each at its own level (see `AmbientLevels`; a
    /// sound with no level plays at the default, which is the old fixed 1).
    /// Everything not listed fades out.
    public mutating func setSounds(_ sounds: [AmbientSound], levels: [AmbientSound: Int] = [:]) {
        let on = Set(sounds)
        for (index, sound) in AmbientSound.allCases.enumerated() {
            targets[index] = on.contains(sound) ? AmbientLevels.gain(AmbientLevels.level(sound, in: levels)) : 0
        }
    }

    /// 0...1.
    public mutating func setVolume(_ volume: Double) {
        masterTarget = Float(min(1, max(0, volume)))
    }

    /// The level `setVolume` last asked for, 0...1.
    public var volume: Double { Double(masterTarget) }

    /// Everything fades to silence; used before stopping so the end is soft.
    public mutating func fadeOut() {
        for index in targets.indices { targets[index] = 0 }
    }

    /// True once every sound has faded all the way out.
    public var isSilent: Bool {
        gains.allSatisfy { $0 < 0.0005 } && targets.allSatisfy { $0 == 0 }
    }

    // MARK: Rendering

    /// The next sample, in -1...1.
    public mutating func next() -> Float {
        master += (masterTarget - master) * glide
        var mix: Float = 0
        let white = noise()
        for index in gains.indices {
            gains[index] += (targets[index] - gains[index]) * glide
        }

        // The shared colours are always advanced so a sound switched on
        // later starts from a settled filter, not from zero.
        let pink = pinkNoise(white)
        brownState = (brownState + 0.02 * white) / 1.02
        let brown = brownState * 3.5

        if gains[0] > 0.0005 { mix += gains[0] * rain(white: white, pink: pink) }
        if gains[1] > 0.0005 { mix += gains[1] * waves(pink: pink) }
        if gains[2] > 0.0005 { mix += gains[2] * wind(white: white) }
        if gains[3] > 0.0005 { mix += gains[3] * fire(brown: brown) }
        if gains[4] > 0.0005 { mix += gains[4] * white * 0.32 }
        if gains[5] > 0.0005 { mix += gains[5] * pink * 0.55 }
        if gains[6] > 0.0005 { mix += gains[6] * brown * 0.7 }

        // A soft knee rather than a hard clip: several sounds at once can
        // sum past full scale, and a clip there is a crackle nobody chose.
        let driven = mix * master
        return driven / (1 + abs(driven) * 0.6)
    }

    /// Fills a buffer with consecutive samples.
    public mutating func render(into buffer: UnsafeMutableBufferPointer<Float>) {
        for index in buffer.indices { buffer[index] = next() }
    }

    // MARK: Voices

    private mutating func rain(white: Float, pink: Float) -> Float {
        rainLow += (pink - rainLow) * rainCut
        let hiss = (pink - rainLow) * 0.9
        // Roughly 60 drops a second, each a few milliseconds of brighter noise.
        if uniform() < Float(60 / sampleRate) {
            dropEnv = max(dropEnv, 0.25 + 0.75 * uniform())
        }
        dropEnv *= dropDecay
        dropTone += (white - dropTone) * 0.5
        return hiss + dropEnv * (white - dropTone) * 0.9
    }

    private mutating func waves(pink: Float) -> Float {
        wavePhase += waveRate / sampleRate
        if wavePhase >= 1 {
            wavePhase -= 1
            // Each swell a little longer or shorter than the last.
            waveRate = 0.06 + 0.05 * Double(uniform())
        }
        let swell = Float(0.5 - 0.5 * cos(2 * Double.pi * wavePhase))
        let shaped = swell * swell
        let cutoff = 180 + 1_400 * Double(shaped)
        let a = Self.coefficient(cutoff, sampleRate)
        waveLow += (pink - waveLow) * a
        waveLow2 += (waveLow - waveLow2) * a
        return waveLow2 * (0.15 + 1.5 * shaped)
    }

    private mutating func wind(white: Float) -> Float {
        if gustCountdown <= 0 {
            gustTarget = 0.2 + 0.8 * uniform()
            gustCountdown = Int(sampleRate * Double(1.5 + 3 * uniform()))
        }
        gustCountdown -= 1
        gust += (gustTarget - gust) * Float(1 / (sampleRate * 1.2))
        let a = Self.coefficient(250 + 650 * Double(gust), sampleRate)
        windLow += (white - windLow) * a
        windLow2 += (windLow - windLow2) * a
        windFloor += (windLow2 - windFloor) * windFloorCut
        return (windLow2 - windFloor) * (0.6 + 1.6 * gust)
    }

    private mutating func fire(brown: Float) -> Float {
        fireLow += (brown - fireLow) * 0.08
        if uniform() < Float(9 / sampleRate) {
            crackleEnv = 0.3 + 0.7 * uniform()
        } else if uniform() < Float(40 / sampleRate) {
            crackleEnv = max(crackleEnv, 0.08 + 0.15 * uniform())
        }
        crackleEnv *= crackleDecay
        return fireLow * 0.55 + crackleEnv * noise() * 0.9
    }

    // MARK: Noise

    private mutating func pinkNoise(_ w: Float) -> Float {
        p0 = 0.99886 * p0 + w * 0.0555179
        p1 = 0.99332 * p1 + w * 0.0750759
        p2 = 0.96900 * p2 + w * 0.1538520
        p3 = 0.86650 * p3 + w * 0.3104856
        p4 = 0.55000 * p4 + w * 0.5329522
        p5 = -0.7616 * p5 - w * 0.0168980
        let out = (p0 + p1 + p2 + p3 + p4 + p5 + p6 + w * 0.5362) * 0.11
        p6 = w * 0.115926
        return out
    }

    /// xorshift64*: fast, allocation-free and good enough for noise.
    private mutating func bits() -> UInt64 {
        seed ^= seed >> 12
        seed ^= seed << 25
        seed ^= seed >> 27
        return seed &* 0x2545_F491_4F6C_DD1D
    }

    /// 0..<1.
    private mutating func uniform() -> Float {
        Float(bits() >> 40) / Float(1 << 24)
    }

    /// -1..<1.
    private mutating func noise() -> Float {
        uniform() * 2 - 1
    }
}
