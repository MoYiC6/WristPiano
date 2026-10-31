import Foundation

enum Finger: Int, CaseIterable, Codable, Identifiable {
    case thumb, index, middle, ring, pinky
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .thumb: "拇指"
        case .index: "食指"
        case .middle: "中指"
        case .ring: "无名指"
        case .pinky: "小指"
        }
    }
}

/// 校准后的 kNN 手指分类器。
///
/// 每根手指录几次敲击的特征，按维度做 z-score 归一化，预测时取最近的 k 个样本投票。
/// 样本少、维度低，kNN 足够，也方便换成 Core ML 模型之前先验证可行性。
struct FingerClassifier: Codable {
    private(set) var samples: [Finger: [[Double]]] = [:]
    private var mean: [Double] = []
    private var std: [Double] = []

    static let samplesPerFinger = 6
    private static let storageKey = "fingerSamples.v1"

    func count(for finger: Finger) -> Int { samples[finger]?.count ?? 0 }

    var calibratedFingers: [Finger] {
        Finger.allCases.filter { count(for: $0) >= 3 }
    }

    var isReady: Bool { calibratedFingers.count >= 2 }

    mutating func add(_ features: [Double], for finger: Finger) {
        samples[finger, default: []].append(features)
        if samples[finger]!.count > Self.samplesPerFinger {
            samples[finger]!.removeFirst()
        }
        refit()
    }

    mutating func clear(_ finger: Finger? = nil) {
        if let finger { samples[finger] = nil } else { samples.removeAll() }
        refit()
    }

    func predict(_ features: [Double], k: Int = 3) -> (finger: Finger, confidence: Double)? {
        guard isReady, features.count == mean.count else { return nil }
        let x = normalize(features)
        var distances: [(Finger, Double)] = []
        for (finger, list) in samples where list.count >= 3 {
            for s in list {
                let d = zip(x, normalize(s)).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
                distances.append((finger, d))
            }
        }
        let nearest = distances.sorted { $0.1 < $1.1 }.prefix(k)
        var votes: [Finger: Int] = [:]
        for (f, _) in nearest { votes[f, default: 0] += 1 }
        guard let best = votes.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, Double(best.value) / Double(nearest.count))
    }

    private func normalize(_ v: [Double]) -> [Double] {
        zip(v, zip(mean, std)).map { ($0 - $1.0) / $1.1 }
    }

    private mutating func refit() {
        let all = samples.values.flatMap { $0 }
        guard let dim = all.first?.count else {
            mean = []; std = []
            return
        }
        mean = (0..<dim).map { i in all.reduce(0) { $0 + $1[i] } / Double(all.count) }
        std = (0..<dim).map { i in
            let v = all.reduce(0) { $0 + pow($1[i] - mean[i], 2) } / Double(all.count)
            return max(sqrt(v), 1e-3)
        }
    }

    // MARK: - 持久化

    static func load() -> FingerClassifier {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let c = try? JSONDecoder().decode(FingerClassifier.self, from: data)
        else { return FingerClassifier() }
        return c
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
