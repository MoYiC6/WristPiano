import Foundation
import Observation
import WatchKit

enum PlayMode: String, CaseIterable, Identifiable {
    /// 手腕左右转动选音，任意手指敲击发声
    case wristZone
    /// 识别哪根手指敲击，五指对应 C D E F G（需先校准）
    case finger
    var id: String { rawValue }

    var title: String {
        switch self {
        case .wristZone: "转腕选音"
        case .finger: "手指识别"
        }
    }
}

@Observable
final class PianoModel: NSObject, WKExtendedRuntimeSessionDelegate {
    // MARK: 界面状态
    var isRunning = false
    var mode: PlayMode = .wristZone
    var sensitivity: Double = 1.0
    var invertYaw = false
    var hapticOnTap = false

    var lastNoteName = "–"
    var lastVelocity = 0.0
    var lastFinger: Finger?
    var lastConfidence = 0.0
    /// 初始在中间音区，和未归中时 zoneIndex 的返回值一致
    var currentZone = 4
    var jerkLevel = 0.0
    var tapCount = 0

    /// 不为 nil 时，下一次敲击记为该手指的校准样本
    var calibratingFinger: Finger?
    private(set) var classifier = FingerClassifier.load()

    // MARK: 音阶
    /// C4 到 C5 的 C 大调
    let scale = [60, 62, 64, 65, 67, 69, 71, 72]
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    /// 每个音区占的偏航角
    let zoneWidth = 10.0 * .pi / 180

    // MARK: 内部（运动队列也会读写，不参与界面观察）
    @ObservationIgnored private let motion = MotionSource()
    @ObservationIgnored private let detector = TapDetector()
    @ObservationIgnored private let synth = Synth()
    @ObservationIgnored private var runtimeSession: WKExtendedRuntimeSession?
    @ObservationIgnored private var yawReference: Double?
    @ObservationIgnored private var latestYaw = 0.0
    @ObservationIgnored private var lastUIUpdate: TimeInterval = 0

    var motionAvailable: Bool { motion.isAvailable }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        detector.reset()
        detector.sensitivity = sensitivity
        yawReference = nil
        synth.start()
        startRuntimeSession()
        motion.start { [weak self] sample in
            self?.handle(sample)
        }
    }

    func stop() {
        isRunning = false
        motion.stop()
        synth.stop()
        runtimeSession?.invalidate()
        runtimeSession = nil
    }

    /// 把当前手腕朝向设为中间音区
    func recenter() {
        yawReference = latestYaw
    }

    func setSensitivity(_ value: Double) {
        sensitivity = value
        detector.sensitivity = value
    }

    func clearCalibration(_ finger: Finger? = nil) {
        classifier.clear(finger)
        classifier.save()
    }

    func sampleCount(for finger: Finger) -> Int { classifier.count(for: finger) }

    /// 模拟器没有运动传感器，用按钮模拟一次敲击
    func simulateTap() {
        if !isRunning { synth.start() }
        let fake = TapEvent(time: 0, velocity: 0.8, yaw: latestYaw, features: [])
        DispatchQueue.main.async { self.onTap(fake) }
    }

    // MARK: - 数据处理（运动队列上）

    private func handle(_ s: MotionSample) {
        if yawReference == nil { yawReference = s.yaw }
        latestYaw = s.yaw
        let tap = detector.process(s)
        let zone = zoneIndex(for: s.yaw)

        // 界面刷新限制到约 20Hz，敲击事件立即处理
        let jerk = detector.lastJerk
        if s.time - lastUIUpdate > 0.05 || tap != nil {
            lastUIUpdate = s.time
            DispatchQueue.main.async {
                self.jerkLevel = jerk
                self.currentZone = zone
                if let tap { self.onTap(tap) }
            }
        }
    }

    private func zoneIndex(for yaw: Double) -> Int {
        guard let ref = yawReference else { return scale.count / 2 }
        var delta = yaw - ref
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        if invertYaw { delta = -delta }
        let center = scale.count / 2
        let idx = center + Int((delta / zoneWidth).rounded())
        return min(max(idx, 0), scale.count - 1)
    }

    // MARK: - 敲击（主线程）

    private func onTap(_ tap: TapEvent) {
        if let finger = calibratingFinger {
            guard !tap.features.isEmpty else { return }
            classifier.add(tap.features, for: finger)
            classifier.save()
            synth.play(midi: scale[finger.rawValue], velocity: 0.5)
            if classifier.count(for: finger) >= FingerClassifier.samplesPerFinger {
                calibratingFinger = nil
                WKInterfaceDevice.current().play(.success)
            }
            return
        }

        let midi: Int
        switch mode {
        case .wristZone:
            midi = scale[zoneIndex(for: tap.yaw)]
            lastFinger = nil
        case .finger:
            guard let result = classifier.predict(tap.features) else {
                lastNoteName = "先校准"
                return
            }
            midi = scale[result.finger.rawValue]
            lastFinger = result.finger
            lastConfidence = result.confidence
        }

        synth.play(midi: midi, velocity: tap.velocity)
        lastNoteName = Self.noteNames[midi % 12] + String(midi / 12 - 1)
        lastVelocity = tap.velocity
        tapCount += 1
        // 振动可能被加速度计读到造成误触发，默认关闭；不应期能挡掉大部分
        if hapticOnTap { WKInterfaceDevice.current().play(.click) }
    }

    // MARK: - 熄屏后继续运行

    /// 物理治疗类型的扩展运行会话，抬手放下后传感器和声音还能继续最多 1 小时。
    private func startRuntimeSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        runtimeSession = session
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        if let error { print("扩展运行会话结束: \(reason.rawValue) \(error)") }
    }
}
