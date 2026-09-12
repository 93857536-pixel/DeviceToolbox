import Foundation

/// 导入落盘结果分类。
enum FileImportDisposition: String, Equatable, Sendable {
    case imported
    case replaced
}

/// 单个文件导入结果。
struct FileImportResult: Equatable, Sendable {
    let destinationURL: URL
    let byteCount: Int64
    let disposition: FileImportDisposition
}

/// 批量导入中单条失败的记录。
struct FileImportFailure: Equatable, Sendable {
    let sourceURL: URL
    let error: FileOperationError
}

/// 批量导入结果:成功项 + 失败项。
struct FileImportBatchResult: Equatable, Sendable {
    let imported: [FileImportResult]
    let failures: [FileImportFailure]

    var succeededCount: Int { imported.count }
    var failedCount: Int { failures.count }
}

/// 文件导入服务:把 UIDocumentPicker 提供的安全作用域副本 [URL] 拷贝进目标目录(默认 Documents/Imported)。
/// 对每个来源 URL 走 startAccessingSecurityScopedResource,并按字节流式拷贝,避免整文件进内存。
enum ImportService: Sendable {
    private static let copyChunkSize = 1_024 * 1_024

    /// 批量导入到指定目录(默认冲突即失败)。
    static func importFiles(
        _ sourceURLs: [URL],
        into directoryURL: URL,
        replaceExisting: Bool = false
    ) throws -> FileImportBatchResult {
        try WorkspaceService.requireDirectory(directoryURL)
        var imported: [FileImportResult] = []
        var failures: [FileImportFailure] = []
        for source in sourceURLs {
            do {
                imported.append(try importFile(source, into: directoryURL, replaceExisting: replaceExisting))
            } catch let error as FileOperationError {
                failures.append(FileImportFailure(sourceURL: source, error: error))
            }
        }
        return FileImportBatchResult(imported: imported, failures: failures)
    }

    /// 导入单个文件到指定目录。
    static func importFile(
        _ sourceURL: URL,
        into directoryURL: URL,
        replaceExisting: Bool = false
    ) throws -> FileImportResult {
        let fm = FileManager.default
        var srcIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &srcIsDirectory) else {
            throw FileOperationError.sourceMissing
        }
        guard !srcIsDirectory.boolValue else {
            throw FileOperationError.sourceIsDirectory
        }
        try WorkspaceService.requireDirectory(directoryURL)

        let destination = directoryURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
        let existed = fm.fileExists(atPath: destination.path)
        if existed && !replaceExisting {
            throw FileOperationError.itemAlreadyExists
        }

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let staging = directoryURL.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: false)
        defer { try? fm.removeItem(at: staging) }
        guard fm.createFile(atPath: staging.path, contents: nil) else {
            throw FileOperationError.cannotImport
        }

        let byteCount: Int64
        do {
            byteCount = try copyFile(from: sourceURL, to: staging)
        } catch let error as FileOperationError {
            throw error
        } catch {
            throw FileOperationError.cannotImport
        }

        do {
            if existed { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
        } catch {
            throw FileOperationError.cannotImport
        }

        return FileImportResult(
            destinationURL: destination,
            byteCount: byteCount,
            disposition: existed ? .replaced : .imported
        )
    }

    /// 便捷入口:导入到沙盒「已导入」目录 Documents/Imported。
    static func importIntoImportedFiles(
        _ sourceURLs: [URL],
        replaceExisting: Bool = false
    ) throws -> FileImportBatchResult {
        let directory = try SandboxRoots.ensureImportedDirectory()
        return try importFiles(sourceURLs, into: directory, replaceExisting: replaceExisting)
    }

    // MARK: - 工具

    private static func copyFile(from source: URL, to destination: URL) throws -> Int64 {
        let src = try FileHandle(forReadingFrom: source)
        let dst = try FileHandle(forWritingTo: destination)
        defer {
            try? src.close()
            try? dst.close()
        }
        var total: Int64 = 0
        while let chunk = try src.read(upToCount: copyChunkSize), !chunk.isEmpty {
            try dst.write(contentsOf: chunk)
            let (next, overflow) = total.addingReportingOverflow(Int64(chunk.count))
            guard !overflow else { throw FileOperationError.sourceTooLarge }
            total = next
        }
        try dst.synchronize()
        return total
    }
}
