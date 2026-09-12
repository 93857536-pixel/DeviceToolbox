import Foundation
import Combine

/// 内核访问状态机:探测 → 判定 → (P1: 执行链)。
/// P0 只做探测与判定;执行由 ExploitRunner(P1, 移植 DarkSword)接管。
@MainActor
final class KernelAccess: ObservableObject {
    enum Phase: Equatable {
        case idle
        case probing
        case ready
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelIdentifier: String = ""
    @Published private(set) var soC: DeviceProbe.SoCFamily = .unknown
    @Published private(set) var verdict: SupportMatrix.Verdict?

    /// 探测设备并给出支持判定。模拟器环境返回 unsupported(可注入测试参数)。
    func probe(
        model: String? = nil,
        version: OperatingSystemVersion? = nil,
        simulator: Bool? = nil
    ) {
        phase = .probing
        let m = model ?? DeviceProbe.modelIdentifier
        let v = version ?? ProcessInfo.processInfo.operatingSystemVersion
        let sim = simulator ?? DeviceProbe.isSimulator
        modelIdentifier = m
        soC = DeviceProbe.socFamily(model: m)
        verdict = SupportMatrix.verdict(soC: soC, iosVersion: v, isSimulator: sim)
        phase = .ready
        Log.info("Privilege probe: \(m) SoC=\(soC.rawValue) verdict=\(verdict?.chain.rawValue ?? "?")")
    }
}
