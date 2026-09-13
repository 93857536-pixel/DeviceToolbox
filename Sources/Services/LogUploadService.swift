import Foundation
import UIKit

/// 日志上传服务:把「操作日志」页的内存日志主动上传到维护者的服务器。
///
/// 设计说明:
/// - 端点 `https://linminhao.top/api/logs/device`(阿里云 ECS + Cloudflare 隧道),
///   服务端按 IP 限流(每分钟 10 次),存于服务器端 `device-logs/` 目录(不公开)。
/// - 只上传**应用自身产生的操作日志**(内存环形缓冲)与最小设备上下文
///   (系统版本/机型/应用版本/语言),**不含任何个人数据**(IMEI/IDFA/位置/账号等)。
/// - 客户端截断:日志文本超过 96KB 时按「保留最近条目」方向截断,保证不超服务端 body 上限。
/// - 上传是用户主动触发(点按钮),不是自动上传。
final class LogUploadService: Sendable {
    struct Result: Sendable, Equatable {
        enum Status: Sendable, Equatable {
            case success
            case failure(String)
        }
        let status: Status
    }

    private static let endpoint = URL(string: "https://linminhao.top/api/logs/device")!
    /// 与服务端 express.json 128KB 上限保持安全余量(留 32KB 给 JSON 包装与 meta)。
    private static let maxLogBytes = 96 * 1024

    /// 上传日志文本 + 设备上下文。
    /// - Parameters:
    ///   - logText: 已格式化的日志纯文本(Log.exportText 产物)。
    ///   - meta: 设备/应用上下文。
    static func upload(logText: String, meta: [String: String]) async -> Result {
        var payload = logText
        // 超长截断:保留**最近**条目(报错通常在日志尾部),从最旧端丢弃。
        if (payload.data(using: .utf8)?.count ?? 0) > maxLogBytes {
            var lines = logText.split(separator: "\n", omittingEmptySubsequences: false)
            var total = lines.reduce(0) { $0 + $1.utf8.count + 1 }
            while lines.count > 1 && total > maxLogBytes {
                let dropped = lines.removeFirst()
                total -= dropped.utf8.count + 1
            }
            payload = "[…] 日志过长,已保留最近条目 \n" + lines.joined(separator: "\n")
        }

        struct Body: Encodable {
            let log: String
            let meta: [String: String]
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(Body(log: payload, meta: meta))
        } catch {
            return Result(status: .failure("日志编码失败"))
        }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Result(status: .failure("服务器无响应"))
            }
            switch http.statusCode {
            case 200...299:
                return Result(status: .success)
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After") ?? "60"
                return Result(status: .failure("上传过于频繁,请 \(retry) 秒后再试"))
            case 400:
                return Result(status: .failure("日志内容为空或超出限制"))
            default:
                let snippet = String(data: responseData.prefix(200), encoding: .utf8) ?? ""
                return Result(status: .failure("服务器拒绝(HTTP \(http.statusCode))\(snippet.isEmpty ? "" : ":\(snippet)")"))
            }
        } catch {
            return Result(status: .failure("网络错误:\(error.localizedDescription)"))
        }
    }

    /// 采集最小设备上下文(无个人数据):系统版本、机型、应用版本、语言。
    static func deviceMeta() -> [String: String] {
        let device = UIDevice.current
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return [
            "os": "iOS \(device.systemVersion)",
            "device": device.model,
            "appVersion": appVersion,
            "locale": Locale.current.identifier,
        ]
    }
}
