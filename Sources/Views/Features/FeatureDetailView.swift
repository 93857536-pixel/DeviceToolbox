import SwiftUI

/// 功能详情:名称/状态/最低 iOS/权限/说明/不支持原因/操作按钮。
struct FeatureDetailView: View {
    let item: FeatureItem

    @State private var actionMessage: String?
    @State private var showActionMessage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.defaultSpacing) {
                header
                statusCard
                descriptionCard
                if item.status == .unsupported {
                    unsupportedCard
                }
                if !item.isApplicable {
                    notApplicableCard
                }
                actions
            }
            .padding(Theme.defaultSpacing)
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(actionMessage ?? "", isPresented: $showActionMessage) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
    }

    private var header: some View {
        SectionCard(title: item.name) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 64, height: 64)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.title3.bold())
                    BadgeView(status: item.status)
                }
                Spacer()
            }
        }
    }

    private var statusCard: some View {
        SectionCard(title: String(localized: "feature.detail.status")) {
            infoRow(String(localized: "feature.detail.min.ios"), item.minimumIOS.isEmpty ? String(localized: "feature.detail.min.ios.none") : item.minimumIOS)
            infoRow(String(localized: "feature.detail.requires.permission"), item.requiresPermission ? String(localized: "common.yes") : String(localized: "common.no"))
        }
    }

    private var descriptionCard: some View {
        SectionCard(title: String(localized: "feature.detail.description")) {
            Text(item.detail)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unsupportedCard: some View {
        SectionCard(title: String(localized: "feature.detail.unsupported.reason"), systemImage: "exclamationmark.triangle") {
            Text(String(localized: "feature.detail.apple.limited"))
                .font(.body)
                .foregroundStyle(Theme.unsupported)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notApplicableCard: some View {
        SectionCard(title: String(localized: "feature.detail.not.applicable"), systemImage: "xmark.circle") {
            Text(String(localized: "feature.detail.not.applicable.body"))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if item.requiresPermission {
                Button {
                    Task { await openAppSettings() }
                } label: {
                    Label(String(localized: "settings.open"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }

    private func openAppSettings() async {
        let result = await URLSchemeService.openAppSettings()
        actionMessage = result.message
        showActionMessage = true
    }
}
