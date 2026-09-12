import Foundation

/// 漏洞链触发的硬门禁(语义还原自 3105 ExploitSupportPolicy,自写实现)。
/// 与 SupportMatrix(芯片×档位,设置页展示)不同:这里决定 trigger() 是否真的允许执行。
/// 版本规则:
///   iOS 17.0–17.7.x / 18.0–18.7.1(不含 18.7.2+) / 26.0–26.6.1 → 支持
///   iOS 27.0 仅限 beta1–4(build ∈ 24A5355q/24A5370h/24A5380h/24A5390f)
///   iOS < 17 或其它 → 不支持
enum SupportPolicy {
    static let verifiedIOS17Range = "17.0–17.7.x"
    static let verifiedIOS18Range = "18.0–18.7.1"
    static let verifiedIOS26Range = "26.0–26.6.1"

    static let iOS27BetaBuilds: Set<String> = [
        "24A5355q", // beta 1
        "24A5370h", // beta 2
        "24A5380h", // beta 3 / public beta 1
        "24A5390f", // beta 4 / public beta 2
    ]

    /// 纯版本判定(不含 build;iOS 27.0 需要另行匹配 build)。
    static func supportsMajorMinor(major: Int, minor: Int, patch: Int) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }
        if major == 17 { return minor <= 7 }
        if major == 18 { return minor < 7 || (minor == 7 && patch <= 1) }
        if major == 26 { return minor < 6 || (minor == 6 && patch <= 1) }
        return false
    }

    /// 完整门禁(含 build)。build 仅对 iOS 27.0 生效。
    static func isSupported(major: Int, minor: Int, patch: Int, build: String?) -> Bool {
        if supportsMajorMinor(major: major, minor: minor, patch: patch) { return true }
        guard major == 27, minor == 0, patch == 0, let build else { return false }
        return iOS27BetaBuilds.contains(build)
    }

    /// 当前设备系统 build(kern.osversion;沙盒内可读,失败返回 nil)。
    static var currentBuildNumber: String? {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    /// 当前设备是否在门禁内。iOS 27.0 取不到 build 时保守返回 false。
    static func isSupportedCurrentDevice() -> Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if supportsMajorMinor(major: v.majorVersion, minor: v.minorVersion, patch: v.patchVersion) {
            return true
        }
        return isSupported(
            major: v.majorVersion,
            minor: v.minorVersion,
            patch: v.patchVersion,
            build: currentBuildNumber
        )
    }
}
