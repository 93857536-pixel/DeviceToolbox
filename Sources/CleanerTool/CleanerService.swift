import Foundation

/// 清理器服务:沙盒安全区扫描/删除 + 逃逸后系统缓存只读预览。
/// 纯文件系统操作,零私有 API;系统区删除仅限 /var/mobile/Library/Caches 下的明确白名单子目录。
enum CleanerService: Sendable {

    /// 单个可清理条目(文件或目录)。
    struct CleanableItem: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let path: String
        let sizeBytes: Int64
        let isDirectory: Bool
        let isSystem: Bool
        /// 是否允许删除(沙盒区恒 true;系统区仅白名单子目录为 true)。
        let deletable: Bool
    }

    /// 扫描结果(纯值,可跨 actor)。
    struct ScanResult: Sendable {
        let sandboxItems: [CleanableItem]
        let systemItems: [CleanableItem]
        let sandboxTotalBytes: Int64
        let systemTotalBytes: Int64
    }

    /// 删除结果。
    struct DeleteResult: Sendable {
        let deletedCount: Int
        let freedBytes: Int64
        let failedCount: Int
    }

    // MARK: - 路径

    private static let systemGlobalCaches = "/var/mobile/Library/Caches"
    private static let systemDataSystem = "/var/mobile/Containers/Data/System"

    /// 系统全局缓存下「明确可安全清理」的白名单子目录名(谨慎,标注实验性)。
    private static let deletableSystemCacheNames: Set<String> = [
        "com.apple.iapd",
        "Snapshots",
        "com.apple.PurpleBuddy",
        "com.apple.AppStore",
    ]

    // MARK: - 扫描

    static func scan() async -> ScanResult {
        await Task.detached(priority: .userInitiated) { scanSync() }.value
    }

    private static func scanSync() -> ScanResult {
        var sandboxItems: [CleanableItem] = []
        sandboxItems += children(of: SandboxRoots.imported, inSystemArea: false, deletableNames: [])
        sandboxItems += children(of: SandboxRoots.temporary, inSystemArea: false, deletableNames: [])
        sandboxItems += children(of: SandboxRoots.caches, inSystemArea: false, deletableNames: [])

        var systemItems: [CleanableItem] = []
        #if !targetEnvironment(simulator)
        if ExploitController.isSandboxActive() || SystemContainerService.isSystemRootAccessible() {
            // 全局缓存:仅白名单子目录可删,其余只预览
            systemItems += children(
                of: URL(fileURLWithPath: systemGlobalCaches),
                inSystemArea: true,
                deletableNames: deletableSystemCacheNames
            )
            // 系统容器各自的 Library/Caches:一律只读预览
            if let dirs = try? FileManager.default.contentsOfDirectory(atPath: systemDataSystem) {
                for d in dirs {
                    let caches = URL(fileURLWithPath: systemDataSystem)
                        .appendingPathComponent(d)
                        .appendingPathComponent("Library/Caches")
                    systemItems += children(of: caches, inSystemArea: true, deletableNames: [])
                }
            }
        }
        #endif

        let sandboxTotal = sandboxItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let systemTotal = systemItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return ScanResult(
            sandboxItems: sandboxItems,
            systemItems: systemItems,
            sandboxTotalBytes: sandboxTotal,
            systemTotalBytes: systemTotal
        )
    }

    // MARK: - 删除

    static func delete(items: [CleanableItem]) async -> DeleteResult {
        await Task.detached(priority: .userInitiated) { deleteSync(items) }.value
    }

    private static func deleteSync(_ items: [CleanableItem]) -> DeleteResult {
        var deleted = 0
        var freed: Int64 = 0
        var failed = 0
        let fm = FileManager.default
        for item in items {
            guard isDeletablePath(item.path) else {
                failed += 1
                continue
            }
            do {
                try fm.removeItem(atPath: item.path)
                deleted += 1
                freed += item.sizeBytes
            } catch {
                failed += 1
            }
        }
        return DeleteResult(deletedCount: deleted, freedBytes: freed, failedCount: failed)
    }

    /// 删除安全门禁:仅沙盒三大安全区 + 系统全局缓存白名单子目录。
    private static func isDeletablePath(_ path: String) -> Bool {
        let sandboxBases = [SandboxRoots.imported.path, SandboxRoots.temporary.path, SandboxRoots.caches.path]
        for base in sandboxBases where path.hasPrefix(base + "/") {
            return true
        }
        #if !targetEnvironment(simulator)
        if path.hasPrefix(systemGlobalCaches + "/") {
            let name = (path as NSString).lastPathComponent
            return deletableSystemCacheNames.contains(name)
        }
        #endif
        return false
    }

    // MARK: - 枚举辅助

    private static func children(of url: URL, inSystemArea: Bool, deletableNames: Set<String>) -> [CleanableItem] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return [] }
        return names.compactMap { name -> CleanableItem? in
            let child = url.appendingPathComponent(name)
            guard let values = try? child.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ]) else { return nil }
            guard values.isSymbolicLink != true else { return nil }
            let isDir = values.isDirectory == true
            guard isDir || values.isRegularFile == true else { return nil }
            let size: Int64 = isDir ? directorySize(at: child) : Int64(values.fileSize ?? 0)
            let deletable = !inSystemArea || deletableNames.contains(name)
            return CleanableItem(
                id: child.path,
                name: name,
                path: child.path,
                sizeBytes: size,
                isDirectory: isDir,
                isSystem: inSystemArea,
                deletable: deletable
            )
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// 递归统计目录总大小(跳过符号链接,设条目/总量上限防爆)。
    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else { return 0 }
        var count = 0
        for case let child as URL in enumerator {
            guard count < 200_000 else { break }
            count += 1
            guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
            if total > 1_000_000_000_000 { break } // 1 TB 上限
        }
        return total
    }

    // MARK: - 展示

    /// 字节数 → 人类可读文本(自由函数,主线程/后台均可用)。
    static func formatBytes(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[index])
    }
}

/// 通用操作失败错误:把错误文案包装成 Error(供 `Result<T, OperationFailure>` 跨 actor 传递)。
/// 各新功能模块(清理器 / Feature Flags / Gestalt / 导出 / 日志)复用。
struct OperationFailure: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
