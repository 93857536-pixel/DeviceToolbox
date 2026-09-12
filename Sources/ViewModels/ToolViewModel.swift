import Combine
import Foundation

/// 工具页状态:诊断任务执行状态(网络连通 / DNS / 延迟)+ 权限只读检查。
@MainActor
final class ToolViewModel: ObservableObject {
    // MARK: - 网络诊断

    @Published private(set) var isNetworkDiagnosing = false
    @Published private(set) var pingResults: [PingResult] = []
    @Published private(set) var dnsResults: [String] = []
    @Published private(set) var averageLatencyMs: Double?
    @Published private(set) var networkError: String?

    // MARK: - 权限检查(只读,不触发授权弹窗)

    @Published private(set) var permissionStatuses: [(permission: AppPermission, status: AppPermissionStatus)] = []

    // MARK: - 环境 / 设备快照(工具页内联展示)

    @Published private(set) var systemInfo: SystemInfo?

    private let diagnostics = DiagnosticsService()
    private let deviceInfoService = DeviceInfoService()

    /// 默认诊断目标:公开站点(SPEC 模块 8)。
    nonisolated static let defaultHosts = ["www.apple.com", "www.baidu.com"]

    /// 执行网络连通 / DNS / 延迟诊断。
    func runNetworkDiagnostics(hosts: [String] = ToolViewModel.defaultHosts) async {
        isNetworkDiagnosing = true
        networkError = nil
        defer { isNetworkDiagnosing = false }

        pingResults = []
        dnsResults = []
        averageLatencyMs = nil

        for host in hosts {
            let result = await diagnostics.ping(host: host)
            pingResults.append(result)
        }
        if let primary = hosts.first {
            dnsResults = await diagnostics.resolveDNS(host: primary)
            averageLatencyMs = await diagnostics.averageLatency(host: primary)
        }
    }

    /// 只读读取各类公开权限状态(绝不 request 授权)。
    func checkPermissions() {
        permissionStatuses = AppPermission.allCases.map { permission in
            (permission, PermissionService.status(of: permission))
        }
    }

    /// 采集系统信息(环境检测)。
    func loadSystemInfo() async {
        systemInfo = await deviceInfoService.collect().system
    }
}
