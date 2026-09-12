import Foundation

// MARK: - 设备信息聚合模型
// 全部为值类型,严格 Codable + Sendable + Equatable,便于跨并发域传递与序列化。
// 仅描述「已采集到的数据」,采集逻辑在 Services/DeviceInfoService 等层。

/// 设备信息顶层聚合:按硬件/软件/存储/电池/屏幕/网络/系统分组。
struct DeviceInfo: Codable, Sendable, Equatable {
    let hardware: HardwareInfo
    let software: SoftwareInfo
    let storage: StorageInfo
    let battery: BatteryInfo
    let screen: ScreenInfo
    let network: NetworkInfo
    let system: SystemInfo
}

// MARK: - 硬件

struct HardwareInfo: Codable, Sendable, Equatable {
    /// UIDevice.current.model,如 "iPhone" / "iPad"
    let model: String
    /// 机器标识符(经 sysctlbyname hw.machine),如 "iPhone17,1"
    let machineIdentifier: String
    /// 尽力映射的市场名称(如 "iPhone 16 Pro");映射不到时回退为 machineIdentifier
    let marketingName: String
    /// 设备大类:iPhone / iPad / iPod touch
    let deviceType: String
    /// 总物理内存字节数(ProcessInfo.physicalMemory)
    let totalRAMBytes: UInt64
    /// 逻辑 CPU 核数(ProcessInfo.processorCount)
    let processorCount: Int
    /// 可用 CPU 核数(ProcessInfo.activeProcessorCount)
    let activeProcessorCount: Int
}

// MARK: - 软件

struct SoftwareInfo: Codable, Sendable, Equatable {
    /// UIDevice.current.systemName,如 "iOS"
    let systemName: String
    /// UIDevice.current.systemVersion,如 "17.5"
    let systemVersion: String
    /// ProcessInfo.operatingSystemVersionString,如 "Version 17.5 (Build 21F79)"
    let versionString: String
    /// Build Number:Apple 未向第三方 App 开放公开读取接口,恒为 nil。
    /// 不通过任何私有/越狱手段获取。
    let buildNumber: String?
    /// 系统运行时间(秒,ProcessInfo.systemUptime)
    let systemUptime: TimeInterval
    /// 区域标识符(NSLocale.current.identifier)
    let localeIdentifier: String
    /// 首选语言列表(Locale.preferredLanguages)
    let preferredLanguages: [String]
}

// MARK: - 存储

struct StorageInfo: Codable, Sendable, Equatable {
    /// 磁盘总容量(字节,FileManager attributesOfFileSystem)
    let totalBytes: Int64
    /// 磁盘可用容量(字节)
    let freeBytes: Int64
    /// 已用容量(字节)= totalBytes - freeBytes
    let usedBytes: Int64
    /// 卷是否只读
    let isReadonly: Bool
}

// MARK: - 电池

enum BatteryState: String, Codable, Sendable {
    case unknown
    case unplugged
    case charging
    case full
}

struct BatteryInfo: Codable, Sendable, Equatable {
    /// 电量 0.0...1.0;无法获取时(如模拟器)为 nil
    let level: Float?
    /// 充电状态
    let state: BatteryState
    /// 是否已开启电量监控(UIDevice.isBatteryMonitoringEnabled)
    let isMonitoringEnabled: Bool
    /// 是否处于低功耗模式(ProcessInfo.isLowPowerModeEnabled)
    let isLowPowerModeEnabled: Bool
}

// MARK: - 屏幕

struct ScreenInfo: Codable, Sendable, Equatable {
    /// 逻辑宽(pt,UIScreen.main.bounds)
    let widthPoints: Double
    /// 逻辑高(pt)
    let heightPoints: Double
    /// 缩放 scale(UIScreen.main.scale)
    let scale: Double
    /// 原生宽(px,UIScreen.main.nativeBounds)
    let nativeWidth: Double
    /// 原生高(px)
    let nativeHeight: Double
    /// 原生缩放 nativeScale
    let nativeScale: Double
    /// 屏幕亮度 0.0...1.0(UIScreen.main.brightness)
    let brightness: Double
    /// 最大帧率(iOS 15.4+ 经 CADisplayLink.maximumFramesPerSecond);无法检测时为 nil
    let maximumFramesPerSecond: Int?
    /// 刷新率说明文案,如 "约 120 Hz" / "无法检测"
    let refreshRateDescription: String
}

// MARK: - 网络

enum NetworkStatus: String, Codable, Sendable {
    case requiresConnection
    case satisfied
    case unsatisfied
    case unknown
}

enum NetworkInterfaceType: String, Codable, Sendable {
    case wifi
    case cellular
    case wiredEthernet
    case loopback
    case other
    case none
}

struct NetworkInfo: Codable, Sendable, Equatable {
    /// 路径状态(NWPathMonitor)
    let status: NetworkStatus
    /// 主接口类型(Wi-Fi / 蜂窝 / 有线 / 回环 / 其他)
    let interfaceType: NetworkInterfaceType
    /// 当前可用接口名列表,如 ["en0"] 或 ["pdp_ip0"]
    let interfaceNames: [String]
    /// 是否为昂贵网络(蜂窝)
    let isExpensive: Bool
    /// 是否受限(低数据模式)
    let isConstrained: Bool
    /// 是否支持 IPv4
    let supportsIPv4: Bool
    /// 是否支持 IPv6
    let supportsIPv6: Bool
}

// MARK: - 系统

struct SystemInfo: Codable, Sendable, Equatable {
    /// CPU 架构,如 "arm64"(经 sysctlbyname hw.optional.arm64 判断)
    let cpuArchitecture: String
    /// 是否运行在模拟器(#if targetEnvironment(simulator))
    let isSimulator: Bool
    /// 机器标识符(hw.machine),与 HardwareInfo.machineIdentifier 一致
    let machineIdentifier: String
    /// 内核版本与架构字符串(经 uname);失败时为 nil
    let kernelVersion: String?
    /// 主机名(ProcessInfo.hostName)
    let hostname: String
}
