import Foundation

/// 功能来源。
enum FeatureSource: String, Codable, Sendable {
    /// 来自兼容性数据库(compatibility_db.json)
    case database
    /// App 本地内置功能
    case local
}

/// 功能中心条目模型(名称/图标/状态/最低iOS/说明/URLScheme)。
struct FeatureItem: Codable, Sendable, Identifiable, Equatable {
    /// 唯一标识
    let id: String
    /// 显示名称(中文)
    let name: String
    /// SF Symbol 图标名,如 "battery.100"
    let icon: String
    /// 状态(可能被运行时探测覆盖)
    let status: CapabilityStatus
    /// 最低 iOS 版本(空字符串表示无下限)
    let minimumIOS: String
    /// 中文说明
    let detail: String
    /// 关联的 URL Scheme(可选,如跳转设置)
    let urlScheme: String?
    /// 是否需要用户授权
    let requiresPermission: Bool
    /// 来源
    let source: FeatureSource
    /// 是否适用当前设备(运行时过滤后)
    let isApplicable: Bool
}
