import Foundation

/// 系统容器浏览(沙盒逃逸激活后可用;纯文件系统扫描,无私有 API、无 MHA token 依赖)。
/// 两条通道:
///   1. MCM/bad_query(mcm_bridge.m)——需要 MHA 身份,免费/全能签走不通,仅编译保留;
///   2. 纯文件系统扫描(本类型主通道)——逃逸后 sandbox 扩展已改,标准 FileManager 可列系统目录。
/// 任何一步失败整体返回空(不抛)。
enum SystemContainerService {

    /// 系统已安装 App 条目。
    struct SystemAppEntry: Identifiable, Equatable, Sendable {
        let bundleID: String
        let name: String
        let iconName: String?
        let bundleURL: URL
        let dataContainerURL: URL?

        var id: String { bundleID }
    }

    /// 逃逸激活后是否能访问系统容器根(/var/mobile/Containers)。
    static func isSystemRootAccessible() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return FileManager.default.isReadableFile(atPath: "/var/mobile/Containers")
        #endif
    }

    /// 列出系统已装 App + 数据容器(尽力而为,失败静默返空)。
    static func listInstalledApps() async -> [SystemAppEntry] {
        #if targetEnvironment(simulator)
        return []
        #else
        guard isSystemRootAccessible() else { return [] }
        return await Task.detached(priority: .utility) { scanSync() }.value
        #endif
    }

    // MARK: - 扫描实现(同步,后台线程)

    private static func scanSync() -> [SystemAppEntry] {
        let fm = FileManager.default
        let bundleRoot = "/var/containers/Bundle/Application"
        let dataRoot = "/var/mobile/Containers/Data/Application"

        // 1. 枚举 .app bundle
        var appPaths: [String] = []
        if let dirs = try? fm.contentsOfDirectory(atPath: bundleRoot) {
            for d in dirs {
                let full = (bundleRoot as NSString).appendingPathComponent(d)
                if let apps = try? fm.contentsOfDirectory(atPath: full) {
                    for a in apps where a.hasSuffix(".app") {
                        appPaths.append((full as NSString).appendingPathComponent(a))
                    }
                }
            }
        }

        // 2. bundleID → 数据容器路径 映射(metadata plist 匹配)
        var containerByID: [String: String] = [:]
        if let dataDirs = try? fm.contentsOfDirectory(atPath: dataRoot) {
            for d in dataDirs {
                let full = (dataRoot as NSString).appendingPathComponent(d)
                let meta = (full as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                guard let plist = NSDictionary(contentsOfFile: meta),
                      let bid = plist["MCMMetadataIdentifier"] as? String else { continue }
                containerByID[bid] = full
            }
        }

        // 3. 组装条目
        var entries: [SystemAppEntry] = []
        for app in appPaths {
            let infoPlist = (app as NSString).appendingPathComponent("Info.plist")
            guard let info = NSDictionary(contentsOfFile: infoPlist),
                  let bid = info["CFBundleIdentifier"] as? String else { continue }
            let displayName = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String) ?? bid
            let icon = (info["CFBundleIcons"] as? NSDictionary)?["CFBundlePrimaryIcon"] as? NSDictionary
            let iconFiles = icon?["CFBundleIconFiles"] as? [String]
            entries.append(SystemAppEntry(
                bundleID: bid,
                name: displayName,
                iconName: iconFiles?.first,
                bundleURL: URL(fileURLWithPath: app),
                dataContainerURL: containerByID[bid].map(URL.init(fileURLWithPath:))
            ))
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
