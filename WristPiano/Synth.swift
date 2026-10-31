import AVFoundation
import os

/// 手表本地发声的小合成器：几个泛音叠加，加指数衰减，听起来接近拨弦 / 电钢琴。
/// 在手表上直接出声，避免走蓝牙到 iPhone 多出的几十毫秒延迟。
final class Synth {
    private struct Voice {
        var frequency: Double
        var amplitude: Double
        var phase: Double = 0
        var age: Double = 0
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var voices: [Voice] = []
    private var lock = os_unfair_lock()
    private let maxVoices = 8
    private var sampleRate: Double = 44_100

    func start() {
        guard !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // 默认 policy 允许从手表扬声器外放
            try session.setCategory(.playback, mode: .default, policy: .default, options: [])
            try session.setActive(true)
        } catch {
            print("AudioSession 失败: \(error)")
        }

        let format = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        sourceNode = AVAudioSourceNode(format: mono) { [unowned self] _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let out = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            self.render(into: out, frames: Int(frameCount))
            return noErr
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: mono)
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
        } catch {
            print("AudioEngine 启动失败: \(error)")
        }
    }

    func stop() {
        engine.stop()
    }

    func play(midi: Int, velocity: Double) {
        let freq = 440 * pow(2, Double(midi - 69) / 12)
        os_unfair_lock_lock(&lock)
        if voices.count >= maxVoices { voices.removeFirst() }
        voices.append(Voice(frequency: freq, amplitude: 0.25 * velocity))
        os_unfair_lock_unlock(&lock)
    }

    private func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1 / sampleRate
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for i in 0..<frames {
            var sum = 0.0
            for v in voices.indices {
                let age = voices[v].age
                let attack = min(1, age / 0.004)
                let env = attack * exp(-age * 3.5)
                let p = voices[v].phase
                let tone = sin(p) + 0.45 * sin(2 * p) * exp(-age * 2) + 0.2 * sin(3 * p) * exp(-age * 4)
                sum += voices[v].amplitude * env * tone
                voices[v].phase += 2 * .pi * voices[v].frequency * dt
                if voices[v].phase > 2 * .pi { voices[v].phase -= 2 * .pi }
                voices[v].age += dt
            }
            out[i] = Float(tanh(sum))
        }
        voices.removeAll { $0.age > 2.5 }
    }
}
