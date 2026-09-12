import SwiftUI

/// 分组卡片容器:标题(可选 SF Symbol)+ 内容,圆角卡片样式。
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.defaultSpacing) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .glassPanel()
    }
}

extension Color {
    /// 页面背景(systemGroupedBackground),支持深色模式。
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    /// 卡片背景(secondarySystemGroupedBackground),支持深色模式。
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}
