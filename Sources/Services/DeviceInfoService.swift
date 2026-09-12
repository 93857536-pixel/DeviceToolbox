import Foundation
import UIKit

/// 全量设备信息聚合:硬件/软件/存储/电池/屏幕/网络/系统。
/// 硬件、软件、屏幕、系统在本层直接采集;存储/电池/网络委托对应 Service。
@MainActor
final class DeviceInfoService {
    /// 采集全量设备信息(异步:网络采样)。
    func collect() async -> DeviceInfo {
        let system = SystemInfoService().collect()
        let hardware = Self.collectHardware(machineIdentifier: system.machineIdentifier)
        let software = Self.collectSoftware()
        let storage = StorageService().collect()
        let battery = BatteryService().collect()
        let screen = Self.collectScreen()
        let network = await NetworkService().collect()

        return DeviceInfo(
            hardware: hardware,
            software: software,
            storage: storage,
            battery: battery,
            screen: screen,
            network: network,
            system: system
        )
    }

    // MARK: - 硬件

    private static func collectHardware(machineIdentifier: String) -> HardwareInfo {
        let device = UIDevice.current
        return HardwareInfo(
            model: device.model,
            machineIdentifier: machineIdentifier,
            marketingName: marketingName(for: machineIdentifier),
            deviceType: deviceType(for: machineIdentifier, fallback: device.model),
            totalRAMBytes: ProcessInfo.processInfo.physicalMemory,
            processorCount: ProcessInfo.processInfo.processorCount,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    /// 市场名称映射表(iPhone/iPad 常见机型);映射不到回退 machineIdentifier。
    private static func marketingName(for identifier: String) -> String {
        return marketingNames[identifier] ?? identifier
    }

    private static func deviceType(for identifier: String, fallback: String) -> String {
        if identifier.hasPrefix("iPhone") { return "iPhone" }
        if identifier.hasPrefix("iPad") { return "iPad" }
        if identifier.hasPrefix("iPod") { return "iPod touch" }
        return fallback
    }

    private static let marketingNames: [String: String] = [
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone13,2": "iPhone 12",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone11,8": "iPhone XR",
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone10,3": "iPhone X",
        "iPhone10,6": "iPhone X",
        "iPhone10,1": "iPhone 8",
        "iPhone10,4": "iPhone 8",
        "iPhone10,2": "iPhone 8 Plus",
        "iPhone10,5": "iPhone 8 Plus",
        "iPhone9,1": "iPhone 7",
        "iPhone9,3": "iPhone 7",
        "iPhone9,2": "iPhone 7 Plus",
        "iPhone9,4": "iPhone 7 Plus",
        "iPhone8,1": "iPhone 6s",
        "iPhone8,2": "iPhone 6s Plus",
        "iPhone8,4": "iPhone SE (1st generation)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)",
        "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad13,18": "iPad (10th generation)",
        "iPad13,19": "iPad (10th generation)",
        "iPad13,16": "iPad Air (5th generation)",
        "iPad13,17": "iPad Air (5th generation)",
        "iPad13,1": "iPad Air (4th generation)",
        "iPad13,2": "iPad Air (4th generation)",
        "iPad13,4": "iPad Pro 11-inch (3rd generation)",
        "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
        "iPad12,1": "iPad (9th generation)",
        "iPad12,2": "iPad (9th generation)",
        "iPad11,1": "iPad mini (5th generation)",
        "iPad11,2": "iPad mini (5th generation)",
        "iPad11,3": "iPad Air (3rd generation)",
        "iPad11,4": "iPad Air (3rd generation)",
        "iPad8,9": "iPad Pro 11-inch (2nd generation)",
        "iPad8,10": "iPad Pro 11-inch (2nd generation)",
        "iPad8,11": "iPad Pro 12.9-inch (4th generation)",
        "iPad8,12": "iPad Pro 12.9-inch (4th generation)",
        "iPad14,1": "iPad mini (6th generation)",
        "iPad14,2": "iPad mini (6th generation)",
        "i386": "iOS Simulator (i386)",
        "x86_64": "iOS Simulator (x86_64)",
        "arm64": "iOS Simulator (arm64)",
    ]

    // MARK: - 软件

    private static func collectSoftware() -> SoftwareInfo {
        let device = UIDevice.current
        return SoftwareInfo(
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            versionString: ProcessInfo.processInfo.operatingSystemVersionString,
            buildNumber: nil, // Apple 未向第三方 App 开放 Build Number 公开读取接口。
            systemUptime: ProcessInfo.processInfo.systemUptime,
            localeIdentifier: Locale.current.identifier,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    // MARK: - 屏幕

    private static func collectScreen() -> ScreenInfo {
        let screen = UIScreen.main
        let bounds = screen.bounds
        let native = screen.nativeBounds

        // UIScreen.maximumFramesPerSecond 为 iOS 15.0+ 公开 API(deployment target 17.0)。
        let maxFPS = screen.maximumFramesPerSecond
        let framesPerSecond: Int? = maxFPS > 0 ? maxFPS : nil
        let refreshDescription: String
        if let fps = framesPerSecond {
            refreshDescription = "约 \(fps) Hz"
        } else {
            refreshDescription = "无法检测"
        }

        return ScreenInfo(
            widthPoints: Double(bounds.width),
            heightPoints: Double(bounds.height),
            scale: Double(screen.scale),
            nativeWidth: Double(native.width),
            nativeHeight: Double(native.height),
            nativeScale: Double(screen.nativeScale),
            brightness: Double(screen.brightness),
            maximumFramesPerSecond: framesPerSecond,
            refreshRateDescription: refreshDescription
        )
    }
}
