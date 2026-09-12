import SwiftUI

/// 全局主题常量:主色、状态色、圆角、间距。
/// 仅使用系统 SwiftUI 类型,零第三方依赖。
enum Theme {
    /// 主色橙色 #FF9500
    static let accent = Color(red: 1.0, green: 149.0 / 255.0, blue: 0.0)

    /// 状态色
    /// ✓ 支持 绿 #34C759
    static let supported = Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0)
    /// △ 部分支持 橙 #FF9500
    static let partial = accent
    /// × 不支持 红 #FF3B30
    static let unsupported = Color(red: 1.0, green: 59.0 / 255.0, blue: 48.0 / 255.0)
    /// ? 未知 灰
    static let unknown = Color(.systemGray)

    /// 卡片圆角 16
    static let cornerRadius: CGFloat = 16
    /// 卡片内边距 16
    static let cardPadding: CGFloat = 16
    /// 默认间距 12
    static let defaultSpacing: CGFloat = 12
}

extension CapabilityStatus {
    /// 状态对应的主题颜色(供 BadgeView / FeatureRowView 使用)
    var themeColor: Color {
        switch self {
        case .supported: return Theme.supported
        case .partial: return Theme.partial
        case .unsupported: return Theme.unsupported
        case .unknown: return Theme.unknown
        }
    }
}

// MARK: - 液态玻璃(Liquid Glass)外观

extension Theme {
    /// 页面色底:柔和纵向渐变(顶部系统分组灰 → 底部微暖橙),材质卡片在此之上呈现通透玻璃感。
    /// 深浅模式自适应(systemGroupedBackground/systemBackground 动态色)。
    static let pageBackdrop: AnyShapeStyle = AnyShapeStyle(
        LinearGradient(
            colors: [
                Color(uiColor: .systemGroupedBackground),
                Color(uiColor: .systemBackground),
                accent.opacity(0.10),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    )
}

extension View {
    /// 玻璃面板:iOS 17+ 统一「超薄材质 + 高光描边 + 柔和投影」,
    /// 全版本观感一致,近似 iOS 26 液态玻璃;无需 iOS 26 专属 API,
    /// 深色模式自动适配。适用于卡片/分组容器等大表面。
    func glassPanel(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.45),
                                    .white.opacity(0.08),
                                    .black.opacity(0.12),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        }
    }

    /// 玻璃细分行:比 glassPanel 更轻的「细材质 + 发丝高光」,用于玻璃卡片内部的行/条目。
    func glassRowFill(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                }
        }
    }
}
