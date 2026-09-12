import Foundation
import Network

/// 网络状态采集:公开 NWPathMonitor 一次性采样。
/// 采样后立即 cancel,不保留 monitor。
@MainActor
final class NetworkService {
    /// 采集网络状态(异步:等待首次 pathUpdateHandler 回调)。
    func collect() async -> NetworkInfo {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.linminhao.DeviceToolbox.network")
        let info = await withCheckedContinuation { (continuation: CheckedContinuation<NetworkInfo, Never>) in
            let sampler = NetworkPathSampler(continuation)
            monitor.pathUpdateHandler = { path in
                sampler.resume(Self.map(path))
            }
            monitor.start(queue: queue)
        }
        monitor.cancel()
        return info
    }

    /// 将 NWPath 映射为磁盘模型 NetworkInfo(全为 Sendable 基础类型)。
    /// 在后台队列调用,故标记 nonisolated。
    nonisolated private static func map(_ path: NWPath) -> NetworkInfo {
        let status: NetworkStatus
        switch path.status {
        case .requiresConnection: status = .requiresConnection
        case .satisfied: status = .satisfied
        case .unsatisfied: status = .unsatisfied
        @unknown default: status = .unknown
        }

        let interfaceType: NetworkInterfaceType
        if path.usesInterfaceType(.wifi) {
            interfaceType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            interfaceType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            interfaceType = .wiredEthernet
        } else if path.usesInterfaceType(.loopback) {
            interfaceType = .loopback
        } else if path.usesInterfaceType(.other) {
            interfaceType = .other
        } else {
            interfaceType = .none
        }

        let interfaceNames = path.availableInterfaces.map { $0.name }

        return NetworkInfo(
            status: status,
            interfaceType: interfaceType,
            interfaceNames: interfaceNames,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            supportsIPv4: path.supportsIPv4,
            supportsIPv6: path.supportsIPv6
        )
    }
}

/// 跨线程安全的一次性 continuation 采样器:保证只 resume 一次。
private final class NetworkPathSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NetworkInfo, Never>?

    init(_ continuation: CheckedContinuation<NetworkInfo, Never>) {
        self.continuation = continuation
    }

    func resume(_ info: NetworkInfo) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: info)
    }
}
