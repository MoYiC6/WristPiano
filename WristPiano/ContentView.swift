import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PlayView()
            CalibrateView()
            SettingsView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - 弹奏

struct PlayView: View {
    @Environment(PianoModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            Text(model.lastNoteName)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.snappy, value: model.tapCount)

            if model.mode == .wristZone {
                KeyStrip(count: model.scale.count, active: model.currentZone)
            } else if let f = model.lastFinger {
                Text("\(f.name) · \(Int(model.lastConfidence * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(" ").font(.footnote)
            }

            LevelBar(value: model.jerkLevel, max: 1.0)
                .frame(height: 6)

            HStack {
                Button(model.isRunning ? "停止" : "开始") {
                    model.isRunning ? model.stop() : model.start()
                }
                .tint(model.isRunning ? .red : .green)

                if model.isRunning && model.mode == .wristZone {
                    Button("归中") { model.recenter() }
                }
            }

            if !model.motionAvailable {
                Button("模拟敲击") { model.simulateTap() }
                    .font(.footnote)
            }
        }
        .navigationTitle(model.mode.title)
    }
}

/// 8 个琴键，高亮当前手腕所在音区
struct KeyStrip: View {
    let count: Int
    let active: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i == active ? Color.yellow : Color.white.opacity(0.85))
                    .frame(height: 22)
            }
        }
    }
}

/// 实时 jerk 电平，帮助调灵敏度
struct LevelBar: View {
    let value: Double
    let max: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.gray.opacity(0.3))
                Capsule()
                    .fill(value > max * 0.3 ? .orange : .green)
                    .frame(width: geo.size.width * min(1, value / max))
            }
        }
    }
}

// MARK: - 校准

struct CalibrateView: View {
    @Environment(PianoModel.self) private var model

    var body: some View {
        List {
            Section {
                Text("点一根手指，然后用这根手指敲桌面 \(FingerClassifier.samplesPerFinger) 次。需要先点\"开始\"。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Finger.allCases) { finger in
                Button {
                    model.calibratingFinger = model.calibratingFinger == finger ? nil : finger
                } label: {
                    HStack {
                        Text(finger.name)
                        Spacer()
                        if model.calibratingFinger == finger {
                            Text("敲击中…").foregroundStyle(.yellow)
                        }
                        Text("\(model.sampleCount(for: finger))/\(FingerClassifier.samplesPerFinger)")
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("清除", role: .destructive) { model.clearCalibration(finger) }
                }
            }
            Button("全部清除", role: .destructive) { model.clearCalibration() }
        }
        .navigationTitle("手指校准")
    }
}

// MARK: - 设置

struct SettingsView: View {
    @Environment(PianoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List {
            Picker("模式", selection: $model.mode) {
                ForEach(PlayMode.allCases) { Text($0.title).tag($0) }
            }
            VStack(alignment: .leading) {
                Text("灵敏度 \(model.sensitivity, specifier: "%.1f")")
                Slider(
                    value: Binding(get: { model.sensitivity }, set: { model.setSensitivity($0) }),
                    in: 0.3...3.0,
                    step: 0.1
                )
            }
            Toggle("音区方向反转", isOn: $model.invertYaw)
            Toggle("敲击振动", isOn: $model.hapticOnTap)
        }
        .navigationTitle("设置")
    }
}
