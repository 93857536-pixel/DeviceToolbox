import Foundation
import Darwin

/// 存储信息采集:FileManager.attributesOfFileSystem 读取总/可用容量。
/// 卷是否只读经公开 POSIX statfs 的 MNT_RDONLY 标志判定。
@MainActor
final class StorageService {
    /// 采集存储信息。同步返回。
    func collect() -> StorageInfo {
        let path = NSHomeDirectory()
        let attrs = (try? FileManager.default.attributesOfFileSystem(forPath: path)) ?? [:]
        let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let used = max(0, total - free)
        let isReadonly = Self.isVolumeReadonly(path: path)
        return StorageInfo(
            totalBytes: total,
            freeBytes: free,
            usedBytes: used,
            isReadonly: isReadonly
        )
    }

    /// 经 statfs 判断卷是否为只读挂载(MNT_RDONLY == 0x1)。失败时按可写处理。
    private static func isVolumeReadonly(path: String) -> Bool {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return false }
        let readOnlyFlag: UInt32 = 0x1 // MNT_RDONLY
        return (stats.f_flags & readOnlyFlag) != 0
    }
}
