//
//  FoldEffectEngine.swift
//  DeviceToolbox
//
//  全应用折叠玻璃特效引擎:App 入口持有单例,是姿态追踪(TiltMotionModel)
//  与用户全局开关(持久化到 UserDefaults)的**单一数据源**。
//  开关开启时整个主界面按设备倾角渲染成"透过倾斜玻璃窗"的效果;
//  关闭或平放(angle≈0)时 shader 自动失效(零采样开销)。
//  设计借鉴 elijah-semyonov/DuoLikeAnimation (MIT License),此处重新实现。
//

import Foundation
import Observation

/// 全局折叠特效状态:App 级单例,经 `.environment()` 注入。
///
/// 所有需要"折叠玻璃"姿态的地方(主界面外层特效、折叠玻璃实验室页)
/// 都读这一个引擎,避免各自再起一份 `CMMotionManager`。
@Observable @MainActor
final class FoldEffectEngine {
    /// 用户全局开关(持久化)。true 时主界面整棵树套玻璃折角效果。
    private(set) var isEnabled: Bool

    @ObservationIgnored let motion: TiltMotionModel

    // MARK: - 姿态 pass-through(实验室页直接绑定这些)

    /// 当前倾角(弧度)。正:右缘远离观察者。
    var tiltAngle: Double { motion.tiltAngle }
    var usesManualTilt: Bool {
        get { motion.usesManualTilt }
        set { motion.usesManualTilt = newValue }
    }
    var manualDegrees: Double {
        get { motion.manualDegrees }
        set { motion.manualDegrees = newValue }
    }
    var isMotionAvailable: Bool { motion.isMotionAvailable }

    init() {
        motion = TiltMotionModel()
        isEnabled = UserDefaults.standard.bool(forKey: AppStorageKeys.foldEffectEnabled)
        if isEnabled {
            motion.start()
        }
    }

    /// 喂给主界面外层 `.glassFold` 的倾角:关闭时恒 0(shader 按 `abs(angle) > 1e-4` 自动失效)。
    /// 钳制到 ±45°:全应用模式下大倾角会把大半屏投影出界面(shader 设计上黑区),
    /// 视觉上像"界面坏了";钳制后效果仍有透视纵深感,同时保住可读性。
    var currentAngle: Double {
        guard isEnabled else { return 0 }
        return min(max(motion.tiltAngle, -45 * .pi / 180), 45 * .pi / 180)
    }

    /// 翻转/设置全局开关;默认持久化到 UserDefaults。关闭时复位姿态,避免冻结在倾斜状态。
    /// `persist=false` 供 UI 测试临时开启(不写默认值,不污染其他测试用例)。
    func setEnabled(_ enabled: Bool, persist: Bool = true) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if persist {
            UserDefaults.standard.set(enabled, forKey: AppStorageKeys.foldEffectEnabled)
        }
        Log.info("全应用折叠特效已\(enabled ? "开启" : "关闭")")
        if enabled {
            motion.start()
        } else {
            motion.stop()
            motion.recalibrate()
        }
    }

    /// 把当前姿态设为零倾角(实验室页"重新校准"按钮调用)。
    func recalibrate() {
        motion.recalibrate()
    }
}
