import Foundation

/// 兼容性数据库条目(与 compatibility_db.json 一一对应)。
struct CompatibilityItem: Codable, Sendable, Identifiable, Equatable {
    /// 唯一标识
    let id: String
    /// 显示名称(中文)
    let name: String
    /// 功能机器键(供运行时探测交叉引用)
    let feature: String
    /// 最低 iOS 版本;空字符串表示无下限
    let minimumIOS: String
    /// 最高 iOS 版本;空字符串表示无上限
    let maximumIOS: String
    /// 指定设备标识符(hw.machine)列表;空数组表示所有设备
    let devices: [String]
    /// 状态:supported / partial / unsupported
    let status: CapabilityStatus
    /// 是否需要用户授权(相机/麦克风/定位/通知/相册/面容等)
    let requiresPermission: Bool
    /// 中文说明
    let detail: String
    /// 可执行动作列表(如打开设置/测试)
    let actions: [CompatibilityAction]

    /// 解析最低版本;空字符串返回 nil
    var minimumVersion: OperatingSystemVersion? {
        Self.parseVersion(minimumIOS)
    }

    /// 解析最高版本;空字符串返回 nil
    var maximumVersion: OperatingSystemVersion? {
        Self.parseVersion(maximumIOS)
    }

    /// 判断指定系统版本是否满足最低要求。
    func isSupported(by osVersion: OperatingSystemVersion) -> Bool {
        if let min = minimumVersion, osVersion < min { return false }
        if let max = maximumVersion, osVersion > max { return false }
        return true
    }

    /// 判断是否适用于指定设备标识符(空 devices = 全部适用)。
    func applies(to machineIdentifier: String?) -> Bool {
        guard let machineIdentifier, !machineIdentifier.isEmpty else { return true }
        return devices.isEmpty || devices.contains(machineIdentifier)
    }

    private static func parseVersion(_ string: String) -> OperatingSystemVersion? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return OperatingSystemVersion(
            majorVersion: parts.count > 0 ? parts[0] : 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
    }
}

/// 兼容性条目的可执行动作。
struct CompatibilityAction: Codable, Sendable, Equatable {
    /// 动作类型:open(打开)/ test(测试)/ settings(跳设置)
    let type: String
    /// 动作标题(可选)
    let title: String?
    /// 动作参数(可选,如 URL Scheme)
    let value: String?
}

extension OperatingSystemVersion: @retroactive Comparable {
    public static func == (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        lhs.majorVersion == rhs.majorVersion && lhs.minorVersion == rhs.minorVersion && lhs.patchVersion == rhs.patchVersion
    }

    public static func < (lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        if lhs.majorVersion != rhs.majorVersion { return lhs.majorVersion < rhs.majorVersion }
        if lhs.minorVersion != rhs.minorVersion { return lhs.minorVersion < rhs.minorVersion }
        return lhs.patchVersion < rhs.patchVersion
    }
}
