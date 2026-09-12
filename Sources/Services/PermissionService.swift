import Foundation
import CoreLocation
import AVFoundation
import Photos
import Contacts
import CoreBluetooth
import LocalAuthentication

/// 权限类型(只读状态查询用)。
enum AppPermission: String, CaseIterable, Sendable {
    case location
    case camera
    case microphone
    case notifications
    case photos
    case contacts
    case bluetooth
    case faceID
}

/// 权限状态。
enum AppPermissionStatus: String, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
    case limited   // 仅相册等支持「部分授权」
    case unavailable
}

/// 权限状态查询。只读,绝不触发授权弹窗(不调用任何 request* 方法)。
@MainActor
enum PermissionService {
    /// 读取指定公开权限的当前状态。同步返回。
    static func status(of permission: AppPermission) -> AppPermissionStatus {
        switch permission {
        case .location:
            return map(CLLocationManager().authorizationStatus)
        case .camera:
            return map(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            return map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .notifications:
            // 通知授权状态需 UNUserNotificationCenter 异步回调,无法同步读取。
            // 为避免阻塞与触发弹窗,此处以 .notDetermined 兜底(诚实标注)。
            return .notDetermined
        case .photos:
            return map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .contacts:
            return map(CNContactStore.authorizationStatus(for: .contacts))
        case .bluetooth:
            return map(CBManager.authorization)
        case .faceID:
            return faceIDStatus()
        }
    }

    // MARK: - 映射

    private static func map(_ status: CLAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .unavailable
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .unavailable
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .unavailable
        }
    }

    private static func map(_ status: CNAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .unavailable
        }
    }

    private static func map(_ status: CBManagerAuthorization) -> AppPermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .allowedAlways: return .authorized
        @unknown default: return .unavailable
        }
    }

    /// 面容 ID 可用性(经 LocalAuthentication,只读 canEvaluatePolicy,不 evaluate)。
    private static func faceIDStatus() -> AppPermissionStatus {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if canEvaluate {
            return .authorized
        }
        if let laError = error as? LAError {
            switch laError.code {
            case .biometryNotEnrolled:
                return .notDetermined // 硬件支持但未录入
            case .biometryLockout:
                return .denied
            default:
                return .unavailable
            }
        }
        return .unavailable
    }
}
