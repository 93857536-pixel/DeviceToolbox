// 来源: YangJiiii/3105 (GPLv3),搬运/改写自 ThreeOneOSFive/helpers/ContainerStore.swift。
import Foundation

/// PosterBoard 数据容器路径解析(壁纸实验室专用)。
///
/// 与 3105 `ContainerStore.resolveAppContainerPath` 语义一致,但只针对 PosterBoard:
///   1. MCM 优先:`MCMActivateContainerPath`(mcm_bridge,类 2 = app data container)。
///      是否派发由 containermanager 守护进程按调用方身份/entitlements 决定 ——
///      免费个人签恒拒绝;全能签企业签若携带相应 entitlements 则可成功(与 3105 企业版一致)。
///   2. 回退:纯文件系统 metadata 扫描 —— 枚举 `/var/mobile/Containers/Data/Application`,
///      读每个容器的 `.com.apple.mobile_container_manager.metadata.plist` 的
///      `MCMMetadataIdentifier` 匹配 bundleID(复用 SystemContainerService 同款逻辑)。
///
/// 前置条件:metadata 扫描通道在 iOS ≥ 26 需沙盒逃逸已激活(`ExploitController.isSandboxActive()`)
/// 或无沙盒类 entitlements;MCM 通道取决于签名身份。
enum PosterBoardResolver {
    static let posterBoardBundleID = "com.apple.PosterBoard"

    /// 解析 PosterBoard 数据容器路径;模拟器或无法解析返回 nil。
    static func resolveContainerPath(bundleID: String) -> String? {
        #if targetEnvironment(simulator)
        return nil
        #else
        // 1. MCM 优先(DeviceToolbox bundle 下恒失败,见头注释)
        if let mcmPath = resolveViaMCM(bundleID: bundleID) {
            return mcmPath
        }
        // 2. metadata 扫描回退
        return resolveViaMetadataScan(bundleID: bundleID)
        #endif
    }

    /// 规范化容器路径:剥掉 /private 前缀(MCM 返回 /private/var/...,规范为 /var/...)。
    static func canonicalPath(_ path: String) -> String {
        if path == "/private" { return "/" }
        if path.hasPrefix("/private/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    /// 判断路径是否为系统 App 数据容器(canonical 前缀 + 末段 UUID)。
    static func isApplicationContainerPath(_ path: String) -> Bool {
        let canonicalRoot = canonicalPath("/var/mobile/Containers/Data/Application") + "/"
        let canonical = canonicalPath(path)
        guard canonical.hasPrefix(canonicalRoot) else { return false }
        let last = (canonical as NSString).lastPathComponent
        return UUID(uuidString: last) != nil
    }

    // MARK: - MCM

    private static func resolveViaMCM(bundleID: String) -> String? {
        var mcmError: NSString?
        let path = MCMActivateContainerPath(2, bundleID, false, &mcmError)
        if let path {
            Log.info("[WallpaperLab] MCM class-2 activate OK: \(path) (MHA-C2)")
        } else {
            let reason = mcmError.map(String.init) ?? "no error detail"
            Log.info("[WallpaperLab] MCM class-2 activate DENIED: \(reason)")
        }
        return path
    }

    // MARK: - 纯文件系统 metadata 扫描

    private static func resolveViaMetadataScan(bundleID: String) -> String? {
        let dataRoot = "/var/mobile/Containers/Data/Application"
        let fm = FileManager.default
        guard let dataDirs = try? fm.contentsOfDirectory(atPath: dataRoot) else { return nil }
        for dir in dataDirs {
            let full = (dataRoot as NSString).appendingPathComponent(dir)
            let meta = (full as NSString).appendingPathComponent(
                ".com.apple.mobile_container_manager.metadata.plist"
            )
            guard let plist = NSDictionary(contentsOfFile: meta),
                  let bid = plist["MCMMetadataIdentifier"] as? String,
                  bid == bundleID else { continue }
            return full
        }
        return nil
    }
}
