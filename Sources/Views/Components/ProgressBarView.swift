import SwiftUI

/// 能力进度条:主色填充的圆角进度条,progress ∈ 0...1。
struct ProgressBarView: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .systemGray5))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, min(1, progress)) * geometry.size.width)
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "home.capability.progress"))
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}
