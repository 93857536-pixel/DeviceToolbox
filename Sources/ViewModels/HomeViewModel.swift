import Combine
import Foundation

/// 首页聚合状态:设备摘要、能力统计与进度、加载态。
@MainActor
final class HomeViewModel: ObservableObject {
    /// 加载状态。
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var deviceInfo: DeviceInfo?
    @Published private(set) var capabilities: [CapabilityResult] = []

    private let deviceInfoService = DeviceInfoService()
    private let capabilityService = CapabilityService()

    // MARK: - 设备摘要

    /// 设备市场名称(如 "iPhone 16 Pro"),未加载时为空。
    var marketingName: String {
        deviceInfo?.hardware.marketingName ?? String(localized: "home.loading")
    }

    /// 系统版本(如 "17.5")。
    var systemVersion: String {
        deviceInfo?.software.systemVersion ?? "—"
    }

    /// 设备大类(如 "iPhone")。
    var deviceType: String {
        deviceInfo?.hardware.deviceType ?? "—"
    }

    // MARK: - 能力统计

    /// 完全支持的数量。
    var supportedCount: Int {
        capabilities.count(where: { $0.status == .supported })
    }

    /// 部分支持的数量。
    var partialCount: Int {
        capabilities.count(where: { $0.status == .partial })
    }

    /// 不支持的数量。
    var unsupportedCount: Int {
        capabilities.count(where: { $0.status == .unsupported })
    }

    /// 能力条目总数。
    var totalCount: Int {
        capabilities.count
    }

    /// 能力进度(0...1),以「完全支持 / 总数」计算。
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(supportedCount) / Double(totalCount)
    }

    // MARK: - 加载

    /// 并发采集设备信息与能力评估。
    func load() async {
        loadState = .loading
        deviceInfo = await deviceInfoService.collect()
        capabilities = await capabilityService.evaluate()
        loadState = .loaded
        Log.info("首页数据加载完成:能力 \(capabilities.count) 项")
    }

    /// 重新检测(别名,语义等价于 load)。
    func reload() async {
        await load()
    }
}
