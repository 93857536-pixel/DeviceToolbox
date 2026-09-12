import SwiftUI

/// 首页快捷功能的导航目标。
enum QuickRoute: Hashable {
    case networkDiagnose
    case features
    case tools
}

/// 首页:设备卡片 + 能力进度条 + 快捷卡片 + 操作按钮。
struct HomeView: View {
    @Binding var selectedTab: MainTab
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.defaultSpacing) {
                deviceCard
                capabilityCard
                quickActionsSection
                actionButtons
            }
            .padding(Theme.defaultSpacing)
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "home.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: QuickRoute.self) { route in
            switch route {
            case .networkDiagnose: NetworkDiagnoseView()
            case .features: FeaturesView()
            case .tools: ToolsView()
            }
        }
        .task {
            if viewModel.loadState == .idle {
                await viewModel.load()
            }
        }
    }

    // MARK: - 设备卡片

    private var deviceCard: some View {
        SectionCard(title: String(localized: "home.device"), systemImage: "iphone") {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.marketingName)
                        .font(.title3.bold())
                    Text("\(String(localized: "home.ios.version")) \(viewModel.systemVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - 能力进度

    private var capabilityCard: some View {
        SectionCard(title: String(localized: "home.capability"), systemImage: "checkmark.seal") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(viewModel.supportedCount) / \(viewModel.totalCount)")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.accent)
                Text(String(localized: "home.supported.of"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((viewModel.progress * 100).rounded()))%")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
            }
            ProgressBarView(progress: viewModel.progress)
            HStack(spacing: 16) {
                statPill(String(localized: "status.supported"), viewModel.supportedCount, Theme.supported)
                statPill(String(localized: "status.partial"), viewModel.partialCount, Theme.partial)
                statPill(String(localized: "status.unsupported"), viewModel.unsupportedCount, Theme.unsupported)
                Spacer()
            }
        }
    }

    private func statPill(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 快捷卡片

    private var quickActionsSection: some View {
        SectionCard(title: String(localized: "home.quick.actions"), systemImage: "square.grid.2x2") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                NavigationLink(value: QuickRoute.networkDiagnose) {
                    quickCard(icon: "stethoscope", title: String(localized: "home.quick.system.diagnose"))
                }
                .buttonStyle(.plain)

                NavigationLink(value: QuickRoute.networkDiagnose) {
                    quickCard(icon: "wifi", title: String(localized: "home.quick.network.diagnose"))
                }
                .buttonStyle(.plain)

                Button {
                    selectedTab = .device
                } label: {
                    quickCard(icon: "iphone", title: String(localized: "home.quick.device.info"))
                }
                .buttonStyle(.plain)

                Button {
                    selectedTab = .device
                } label: {
                    quickCard(icon: "battery.75", title: String(localized: "home.quick.battery"))
                }
                .buttonStyle(.plain)

                NavigationLink(value: QuickRoute.tools) {
                    quickCard(icon: "paintbrush", title: String(localized: "home.quick.personalization"))
                }
                .buttonStyle(.plain)

                NavigationLink(value: QuickRoute.tools) {
                    quickCard(icon: "gearshape.2", title: String(localized: "home.quick.system.tools"))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickCard(icon: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.reload() }
            } label: {
                Label(String(localized: "home.rescan"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            NavigationLink(value: QuickRoute.features) {
                Label(String(localized: "home.check.capabilities"), systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
    }
}
