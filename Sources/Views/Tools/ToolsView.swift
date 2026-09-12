import SwiftUI

/// 工具页导航目标。
enum ToolRoute: Hashable {
    case networkDiagnose
    case cleaner
    case featureFlags
}

/// 工具:诊断工具入口 + 权限检查(只读)+ 环境检测。
struct ToolsView: View {
    @StateObject private var viewModel = ToolViewModel()

    var body: some View {
        List {
            Section(String(localized: "tools.diagnostics")) {
                NavigationLink(value: ToolRoute.networkDiagnose) {
                    Label(String(localized: "tools.network.diagnose"), systemImage: "wifi")
                }
                NavigationLink(value: ToolRoute.networkDiagnose) {
                    Label(String(localized: "tools.system.diagnose"), systemImage: "stethoscope")
                }
            }

            Section(String(localized: "tools.section.cleanup")) {
                NavigationLink(value: ToolRoute.cleaner) {
                    Label(String(localized: "tools.cleaner"), systemImage: "trash")
                }
                NavigationLink(value: ToolRoute.featureFlags) {
                    Label(String(localized: "tools.featureflags"), systemImage: "flag")
                }
            }

            Section {
                if viewModel.permissionStatuses.isEmpty {
                    Text(String(localized: "tools.permission.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.permissionStatuses, id: \.permission) { entry in
                        HStack {
                            Text(permissionTitle(entry.permission))
                            Spacer()
                            Text(permissionStatusTitle(entry.status))
                                .foregroundStyle(permissionStatusColor(entry.status))
                        }
                    }
                }
            } header: {
                Text(String(localized: "tools.permission"))
            } footer: {
                Text(String(localized: "tools.permission.footer"))
            }

            Button(String(localized: "tools.permission.refresh")) {
                viewModel.checkPermissions()
            }

            Section(String(localized: "tools.environment")) {
                if let sys = viewModel.systemInfo {
                    envRow(String(localized: "device.system.arch"), sys.cpuArchitecture)
                    envRow(String(localized: "device.system.simulator"), sys.isSimulator ? String(localized: "common.yes") : String(localized: "common.no"))
                    envRow(String(localized: "device.system.hostname"), sys.hostname)
                } else {
                    Text(String(localized: "tools.environment.empty"))
                        .foregroundStyle(.secondary)
                }
            }

            Button(String(localized: "tools.environment.refresh")) {
                Task { await viewModel.loadSystemInfo() }
            }
        }
        .navigationTitle(String(localized: "tools.title"))
        .navigationDestination(for: ToolRoute.self) { route in
            switch route {
            case .networkDiagnose: NetworkDiagnoseView()
            case .cleaner: CleanerView()
            case .featureFlags: FeatureFlagsView()
            }
        }
        .task {
            viewModel.checkPermissions()
            await viewModel.loadSystemInfo()
        }
    }

    private func envRow(_ label: String, _ value: String) -> some View {
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

    // MARK: - 权限文案映射

    private func permissionTitle(_ permission: AppPermission) -> String {
        switch permission {
        case .location: return String(localized: "permission.location")
        case .camera: return String(localized: "permission.camera")
        case .microphone: return String(localized: "permission.microphone")
        case .notifications: return String(localized: "permission.notifications")
        case .photos: return String(localized: "permission.photos")
        case .contacts: return String(localized: "permission.contacts")
        case .bluetooth: return String(localized: "permission.bluetooth")
        case .faceID: return String(localized: "permission.faceid")
        }
    }

    private func permissionStatusTitle(_ status: AppPermissionStatus) -> String {
        switch status {
        case .notDetermined: return String(localized: "permission.status.notDetermined")
        case .denied: return String(localized: "permission.status.denied")
        case .restricted: return String(localized: "permission.status.restricted")
        case .authorized: return String(localized: "permission.status.authorized")
        case .limited: return String(localized: "permission.status.limited")
        case .unavailable: return String(localized: "permission.status.unavailable")
        }
    }

    private func permissionStatusColor(_ status: AppPermissionStatus) -> Color {
        switch status {
        case .authorized: return Theme.supported
        case .limited: return Theme.partial
        case .denied: return Theme.unsupported
        case .notDetermined, .restricted, .unavailable: return Theme.unknown
        }
    }
}
