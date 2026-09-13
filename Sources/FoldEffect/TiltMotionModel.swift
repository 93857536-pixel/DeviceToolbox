//
//  TiltMotionModel.swift
//  DeviceToolbox
//
//  从 CoreMotion 设备姿态推导绕屏幕空间 Y 轴的倾角,相对"校准零倾角"姿态。
//  设计借鉴 elijah-semyonov/DuoLikeAnimation (MIT License) 的
//  校准零倾角 + 陀螺外推延迟补偿管线,此处重新实现。
//

import CoreMotion
import Observation
import UIKit
import simd

/// 设备倾角追踪:姿态融合 + 陀螺外推 + 低通,喂给折叠玻璃 shader。
/// 模拟器无运动数据时 `isMotionAvailable` 为 false,界面应切手动滑杆模式。
@Observable @MainActor
final class TiltMotionModel {
    /// 喂给 shader 的倾角(弧度)。正:右缘远离观察者。
    var tiltAngle: Double {
        usesManualTilt ? manualDegrees * .pi / 180 : motionTilt
    }

    var usesManualTilt: Bool
    var manualDegrees: Double = 0
    private(set) var isMotionAvailable: Bool
    private(set) var motionTilt: Double = 0

    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private var reference: simd_double3x3?
    /// CMRotationMatrix 行列约定运行时用重力向量对拍实测定(不猜文档)。
    @ObservationIgnored private var rowsAreDeviceAxes: Bool?
    /// 姿态本身已融合,额外滤波会引入可见滞后,因此取值偏高。
    @ObservationIgnored private let smoothing = 0.7
    /// 用陀螺角速度向前外推的补偿量,覆盖传感器与显示延迟。
    @ObservationIgnored private let predictionInterval = 0.04

    init(manualDegrees: Double = 0) {
        self.manualDegrees = manualDegrees
        let motionAvailable = motionManager.isDeviceMotionAvailable
        self.isMotionAvailable = motionAvailable
        #if targetEnvironment(simulator)
        usesManualTilt = true
        #else
        usesManualTilt = !motionAvailable
        #endif
    }

    func start() {
        guard isMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        // 陀螺参考帧:磁力计校正版拿长期 yaw 稳定度换延迟,而 yaw 正是
        // 这个效果跟踪的轴,所以不取。
        motionManager.deviceMotionUpdateInterval = 1.0 / 120.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.process(motion) }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    /// 把当前姿态设为零倾角姿态(UI 平面所在基准)。
    func recalibrate() {
        reference = nil
        motionTilt = 0
    }

    private func process(_ motion: CMDeviceMotion) {
        let deviceToReference = deviceToReferenceMatrix(motion)
        guard let reference else {
            reference = deviceToReference
            return
        }

        // 当前设备轴在校准设备坐标系中的表达。
        let relative = reference.transpose * deviceToReference
        let normal = relative.columns.2                       // 当前屏幕法线
        let screenAxes = screenAxesInDeviceSpace()
        let measured = atan2(simd_dot(normal, screenAxes.x), normal.z)

        // 沿屏幕 Y 轴方向的旋转角速度外推,补偿传感器/显示延迟。
        let rate = SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
        let predicted = measured + simd_dot(rate, screenAxes.y) * predictionInterval

        motionTilt += (predicted - motionTilt) * smoothing
    }

    /// 设备帧向量 → 参考帧向量的旋转(列向量约定)。
    private func deviceToReferenceMatrix(_ motion: CMDeviceMotion) -> simd_double3x3 {
        let m = motion.attitude.rotationMatrix
        let asRows = simd_double3x3(rows: [
            SIMD3(m.m11, m.m12, m.m13),
            SIMD3(m.m21, m.m22, m.m23),
            SIMD3(m.m31, m.m32, m.m33),
        ])

        if rowsAreDeviceAxes == nil {
            // 重力在设备帧上报、Z-vertical 参考下指向 -Z。用两种约定对
            // 重力的预测做对拍,差值足够大时锁住更好的一种。
            let gravity = simd_normalize(SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z))
            let down = SIMD3(0.0, 0.0, -1.0)
            let rowsScore = simd_dot(gravity, asRows * down)
            let columnsScore = simd_dot(gravity, asRows.transpose * down)
            if abs(rowsScore - columnsScore) > 0.2 {
                rowsAreDeviceAxes = rowsScore > columnsScore
            }
        }
        return (rowsAreDeviceAxes ?? true) ? asRows.transpose : asRows
    }

    /// 界面在设备坐标中的屏幕 X(右)/Y(上)轴,按当前界面朝向取。
    private func screenAxesInDeviceSpace() -> (x: SIMD3<Double>, y: SIMD3<Double>) {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft:        return (SIMD3(0, 1, 0), SIMD3(-1, 0, 0))
        case .landscapeRight:       return (SIMD3(0, -1, 0), SIMD3(1, 0, 0))
        case .portraitUpsideDown:   return (SIMD3(-1, 0, 0), SIMD3(0, -1, 0))
        default:                    return (SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        }
    }
}
