//
//  FoldLabView.swift
//  DeviceToolbox
//
//  折叠玻璃实验室:实时跟踪设备姿态,把界面渲染成"透过一块倾斜磨砂玻璃窗
//  观察"的折叠动画效果。运动数据不可用(如模拟器)时自动切手动滑杆模式。
//  效果设计借鉴 elijah-semyonov/DuoLikeAnimation (MIT License),此处重新实现。
//

import SwiftUI

/// 折叠玻璃实验室页面。
@MainActor
struct FoldLabView: View {
    @State private var model: FoldLabViewModel = FoldLabViewModel()

    var body: some View {
        List {
            Section(String(localized: "fold.lab.effect")) {
                demoScreen
                    .glassFold(angle: model.tiltAngle)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                LabeledContent(String(localized: "fold.lab.angle.label")) {
                    Text(model.displayDegrees)
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
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: - 控制行

    /// 被玻璃效果作用的那块"界面":模拟一块手机屏幕(时钟 + 卡片),
    /// 全部纯 SwiftUI,保证整棵子树都能被 layerEffect 压平取样。
    private var demoScreen: some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(localized: "fold.lab.demo.title"))
                    .font(.headline)
                Spacer()
                Text(model.clockText)
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
        if model.isMotionAvailable {
            LabeledContent(String(localized: "fold.lab.mode")) {
                Text(model.usesManualTilt
                     ? String(localized: "fold.lab.mode.manual")
                     : String(localized: "fold.lab.mode.motion"))
                    .foregroundStyle(.secondary)
            }
            Toggle(String(localized: "fold.lab.mode.manual"), isOn: $model.usesManualTilt)
                .font(.subheadline)
            Button {
                model.recalibrate()
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
                Text(model.displayDegrees).font(.subheadline.monospacedDigit())
            }
            Slider(value: $model.manualDegrees, in: -45...45, step: 1)
        }
        .disabled(model.isMotionAvailable && !model.usesManualTilt)
    }
}

/// 折叠玻璃实验室视图模型。
@MainActor
@Observable
final class FoldLabViewModel {
    @ObservationIgnored private let motion: TiltMotionModel

    var usesManualTilt: Bool {
        get { motion.usesManualTilt }
        set { motion.usesManualTilt = newValue }
    }
    var manualDegrees: Double {
        get { motion.manualDegrees }
        set { motion.manualDegrees = newValue }
    }
    var tiltAngle: Double { motion.tiltAngle }
    var isMotionAvailable: Bool { motion.isMotionAvailable }

    private(set) var clockText = ""
    @ObservationIgnored private var clockTask: Task<Void, Never>?

    init(manualDegrees: Double = 0) {
        motion = TiltMotionModel(manualDegrees: manualDegrees)
    }

    /// 当前倾角的人类可读度数(带符号,保留 1 位小数)。
    var displayDegrees: String { String(format: "%+.1f°", tiltAngle * 180 / .pi) }

    func start() {
        motion.start()
        startClock()
    }

    func stop() {
        motion.stop()
        clockTask?.cancel()
        clockTask = nil
    }

    func recalibrate() {
        motion.recalibrate()
    }

    private func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.clockText = Self.clockFormatter.string(from: Date())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ObservationIgnored private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
