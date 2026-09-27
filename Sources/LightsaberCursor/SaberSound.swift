import AVFoundation

/// Sound sources, in priority order:
/// 1. `~/Library/Application Support/Lightsaber Cursor/Sounds/{hum,ignite,retract,swing,clash}.wav` (any format AVAudioFile reads)
/// 2. The bundled recorded `hum.wav`; ignite, retract and swing are derived from it by pitch-sweeping the hum
/// 3. Synthesized fallbacks
final class SaberSound {
    static var overrideDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lightsaber Cursor/Sounds", isDirectory: true)
    }

    enum Kind: CaseIterable { case ignite, retract, clash, swing }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var pitchUnits: [AVAudioUnitVarispeed] = []
    private var buffers: [Kind: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0

    private let humPlayer = AVAudioPlayerNode()
    private let humPitch = AVAudioUnitVarispeed()
    private var humBuffer: AVAudioPCMBuffer?
    private var humPlaying = false

    init() {
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            let v = AVAudioUnitVarispeed()
            engine.attach(p)
            engine.attach(v)
            engine.connect(p, to: v, format: format)
            engine.connect(v, to: engine.mainMixerNode, format: format)
            players.append(p)
            pitchUnits.append(v)
        }
        engine.attach(humPlayer)
        engine.attach(humPitch)
        engine.connect(humPlayer, to: humPitch, format: format)
        engine.connect(humPitch, to: engine.mainMixerNode, format: format)
        let hum = loadSamples("hum")
        humBuffer = hum.flatMap { makeBuffer($0) } ?? synthesizeHum()
        for k in Kind.allCases {
            if let own = loadSamples(k.fileName, bundled: false) {
                buffers[k] = makeBuffer(own)
            } else if let hum, let derived = derive(k, from: hum) {
                buffers[k] = makeBuffer(derived)
            } else {
                buffers[k] = synthesize(k)
            }
        }
    }

    // MARK: Recorded sources

    private func loadSamples(_ name: String, bundled: Bool = true) -> [Float]? {
        let override = Self.overrideDirectory
        let candidates = ["wav", "aif", "aiff", "m4a", "mp3", "caf"].map { override.appendingPathComponent("\(name).\($0)") }
        let url = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? (bundled ? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") : nil)
        guard let url, let file = try? AVAudioFile(forReading: url),
              let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: src)) != nil else { return nil }
        if file.processingFormat.sampleRate == format.sampleRate && file.processingFormat.channelCount == 1,
           let ch = src.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: ch, count: Int(src.frameLength)))
        }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else { return nil }
        let ratio = format.sampleRate / file.processingFormat.sampleRate
        guard let dst = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(src.frameLength) * ratio) + 1024) else { return nil }
        var fed = false
        var err: NSError?
        converter.convert(to: dst, error: &err) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return src
        }
        guard err == nil, let ch = dst.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(dst.frameLength)))
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: samples.count) }
        return buf
    }

    /// Reads through the looping hum at a time-varying rate (pitch) and gain, like a tape being sped up or slowed down.
    private func sweep(_ hum: [Float], seconds: Double, rate: (Double) -> Double, gain: (Double) -> Double) -> [Float] {
        let n = Int(format.sampleRate * seconds)
        var out = [Float](repeating: 0, count: n)
        var pos = Double(hum.count / 3)
        for i in 0..<n {
            let u = Double(i) / Double(n)
            let i0 = Int(pos) % hum.count
            let i1 = (i0 + 1) % hum.count
            let f = Float(pos - floor(pos))
            out[i] = (hum[i0] * (1 - f) + hum[i1] * f) * Float(gain(u))
            pos += rate(u)
        }
        return out
    }

    private func derive(_ kind: Kind, from hum: [Float]) -> [Float]? {
        switch kind {
        case .ignite:
            // Starts low and snaps up to full pitch, with a short bright swell.
            return sweep(hum, seconds: 0.7,
                         rate: { u in 0.3 + 0.7 * min(1, pow(u / 0.55, 0.6)) + 0.12 * sin(.pi * min(1, u / 0.55)) },
                         gain: { u in min(1, u / 0.03) * (0.75 + 0.35 * sin(.pi * min(1, u / 0.6))) * (u > 0.85 ? 1 - (u - 0.85) / 0.15 * 0.4 : 1) })
        case .retract:
            return sweep(hum, seconds: 0.55,
                         rate: { u in 1.0 - 0.72 * pow(u, 1.3) },
                         gain: { u in 0.85 * pow(1 - u, 1.2) * min(1, (1 - u) / 0.02) })
        case .swing:
            return sweep(hum, seconds: 0.42,
                         rate: { u in 1 + 0.4 * sin(.pi * u) },
                         gain: { u in 0.35 + 0.75 * pow(sin(.pi * u), 1.4) })
        case .clash:
            return nil
        }
    }


    func bufferFor(_ kind: Kind) -> AVAudioPCMBuffer? { buffers[kind] }
    var humLoopBuffer: AVAudioPCMBuffer? { humBuffer }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do { try engine.start() } catch { return false }
        return true
    }

    /// `rate` 1 = original pitch; higher plays faster and higher.
    func play(_ kind: Kind, volume: Double, rate: Double = 1) {
        guard let buffer = buffers[kind], ensureRunning() else { return }
        let i = nextPlayer
        nextPlayer = (nextPlayer + 1) % players.count
        let p = players[i]
        p.stop()
        pitchUnits[i].rate = Float(max(0.25, min(4, rate)))
        p.volume = Float(max(0, min(1, volume)))
        p.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    /// Continuous hum whose pitch tracks cursor speed; call every frame.
    func updateHum(active: Bool, rate: Double, volume: Double) {
        if active {
            guard let humBuffer, ensureRunning() else { return }
            if !humPlaying {
                humPlayer.volume = 0
                humPlayer.scheduleBuffer(humBuffer, at: nil, options: .loops, completionHandler: nil)
                humPlayer.play()
                humPlaying = true
            }
            humPitch.rate = Float(max(0.25, min(4, rate)))
            humPlayer.volume = Float(max(0, min(1, volume)))
        } else if humPlaying {
            humPlayer.stop()
            humPlaying = false
        }
    }

    func shutdown() {
        players.forEach { $0.stop() }
        humPlayer.stop()
        humPlaying = false
        if engine.isRunning { engine.stop() }
    }

    /// One second of detuned buzz with whole-number cycles for every partial, so it loops seamlessly.
    private func synthesizeHum() -> AVAudioPCMBuffer? {
        let sr = 44_100.0
        let n = Int(sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        var lp = 0.0
        func sample(_ t: Double) -> Double {
            let saw1 = 2 * (90 * t - floor(90 * t)) - 1
            let saw2 = 2 * (91 * t - floor(91 * t)) - 1
            let wobble = 1 + 0.12 * sin(2 * .pi * 3 * t)
            return (0.5 * saw1 + 0.4 * saw2 + 0.3 * sin(2 * .pi * 180 * t)) * wobble
        }
        for i in 0..<n { lp += (sample(Double(i) / sr) - lp) * 0.14 }
        for i in 0..<n {
            lp += (sample(Double(i) / sr) - lp) * 0.14
            out[i] = Float(tanh(lp * 1.8) * 0.6)
        }
        return buf
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

extension SaberSound.Kind {
    var fileName: String {
        switch self {
        case .ignite: "ignite"
        case .retract: "retract"
        case .clash: "clash"
        case .swing: "swing"
        }
    }
}

extension SaberSound {
    /// Debug aid: `LightsaberCursor --export-sounds <dir>` writes every effect buffer as WAV.
    func export(to dir: String) {
        var all: [(String, AVAudioPCMBuffer?)] = Kind.allCases.map { ($0.fileName, bufferFor($0)) }
        all.append(("hum", humLoopBuffer))
        for (name, buf) in all {
            guard let buf else { continue }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).wav")
            if let f = try? AVAudioFile(forWriting: url, settings: buf.format.settings) {
                try? f.write(from: buf)
            }
        }
    }
}
