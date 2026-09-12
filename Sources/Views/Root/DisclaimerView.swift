import SwiftUI

/// 免责声明页(首次启动全屏展示,不可跳过)。
/// `onAccept` 为 nil 时表示「重看模式」,显示关闭按钮而非同意/退出。
struct DisclaimerView: View {
    /// 同意回调;nil 表示只读模式(设置页重看)。
    var onAccept: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showQuitHint = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)

                    Text(String(localized: "disclaimer.title"))
                        .font(.largeTitle.bold())

                    Text(String(localized: "disclaimer.body"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            if let onAccept {
                VStack(spacing: 12) {
                    Button(action: onAccept) {
                        Text(String(localized: "disclaimer.accept"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("disclaimer.accept")

                    Button {
                        showQuitHint = true
                    } label: {
                        Text(String(localized: "disclaimer.quit"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            } else {
                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "common.close"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(20)
            }
        }
        .background(Theme.pageBackdrop)
        .alert(String(localized: "disclaimer.quit.hint"), isPresented: $showQuitHint) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
    }
}
