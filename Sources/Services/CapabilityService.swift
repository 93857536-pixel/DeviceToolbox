import Foundation
import LocalAuthentication

/// 能力评估:兼容性库条目 × 运行时探测(OS 版本 / 设备适用性 / 硬件 / 权限状态)。
/// 输出 CapabilityResult(类型在 Sources/Core/DeviceCapability.swift 已定义,直接复用)。
@MainActor
final class CapabilityService {
    /// 逐条评估兼容性库,返回汇总结果。
    func evaluate() async -> [CapabilityResult] {
        let items = CompatibilityStore.bundled.allItems()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let machineIdentifier = SystemInfoService().collect().machineIdentifier
        return items.map { item in
            Self.evaluate(item: item, osVersion: osVersion, machineIdentifier: machineIdentifier)
        }
    }

    private static func evaluate(
        item: CompatibilityItem,
        osVersion: OperatingSystemVersion,
        machineIdentifier: String
    ) -> CapabilityResult {
        var status = item.status
        var detail = item.detail

        // 1. 设备适用性(devices 列表)
        if !item.applies(to: machineIdentifier) {
            status = .unsupported
            detail = "该功能不适用于当前设备型号"
        }
        // 2. OS 版本(minimumIOS / maximumIOS)
        else if !item.isSupported(by: osVersion) {
            status = .unsupported
            detail = "当前 iOS 版本不满足该功能要求(最低 \(item.minimumIOS))"
        }
        // 3. 运行时硬件探测(face-id / touch-id,公开 API)
        else if let probe = probeHardware(feature: item.feature) {
            status = probe.status
            detail = probe.detail
        }
        // 4. 权限叠加(requiresPermission 项)
        else if item.requiresPermission, let permission = permission(for: item.feature) {
            switch PermissionService.status(of: permission) {
            case .authorized, .limited:
                break // 已授权,保持数据库状态
            case .notDetermined:
                status = .partial
                detail = "\(item.detail)(需授权后使用,当前未授权)"
            case .denied, .restricted:
                status = .partial
                detail = "\(item.detail)(当前未授权,未授权≠不支持)"
            case .unavailable:
                status = .unknown
                detail = "\(item.detail)(权限状态不可读)"
            }
        }

        return CapabilityResult(
            id: item.id,
            name: item.name,
            status: status,
            detail: detail,
            requiresPermission: item.requiresPermission
        )
    }

    /// 针对特定硬件能力的运行时探测(公开 API);其余返回 nil(不覆盖数据库状态)。
    private static func probeHardware(feature: String) -> (status: CapabilityStatus, detail: String)? {
        switch feature {
        case "face-id":
            if biometryType() == .faceID {
                return (.supported, "经 LocalAuthentication 公开 API 检测,当前设备支持面容 ID")
            }
            return (.unsupported, "当前设备无面容 ID 硬件")
        case "touch-id":
            if biometryType() == .touchID {
                return (.supported, "经 LocalAuthentication 公开 API 检测,当前设备支持触控 ID")
            }
            return (.unsupported, "当前设备无触控 ID 硬件")
        default:
            return nil
        }
    }

    /// 读取生物识别类型(只读 canEvaluatePolicy,不触发授权)。
    private static func biometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }

    /// feature 键 → 权限类型(仅 requiresPermission 项会被查询);未匹配返回 nil。
    private static func permission(for feature: String) -> AppPermission? {
        switch feature {
        case "camera": return .camera
        case "microphone": return .microphone
        case "location": return .location
        case "notifications": return .notifications
        case "photos": return .photos
        case "contacts": return .contacts
        case "bluetooth": return .bluetooth
        case "face-id": return .faceID
        default: return nil
        }
    }
}
