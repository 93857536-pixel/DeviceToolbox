import Foundation

/// 特权引擎支持矩阵:按「iOS 版本 × SoC 芯片」判定可用漏洞链。
/// 数据依据 docs/PRIVILEGE-ENGINE.md(2026-09-05 公开生态调研)。
enum SupportMatrix {
    /// 可用漏洞链。
    enum Chain: String, Sendable {
        case darksword = "DarkSword"
        case kfd = "kfd"
        case none = "None"
    }

    /// 支持档位。
    enum Tier: String, Sendable {
        case verified = "verified"      // 第三方项目实测支持
        case claimed = "claimed"        // 3105 声称支持(需真机验证)
        case experimental = "experimental"
    }

    /// 判定结果。
    struct Verdict: Equatable, Sendable {
        let chain: Chain
        let tier: Tier?
        let note: String
        var isSupported: Bool { chain != .none }
    }

    /// 核心判定。参数可注入以便测试。
    static func verdict(
        soC: DeviceProbe.SoCFamily,
        iosVersion: OperatingSystemVersion,
        isSimulator: Bool
    ) -> Verdict {
        if isSimulator {
            return Verdict(chain: .none, tier: nil, note: "Simulator has no kernel to exploit")
        }

        // 芯片硬排除(MIE): A19 / M5 / 未知一律不支持
        switch soC {
        case .a19:
            return Verdict(chain: .none, tier: nil, note: "A19 (MIE) is not supported by any public chain")
        case .m5:
            return Verdict(chain: .none, tier: nil, note: "M5 (MIE) is not supported by any public chain")
        case .unknown:
            return Verdict(chain: .none, tier: nil, note: "Unknown SoC — no public chain can be matched")
        default:
            break
        }

        let maj = iosVersion.majorVersion
        let min = iosVersion.minorVersion
        let pat = iosVersion.patchVersion

        // iOS 17.x: 全系 DarkSword verified(17.0–17.7)
        if maj == 17 {
            return Verdict(chain: .darksword, tier: .verified,
                           note: "DarkSword verified on iOS 17.\(min)")
        }
        // iOS 18.0–18.7.1 verified; 18.7.2+ 已封
        if maj == 18 {
            if min < 7 || (min == 7 && pat <= 1) {
                return Verdict(chain: .darksword, tier: .verified,
                               note: "DarkSword verified on iOS 18.\(min)")
            }
            return Verdict(chain: .none, tier: nil, note: "iOS 18.7.2+ patched DarkSword")
        }
        // iOS 26.0–26.0.1 verified; 26.1 claimed(3105); 26.2+ 无链
        if maj == 26 {
            if min == 0 && pat <= 1 {
                return Verdict(chain: .darksword, tier: .verified, note: "DarkSword verified on iOS 26.0.x")
            }
            if min == 1 {
                return Verdict(chain: .darksword, tier: .claimed,
                               note: "DarkSword claimed by 3105 for iOS 26.1 (unverified)")
            }
            return Verdict(chain: .none, tier: nil,
                           note: "No public chain for iOS 26.\(min)")
        }
        // iOS 27: 无公开链
        if maj == 27 {
            return Verdict(chain: .none, tier: nil, note: "No public chain for iOS 27")
        }
        // iOS 15–16: DarkSword 实验档(需 offsets)
        if maj == 15 || maj == 16 {
            return Verdict(chain: .darksword, tier: .experimental,
                           note: "DarkSword experimental on iOS \(maj).x (offsets needed)")
        }
        return Verdict(chain: .none, tier: nil, note: "Unsupported legacy iOS")
    }
}
