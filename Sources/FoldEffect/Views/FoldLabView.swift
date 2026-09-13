//
//  FoldLabView.swift
//  DeviceToolbox
//
//  折叠玻璃实验室:实时跟踪设备姿态,把界面渲染成"透过一块倾斜磨砂玻璃窗
//  观察"的折叠动画效果。运动数据不可用(如模拟器)时自动切手动滑杆模式。
//  姿态数据来自全局 FoldEffectEngine(App 级单例),本页不再各自起 tracker。
//  效果设计借鉴 elijah-semyonov/DuoLikeAnimation (MIT License),此处重新实现。
//

import SwiftUI

/// 折叠玻璃实验室页面。
@MainActor
struct FoldLabView: View {
    /// 全局折叠特效引擎(单一姿态数据源 + 全应用开关)。
    @Environment(FoldEffectEngine.self) private var engine
    @State private var clock = FoldLabClock()

    var body: some View {
        List {
            // 全应用特效开关:开启后整个 App(6 个 Tab)都按设备倾角渲染折角效果。
            Section(String(localized: "fold.lab.global")) {
                Toggle(isOn: Binding(
                    get: { engine.isEnabled },
                    set: { engine.setEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "fold.lab.global.toggle"))
                            .font(.subheadline)
                        Text(String(localized: "fold.lab.global.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 主界面外层 MainTabView 已按全局开关套 glassFold:开着时本页效果已由外层提供,
            // 演示区不再单独套效果(避免双份叠加);关着时演示区局部套效果保证始终可演示。
            Section(String(localized: "fold.lab.effect")) {
                demoScreen
                    .glassFold(angle: engine.isEnabled ? 0 : engine.tiltAngle)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                LabeledContent(String(localized: "fold.lab.angle.label")) {
                    Text(engine.isEnabled
                         ? String(localized: "fold.lab.angle.global")
                         : String(format: "%+.1f°", engine.tiltAngle * 180 / .pi))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "fold.lab.control")) {
                controlRows
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(String(localized: "fold.lab.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            clock.start()
            engine.motion.start()
        }
        .onDisappear {
            clock.stop()
            // 全应用开关开着时主界面还需要这份姿态流,不能停;
            // 关着的话本页是最后的使用方,随页面退出停止。
            if !engine.isEnabled {
                engine.motion.stop()
            }
        }
    }

    // MARK: - 演示区

    /// 被玻璃效果作用的那块"界面":模拟一块手机屏幕(时钟 + 卡片),
    /// 全部纯 SwiftUI,保证整棵子树都能被 layerEffect 压平取样。
    private var demoScreen: some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(localized: "fold.lab.demo.title"))
                    .font(.headline)
                Spacer()
                Text(clock.text)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                demoTile(title: "60%", caption: String(localized: "fold.lab.demo.battery"))
                demoTile(title: "5G", caption: String(localized: "fold.lab.demo.network"))
                demoTile(title: "12", caption: String(localized: "fold.lab.demo.messages"))
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.accent.opacity(0.7), Theme.accent.opacity(0.25)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 44)
        }
        .padding(14)
        .background(Theme.pageBackdrop)
    }

    private func demoTile(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassPanel()
    }

    // MARK: - 控制行

    @ViewBuilder
    private var controlRows: some View {
        if engine.isMotionAvailable {
            LabeledContent(String(localized: "fold.lab.mode")) {
                Text(engine.usesManualTilt
                     ? String(localized: "fold.lab.mode.manual")
                     : String(localized: "fold.lab.mode.motion"))
                    .foregroundStyle(.secondary)
            }
            Toggle(String(localized: "fold.lab.mode.manual"), isOn: Binding(
                get: { engine.usesManualTilt },
                set: { engine.usesManualTilt = $0 }
            ))
            .font(.subheadline)
            Button {
                engine.recalibrate()
            } label: {
                Label(String(localized: "fold.lab.recalibrate"), systemImage: "target")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline)
            Text(String(localized: "fold.lab.recalibrate.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(String(localized: "fold.lab.motion.unavailable"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(String(localized: "fold.lab.manual.angle")) {
                Text(String(format: "%+.1f°", engine.manualDegrees)).font(.subheadline.monospacedDigit())
            }
            Slider(value: Binding(
                get: { engine.manualDegrees },
                set: { engine.manualDegrees = $0 }
            ), in: -45...45, step: 1)
        }
        .disabled(engine.isMotionAvailable && !engine.usesManualTilt)
    }
}

/// 演示区时钟:每秒刷新的 @Observable,替代旧版 ViewModel 内的 clockTask。
@MainActor @Observable
private final class FoldLabClock {
    private(set) var text = ""
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.text = Self.formatter.string(from: Date())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    @ObservationIgnored private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
