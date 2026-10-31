import CoreMotion
import simd

/// 一帧融合后的运动数据（已去掉重力）。
struct MotionSample {
    var time: TimeInterval
    /// 用户加速度，单位 g，已扣除重力
    var accel: SIMD3<Double>
    /// 角速度，单位 rad/s
    var rotation: SIMD3<Double>
    /// 偏航角（绕竖直轴），单位 rad
    var yaw: Double
}

/// 用 CMMotionManager 以 100Hz 读取 deviceMotion。
///
/// 为什么不用 800Hz 的 CMBatchedSensorManager：它按批次送数据（间隔明显大于一次敲击），
/// 适合事后分析挥杆之类的动作，不适合要求实时出声的乐器。
final class MotionSource {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// handler 在后台串行队列上回调。
    func start(handler: @escaping (MotionSample) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { motion, _ in
            guard let m = motion else { return }
            let sample = MotionSample(
                time: m.timestamp,
                accel: SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z),
                rotation: SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
                yaw: m.attitude.yaw
            )
            handler(sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
