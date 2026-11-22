import XCTest

/// 合成环境音做细以后的几条底线：起音没有爆音、高频柔化过、慢速起伏有但不成周期、
/// 参数本身合理。渲染用 16 kHz，CI 上几十秒的声音也很快。
final class AmbientVoicingTests: XCTestCase {
    private func render(_ sounds: [AmbientSound], seconds: Double, rate: Double = 16_000,
                        seed: UInt64 = 7, fadeIn: Bool = false) -> [Float] {
        var synth = AmbientSynth(sampleRate: rate, seed: seed)
        synth.setVolume(1)
        synth.setSounds(sounds)
        if fadeIn {
            synth.setFade(0)
            synth.fade(to: 1, over: AmbientFade.fadeIn)
        }
        return (0..<Int(rate * seconds)).map { _ in synth.next() }
    }

    private func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
    }

    /// 相邻采样差的平均值和 RMS 之比：越大高频越多。独立均匀白噪声约 1.15。
    private func roughness(_ samples: [Float]) -> Float {
        var sum: Float = 0
        for index in 1..<samples.count { sum += abs(samples[index] - samples[index - 1]) }
        return sum / Float(samples.count - 1) / rms(samples)
    }

    // MARK: 参数

    func testFadesAreBetweenOneAndTwoSeconds() {
        for seconds in [AmbientFade.fadeIn, AmbientFade.fadeOut, AmbientFade.voice] {
            XCTAssertTrue((1...2).contains(seconds), "\(seconds)")
        }
        XCTAssertGreaterThan(AmbientFade.preview, AmbientFade.fadeIn + 1, "试听淡入后还能听一会儿")
    }

    func testVoicingRangesAreSane() {
        let ranges: [ClosedRange<Double>] = [
            AmbientVoicing.rainWashHigh, AmbientVoicing.rainNearDrops, AmbientVoicing.rainFarDrops,
            AmbientVoicing.rainNearTone, AmbientVoicing.rainFarTone, AmbientVoicing.waveLength,
            AmbientVoicing.waveBody, AmbientVoicing.windBody, AmbientVoicing.windHowl,
            AmbientVoicing.fireCrackles, AmbientVoicing.firePopTone, AmbientVoicing.firePopGap,
        ]
        for range in ranges { XCTAssertLessThan(range.lowerBound, range.upperBound) }
        XCTAssertLessThan(AmbientVoicing.airCutoff, 12_000, "总输出柔化高频")
        XCTAssertLessThan(AmbientVoicing.whiteCutoff, AmbientVoicing.airCutoff)
        XCTAssertGreaterThanOrEqual(AmbientVoicing.dropAttack, 0.0003, "雨滴和噼啪声有起音，不是咔哒")
        XCTAssertLessThan(AmbientVoicing.rainFarDecay.upperBound, AmbientVoicing.rainNearDecay.upperBound)
    }

    func testSwellShapeIsSmooth() {
        XCTAssertEqual(Swell.shape(0, rise: 0.4), 0)
        XCTAssertEqual(Swell.shape(0.4, rise: 0.4), 1, accuracy: 0.0001)
        XCTAssertEqual(Swell.shape(1, rise: 0.4), 0, accuracy: 0.0001)
        var last = Swell.shape(0, rise: 0.35)
        for step in 1...1_000 {
            let value = Swell.shape(Float(step) / 1_000, rise: 0.35)
            XCTAssertLessThan(abs(value - last), 0.01, "没有跳变")
            XCTAssertTrue((0...1).contains(value))
            last = value
        }
    }

    func testDriftStaysInRangeAndKeepsMoving() {
        var drift = DriftState(AmbientVoicing.windGust, seed: 11)
        var seen: [Float] = []
        for _ in 0..<6_000 { seen.append(drift.advance(seconds: 0.01)) }
        let range = AmbientVoicing.windGust.range
        XCTAssertTrue(seen.allSatisfy { range.contains($0) })
        XCTAssertGreaterThan(seen.max()! - seen.min()!, 0.2, "一分钟里阵风有起伏")
    }

    // MARK: 渲染

    func testEverySoundFadesInWithoutAPop() {
        for sound in AmbientSound.allCases {
            let out = render([sound], seconds: 2.5, fadeIn: true)
            let opening = out.prefix(Int(16_000 * 0.02)).map { abs($0) }.max() ?? 0
            let settled = rms(out.suffix(8_000))
            XCTAssertLessThan(opening, 0.005, "\(sound) 开头 20 毫秒应该几乎无声")
            XCTAssertGreaterThan(settled, 0.03, "\(sound) 淡入后听得见")
            XCTAssertTrue(out.allSatisfy { $0.isFinite && abs($0) < 1 }, "\(sound)")
        }
    }

    func testSoundsSitAtSimilarLoudness() {
        let levels = AmbientSound.allCases.map { rms(render([$0], seconds: 4).suffix(32_000)) }
        XCTAssertLessThan(levels.max()! / levels.min()!, 2.2, "换声音时不会忽大忽小：\(levels)")
    }

    func testWhiteNoiseHighsAreSoftened() {
        let out = render([.white], seconds: 1.5, rate: 48_000)
        XCTAssertLessThan(roughness(Array(out.suffix(48_000))), 0.9, "比原始白噪声（约 1.15）柔")
    }

    func testWavesAndWindRiseAndFallWithoutALoop() {
        for sound in [AmbientSound.waves, .wind] {
            let out = Array(render([sound], seconds: 40).dropFirst(32_000))
            // 每 0.25 秒一个响度值，看起伏和自相关。
            let window = 4_000
            let envelope = stride(from: 0, to: out.count - window + 1, by: window).map { rms(out[$0..<$0 + window]) }
            let seconds = stride(from: 0, to: envelope.count - 3, by: 4).map { envelope[$0..<$0 + 4].reduce(0, +) / 4 }
            XCTAssertGreaterThan(seconds.max()! / seconds.min()!, 1.4, "\(sound) 有慢速起伏")
            let mean = envelope.reduce(0, +) / Float(envelope.count)
            let centred = envelope.map { $0 - mean }
            let energy = centred.reduce(0) { $0 + $1 * $1 }
            // 4 到 20 秒的延迟上都不像自己：没有固定周期的循环。
            for lag in 16...80 {
                var sum: Float = 0
                for index in 0..<(centred.count - lag) { sum += centred[index] * centred[index + lag] }
                XCTAssertLessThan(sum / energy, 0.8, "\(sound) 在 \(Double(lag) / 4) 秒处像在循环")
            }
        }
    }

    func testRainAndFireHaveTransientsOnTopOfTheBed() {
        for sound in [AmbientSound.rain, .fire] {
            let out = Array(render([sound], seconds: 6).suffix(48_000))
            let peak = out.map { abs($0) }.max()!
            XCTAssertGreaterThan(peak / rms(out), 3.5, "\(sound) 有雨滴、噼啪这类短促的声音")
        }
    }

    func testSwitchingASoundOffFadesOverAboutASecond() {
        var synth = AmbientSynth(sampleRate: 16_000, seed: 3)
        synth.setVolume(1)
        synth.setSounds([.brown])
        for _ in 0..<32_000 { _ = synth.next() }
        synth.setSounds([])
        let tail = (0..<Int(16_000 * 0.4)).map { _ in synth.next() }
        XCTAssertGreaterThan(rms(tail.suffix(1_600)), 0.005, "0.4 秒时还没断")
        for _ in 0..<Int(16_000 * AmbientFade.voice) { _ = synth.next() }
        XCTAssertTrue(synth.isSilent)
    }

    func testVeryLowSampleRateStaysStable() {
        let out = render(AmbientSound.allCases, seconds: 3, rate: 8_000)
        XCTAssertTrue(out.allSatisfy { $0.isFinite && abs($0) < 1 })
    }
}
