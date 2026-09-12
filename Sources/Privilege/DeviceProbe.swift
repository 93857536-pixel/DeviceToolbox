import Foundation

/// 设备硬件探测:型号标识 + SoC 芯片族(全部公开 API,仅信息读取)。
enum DeviceProbe {
    /// 硬件型号标识(hw.machine,如 "iPhone16,2");模拟器返回宿主架构。
    static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// 是否为模拟器运行环境。
    static var isSimulator: Bool {
#if targetEnvironment(simulator)
        return true
#else
        return false
#endif
    }

    /// SoC 芯片族。
    enum SoCFamily: String, CaseIterable, Sendable {
        case a12
        case a13
        case a14
        case a15
        case a16
        case a17
        case a18
        case a19
        case m1
        case m2
        case m3
        case m4
        case m5
        case unknown
    }

    /// 从型号标识推断芯片族(覆盖 iPhone/iPad 主要世代)。
    static func socFamily(model: String? = nil) -> SoCFamily {
        let id = model ?? modelIdentifier
        // 模拟器与未知名
        if id == "x86_64" || id == "arm64" || id.isEmpty { return .unknown }

        // iPhone 型号表(第一代 iPhone 为 1,1;近年递增)
        // iPhone XS/XR = iPhone11,x (A12); 11 系 = iPhone12,x (A13);
        // 12 系 = iPhone13,x (A14); 13 系 = iPhone14,x (A15);
        // SE3 = iPhone14,6 (A15); 14 系 = iPhone14,x (A15/A16); 15 系 = iPhone15,x (A16/A17);
        // 16 系 = iPhone17,x? 注意: 苹果 machine 与营销代差。
        // 以已知真实映射为准(2020-2026):
        let iphoneMap: [SoCFamily: [String]] = [
            .a12: ["iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8"],
            .a13: ["iPhone12,1", "iPhone12,3", "iPhone12,5", "iPhone12,8"],
            .a14: ["iPhone13,1", "iPhone13,2", "iPhone13,3", "iPhone13,4"],
            .a15: ["iPhone14,2", "iPhone14,3", "iPhone14,4", "iPhone14,5", "iPhone14,6", "iPhone14,7", "iPhone14,8"],
            .a16: ["iPhone15,2", "iPhone15,3", "iPhone14,9", "iPhone14,10"],
            .a17: ["iPhone15,4", "iPhone15,5", "iPhone15,6", "iPhone15,7", "iPhone15,8"],
            .a18: ["iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5", "iPhone16,1", "iPhone16,2"],
            .a19: ["iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4", "iPhone18,5"],
        ]
        for (family, ids) in iphoneMap where ids.contains(id) {
            return family
        }

        // iPad(芯片世代直接对应机器前缀,iPad13,x 等复杂,只覆盖主要)
        let iPadPrefix: [(String, SoCFamily)] = [
            ("iPad8,", .a12), ("iPad11,", .a12),        // A12X/A12
            ("iPad13,", .m1), ("iPad14,", .m2),         // M1/M2 (iPad13 混 A14/15/M1)
            ("iPad16,", .m3), ("iPad17,", .m4), ("iPad18,", .m5),
        ]
        for (prefix, family) in iPadPrefix where id.hasPrefix(prefix) {
            return family
        }
        return .unknown
    }

    /// 当前设备 SoC。
    static var currentSoC: SoCFamily { socFamily() }
}
