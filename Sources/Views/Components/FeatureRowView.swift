import SwiftUI

/// 功能行:图标 + 名称 + 最低 iOS + 状态徽章。
struct FeatureRowView: View {
    let item: FeatureItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                if !item.minimumIOS.isEmpty {
                    Text("\(String(localized: "features.min.ios")) \(item.minimumIOS)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            BadgeView(status: item.status)
        }
        .padding(.vertical, 6)
        .opacity(item.isApplicable ? 1.0 : 0.5)
        .accessibilityElement(children: .combine)
    }
}
