import Foundation

/// 文件条目:沙盒浏览列表中的一行数据。
/// 只读快照,由服务层 `stat` / `listDirectory` 生成。
struct FileEntry: Identifiable, Hashable, Sendable {
    /// 显示名称(路径最后一段)。
    let name: String
    /// 完整绝对路径(限定在 app 沙盒内)。
    let path: String
    /// 是否为目录。
    let isDirectory: Bool
    /// 字节大小(目录为 0)。
    let size: Int64
    /// 最后修改时间。
    let modifiedAt: Date
    /// 子条目数量(仅目录有效,文件为 0)。
    let childCount: Int

    var id: String { path }

    var url: URL { URL(fileURLWithPath: path) }

    init(name: String, path: String, isDirectory: Bool, size: Int64, modifiedAt: Date, childCount: Int = 0) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
        self.childCount = childCount
    }

    /// 从磁盘 URL 读取资源属性构建条目;目录会顺带统计直接子项数量。
    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let isDirectory = values.isDirectory == true
        let childCount: Int
        if isDirectory {
            childCount = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
        } else {
            childCount = 0
        }
        self.init(
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: isDirectory,
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
            childCount: childCount
        )
    }
}
