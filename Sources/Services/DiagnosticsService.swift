import Foundation
import Darwin

/// 诊断服务:网络连通性(URLSession)、DNS 解析(POSIX getaddrinfo + inet_ntop)、延迟测量。
/// 全部公开 API,零第三方依赖。
@MainActor
final class DiagnosticsService {
    /// 一次 GET 请求(https://host)测连通性,记录状态码与耗时(ms)。
    func ping(host: String, timeout: TimeInterval = 8) async -> PingResult {
        guard let url = URL(string: "https://\(host)") else {
            return PingResult(
                host: host,
                statusCode: nil,
                latencyMs: nil,
                resolvedIPs: [],
                errorDescription: "无法构造有效地址"
            )
        }
        let resolvedIPs = await resolveDNS(host: host)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let latency = Date().timeIntervalSince(start) * 1000
            let code = (response as? HTTPURLResponse)?.statusCode
            return PingResult(
                host: host,
                statusCode: code,
                latencyMs: latency,
                resolvedIPs: resolvedIPs,
                errorDescription: nil
            )
        } catch {
            let latency = Date().timeIntervalSince(start) * 1000
            return PingResult(
                host: host,
                statusCode: nil,
                latencyMs: latency,
                resolvedIPs: resolvedIPs,
                errorDescription: error.localizedDescription
            )
        }
    }

    /// DNS 解析(公开 POSIX getaddrinfo + inet_ntop)。失败返回 []。
    func resolveDNS(host: String) async -> [String] {
        return await Task.detached(priority: .userInitiated) {
            Self.resolveDNSBlocking(host)
        }.value
    }

    /// 连续多次请求测平均耗时(ms);全部失败返回 nil。
    func averageLatency(host: String, attempts: Int = 3) async -> Double? {
        guard attempts > 0, let url = URL(string: "https://\(host)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        var total: Double = 0
        var succeeded = 0
        for _ in 0..<attempts {
            let start = Date()
            do {
                _ = try await URLSession.shared.data(for: request)
                total += Date().timeIntervalSince(start) * 1000
                succeeded += 1
            } catch {
                // 单次失败不计入平均,继续下一次。
            }
        }
        guard succeeded > 0 else { return nil }
        return total / Double(succeeded)
    }

    /// 同步 POSIX 解析(在 Task.detached 中运行,避免阻塞主线程)。
    nonisolated private static func resolveDNSBlocking(_ host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else { return [] }
        defer { freeaddrinfo(result) }

        var ips: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = result
        while let node = current {
            defer { current = node.pointee.ai_next }
            if let addr = node.pointee.ai_addr, let ip = ipString(from: addr) {
                ips.append(ip)
            }
        }
        return ips
    }

    /// 将 sockaddr 转为 IPv4/IPv6 点分/冒号字符串。
    nonisolated private static func ipString(from addr: UnsafePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let family = addr.pointee.sa_family

        if family == sa_family_t(AF_INET) {
            return addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sa -> String? in
                var copy = sa.pointee
                guard let c = inet_ntop(AF_INET, &copy.sin_addr, &buffer, socklen_t(buffer.count)) else { return nil }
                return String(cString: c)
            }
        } else if family == sa_family_t(AF_INET6) {
            return addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sa -> String? in
                var copy = sa.pointee
                guard let c = inet_ntop(AF_INET6, &copy.sin6_addr, &buffer, socklen_t(buffer.count)) else { return nil }
                return String(cString: c)
            }
        }
        return nil
    }
}

/// 连通性诊断结果。
struct PingResult: Identifiable, Sendable, Equatable {
    let id = UUID()
    let host: String
    /// 状态码;无响应为 nil。
    let statusCode: Int?
    /// 请求耗时(ms);失败或未测为 nil。
    let latencyMs: Double?
    /// DNS 解析结果(可能为 [])。
    let resolvedIPs: [String]
    /// 错误描述;成功为 nil。
    let errorDescription: String?
}
