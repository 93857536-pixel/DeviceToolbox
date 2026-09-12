import Foundation
import Compression

/// CP437(DOS 代码页 437)高半区(0x80–0xFF)到 Unicode 的映射。
/// 用于 ZIP 文件名非 UTF-8 时的回退解码(公开标准,零第三方依赖)。
enum CP437: Sendable {
    private static let highTable: [UInt16] = [
        0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7,
        0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
        0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9,
        0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
        0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA,
        0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
        0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
        0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
        0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
        0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
        0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
        0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
        0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4,
        0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
        0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248,
        0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0,
    ]

    static func decode(_ data: Data) -> String {
        var result = ""
        result.reserveCapacity(data.count)
        for byte in data {
            if byte < 0x80 {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                // 高半区 0x80–0xFF 均为合法 Unicode 标量(非代理区),强制解包安全。
                result.append(Character(UnicodeScalar(highTable[Int(byte - 0x80)])!))
            }
        }
        return result
    }
}

/// 自实现的 ZIP 读取器:解析 EOCD / central directory / local header,
/// 支持 stored(0)与 deflate(8),文件名 UTF-8 优先、CP437 回退,并做防 zip-slip 校验。
enum ZIPReader: Sendable {
    struct Entry: Sendable {
        let components: [String]
        let isDirectory: Bool
        let method: UInt16
        let crc32: UInt32
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let dataOffset: UInt64
    }

    static let maxEntryUncompressedBytes: UInt64 = 256 * 1_024 * 1_024
    static let maxTotalUncompressedBytes: UInt64 = 1_024 * 1_024 * 1_024
    static let maxEntryCount = 5_000

    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralHeaderSignature: UInt32 = 0x0201_4B50
    private static let endSignature: UInt32 = 0x0605_4B50

    // MARK: - 解析

    static func entries(in archiveURL: URL) throws -> [Entry] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: archiveURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ZIPCodecError.invalidArchive
        }
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try fm.attributesOfItem(atPath: archiveURL.path)
        } catch {
            throw ZIPCodecError.invalidArchive
        }
        guard let sizeNumber = attrs[.size] as? NSNumber else { throw ZIPCodecError.invalidArchive }
        let archiveSize = sizeNumber.uint64Value
        guard archiveSize >= 22 else { throw ZIPCodecError.invalidArchive }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: archiveURL)
        } catch {
            throw ZIPCodecError.invalidArchive
        }
        defer { try? handle.close() }

        // EOCD:在尾部最多 65557 字节内回扫签名。
        let tailSize = Int(min(archiveSize, 65_557))
        let tail = try read(handle, offset: archiveSize - UInt64(tailSize), count: tailSize)
        guard let relativeEnd = lastSignature(endSignature, in: tail), relativeEnd + 22 <= tail.count else {
            throw ZIPCodecError.invalidArchive
        }
        let diskNumber = u16(tail, relativeEnd + 4)
        let centralDisk = u16(tail, relativeEnd + 6)
        let diskEntries = u16(tail, relativeEnd + 8)
        let totalEntries = u16(tail, relativeEnd + 10)
        let centralSize = u32(tail, relativeEnd + 12)
        let centralOffset = u32(tail, relativeEnd + 16)
        let commentLength = Int(u16(tail, relativeEnd + 20))
        let endOffset = archiveSize - UInt64(tailSize) + UInt64(relativeEnd)
        guard diskNumber == 0,
              centralDisk == 0,
              diskEntries == totalEntries,
              totalEntries != 0xFFFF,
              centralSize != 0xFFFF_FFFF,
              centralOffset != 0xFFFF_FFFF,
              relativeEnd + 22 + commentLength == tail.count,
              UInt64(centralOffset) + UInt64(centralSize) == endOffset else {
            throw ZIPCodecError.invalidArchive
        }
        guard Int(totalEntries) <= maxEntryCount else { throw ZIPCodecError.tooManyEntries }

        var entries: [Entry] = []
        var seen: [String: Bool] = [:]
        var totalUncompressed: UInt64 = 0
        var cursor = UInt64(centralOffset)
        let centralEnd = cursor + UInt64(centralSize)

        for _ in 0..<Int(totalEntries) {
            let header = try read(handle, offset: cursor, count: 46)
            guard u32(header, 0) == centralHeaderSignature else { throw ZIPCodecError.invalidArchive }
            let flags = u16(header, 8)
            let method = u16(header, 10)
            let checksum = u32(header, 16)
            let compressedSize = u32(header, 20)
            let uncompressedSize = u32(header, 24)
            let nameLength = Int(u16(header, 28))
            let extraLength = Int(u16(header, 30))
            let commentLength = Int(u16(header, 32))
            let diskStart = u16(header, 34)
            let externalAttributes = u32(header, 38)
            let localOffset = u32(header, 42)
            let variableCount = nameLength + extraLength + commentLength

            guard nameLength > 0,
                  cursor + 46 + UInt64(variableCount) <= centralEnd,
                  flags & 0x0001 == 0,
                  method == 0 || method == 8,
                  diskStart == 0,
                  compressedSize != 0xFFFF_FFFF,
                  uncompressedSize != 0xFFFF_FFFF,
                  localOffset != 0xFFFF_FFFF else {
                throw ZIPCodecError.invalidArchive
            }

            let nameData = try read(handle, offset: cursor + 46, count: nameLength)
            let utf8FlagSet = (flags & (1 << 11)) != 0
            let rawName = try decodeName(nameData, utf8FlagSet: utf8FlagSet)

            let fileType = UInt16((externalAttributes >> 16) & 0xFFFF) & 0o170000
            guard fileType != 0o120000 else { throw ZIPCodecError.unsafeEntry }  // 符号链接拒绝
            guard fileType == 0 || fileType == 0o100000 || fileType == 0o040000 else {
                throw ZIPCodecError.invalidArchive
            }
            let isDirectory = rawName.hasSuffix("/") || fileType == 0o040000

            let components = try safeComponents(rawName, isDirectory: isDirectory)
            let normalized = components.joined(separator: "/").lowercased()
            guard seen[normalized] == nil else { throw ZIPCodecError.unsafeEntry }
            for count in 1..<components.count {
                let parent = components.prefix(count).joined(separator: "/").lowercased()
                if seen[parent] == false { throw ZIPCodecError.unsafeEntry }
            }
            seen[normalized] = isDirectory

            guard UInt64(uncompressedSize) <= maxEntryUncompressedBytes else { throw ZIPCodecError.entryTooLarge }
            let (sum, overflow) = totalUncompressed.addingReportingOverflow(UInt64(uncompressedSize))
            guard !overflow, sum <= maxTotalUncompressedBytes else { throw ZIPCodecError.archiveTooLarge }
            totalUncompressed = sum

            let localHeader = try read(handle, offset: UInt64(localOffset), count: 30)
            guard u32(localHeader, 0) == localHeaderSignature,
                  u16(localHeader, 6) & 0x0001 == 0,
                  u16(localHeader, 8) == method else {
                throw ZIPCodecError.invalidArchive
            }
            let localNameLength = Int(u16(localHeader, 26))
            let localExtraLength = UInt64(u16(localHeader, 28))
            let localName = try read(handle, offset: UInt64(localOffset) + 30, count: localNameLength)
            guard localName == nameData else { throw ZIPCodecError.invalidArchive }
            let dataOffset = UInt64(localOffset) + 30 + UInt64(localNameLength) + localExtraLength
            guard dataOffset <= UInt64(centralOffset),
                  UInt64(compressedSize) <= UInt64(centralOffset) - dataOffset else {
                throw ZIPCodecError.invalidArchive
            }

            entries.append(Entry(
                components: components,
                isDirectory: isDirectory,
                method: method,
                crc32: checksum,
                compressedSize: UInt64(compressedSize),
                uncompressedSize: UInt64(uncompressedSize),
                dataOffset: dataOffset
            ))
            cursor += 46 + UInt64(variableCount)
        }
        guard cursor == centralEnd else { throw ZIPCodecError.invalidArchive }
        return entries
    }

    // MARK: - 单条提取

    /// 提取单条到目标文件,返回未压缩字节数。校验解压长度与 CRC-32。
    static func extract(_ entry: Entry, from archiveURL: URL, to destinationURL: URL) throws -> Int64 {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: archiveURL)
        } catch {
            throw ZIPCodecError.readFailed
        }
        defer { try? handle.close() }

        let compressed = try read(handle, offset: entry.dataOffset, count: Int(entry.compressedSize))
        let uncompressed: Data
        switch entry.method {
        case 0:
            uncompressed = compressed
        case 8:
            uncompressed = try inflate(compressed, expectedSize: Int(entry.uncompressedSize))
        default:
            throw ZIPCodecError.unsupportedCompression
        }
        guard uncompressed.count == Int(entry.uncompressedSize) else { throw ZIPCodecError.crcMismatch }
        guard CRC32.checksum(of: uncompressed) == entry.crc32 else { throw ZIPCodecError.crcMismatch }
        do {
            try uncompressed.write(to: destinationURL)
        } catch {
            throw ZIPCodecError.readFailed
        }
        return Int64(uncompressed.count)
    }

    // MARK: - 名称与路径

    /// 从归档条目路径构建沙盒内目标 URL,并做二次包含校验(纵深防御)。
    static func destinationURL(components: [String], root: URL, isDirectory: Bool) throws -> URL {
        var result = root
        for (index, component) in components.enumerated() {
            result.appendPathComponent(component, isDirectory: isDirectory && index == components.count - 1)
        }
        let standardized = result.standardizedFileURL
        let rootStandardized = root.standardizedFileURL
        guard standardized.path == rootStandardized.path || standardized.path.hasPrefix(rootStandardized.path + "/") else {
            throw ZIPCodecError.unsafeEntry
        }
        return standardized
    }

    private static func safeComponents(_ rawName: String, isDirectory: Bool) throws -> [String] {
        guard !rawName.isEmpty,
              !rawName.hasPrefix("/"),
              !rawName.contains("\\"),
              !rawName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw ZIPCodecError.unsafeEntry
        }
        var components = rawName.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if isDirectory, components.last == "" { components.removeLast() }
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ZIPCodecError.unsafeEntry
        }
        return components
    }

    private static func decodeName(_ data: Data, utf8FlagSet: Bool) throws -> String {
        if utf8FlagSet {
            guard let name = String(data: data, encoding: .utf8) else { throw ZIPCodecError.invalidArchive }
            return name
        }
        if let name = String(data: data, encoding: .utf8) { return name }
        return CP437.decode(data)
    }

    // MARK: - 解压

    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        guard !data.isEmpty else { throw ZIPCodecError.invalidArchive }
        let scratchSize = Int(compression_decode_scratch_buffer_size(COMPRESSION_ZLIB))
        var scratch = [UInt8](repeating: 0, count: scratchSize)
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let written = data.withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> Int in
            let src = srcBuffer.bindMemory(to: UInt8.self)
            return dst.withUnsafeMutableBytes { (dstBuffer: UnsafeMutableRawBufferPointer) -> Int in
                let dstPtr = dstBuffer.bindMemory(to: UInt8.self)
                return scratch.withUnsafeMutableBytes { (scratchBuffer: UnsafeMutableRawBufferPointer) -> Int in
                    let scratchPtr = scratchBuffer.bindMemory(to: UInt8.self)
                    return compression_decode_buffer(
                        dstPtr.baseAddress!, expectedSize,
                        src.baseAddress!, data.count,
                        scratchPtr.baseAddress!,
                        COMPRESSION_ZLIB
                    )
                }
            }
        }
        guard written == expectedSize else { throw ZIPCodecError.invalidArchive }
        return Data(dst)
    }

    // MARK: - 二进制工具

    private static func read(_ handle: FileHandle, offset: UInt64, count: Int) throws -> Data {
        guard count >= 0 else { throw ZIPCodecError.invalidArchive }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw ZIPCodecError.invalidArchive
            }
            return data
        } catch let error as ZIPCodecError {
            throw error
        } catch {
            throw ZIPCodecError.invalidArchive
        }
    }

    private static func lastSignature(_ signature: UInt32, in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        var offset = data.count - 4
        while offset >= 0 {
            if u32(data, offset) == signature { return offset }
            offset -= 1
        }
        return nil
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
