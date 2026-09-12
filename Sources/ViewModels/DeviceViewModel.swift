import Combine
import Foundation

/// 设备详情状态:分组设备信息 + 加载态。
@MainActor
final class DeviceViewModel: ObservableObject {
    @Published private(set) var deviceInfo: DeviceInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let deviceInfoService = DeviceInfoService()

    /// 采集全量设备信息(硬件/软件/存储/电池/屏幕/网络/系统)。
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        deviceInfo = await deviceInfoService.collect()
    }

    /// 重新检测。
    func reload() async {
        await load()
    }
}
