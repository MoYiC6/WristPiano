# 腕上钢琴 Demo（watchOS）

戴着 Apple Watch 敲桌面就能出声。两种玩法：

- **转腕选音**：手腕左右转动（偏航角）选 C4–C5 八个音中的一个，任意手指敲击发声，敲得越重声音越大。
- **手指识别**：先在"手指校准"页给每根手指录 6 次敲击，之后拇指到小指分别对应 C D E F G。

## 运行

需要完整版 Xcode（15 以上）和一块真实的 Apple Watch（模拟器没有运动传感器，只能点"模拟敲击"听声音）。

```bash
brew install xcodegen   # 已装可跳过
xcodegen generate
open WristPiano.xcodeproj
```

在 Xcode 里选 WristPiano target → Signing & Capabilities 选你的 Team，必要时改 Bundle ID，然后选你的手表运行。
免费 Apple ID 也能装（7 天有效），没用到 HealthKit。

如果 xcodegen 生成的工程有问题：在 Xcode 新建 watchOS App（Watch-only），把 `WristPiano/` 下的 `.swift` 文件拖进去，
在 Info 里加 `NSMotionUsageDescription` 和 `WKBackgroundModes = physical-therapy`。

## 代码结构

| 文件 | 作用 |
| --- | --- |
| `MotionSource.swift` | CMMotionManager 100Hz deviceMotion：去重力加速度、角速度、偏航角 |
| `TapDetector.swift` | 相邻帧加速度差（jerk）超过自适应门限即判为敲击，带不应期，提 9 维特征 |
| `FingerClassifier.swift` | z-score + kNN 手指分类，校准数据存 UserDefaults |
| `Synth.swift` | AVAudioSourceNode 泛音叠加 + 指数衰减，手表本地外放 |
| `PianoModel.swift` | 串起以上模块；WKExtendedRuntimeSession 让放下手腕后继续运行 |
| `ContentView.swift` | 弹奏 / 校准 / 设置三页，上下滑或转表冠切换 |

## 调试提示

- 弹奏页的电平条是实时 jerk，敲一下看它跳多高，再到设置页调灵敏度。
- 转腕方向反了就打开"音区方向反转"；偏航角会慢慢漂移，按"归中"重置。
- 为什么用 100Hz 而不是 800Hz：800Hz 的 CMBatchedSensorManager 按批送数据、必须开健身记录，延迟太大不适合实时演奏。
  想提高手指识别率，可以用它离线采集数据训练 Core ML 模型，再在 100Hz 实时流上推理。
