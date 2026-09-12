import Foundation

/// ZIP 归档服务:对上层暴露写入与解压两个入口,内部映射底层编解码错误为 `FileOperationError`。
enum ZipArchiveService: Sendable {
    /// 写入结果。
    struct WriteResult: Equatable, Sendable {
        let entryCount: Int
        let sourceBytes: Int64
    }

    /// 解压结果。
    struct ZipResult: Equatable, Sendable {
        let fileCount: Int
        let byteCount: Int64
    }

    /// 把一组沙盒内文件/目录打包成 ZIP 写到目标 URL(目标不得已存在)。
    static func write(files sourceURLs: [URL], to destinationURL: URL) throws -> WriteResult {
        do {
            let result = try ZIPWriter.write(items: sourceURLs, to: destinationURL)
            return WriteResult(entryCount: result.entryCount, sourceBytes: result.sourceBytes)
        } catch {
            throw FileOperationError.cannotArchive
        }
    }

    /// 解压 ZIP 到目标目录(顶层内容直接落在 `to` 下),逐条回调进度 0...1。
    /// 防 zip-slip、单条/总量/条目数上限、CRC 校验均在底层完成,违规抛 `.unsafeArchive`。
    static func extract(
        archive archiveURL: URL,
        to directoryURL: URL,
        progress: ((Double) -> Void)? = nil
    ) throws -> ZipResult {
        let fm = FileManager.default
        do {
            let entries = try ZIPReader.entries(in: archiveURL)

            do {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            } catch {
                if !fm.fileExists(atPath: directoryURL.path) { throw FileOperationError.cannotExtract }
            }

            // 先解压到 staging,再整体搬入目标目录,避免半成品暴露。
            let staging = directoryURL.deletingLastPathComponent()
                .appendingPathComponent(".unzip-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)

            var fileCount = 0
            var byteCount: Int64 = 0
            for (index, entry) in entries.enumerated() {
                let target = try ZIPReader.destinationURL(components: entry.components, root: staging, isDirectory: entry.isDirectory)
                if entry.isDirectory {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    byteCount += try ZIPReader.extract(entry, from: archiveURL, to: target)
                    fileCount += 1
                }
                if let progress {
                    progress(entries.isEmpty ? 1.0 : Double(index + 1) / Double(entries.count))
                }
            }

            let topLevel = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            for item in topLevel {
                let destination = directoryURL.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: item, to: destination)
            }
            return ZipResult(fileCount: fileCount, byteCount: byteCount)
        } catch let error as FileOperationError {
            throw error
        } catch let error as ZIPCodecError {
            throw mapToFileOperationError(error)
        } catch {
            throw FileOperationError.cannotExtract
        }
    }

    private static func mapToFileOperationError(_ error: ZIPCodecError) -> FileOperationError {
        switch error {
        case .emptySelection, .invalidSource, .writeFailed:
            return .cannotArchive
        case .invalidArchive, .unsupportedCompression, .unsafeEntry, .entryTooLarge,
             .tooManyEntries, .archiveTooLarge, .crcMismatch:
            return .unsafeArchive
        case .readFailed:
            return .cannotExtract
        }
    }
}
