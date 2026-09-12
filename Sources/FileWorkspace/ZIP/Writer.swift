import Foundation
import Compression

/// CRC-32(IEEE 802.3,多项式 0xEDB88320)自实现查表算法。
/// 供 ZIP 写入与读取校验共用,零第三方依赖。
enum CRC32: Sendable {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    /// 计算整段数据的 CRC-32。
    static func checksum(of data: Data) -> UInt32 {
        update(0xFFFF_FFFF, with: data) ^ 0xFFFF_FFFF
    }

    /// 增量更新(初始值传入 0xFFFFFFFF,结束后异或 0xFFFFFFFF)。
    static func update(_ crc: UInt32, with data: Data) -> UInt32 {
        var crc = crc
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc
    }
}

/// deflate 压缩封装:经 Compression 框架 COMPRESSION_ZLIB 逐块压缩。
enum Deflate: Sendable {
    /// 对数据做 zlib deflate;若结果不小于原数据(或输入为空)则返回 nil,由调用方回退 stored。
    static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let srcSize = data.count
        let scratchSize = Int(compression_encode_scratch_buffer_size(COMPRESSION_ZLIB))
        let dstSize = srcSize + (srcSize >> 3) + 1024
        var scratch = [UInt8](repeating: 0, count: scratchSize)
        var dst = [UInt8](repeating: 0, count: dstSize)

        let written = data.withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> Int in
            let src = srcBuffer.bindMemory(to: UInt8.self)
            return dst.withUnsafeMutableBytes { (dstBuffer: UnsafeMutableRawBufferPointer) -> Int in
                let dstPtr = dstBuffer.bindMemory(to: UInt8.self)
                return scratch.withUnsafeMutableBytes { (scratchBuffer: UnsafeMutableRawBufferPointer) -> Int in
                    let scratchPtr = scratchBuffer.bindMemory(to: UInt8.self)
                    return compression_encode_buffer(
                        dstPtr.baseAddress!, dstSize,
                        src.baseAddress!, srcSize,
                        scratchPtr.baseAddress!,
                        COMPRESSION_ZLIB
                    )
                }
            }
        }
        guard written > 0, written < srcSize else { return nil }
        return Data(dst[0..<written])
    }
}

/// 自实现的 ZIP 写入器:支持 stored(方法 0)与 deflate(方法 8)。
/// 自写 local header / central directory / EOCD,零第三方依赖。
enum ZIPWriter: Sendable {
    struct Result: Equatable, Sendable {
        let entryCount: Int
        let sourceBytes: Int64
    }

    private struct Entry {
        let archivePath: String
        let isDirectory: Bool
        let method: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let modifiedTime: UInt16
        let modifiedDate: UInt16
        let localHeaderOffset: UInt32
    }

    private struct Content {
        let method: UInt16
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        /// nil 表示「大文件 stored 流式」,由写入端直接从源文件流式读取。
        let compressedData: Data?
    }

    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralHeaderSignature: UInt32 = 0x0201_4B50
    private static let endOfCentralSignature: UInt32 = 0x0605_4B50
    private static let utf8Flag: UInt16 = 1 << 11
    private static let chunkSize = 1_024 * 1_024
    private static let maxInMemoryBytes: Int64 = 8 * 1_024 * 1_024
    private static let maxEntryCount = 5_000

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
    ]

    static func write(items sourceURLs: [URL], to destinationURL: URL) throws -> Result {
        guard !sourceURLs.isEmpty else { throw ZIPCodecError.emptySelection }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destinationURL.path) else { throw ZIPCodecError.writeFailed }
        let parent = destinationURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            do { try fm.createDirectory(at: parent, withIntermediateDirectories: true) }
            catch { throw ZIPCodecError.writeFailed }
        }
        // staging 放到系统临时目录,避免落在被归档的源目录树内被一并枚举。
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(".zip-\(UUID().uuidString)", isDirectory: false)
        defer { try? fm.removeItem(at: staging) }
        guard fm.createFile(atPath: staging.path, contents: nil) else { throw ZIPCodecError.writeFailed }

        do {
            let handle = try FileHandle(forWritingTo: staging)
            defer { try? handle.close() }
            var entries: [Entry] = []
            var sourceBytes: Int64 = 0

            for source in sourceURLs {
                let standardized = source.standardizedFileURL
                try appendTree(
                    rootedAt: standardized,
                    rootName: standardized.lastPathComponent,
                    entries: &entries,
                    handle: handle,
                    sourceBytes: &sourceBytes
                )
            }
            guard entries.count <= maxEntryCount else { throw ZIPCodecError.tooManyEntries }

            let centralOffset = try handle.offset()
            for entry in entries {
                try writeCentralHeader(entry, to: handle)
            }
            let endOffset = try handle.offset()
            let centralSize = endOffset - centralOffset
            guard centralOffset <= UInt64(UInt32.max), centralSize <= UInt64(UInt32.max) else {
                throw ZIPCodecError.archiveTooLarge
            }
            try writeEndRecord(
                entryCount: UInt16(entries.count),
                centralSize: UInt32(centralSize),
                centralOffset: UInt32(centralOffset),
                to: handle
            )
            try handle.synchronize()
            try handle.close()
            try fm.moveItem(at: staging, to: destinationURL)
            return Result(entryCount: entries.count, sourceBytes: sourceBytes)
        } catch let error as ZIPCodecError {
            throw error
        } catch {
            throw ZIPCodecError.writeFailed
        }
    }

    // MARK: - 目录树遍历

    private static func appendTree(
        rootedAt sourceURL: URL,
        rootName: String,
        entries: inout [Entry],
        handle: FileHandle,
        sourceBytes: inout Int64
    ) throws {
        let fm = FileManager.default
        let rootValues = try resourceValues(for: sourceURL)
        if rootValues.isDirectory == true {
            try appendEntry(sourceURL, archivePath: rootName + "/", values: rootValues, entries: &entries, handle: handle, sourceBytes: &sourceBytes)
            var enumerationFailed = false
            guard let enumerator = fm.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [],
                errorHandler: { _, _ in
                    enumerationFailed = true
                    return false
                }
            ) else {
                throw ZIPCodecError.invalidSource
            }
            while let child = enumerator.nextObject() as? URL {
                let values = try resourceValues(for: child)
                let relative = child.pathComponents
                    .dropFirst(sourceURL.pathComponents.count)
                    .joined(separator: "/")
                guard !relative.isEmpty else { throw ZIPCodecError.invalidSource }
                var archivePath = rootName + "/" + relative
                if values.isDirectory == true { archivePath += "/" }
                try appendEntry(child, archivePath: archivePath, values: values, entries: &entries, handle: handle, sourceBytes: &sourceBytes)
            }
            if enumerationFailed { throw ZIPCodecError.invalidSource }
        } else if rootValues.isRegularFile == true {
            try appendEntry(sourceURL, archivePath: rootName, values: rootValues, entries: &entries, handle: handle, sourceBytes: &sourceBytes)
        } else {
            throw ZIPCodecError.invalidSource
        }
    }

    private static func resourceValues(for url: URL) throws -> URLResourceValues {
        do {
            let values = try url.resourceValues(forKeys: resourceKeys)
            if values.isSymbolicLink == true { throw ZIPCodecError.invalidSource }
            return values
        } catch let error as ZIPCodecError {
            throw error
        } catch {
            throw ZIPCodecError.invalidSource
        }
    }

    // MARK: - 条目写入

    private static func appendEntry(
        _ sourceURL: URL,
        archivePath: String,
        values: URLResourceValues,
        entries: inout [Entry],
        handle: FileHandle,
        sourceBytes: inout Int64
    ) throws {
        guard let nameData = archivePath.data(using: .utf8),
              !nameData.isEmpty,
              nameData.count <= Int(UInt16.max),
              !archivePath.hasPrefix("/"),
              !archivePath.contains("\\"),
              !archivePath.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else {
            throw ZIPCodecError.invalidSource
        }

        let isDirectory = values.isDirectory == true
        let fileSize = isDirectory ? 0 : Int64(values.fileSize ?? 0)
        guard fileSize >= 0, fileSize <= Int64(UInt32.max) else { throw ZIPCodecError.archiveTooLarge }

        let offset = try handle.offset()
        guard offset <= UInt64(UInt32.max) else { throw ZIPCodecError.archiveTooLarge }

        var method: UInt16 = 0
        var crc: UInt32 = 0
        var compressedSize: UInt32 = 0
        var uncompressedSize: UInt32 = 0
        var compressedData: Data?

        if !isDirectory {
            let content = try compressedContent(of: sourceURL, expectedSize: fileSize)
            method = content.method
            crc = content.crc32
            compressedSize = content.compressedSize
            uncompressedSize = content.uncompressedSize
            compressedData = content.compressedData
        }

        let (time, date) = dosDateTime(values.contentModificationDate ?? Date())
        let entry = Entry(
            archivePath: archivePath,
            isDirectory: isDirectory,
            method: method,
            crc32: crc,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            modifiedTime: time,
            modifiedDate: date,
            localHeaderOffset: UInt32(offset)
        )
        try writeLocalHeader(entry, nameData: nameData, to: handle)
        if !isDirectory {
            if let data = compressedData {
                if !data.isEmpty { try handle.write(contentsOf: data) }
            } else {
                try stream(sourceURL, to: handle)
            }
            let (next, overflow) = sourceBytes.addingReportingOverflow(fileSize)
            guard !overflow else { throw ZIPCodecError.archiveTooLarge }
            sourceBytes = next
        }
        entries.append(entry)
    }

    private static func compressedContent(of url: URL, expectedSize: Int64) throws -> Content {
        if expectedSize > maxInMemoryBytes {
            // 大文件:stored 流式,先流式计算 CRC 与总长。
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var crc: UInt32 = 0xFFFF_FFFF
            var total: UInt64 = 0
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                crc = CRC32.update(crc, with: chunk)
                total += UInt64(chunk.count)
            }
            return Content(
                method: 0,
                crc32: crc ^ 0xFFFF_FFFF,
                compressedSize: UInt32(total),
                uncompressedSize: UInt32(total),
                compressedData: nil
            )
        }
        let data = try Data(contentsOf: url)
        let crc = CRC32.checksum(of: data)
        let uncompressedSize = UInt32(data.count)
        if let deflated = Deflate.compress(data), deflated.count < data.count {
            return Content(
                method: 8,
                crc32: crc,
                compressedSize: UInt32(deflated.count),
                uncompressedSize: uncompressedSize,
                compressedData: deflated
            )
        }
        return Content(
            method: 0,
            crc32: crc,
            compressedSize: uncompressedSize,
            uncompressedSize: uncompressedSize,
            compressedData: data
        )
    }

    private static func stream(_ sourceURL: URL, to destination: FileHandle) throws {
        let source = try FileHandle(forReadingFrom: sourceURL)
        defer { try? source.close() }
        while let chunk = try source.read(upToCount: chunkSize), !chunk.isEmpty {
            try destination.write(contentsOf: chunk)
        }
    }

    // MARK: - 头部与记录

    private static func writeLocalHeader(_ entry: Entry, nameData: Data, to handle: FileHandle) throws {
        var header = Data()
        header.appendLittleEndian(localHeaderSignature)
        header.appendLittleEndian(UInt16(20))
        header.appendLittleEndian(utf8Flag)
        header.appendLittleEndian(entry.method)
        header.appendLittleEndian(entry.modifiedTime)
        header.appendLittleEndian(entry.modifiedDate)
        header.appendLittleEndian(entry.crc32)
        header.appendLittleEndian(entry.compressedSize)
        header.appendLittleEndian(entry.uncompressedSize)
        header.appendLittleEndian(UInt16(nameData.count))
        header.appendLittleEndian(UInt16(0))
        header.append(nameData)
        try handle.write(contentsOf: header)
    }

    private static func writeCentralHeader(_ entry: Entry, to handle: FileHandle) throws {
        guard let nameData = entry.archivePath.data(using: .utf8) else { throw ZIPCodecError.invalidSource }
        var header = Data()
        header.appendLittleEndian(centralHeaderSignature)
        header.appendLittleEndian(UInt16(0x0314))  // version made by 3.20
        header.appendLittleEndian(UInt16(20))
        header.appendLittleEndian(utf8Flag)
        header.appendLittleEndian(entry.method)
        header.appendLittleEndian(entry.modifiedTime)
        header.appendLittleEndian(entry.modifiedDate)
        header.appendLittleEndian(entry.crc32)
        header.appendLittleEndian(entry.compressedSize)
        header.appendLittleEndian(entry.uncompressedSize)
        header.appendLittleEndian(UInt16(nameData.count))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(UInt16(0))
        header.appendLittleEndian(UInt16(0))
        let permissions: UInt32 = entry.isDirectory ? 0o040755 : 0o100600
        header.appendLittleEndian((permissions << 16) | (entry.isDirectory ? 0x10 : 0))
        header.appendLittleEndian(entry.localHeaderOffset)
        header.append(nameData)
        try handle.write(contentsOf: header)
    }

    private static func writeEndRecord(
        entryCount: UInt16,
        centralSize: UInt32,
        centralOffset: UInt32,
        to handle: FileHandle
    ) throws {
        var record = Data()
        record.appendLittleEndian(endOfCentralSignature)
        record.appendLittleEndian(UInt16(0))
        record.appendLittleEndian(UInt16(0))
        record.appendLittleEndian(entryCount)
        record.appendLittleEndian(entryCount)
        record.appendLittleEndian(centralSize)
        record.appendLittleEndian(centralOffset)
        record.appendLittleEndian(UInt16(0))
        try handle.write(contentsOf: record)
    }

    // MARK: - DOS 时间

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone.current, from: date)
        let year = UInt16(max(1980, min(2107, components.year ?? 1980)) - 1980)
        let month = UInt16(max(1, min(12, components.month ?? 1)))
        let day = UInt16(max(1, min(31, components.day ?? 1)))
        let hour = UInt16(max(0, min(23, components.hour ?? 0)))
        let minute = UInt16(max(0, min(59, components.minute ?? 0)))
        let second = UInt16(max(0, min(59, components.second ?? 0)) / 2)
        return (
            time: (hour << 11) | (minute << 5) | second,
            date: (year << 9) | (month << 5) | day
        )
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
