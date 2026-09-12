import Foundation

/// 能力状态枚举。
/// - `supported`:完全可用
/// - `partial`:部分可用(受系统版本/硬件/权限等限制)
/// - `unsupported`:Apple 未向第三方 App 开放,无法实现
/// - `unknown`:运行时无法确定
enum CapabilityStatus: String, Codable, Sendable, CaseIterable {
    case supported
    case partial
    case unsupported
    case unknown

    /// 状态徽章符号(纯文本,UI 层可映射为对应颜色)。
    var symbol: String {
        switch self {
        case .supported: return "✓"
        case .partial: return "△"
        case .unsupported: return "×"
        case .unknown: return "?"
        }
    }

    /// 状态显示文案(中文)。
    var displayTitle: String {
        switch self {
        case .supported: return "支持"
        case .partial: return "部分支持"
        case .unsupported: return "不支持"
        case .unknown: return "未知"
        }
    }
}

/// 一次运行时能力探测的原始结果(供 CapabilityService 汇总)。
struct CapabilityResult: Codable, Sendable, Identifiable, Equatable {
    /// 唯一标识(与 compatibility_db.json 的 feature 字段对应)
    let id: String
    /// 显示名称
    let name: String
    /// 探测/汇总后的状态
    let status: CapabilityStatus
    /// 说明(中文)
    let detail: String
    /// 是否需要用户授权
    let requiresPermission: Bool
}
