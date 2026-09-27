import AVFoundation

/// Lightsaber effects synthesized at launch (detuned buzz + filtered noise), played on a small voice pool.
final class SaberSound {
    enum Kind: CaseIterable { case ignite, retract, clash, swing }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Kind: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0

    init() {
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        for k in Kind.allCases { buffers[k] = synthesize(k) }
    }

    func play(_ kind: Kind, volume: Double) {
        guard let buffer = buffers[kind] else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.volume = Float(max(0, min(1, volume)))
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    func shutdown() {
        players.forEach { $0.stop() }
        if engine.isRunning { engine.stop() }
    }

    private func synthesize(_ kind: Kind) -> AVAudioPCMBuffer? {
        let sr = 44_100.0
        let dur: Double
        switch kind {
        case .ignite: dur = 0.6
        case .retract: dur = 0.5
        case .clash: dur = 0.4
        case .swing: dur = 0.34
        }
        let n = Int(sr * dur)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)

        var seed: UInt32 = 0x9E37_79B9
        func noise() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 23) - 1
        }
        var phase1 = 0.0
        var phase2 = 0.0
        var humLP = 0.0
        var noiseLP = 0.0

        for i in 0..<n {
            let t = Double(i) / sr
            let u = t / dur
            var freq: Double
            var amp: Double
            var hiss: Double
            switch kind {
            case .ignite:
                freq = 50 + 62 * pow(u, 0.35)
                amp = min(1, t / 0.025) * (u < 0.6 ? 1 : 1 - (u - 0.6) / 0.4 * 0.75)
                hiss = max(0, 1 - t / 0.14) * 0.9
            case .retract:
                freq = 112 - 78 * u * u
                amp = pow(1 - u, 1.4)
                hiss = 0.12 * (1 - u)
            case .swing:
                let bump = sin(.pi * u)
                freq = 98 + 52 * bump
                amp = pow(bump, 1.3)
                hiss = 0.35 * bump
            case .clash:
                freq = 118
                amp = exp(-t * 7)
                hiss = exp(-t * 22) * 1.3
            }
            phase1 += freq / sr
            phase2 += freq * 1.009 / sr
            let saw1 = 2 * (phase1 - floor(phase1)) - 1
            let saw2 = 2 * (phase2 - floor(phase2)) - 1
            let raw = 0.55 * saw1 + 0.4 * saw2 + 0.3 * sin(2 * .pi * phase1 * 2)
            humLP += (raw - humLP) * 0.16
            noiseLP += (noise() - noiseLP) * 0.35
            var s = humLP * 1.6 * amp + noiseLP * hiss
            if kind == .clash {
                let ring = sin(2 * .pi * 1180 * t) + 0.6 * sin(2 * .pi * 2310 * t) + 0.4 * sin(2 * .pi * 3070 * t)
                s += ring * exp(-t * 16) * 0.35
                if noise() > 0.985 { s += noise() * exp(-t * 6) * 0.8 }
            }
            let edge = min(1, t / 0.004, (dur - t) / 0.02)
            out[i] = Float(tanh(s * 1.3) * 0.7 * edge)
        }
        return buf
    }
}
