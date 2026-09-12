import Foundation

/// Apple Intelligence 强开策略矩阵(纯判定,可单测)。
///
/// 依据(功能性事实,非代码搬运;来源: leminlimez/Nugget、rooootdev/mond、EnsWilde、misaka26
/// 社区报告与 f1shy-dev/icedmoca gist —— 均为「键名/路径/版本窗口」事实性数据):
/// - 写入落点: MobileGestalt 缓存 CacheExtra + /var/db/eligibilityd/eligibility.plist(GREYMATTER)。
/// - AI 框架 18.1 才引入 → 17.x / 18.0 无强开对象。
/// - 18.1b5+ 服务端对「硬件不支持机型」的模型下载做断言 → ≤A16 机型在 18.1 正式版起不可行。
/// - 26.0–26.1 有 A16(iPhone 15 Plus)经明文键 + ProductType 伪装成功先例(misaka26/Nugget 7.2)。
/// - 本工程 ExploitCore 内核链(offsets.m 运行时 guard)实际覆盖 iOS 17.0–26.0.x;
///   iOS 27.0 beta1–4 依赖 bad_query 通道(与 mond 同源机制),27.0 正式版起无可验证通道。
/// - 26.5+ 有报告称 eligibility 改写失效(Nugget issue #1073);本工程内核窗口 ≤26.0.x,不受影响。
enum AIEnablePolicy {

    enum Target: String, Sendable, Equatable {
        case official       // 官方支持(非国行 / 已解锁地区),无需强开
        case regionUnlock   // 地区锁解锁(国行 CH/A;或资格表兜底写入,幂等)
        case hardwareSpoof  // 硬件不支持(A16 及以下),需伪装机型下载模型
        case unavailable    // 此版本/机型组合不可行
    }

    struct Verdict: Equatable, Sendable {
        let target: Target
        /// 实验性(证据来自社区单点报告/他工具自述,未在全部机型复现)。
        let experimental: Bool
        /// 附加说明(中文)。
        let note: String
        /// 是否需要沙盒逃逸激活才能执行。
        let requiresEscape: Bool

        var isActionable: Bool { target == .regionUnlock || target == .hardwareSpoof }
    }

    /// iOS 27.0 beta1–4 build(与 SupportPolicy 门禁一致)。
    private static let iOS27BetaBuilds: Set<String> = [
        "24A5355q", "24A5370h", "24A5380h", "24A5390f",
    ]

    // MARK: - 机型能力

    /// 官方支持 Apple Intelligence 的机型(A17 Pro 起;M1 起 iPad;A17 Pro iPad mini)。
    /// 对照 Nugget 伪装型号表(事实): iPhone16,1/16,2=15 Pro(Max), iPhone17,x=16 系, iPhone18,x=17 系。
    private static let officialPhonePrefixes = ["iPhone16,1", "iPhone16,2", "iPhone17,", "iPhone18,"]
    private static let officialIPadPrefixes = ["iPad13,", "iPad14,", "iPad16,"]

    static func isOfficialAISupport(model: String) -> Bool {
        if officialPhonePrefixes.contains(where: { model.hasPrefix($0) }) { return true }
        if officialIPadPrefixes.contains(where: { model.hasPrefix($0) }) { return true }
        return false
    }

    // MARK: - 通道与框架

    /// AI 框架存在(18.1+)。
    static func hasAIFramework(major: Int, minor: Int) -> Bool {
        major > 18 || (major == 18 && minor >= 1)
    }

    /// 内核逃逸通道覆盖(与 ExploitCore offsets.m 运行时 guard `>=17.0 && <26.1` 对齐)。
    static func hasKernelEscape(major: Int, minor: Int) -> Bool {
        (major == 17 || major == 18) || (major == 26 && minor == 0)
    }

    /// bad_query 通道(仅 27.0 beta1–4 理论窗口,与 mond 支持范围一致)。
    static func hasBadQueryRoute(major: Int, minor: Int, patch: Int, build: String?) -> Bool {
        major == 27 && minor == 0 && patch == 0 && (build.map(iOS27BetaBuilds.contains) ?? false)
    }

    // MARK: - 主判定

    /// - Parameters:
    ///   - model: hw.machine(如 iPhone15,5)。
    ///   - build: kern.osversion(仅 27.0 判定用)。
    static func verdict(model: String,
                        major: Int, minor: Int, patch: Int,
                        build: String?,
                        isSimulator: Bool) -> Verdict {
        if isSimulator {
            return Verdict(target: .unavailable, experimental: false,
                           note: "模拟器无真实系统与资格服务,不可强开。", requiresEscape: false)
        }
        guard hasAIFramework(major: major, minor: minor) else {
            return Verdict(target: .unavailable, experimental: false,
                           note: "Apple Intelligence 自 iOS 18.1 起引入,本系统无此框架,无法强开。",
                           requiresEscape: false)
        }

        let officialHW = isOfficialAISupport(model: model)
        let kernel = hasKernelEscape(major: major, minor: minor)
        let badQuery = hasBadQueryRoute(major: major, minor: minor, patch: patch, build: build)

        // 27.0 beta1–4: 仅有 bad_query 通道(mond 验证 gestalt 可写;无 root 时资格表不可写)
        if major == 27 {
            guard badQuery else {
                return Verdict(target: .unavailable, experimental: false,
                               note: "iOS 27.0 正式版(beta5+)已无可验证的强开通道(内核链不支持 27)。",
                               requiresEscape: false)
            }
            if !officialHW {
                return Verdict(target: .unavailable, experimental: true,
                               note: "27.0b1–4 的 AI 机型伪装在 ≤A16 机型上社区报告失效(mond known issue),暂不可行。",
                               requiresEscape: true)
            }
            return Verdict(target: .regionUnlock, experimental: true,
                           note: "27.0 beta1–4 实验性地区解锁:经 bad_query 写 MobileGestalt 地区键;资格表(root 文件)可能不可写,成败需实测。",
                           requiresEscape: false)
        }

        // 26.x: 主战场
        if major == 26 {
            guard kernel else {
                return Verdict(target: .unavailable, experimental: false,
                               note: "本工程内核链窗口为 iOS 26.0.x;26.1+ 无可用写入通道(PC 侧 BookRestore 通道已封)。",
                               requiresEscape: true)
            }
            if !officialHW {
                return Verdict(target: .hardwareSpoof, experimental: true,
                               note: "26.0.x 硬件强开(实验性):写 AppleIntelligence 明文键 + 伪装 iPhone16,1(15 Pro),重启联网等待模型下载;服务端断言强度需实测(26.1 A16 有成功先例)。",
                               requiresEscape: true)
            }
            return Verdict(target: .regionUnlock, experimental: false,
                           note: "26.0.x 地区/资格解锁:写 MobileGestalt 地区键(LL)+ eligibility GREYMATTER/CALCIUM,重启生效;若为 LL/A 非国行,写入幂等无害。",
                           requiresEscape: true)
        }

        // 18.x
        if major == 18 {
            if !officialHW {
                return Verdict(target: .unavailable, experimental: false,
                               note: "18.1b5 起 Apple 在模型下载端点做服务端硬件断言,≤A16 机型强开已被封(仅 18.1 beta1–4 有效)。",
                               requiresEscape: true)
            }
            if minor == 1 && patch == 0 {
                // 18.1 正式版即 b5+ 之后
                return Verdict(target: .unavailable, experimental: false,
                               note: "iOS 18.1 正式版已含服务端地区断言;国行解锁请升级至 18.4+/26.x 后再试。",
                               requiresEscape: true)
            }
            return Verdict(target: .regionUnlock, experimental: false,
                           note: "18.4–18.7 地区解锁:写 MobileGestalt 地区键 + eligibility 资格表,重启生效。",
                           requiresEscape: true)
        }

        return Verdict(target: .unavailable, experimental: false,
                       note: "此系统版本不在支持矩阵内。", requiresEscape: false)
    }
}
