import Foundation
import Darwin

/// 系统层信息采集:CPU 架构、运行环境、机器标识符、内核版本、主机名。
/// 仅使用公开 POSIX/Darwin 接口(uname / sysctlbyname),零第三方依赖。
@MainActor
final class SystemInfoService {
    /// 采集系统层信息。同步返回(无需网络/异步 I/O)。
    func collect() -> SystemInfo {
        return SystemInfo(
            cpuArchitecture: Self.cpuArchitecture(),
            isSimulator: Self.isSimulator,
            machineIdentifier: Self.machineIdentifier(),
            kernelVersion: Self.kernelVersion(),
            hostname: ProcessInfo.processInfo.hostName
        )
    }

    /// 是否运行在模拟器(编译期判定,公开方式)。
    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// 机器标识符(经 sysctlbyname "hw.machine"),如 "iPhone17,1"。
    private static func machineIdentifier() -> String {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// CPU 架构:优先经 sysctlbyname "hw.optional.arm64",其次按机器标识符推断。
    private static func cpuArchitecture() -> String {
        var arm64Flag: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &arm64Flag, &size, nil, 0) == 0, arm64Flag == 1 {
            return "arm64"
        }
        let machine = machineIdentifier()
        if machine.contains("arm64") || machine.contains("iPhone") || machine.contains("iPad") {
            return "arm64"
        }
        return "x86_64"
    }

    /// 内核版本与架构字符串(经 uname);失败返回 nil。
    private static func kernelVersion() -> String? {
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        let sysname = withUnsafeBytes(of: &info.sysname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let release = withUnsafeBytes(of: &info.release) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        let machine = withUnsafeBytes(of: &info.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        return "\(sysname) \(release) \(machine)"
    }
}
