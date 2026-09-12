import SwiftUI

/// 状态徽章:✓支持 / △部分 / ×不支持 / ?未知。
/// 颜色复用 `CapabilityStatus.themeColor`,文案走本地化。
struct BadgeView: View {
    let status: CapabilityStatus

    var body: some View {
        HStack(spacing: 4) {
            Text(status.symbol)
                .accessibilityHidden(true)
            Text(Self.title(for: status))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(status.themeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.themeColor.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityLabel(Self.title(for: status))
    }

    /// 状态显示文案(本地化)。
    static func title(for status: CapabilityStatus) -> String {
        switch status {
        case .supported: return String(localized: "status.supported")
        case .partial: return String(localized: "status.partial")
        case .unsupported: return String(localized: "status.unsupported")
        case .unknown: return String(localized: "status.unknown")
        }
    }
}
