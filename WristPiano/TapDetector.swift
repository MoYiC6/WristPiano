import Foundation
import simd

/// 一次被检测到的敲击。
struct TapEvent {
    var time: TimeInterval
    /// 0.15 ~ 1.0，用作发声力度
    var velocity: Double
    /// 触发瞬间的偏航角
    var yaw: Double
    /// 给手指分类器用的特征向量
    var features: [Double]
}

/// 在 100Hz 运动数据里找"手指敲桌面"产生的短促冲击。
///
/// 思路：敲击会让加速度在 10~20ms 内突变，所以看相邻两帧加速度差（jerk）的模长。
/// 用指数平均跟踪背景噪声，jerk 明显高出噪声且超过下限时触发，
/// 再多等 `postSamples` 帧把峰值收进窗口，然后提特征、输出事件。
final class TapDetector {
    /// 灵敏度，越大越容易触发
    var sensitivity: Double = 1.0
    /// 两次敲击的最小间隔，也用来屏蔽敲击后的余振
    var refractory: TimeInterval = 0.12

    /// 最近一帧的 jerk，给界面画电平条
    private(set) var lastJerk: Double = 0

    private let preSamples = 3
    private let postSamples = 2
    private let baseThreshold = 0.12

    private var history: [MotionSample] = []
    private var previous: MotionSample?
    private var noise = 0.02
    private var lastTapTime: TimeInterval = -1
    private var pending: (trigger: MotionSample, jerk: Double, remaining: Int)?

    var threshold: Double { max(baseThreshold, noise * 6) / sensitivity }

    func reset() {
        history.removeAll()
        previous = nil
        pending = nil
        noise = 0.02
    }

    /// 喂一帧数据，检测到敲击时返回事件。
    func process(_ s: MotionSample) -> TapEvent? {
        defer {
            previous = s
            history.append(s)
            if history.count > preSamples + postSamples + 2 { history.removeFirst() }
        }
        guard let prev = previous else { return nil }

        let jerk = simd_length(s.accel - prev.accel)
        lastJerk = jerk

        if var p = pending {
            p.jerk = max(p.jerk, jerk)
            p.remaining -= 1
            if p.remaining > 0 {
                pending = p
                return nil
            }
            pending = nil
            let window = Array(history.suffix(preSamples + postSamples)) + [s]
            return TapEvent(
                time: p.trigger.time,
                velocity: Self.velocity(fromJerk: p.jerk),
                yaw: p.trigger.yaw,
                features: Self.features(window)
            )
        }

        if jerk > threshold, s.time - lastTapTime > refractory {
            lastTapTime = s.time
            pending = (s, jerk, postSamples)
            return nil
        }

        // 只在安静时更新噪声估计，避免敲击本身把门限抬高
        noise = noise * 0.98 + jerk * 0.02
        return nil
    }

    /// jerk 大致在 0.1 ~ 2g 之间，取对数映射到 0.15 ~ 1。
    private static func velocity(fromJerk j: Double) -> Double {
        let t = (log10(max(j, 0.1)) + 1) / 1.3   // 0.1 -> 0, 2.0 -> 1
        return min(1, max(0.15, 0.15 + 0.85 * t))
    }

    /// 9 维特征：三轴加速度峰值、三轴角速度峰值（都带符号），加速度峰值的方向单位向量。
    /// 不同手指敲击时，冲击传到手腕的方向和带出的转动不同，这是分类的依据。
    static func features(_ window: [MotionSample]) -> [Double] {
        func signedPeak(_ values: [Double]) -> Double {
            values.max { abs($0) < abs($1) } ?? 0
        }
        let a = SIMD3(
            signedPeak(window.map { $0.accel.x }),
            signedPeak(window.map { $0.accel.y }),
            signedPeak(window.map { $0.accel.z })
        )
        let r = SIMD3(
            signedPeak(window.map { $0.rotation.x }),
            signedPeak(window.map { $0.rotation.y }),
            signedPeak(window.map { $0.rotation.z })
        )
        let len = simd_length(a)
        let dir = len > 1e-6 ? a / len : .zero
        return [a.x, a.y, a.z, r.x, r.y, r.z, dir.x, dir.y, dir.z]
    }
}
