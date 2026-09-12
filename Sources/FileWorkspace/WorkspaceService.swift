import Foundation

/// 复制/移动的冲突处理策略。
enum FileConflictPolicy: String, Sendable, Hashable {
    case fail
    case replace
    case keepBoth
}

/// 传输方式:复制或移动。
enum FileTransferMode: String, Sendable, Hashable {
    case copy
    case move
}

/// 单次复制/移动的结果。
struct FileTransferResult: Equatable, Sendable {
    enum Disposition: String, Equatable, Sendable {
        case copied
        case moved
        case replaced
        case renamed
    }

    let sourceURL: URL
    let destinationURL: URL
    let disposition: Disposition
}

/// 批量操作中单条失败的记录。
struct FileTransferFailure: Equatable, Sendable {
    let sourceURL: URL
    let error: FileOperationError
}

/// 批量复制/移动的结果:成功项 + 失败项。
struct FileBatchResult: Equatable, Sendable {
    let transferred: [FileTransferResult]
    let failures: [FileTransferFailure]

    var succeededCount: Int { transferred.count }
    var failedCount: Int { failures.count }
}

/// 文件工作台服务层:沙盒内浏览 / 增删改 / 复制移动(冲突策略 fail|replace|keepBoth) / 批量。
/// 所有操作严格限定在 FileManager 可达的沙盒范围内,拒绝符号链接与递归目标。
enum WorkspaceService: Sendable {
    private static let maximumNameByteCount = 255
    private static let copyChunkSize = 1_024 * 1_024

    // MARK: - 浏览

    /// 列出目录直接子项(目录在前,随后按名称不区分大小写排序)。
    static func listDirectory(at directoryURL: URL) throws -> [FileEntry] {
        try requireDirectory(directoryURL)
        let fm = FileManager.default
        let childURLs: [URL]
        do {
            childURLs = try fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw FileOperationError.cannotRead
        }
        let entries = try childURLs.map { try FileEntry(url: $0) }
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// 读取单个条目的元数据。
    static func stat(at url: URL) throws -> FileEntry {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileOperationError.sourceMissing
        }
        return try FileEntry(url: url)
    }

    // MARK: - 增删改

    /// 新建文件夹,返回其 URL。
    @discardableResult
    static func makeDirectory(named rawName: String, in directoryURL: URL) throws -> URL {
        let destination = try destinationURL(named: rawName, in: directoryURL, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.itemAlreadyExists
        }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            return destination
        } catch {
            throw FileOperationError.cannotCreate
        }
    }

    /// 重命名条目,返回新 URL。改名前后路径相同则原样返回。
    @discardableResult
    static func renameItem(at sourceURL: URL, to rawName: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw FileOperationError.sourceMissing
        }
        try requireNotSymbolicLink(sourceURL)
        let parent = sourceURL.deletingLastPathComponent()
        let destination = try destinationURL(named: rawName, in: parent, isDirectory: false)
        if destination.standardizedFileURL == sourceURL.standardizedFileURL {
            return sourceURL
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.itemAlreadyExists
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
            return destination
        } catch {
            throw FileOperationError.cannotRename
        }
    }

    /// 删除条目(文件或文件夹)。
    static func deleteItem(at itemURL: URL) throws {
        guard FileManager.default.fileExists(atPath: itemURL.path) else {
            throw FileOperationError.sourceMissing
        }
        try requireNotSymbolicLink(itemURL)
        do {
            try FileManager.default.removeItem(at: itemURL)
        } catch {
            throw FileOperationError.cannotDelete
        }
    }

    // MARK: - 复制 / 移动

    /// 复制单个条目到目标目录,冲突策略决定同名处理。
    @discardableResult
    static func copyItem(
        at sourceURL: URL,
        into directoryURL: URL,
        conflictPolicy: FileConflictPolicy = .fail
    ) throws -> FileTransferResult {
        try transferItem(at: sourceURL, into: directoryURL, mode: .copy, conflictPolicy: conflictPolicy)
    }

    /// 移动单个条目到目标目录。
    @discardableResult
    static func moveItem(
        at sourceURL: URL,
        into directoryURL: URL,
        conflictPolicy: FileConflictPolicy = .fail
    ) throws -> FileTransferResult {
        try transferItem(at: sourceURL, into: directoryURL, mode: .move, conflictPolicy: conflictPolicy)
    }

    /// 批量复制/移动:单条失败不中断,返回成功与失败清单。
    static func transferItems(
        _ sourceURLs: [URL],
        into directoryURL: URL,
        mode: FileTransferMode,
        conflictPolicy: FileConflictPolicy = .fail
    ) throws -> FileBatchResult {
        try requireDirectory(directoryURL)
        var transferred: [FileTransferResult] = []
        var failures: [FileTransferFailure] = []
        for source in sourceURLs {
            do {
                transferred.append(try transferItem(at: source, into: directoryURL, mode: mode, conflictPolicy: conflictPolicy))
            } catch let error as FileOperationError {
                failures.append(FileTransferFailure(sourceURL: source, error: error))
            }
        }
        return FileBatchResult(transferred: transferred, failures: failures)
    }

    // MARK: - 传输核心

    private static func transferItem(
        at sourceURL: URL,
        into directoryURL: URL,
        mode: FileTransferMode,
        conflictPolicy: FileConflictPolicy
    ) throws -> FileTransferResult {
        let fm = FileManager.default
        let source = sourceURL.standardizedFileURL
        let destinationDirectory = directoryURL.standardizedFileURL

        guard fm.fileExists(atPath: source.path) else { throw FileOperationError.sourceMissing }
        try requireNotSymbolicLink(source)
        try requireDirectory(destinationDirectory)

        let isDirectory = try isDirectory(source)
        // 递归目标检查:目录不能移入自身或其后代。
        if isDirectory {
            let sourcePrefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
            let destPath = destinationDirectory.path.hasSuffix("/")
                ? destinationDirectory.path
                : destinationDirectory.path + "/"
            if destinationDirectory.path == source.path || destPath.hasPrefix(sourcePrefix) {
                throw FileOperationError.recursiveDestination
            }
        }

        let requested = destinationDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: isDirectory)
        if mode == .move, requested.standardizedFileURL == source.standardizedFileURL {
            return FileTransferResult(sourceURL: source, destinationURL: requested, disposition: .moved)
        }

        let exists = fm.fileExists(atPath: requested.path)
        let destination: URL
        let replacing: Bool
        if exists {
            switch conflictPolicy {
            case .fail:
                throw FileOperationError.itemAlreadyExists
            case .replace:
                destination = requested
                replacing = true
            case .keepBoth:
                destination = keepBothDestination(for: requested, isDirectory: isDirectory)
                replacing = false
            }
        } else {
            destination = requested
            replacing = false
        }

        do {
            switch mode {
            case .copy:
                try installCopy(source, to: destination, replacing: replacing)
            case .move:
                try installMove(source, to: destination, replacing: replacing)
            }
        } catch let error as FileOperationError {
            throw error
        } catch {
            throw mode == .copy ? FileOperationError.cannotCopy : FileOperationError.cannotMove
        }

        let disposition: FileTransferResult.Disposition
        if replacing {
            disposition = .replaced
        } else if destination != requested {
            disposition = .renamed
        } else {
            disposition = mode == .copy ? .copied : .moved
        }
        return FileTransferResult(sourceURL: source, destinationURL: destination, disposition: disposition)
    }

    private static func installCopy(_ source: URL, to destination: URL, replacing: Bool) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".copy-\(UUID().uuidString)", isDirectory: false)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.copyItem(at: source, to: staging)
            if replacing {
                let backup = destination.deletingLastPathComponent()
                    .appendingPathComponent(".displaced-\(UUID().uuidString)", isDirectory: false)
                try fm.moveItem(at: destination, to: backup)
                do {
                    try fm.moveItem(at: staging, to: destination)
                    try? fm.removeItem(at: backup)
                } catch {
                    if !fm.fileExists(atPath: destination.path) {
                        try? fm.moveItem(at: backup, to: destination)
                    }
                    throw FileOperationError.cannotCopy
                }
            } else {
                try fm.moveItem(at: staging, to: destination)
            }
        } catch let error as FileOperationError {
            throw error
        } catch {
            throw FileOperationError.cannotCopy
        }
    }

    private static func installMove(_ source: URL, to destination: URL, replacing: Bool) throws {
        let fm = FileManager.default
        if !replacing {
            do {
                try fm.moveItem(at: source, to: destination)
                return
            } catch {
                // 跨卷移动失败时退化为复制+删除。
                do {
                    try installCopy(source, to: destination, replacing: false)
                    try fm.removeItem(at: source)
                    return
                } catch {
                    try? fm.removeItem(at: destination)
                    throw FileOperationError.cannotMove
                }
            }
        }
        let backup = destination.deletingLastPathComponent()
            .appendingPathComponent(".displaced-\(UUID().uuidString)", isDirectory: false)
        do {
            try fm.moveItem(at: destination, to: backup)
            do {
                try fm.moveItem(at: source, to: destination)
                try? fm.removeItem(at: backup)
            } catch {
                if !fm.fileExists(atPath: destination.path) {
                    try? fm.moveItem(at: backup, to: destination)
                }
                throw FileOperationError.cannotMove
            }
        } catch {
            throw FileOperationError.cannotMove
        }
    }

    // MARK: - 工具

    /// 校验目录存在且确为目录(供兄弟服务与测试复用)。
    static func requireDirectory(_ directoryURL: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directoryURL.path, isDirectory: &isDir) else {
            throw FileOperationError.destinationMissing
        }
        guard isDir.boolValue else {
            throw FileOperationError.destinationNotDirectory
        }
    }

    private static func requireNotSymbolicLink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw FileOperationError.symbolicLinkUnsupported
        }
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
            throw FileOperationError.sourceMissing
        }
        return values.isDirectory == true
    }

    private static func destinationURL(named rawName: String, in directoryURL: URL, isDirectory: Bool) throws -> URL {
        try requireDirectory(directoryURL)
        let name = try validatedName(rawName)
        return directoryURL.appendingPathComponent(name, isDirectory: isDirectory)
    }

    /// 校验名称:非空、非 "." / ".."、不含 "/"、不含控制字符、UTF-8 长度 ≤ 255。
    private static func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw FileOperationError.invalidName
        }
        guard name.lengthOfBytes(using: .utf8) <= maximumNameByteCount else {
            throw FileOperationError.nameTooLong
        }
        return name
    }

    /// keepBoth 命名规则:「name 2.ext」「name 3.ext」;无扩展名或目录则为「name 2」。
    private static func keepBothDestination(for requested: URL, isDirectory: Bool) -> URL {
        let fm = FileManager.default
        let directory = requested.deletingLastPathComponent()
        let original = requested.lastPathComponent
        let ext = isDirectory ? "" : (original as NSString).pathExtension
        let stem = ext.isEmpty ? original : (original as NSString).deletingPathExtension
        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName, isDirectory: isDirectory)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }
}
