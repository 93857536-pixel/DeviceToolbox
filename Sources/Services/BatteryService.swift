import Foundation
import UIKit

/// 电池信息采集:UIDevice.batteryLevel / batteryState + 低功耗模式。
/// 仅使用公开 API,零第三方依赖。
@MainActor
final class BatteryService {
    /// 采集电池信息。同步返回。先开启电量监控再读取。
    func collect() -> BatteryInfo {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        // batteryLevel 取值 0...1;不可用(如模拟器)时返回 -1,映射为 nil。
        let rawLevel = device.batteryLevel
        let level: Float? = rawLevel >= 0 ? rawLevel : nil

        let state: BatteryState
        switch device.batteryState {
        case .charging: state = .charging
        case .full: state = .full
        case .unplugged: state = .unplugged
        default: state = .unknown
        }

        return BatteryInfo(
            level: level,
            state: state,
            isMonitoringEnabled: device.isBatteryMonitoringEnabled,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}
