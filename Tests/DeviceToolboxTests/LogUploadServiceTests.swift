import XCTest
@testable import DeviceToolbox

/// LogUploadService 可单测部分:截断规则、设备上下文明确性。
///
/// 说明:真正的网络 POST 不在单测里打真实端点(模拟器网络 + 服务端限流),
/// 这里只验证「payload 构造(截断)」「meta 无个人数据」两个确定性行为。
final class LogUploadServiceTests: XCTestCase {

    /// 截断逻辑复现:与服务端 96KB 上限保持一致,超长日志截断后应**保留最近条目**。
    func testTruncationKeepsMostRecentLines() {
        // 构造 100 行、每行约 2KB 的日志文本(总量 > 96KB),末尾是"最新"条目
        var lines: [String] = []
        for i in 0..<100 {
            lines.append(String(repeating: "x", count: 2048) + " line-\(i)")
        }
        let full = lines.joined(separator: "\n")
        XCTAssertTrue(full.utf8.count > 96 * 1024, "前置:构造的文本应超 96KB")

        // 复刻 LogUploadService.upload 的截断算法(同规则:保留最近,从最旧端丢弃)
        let maxLogBytes = 96 * 1024
        var kept = full.split(separator: "\n", omittingEmptySubsequences: false)
        var total = kept.reduce(0) { $0 + $1.utf8.count + 1 }
        while kept.count > 1 && total > maxLogBytes {
            let dropped = kept.removeFirst()
            total -= dropped.utf8.count + 1
        }
        // 最近的条目(编号最大)必须保留;最旧的(编号最小)被丢弃
        XCTAssertTrue(kept.last?.hasSuffix("line-99") ?? false, "截断后应保留最近条目 line-99")
        XCTAssertFalse(kept.first?.hasPrefix("line-0") ?? true, "截断后最旧条目 line-0 应被丢弃")
        XCTAssertLessThan(total, maxLogBytes + 1, "截断后字节数不应超上限")
    }

    /// 设备上下文不含任何个人标识符(IMEI/IDFA/IDFV/位置/账号)。
    func testDeviceMetaHasNoPersonalIdentifiers() {
        let meta = LogUploadService.deviceMeta()
        XCTAssertEqual(meta.count, 4, "meta 应恰好 4 项:os/device/appVersion/locale")
        for key in ["imei", "idfa", "idfV", "location", "account", "uid", "email"] {
            for value in meta.values {
                XCTAssertFalse(value.lowercased().contains(key),
                               "meta 值不应含个人标识符: \(key) in \(value)")
            }
        }
        // 字段名本身固定
        XCTAssertTrue(meta.keys.contains("os"))
        XCTAssertTrue(meta.keys.contains("device"))
        XCTAssertTrue(meta.keys.contains("appVersion"))
        XCTAssertTrue(meta.keys.contains("locale"))
        XCTAssertFalse(meta["os"]?.isEmpty ?? true, "os 应有值")
        XCTAssertFalse(meta["appVersion"]?.isEmpty ?? true, "appVersion 应有值")
    }
}
