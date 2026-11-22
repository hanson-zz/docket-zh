import Foundation

/// The sounds the ambient widget can mix.
///
/// Every one is synthesised from noise rather than played from a recording:
/// nothing to license, nothing to download, nothing that loops audibly every
/// thirty seconds, and the whole set costs no space in the app. 每种声音是几层合成叠起来的，
/// 见 `AmbientSynth` 和 `AmbientVoicing`。
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

/// 环境音淡入淡出的时长（秒）。专注开始、停下、试听、小组件播放暂停都用这一套，
/// 比收音机的 `AudioFade` 略长：噪声起得太快像爆音，停得太快像断电。
public enum AmbientFade {
    /// 整体淡入：开始专注、按播放、试听开头。
    public static let fadeIn: Double = 1.5
    /// 整体淡出：专注停下、按暂停、试听结尾。
    public static let fadeOut: Double = 1.5
    /// 某一种声音单独点亮或熄掉时，它自己从 0 走到满（或反过来）用的秒数（线性）。
    public static let voice: Double = 1.2
    /// 淡出走完之后再多等一会儿才放掉音频引擎，免得最后几毫秒被截断。
    public static let releaseMargin: Double = 0.15
    /// 专注面板里选了声音、专注还没开始时试听多久（含淡入淡出）。
    public static let preview: Double = 4.5
}

/// 合成器每种声音的参数：滤波的截止频率、雨滴和噼啪声的密度、慢速调制的范围和快慢。
///
/// 全是纯数字，`AmbientSynth` 照着用，测试也读它们。频率单位赫兹，时间单位秒。
/// 「慢速调制」是一个随机游走：每隔 `every` 秒（区间里随机）挑一个 `range` 里的新目标，
/// 用 `glide` 秒的时间常数滑过去，所以起伏没有固定周期，听不出循环。
public enum AmbientVoicing {
    public struct Drift: Sendable, Equatable {
        public var range: ClosedRange<Float>
        public var every: ClosedRange<Double>
        public var glide: Double
    }

    /// 控制量（调制、滤波系数）每隔这么多个采样更新一次，省下音频线程的算力。
    public static let controlInterval = 32
    /// 总输出最后过一道一阶低通，削掉耳朵最累的那段高频。
    public static let airCutoff: Double = 9_000
    /// 去直流：棕噪和低频叠多了会慢慢偏，扬声器上是一下闷响。
    public static let dcCutoff: Double = 16
    /// 合成器里滤波器最高用到采样率的这个比例（低采样率时防止滤波器失稳）。
    public static let maxCutoffRatio: Double = 0.16

    // 纯噪声：轻微的音量呼吸（约 ±1.4 dB），白噪再压掉刺耳的高频。
    public static let noiseBreath = Drift(range: 0.85...1, every: 8...20, glide: 5)
    public static let whiteCutoff: Double = 7_500
    public static let pinkCutoff: Double = 10_000

    // 雨：中频的沙沙声（雨势慢慢起伏），远处的低频闷响，近处稀疏清脆的大雨滴，远处密集的小雨滴。
    public static let rainIntensity = Drift(range: 0.55...1, every: 6...18, glide: 4)
    public static let rainWashLow: Double = 450
    public static let rainWashHigh: ClosedRange<Double> = 3_800...5_600
    public static let rainRumble: Double = 260
    public static let rainNearDrops: ClosedRange<Double> = 5...14
    public static let rainFarDrops: ClosedRange<Double> = 40...95
    public static let rainNearTone: ClosedRange<Double> = 2_200...5_500
    public static let rainFarTone: ClosedRange<Double> = 1_100...2_800
    public static let rainNearDecay: ClosedRange<Double> = 0.004...0.010
    public static let rainFarDecay: ClosedRange<Double> = 0.002...0.005
    /// 每滴雨的起音，太快就是咔哒声。
    public static let dropAttack: Double = 0.0006

    // 海浪：两层互相错开的浪，每道浪的长度、高度、涨落快慢都随机；浪头上有泡沫，底下一直有暗涌。
    public static let waveLength: ClosedRange<Double> = 6.5...12.5
    public static let waveHeight: ClosedRange<Float> = 0.55...1
    /// 一道浪里上涨占的比例，其余是退。
    public static let waveRise: ClosedRange<Float> = 0.3...0.45
    public static let waveBody: ClosedRange<Double> = 150...1_250
    public static let waveFoam: Double = 1_800
    public static let waveUndertow: Double = 120

    // 风：一层快的阵风（几秒一变），一层慢的风势（十几秒一变），大风时带一点呼啸。
    public static let windGust = Drift(range: 0.15...1, every: 1.5...5, glide: 1.2)
    public static let windSwell = Drift(range: 0.35...1, every: 10...26, glide: 6)
    public static let windBody: ClosedRange<Double> = 200...900
    public static let windFloor: Double = 90
    public static let windHowl: ClosedRange<Double> = 280...820
    /// 呼啸的带通 Q 值。
    public static let windHowlQ: Double = 4

    // 篝火：低沉的火声（火势慢慢变），火苗的快速闪动，一阵一阵的噼啪声（每阵 1 到 5 下），零星的小火星。
    public static let fireBody = Drift(range: 0.7...1, every: 5...15, glide: 4)
    public static let fireFlicker = Drift(range: 0.6...1, every: 0.25...1.1, glide: 0.2)
    public static let fireRoar: Double = 480
    public static let fireCrackles: ClosedRange<Double> = 2.5...7
    public static let fireEmbers: Double = 18
    public static let firePopsPerCrackle: ClosedRange<Int> = 1...5
    public static let firePopGap: ClosedRange<Double> = 0.003...0.028
    public static let firePopTone: ClosedRange<Double> = 1_800...5_000
    public static let firePopDecay: ClosedRange<Double> = 0.0008...0.003
    public static let fireHiss: Double = 3_000
    /// 雨滴、火星这类短促声音先过一道高通，去掉「噗」的低频。
    public static let clickHighPass: Double = 700
}

/// A mono ambience synthesiser, one sample at a time.
///
/// Pure arithmetic with its own seeded generator, so it runs on the audio
/// thread without allocating or locking anything of its own, and the tests
/// can render it on Linux and check what comes out.
///
/// 每种声音都是几层叠在一起的（见 `AmbientVoicing`），起伏靠随机游走的慢速调制，
/// 没有固定周期，所以没有可听出的循环；短促的雨滴和噼啪声都有约半毫秒的起音，
/// 总输出去直流、柔化高频、软削波，开关一种声音和整体淡入淡出都是 1 到 2 秒的平滑过渡。
public struct AmbientSynth: Sendable {
    public let sampleRate: Double

    /// What each sound is fading towards, 0...1.25.
    private var targets = [Float](repeating: 0, count: AmbientSound.allCases.count)
    /// What each sound is actually at; follows `targets` in a straight line
    /// over `AmbientFade.voice` seconds, so a sound switched on or off fades
    /// instead of clicking.
    private var gains = [Float](repeating: 0, count: AmbientSound.allCases.count)
    private let gainStep: Float
    private var masterTarget: Float = 0.5
    private var master: Float = 0.5
    private let glide: Float
    /// 淡入淡出的系数（`AudioFade` 的平滑阶梯之前的线性进度），1 是不淡。
    private var fadeLevel: Float = 1
    private var fadeTarget: Float = 1
    /// 每个采样走多少，走满 0 到 1 是 `fade(to:over:)` 给的秒数。
    private var fadeStep: Float = 1

    private var rng: AmbientRandom
    private var control = 0

    // Shared colours.
    private var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0
    private var p4: Float = 0, p5: Float = 0, p6: Float = 0
    private var brownState: Float = 0

    // Output conditioning.
    private var dc = OnePole()
    private var air = OnePole()
    private let dcCut: Float
    private let airCut: Float

    // Plain noises.
    private var breath: DriftState
    private var whiteLow = OnePole()
    private var pinkLow = OnePole()
    private let whiteCut: Float
    private let pinkCut: Float

    // Rain.
    private var rainIntensity: DriftState
    private var rainLowCut = OnePole()
    private var rainHighCut = OnePole()
    private var rainRumble = OnePole()
    private var nearDrop = Drop()
    private var farDrop = Drop()
    private let rainLowCoef: Float
    private let rainRumbleCoef: Float
    private var rainHighCoef: Float = 0.5
    private var nearRate: Float = 0
    private var farRate: Float = 0

    // Waves.
    private var swellA = Swell()
    private var swellB = Swell()
    private var waveLow = OnePole()
    private var waveLow2 = OnePole()
    private var foamLow = OnePole()
    private var undertow = OnePole()
    private var waveCoef: Float = 0.02
    private var waveLevel: Float = 0
    private var foamLevel: Float = 0
    private let foamCoef: Float
    private let undertowCoef: Float

    // Wind.
    private var gust: DriftState
    private var windSwell: DriftState
    private var windLow = OnePole()
    private var windLow2 = OnePole()
    private var windFloor = OnePole()
    private var howl = StateVariable()
    private var windCoef: Float = 0.03
    private var howlF: Float = 0.05
    private let howlDamping: Float
    private let windFloorCoef: Float
    private var windLevel: Float = 1
    private var howlLevel: Float = 0

    // Fire.
    private var fireBody: DriftState
    private var flicker: DriftState
    private var roar = OnePole()
    private var hissLow = OnePole()
    private var pop = Drop()
    private var ember = Drop()
    private let roarCoef: Float
    private let hissCoef: Float
    private var popsLeft = 0
    private var popGap = 0
    private var crackleRate: Float = 0

    private let clickCoef: Float

    public init(sampleRate: Double = 48_000, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        let rate = max(8_000, sampleRate)
        self.sampleRate = rate
        var rng = AmbientRandom(seed: seed)
        glide = Float(1 - exp(-1 / (rate * 0.12)))
        gainStep = Float(1 / (AmbientFade.voice * rate))
        func cut(_ hertz: Double) -> Float { AmbientSynth.coefficient(hertz, rate) }
        dcCut = cut(AmbientVoicing.dcCutoff)
        airCut = cut(AmbientVoicing.airCutoff)
        whiteCut = cut(AmbientVoicing.whiteCutoff)
        pinkCut = cut(AmbientVoicing.pinkCutoff)
        rainLowCoef = cut(AmbientVoicing.rainWashLow)
        rainRumbleCoef = cut(AmbientVoicing.rainRumble)
        foamCoef = cut(AmbientVoicing.waveFoam)
        undertowCoef = cut(AmbientVoicing.waveUndertow)
        windFloorCoef = cut(AmbientVoicing.windFloor)
        howlDamping = Float(1 / AmbientVoicing.windHowlQ)
        roarCoef = cut(AmbientVoicing.fireRoar)
        hissCoef = cut(AmbientVoicing.fireHiss)
        clickCoef = cut(AmbientVoicing.clickHighPass)
        breath = DriftState(AmbientVoicing.noiseBreath, seed: rng.split())
        rainIntensity = DriftState(AmbientVoicing.rainIntensity, seed: rng.split())
        gust = DriftState(AmbientVoicing.windGust, seed: rng.split())
        windSwell = DriftState(AmbientVoicing.windSwell, seed: rng.split())
        fireBody = DriftState(AmbientVoicing.fireBody, seed: rng.split())
        flicker = DriftState(AmbientVoicing.fireFlicker, seed: rng.split())
        // 两层浪错开：一层从中途开始，一层刚起，第一秒就听得到浪。
        var a = Swell(), b = Swell()
        a.begin(&rng, at: 0.35)
        b.begin(&rng, at: 0.85)
        swellA = a
        swellB = b
        self.rng = rng
    }

    /// One-pole low-pass coefficient for a cutoff in hertz.
    static func coefficient(_ hertz: Double, _ rate: Double) -> Float {
        let safe = min(max(hertz, 1), rate * 0.45)
        return Float(1 - exp(-2 * Double.pi * safe / rate))
    }

    /// 状态变量滤波器的频率系数，截止频率夹在 `maxCutoffRatio` 以内保证稳定。
    static func svfFrequency(_ hertz: Double, _ rate: Double) -> Float {
        let safe = min(max(hertz, 1), rate * AmbientVoicing.maxCutoffRatio)
        return Float(2 * sin(Double.pi * safe / rate))
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
        masterTarget = Float(min(1, max(0, volume.isFinite ? volume : 0)))
    }

    /// The level `setVolume` last asked for, 0...1.
    public var volume: Double { Double(masterTarget) }

    /// Every sound fades to silence over `AmbientFade.voice` seconds.
    public mutating func fadeOut() {
        for index in targets.indices { targets[index] = 0 }
    }

    /// 整体淡到 `target`（0...1），走满 0 到 1 用 `seconds` 秒，只走一半就只用一半的时间。
    /// 淡出一半又淡入，从那一半往回升。曲线见 `AudioFade.curve`。
    public mutating func fade(to target: Double, over seconds: Double) {
        fadeTarget = Float(AudioFade.clamp(target))
        fadeStep = seconds > 0 ? Float(1 / (seconds * sampleRate)) : 1
    }

    /// 直接把淡入淡出系数放到 `value`，淡入从 0 起时用。
    public mutating func setFade(_ value: Double) {
        fadeLevel = Float(AudioFade.clamp(value))
        fadeTarget = fadeLevel
    }

    /// 现在的淡入淡出进度，0...1（曲线之前）。
    public var fadeProgress: Double { Double(fadeLevel) }

    /// True once every sound has faded all the way out.
    public var isSilent: Bool {
        gains.allSatisfy { $0 < 0.0005 } && targets.allSatisfy { $0 == 0 }
    }

    // MARK: Rendering

    /// The next sample, in -1...1.
    public mutating func next() -> Float {
        if control == 0 {
            updateControls()
            control = AmbientVoicing.controlInterval
        }
        control -= 1
        master += (masterTarget - master) * glide
        for index in gains.indices where gains[index] != targets[index] {
            let g = gains[index], t = targets[index]
            gains[index] = g < t ? min(t, g + gainStep) : max(t, g - gainStep)
        }

        // The shared colours are always advanced so a sound switched on
        // later starts from a settled filter, not from zero.
        let white = rng.noise()
        let pink = pinkNoise(white)
        brownState = (brownState + 0.02 * white) / 1.02
        let brown = brownState * 3.5

        var mix: Float = 0
        if gains[0] > 0 { mix += gains[0] * rain(white: white, pink: pink, brown: brown) }
        if gains[1] > 0 { mix += gains[1] * waves(pink: pink, brown: brown) }
        if gains[2] > 0 { mix += gains[2] * wind(white: white) }
        if gains[3] > 0 { mix += gains[3] * fire(pink: pink, brown: brown) }
        if gains[4] > 0 { mix += gains[4] * whiteLow.low(white, whiteCut) * 0.32 * breath.value }
        if gains[5] > 0 { mix += gains[5] * pinkLow.low(pink, pinkCut) * 0.7 * breath.value }
        if gains[6] > 0 { mix += gains[6] * brown * 0.7 * breath.value }

        // 去直流、柔化高频，都在淡入淡出之前：淡到 0 时输出就是真的 0。
        let centred = mix - dc.low(mix, dcCut)
        let soft = air.low(centred, airCut)

        if fadeLevel != fadeTarget {
            fadeLevel = fadeLevel < fadeTarget ? min(fadeTarget, fadeLevel + fadeStep)
                                               : max(fadeTarget, fadeLevel - fadeStep)
        }
        let shaped = fadeLevel >= 1 ? 1 : Float(AudioFade.curve(Double(fadeLevel)))
        // A soft knee rather than a hard clip: several sounds at once can
        // sum past full scale, and a clip there is a crackle nobody chose.
        // x / (1 + |x|) 严格落在 -1...1 里，斜率处处连续。
        let driven = soft * master * shaped
        return driven / (1 + abs(driven))
    }

    /// Fills a buffer with consecutive samples.
    public mutating func render(into buffer: UnsafeMutableBufferPointer<Float>) {
        for index in buffer.indices { buffer[index] = next() }
    }

    // MARK: Control rate

    /// 每 `controlInterval` 个采样一次：走慢速调制，重算跟着它变的滤波系数和密度。
    private mutating func updateControls() {
        let step = Double(AmbientVoicing.controlInterval) / sampleRate
        breath.advance(seconds: step)
        if gains[0] > 0 || targets[0] > 0 {
            let i = rainIntensity.advance(seconds: step)
            rainHighCoef = Self.coefficient(Self.lerp(AmbientVoicing.rainWashHigh, Double(i)), sampleRate)
            nearRate = Float(Self.lerp(AmbientVoicing.rainNearDrops, Double(i)) / sampleRate)
            farRate = Float(Self.lerp(AmbientVoicing.rainFarDrops, Double(i)) / sampleRate)
        }
        if gains[1] > 0 || targets[1] > 0 {
            // 随机源先拷出来再传，避免同时对 self 的两个属性做 inout 访问。
            var random = rng
            let a = swellA.advance(seconds: step, rng: &random)
            let b = swellB.advance(seconds: step, rng: &random)
            rng = random
            let swell = min(1.2, 0.62 * (a + b))
            let open = Double(pow(swell / 1.2, 1.5))
            waveCoef = Self.coefficient(Self.lerp(AmbientVoicing.waveBody, open), sampleRate)
            waveLevel = 0.2 + 1.25 * swell
            let crest = max(0, swell - 0.5)
            foamLevel = crest * crest * 1.6
        }
        if gains[2] > 0 || targets[2] > 0 {
            let g = gust.advance(seconds: step) * windSwell.advance(seconds: step)
            windCoef = Self.coefficient(Self.lerp(AmbientVoicing.windBody, Double(g)), sampleRate)
            howlF = Self.svfFrequency(Self.lerp(AmbientVoicing.windHowl, Double(g)), sampleRate)
            windLevel = 0.55 + 1.5 * g
            howlLevel = 0.1 * g * g
        }
        if gains[3] > 0 || targets[3] > 0 {
            let body = fireBody.advance(seconds: step)
            flicker.advance(seconds: step)
            crackleRate = Float(Self.lerp(AmbientVoicing.fireCrackles, Double((body - 0.7) / 0.3)) / sampleRate)
        }
    }

    static func lerp(_ range: ClosedRange<Double>, _ t: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * min(1, max(0, t))
    }

    // MARK: Voices

    private mutating func rain(white: Float, pink: Float, brown: Float) -> Float {
        let intensity = rainIntensity.value
        // 中频沙沙声：粉噪去掉 450 赫兹以下，再按雨势收一点高频。
        let lifted = pink - rainLowCut.low(pink, rainLowCoef)
        let wash = rainHighCut.low(lifted, rainHighCoef) * (0.62 + 0.38 * intensity)
        let rumble = rainRumble.low(brown, rainRumbleCoef) * 0.22
        var random = rng
        if random.uniform() < nearRate {
            let amplitude = 0.3 + 0.5 * random.uniform()
            nearDrop.trigger(amplitude: amplitude, tone: AmbientVoicing.rainNearTone,
                             decay: AmbientVoicing.rainNearDecay, rng: &random, rate: sampleRate)
        }
        if random.uniform() < farRate {
            let amplitude = 0.08 + 0.18 * random.uniform()
            farDrop.trigger(amplitude: amplitude, tone: AmbientVoicing.rainFarTone,
                            decay: AmbientVoicing.rainFarDecay, rng: &random, rate: sampleRate)
        }
        rng = random
        let drops = nearDrop.next(white, click: clickCoef) + farDrop.next(white, click: clickCoef)
        return wash * 1.05 + rumble + drops * 0.9
    }

    private mutating func waves(pink: Float, brown: Float) -> Float {
        let body = waveLow2.low(waveLow.low(pink, waveCoef), waveCoef) * waveLevel
        let hiss = pink - foamLow.low(pink, foamCoef)
        let foam = hiss * foamLevel * 0.5
        let deep = undertow.low(brown, undertowCoef) * 0.3
        return body * 1.1 + foam + deep
    }

    private mutating func wind(white: Float) -> Float {
        let low = windLow2.low(windLow.low(white, windCoef), windCoef)
        let floor = windFloor.low(low, windFloorCoef)
        let band = howl.band(white, f: howlF, damping: howlDamping)
        return ((low - floor) * windLevel + band * howlLevel) * 1.8
    }

    private mutating func fire(pink: Float, brown: Float) -> Float {
        let body = fireBody.value, flame = flicker.value
        let roarOut = roar.low(brown, roarCoef) * 0.62 * body * flame
        let hiss = (pink - hissLow.low(pink, hissCoef)) * 0.05 * flame
        // 一阵噼啪：先响最大的一下，后面几下越来越小，间隔随机。
        var random = rng
        let pops = AmbientVoicing.firePopsPerCrackle
        if popsLeft == 0, random.uniform() < crackleRate {
            popsLeft = min(pops.upperBound, pops.lowerBound + Int(random.uniform() * Float(pops.count)))
            popGap = 0
        }
        if popsLeft > 0 {
            if popGap <= 0 {
                let weight = 0.45 + 0.55 * Float(popsLeft) / Float(pops.upperBound)
                let amplitude = (0.35 + 0.6 * random.uniform()) * weight
                pop.trigger(amplitude: amplitude, tone: AmbientVoicing.firePopTone,
                            decay: AmbientVoicing.firePopDecay, rng: &random, rate: sampleRate)
                popsLeft -= 1
                popGap = Int(Self.lerp(AmbientVoicing.firePopGap, Double(random.uniform())) * sampleRate)
            } else {
                popGap -= 1
            }
        }
        if random.uniform() < Float(AmbientVoicing.fireEmbers / sampleRate) {
            let amplitude = 0.04 + 0.08 * random.uniform()
            ember.trigger(amplitude: amplitude, tone: AmbientVoicing.firePopTone,
                          decay: AmbientVoicing.firePopDecay, rng: &random, rate: sampleRate)
        }
        rng = random
        let noise = rng.noise()
        let crackle = (pop.next(noise, click: clickCoef) + ember.next(noise, click: clickCoef)) * 1.1
        return (roarOut + hiss + crackle) * 1.25
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
}

// MARK: - Building blocks

/// xorshift64*：快、不分配内存，做噪声够用。
struct AmbientRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x2545_F491_4F6C_DD1D : seed
    }

    mutating func bits() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// 0..<1.
    mutating func uniform() -> Float {
        Float(bits() >> 40) / Float(1 << 24)
    }

    /// -1..<1.
    mutating func noise() -> Float {
        uniform() * 2 - 1
    }

    /// 给另一个独立的随机源用的种子（splitmix64 打散，永不为 0）。
    mutating func split() -> UInt64 {
        var z = bits() &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return z == 0 ? 1 : z
    }
}

/// 一阶低通，`low` 返回低通后的值；高通就是输入减去它。
struct OnePole: Sendable {
    var y: Float = 0

    mutating func low(_ x: Float, _ a: Float) -> Float {
        y += (x - y) * a
        return y
    }
}

/// Chamberlin 状态变量滤波器，这里只取带通。
struct StateVariable: Sendable {
    var lowState: Float = 0
    var bandState: Float = 0

    mutating func band(_ x: Float, f: Float, damping: Float) -> Float {
        lowState += f * bandState
        let high = x - lowState - damping * bandState
        bandState += f * high
        return bandState
    }
}

/// 慢速随机调制（见 `AmbientVoicing.Drift`），自带随机源。
struct DriftState: Sendable {
    let spec: AmbientVoicing.Drift
    private(set) var value: Float
    private var target: Float
    private var countdown: Double = 0
    private var rng: AmbientRandom

    init(_ spec: AmbientVoicing.Drift, seed: UInt64) {
        self.spec = spec
        rng = AmbientRandom(seed: seed)
        let start = spec.range.lowerBound + (spec.range.upperBound - spec.range.lowerBound) * rng.uniform()
        value = start
        target = start
    }

    @discardableResult
    mutating func advance(seconds: Double) -> Float {
        countdown -= seconds
        if countdown <= 0 {
            let span = spec.range.upperBound - spec.range.lowerBound
            target = spec.range.lowerBound + span * rng.uniform()
            countdown = AmbientSynth.lerp(spec.every, Double(rng.uniform()))
        }
        let k = Float(1 - exp(-seconds / max(0.01, spec.glide)))
        value += (target - value) * k
        return value
    }
}

/// 一道浪：长度、高度、涨的比例都随机，涨用平滑阶梯，退得慢一些。走完自己接下一道。
struct Swell: Sendable {
    private var phase: Double = 0
    private var length: Double = 9
    private var height: Float = 0.8
    private var rise: Float = 0.4

    mutating func begin(_ rng: inout AmbientRandom, at start: Double = 0) {
        length = AmbientSynth.lerp(AmbientVoicing.waveLength, Double(rng.uniform()))
        let heights = AmbientVoicing.waveHeight, rises = AmbientVoicing.waveRise
        height = heights.lowerBound + (heights.upperBound - heights.lowerBound) * rng.uniform()
        rise = rises.lowerBound + (rises.upperBound - rises.lowerBound) * rng.uniform()
        phase = start
    }

    /// 这一刻的浪高，0...1。
    mutating func advance(seconds: Double, rng: inout AmbientRandom) -> Float {
        phase += seconds / length
        if phase >= 1 { begin(&rng) }
        return Self.shape(Float(phase), rise: rise) * height
    }

    /// 0 到 `rise` 平滑涨到 1，之后退回 0（退的曲线带个弧度，像浪拍完往回拖）。
    static func shape(_ p: Float, rise: Float) -> Float {
        let p = min(max(p, 0), 1)
        if p < rise {
            let t = p / rise
            return t * t * (3 - 2 * t)
        }
        let t = (p - rise) / (1 - rise)
        let s = 1 - t * t * (3 - 2 * t)
        return s * (0.6 + 0.4 * s)
    }
}

/// 一下短促的声音（雨滴、火星、噼啪）：约半毫秒的线性起音，然后指数衰减；音色是
/// 一段低通后的噪声，再高通去掉低频的「噗」。起音不是 0 毫秒，所以不会有咔哒声。
struct Drop: Sendable {
    private var env: Float = 0
    private var rising = 0
    private var riseStep: Float = 0
    private var decay: Float = 0.99
    private var tone: Float = 0.3
    private var lowPass = OnePole()
    private var highPass = OnePole()

    mutating func trigger(amplitude: Float, tone range: ClosedRange<Double>, decay span: ClosedRange<Double>,
                          rng: inout AmbientRandom, rate: Double) {
        let peak = max(env, amplitude)
        let attack = max(2, Int(AmbientVoicing.dropAttack * rate))
        rising = attack
        riseStep = (peak - env) / Float(attack)
        tone = AmbientSynth.coefficient(AmbientSynth.lerp(range, Double(rng.uniform())), rate)
        let seconds = AmbientSynth.lerp(span, Double(rng.uniform()))
        decay = Float(exp(-1 / (rate * seconds)))
    }

    mutating func next(_ noise: Float, click: Float) -> Float {
        if rising > 0 {
            env += riseStep
            rising -= 1
        } else {
            env *= decay
            if env < 1e-6 { env = 0 }
        }
        let shaped = lowPass.low(noise, tone)
        let bright = shaped - highPass.low(shaped, click)
        return env * bright
    }
}
