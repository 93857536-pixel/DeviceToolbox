import Foundation
import XCTest
@testable import DeviceToolbox

/// 域 A 单测共享工具:小端写入、手搓 stored ZIP、临时目录/文件创建。
/// (与 app 模块内 Writer.swift 的 Data 扩展处于不同模块,无符号冲突。)

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

struct ZIPTestEntry {
    let name: String
    let data: Data
    let crcOverride: UInt32?
    let sizeOverride: UInt32?

    init(name: String, data: Data, crcOverride: UInt32? = nil, sizeOverride: UInt32? = nil) {
        self.name = name
        self.data = data
        self.crcOverride = crcOverride
        self.sizeOverride = sizeOverride
    }
}

/// 手搓一个「stored(方法 0)」ZIP 的字节,支持覆盖 CRC / 声明大小,用于恶意/损坏归档测试。
func buildStoredZIP(entries: [ZIPTestEntry]) -> Data {
    var out = Data()
    var central = Data()
    var offset: UInt32 = 0

    for entry in entries {
        let nameData = entry.name.data(using: .utf8)!
        let crc = entry.crcOverride ?? CRC32.checksum(of: entry.data)
        let uncompressed = entry.sizeOverride ?? UInt32(entry.data.count)
        let compressed = entry.sizeOverride ?? UInt32(entry.data.count)
        let isDirectory = entry.name.hasSuffix("/")

        // local header
        out.appendLittleEndian(UInt32(0x0403_4B50))
        out.appendLittleEndian(UInt16(20))
        out.appendLittleEndian(UInt16(1 << 11))  // UTF-8 flag
        out.appendLittleEndian(UInt16(0))        // method stored
        out.appendLittleEndian(UInt16(0))        // mod time
        out.appendLittleEndian(UInt16(0x21))     // mod date 1980-01-01
        out.appendLittleEndian(crc)
        out.appendLittleEndian(compressed)
        out.appendLittleEndian(uncompressed)
        out.appendLittleEndian(UInt16(nameData.count))
        out.appendLittleEndian(UInt16(0))
        out.append(nameData)
        out.append(entry.data)

        // central header
        central.appendLittleEndian(UInt32(0x0201_4B50))
        central.appendLittleEndian(UInt16(0x0314))
        central.appendLittleEndian(UInt16(20))
        central.appendLittleEndian(UInt16(1 << 11))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0x21))
        central.appendLittleEndian(crc)
        central.appendLittleEndian(compressed)
        central.appendLittleEndian(uncompressed)
        central.appendLittleEndian(UInt16(nameData.count))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt16(0))
        central.appendLittleEndian(UInt32(isDirectory ? 0x10 : 0))
        central.appendLittleEndian(offset)
        central.append(nameData)

        offset += UInt32(30 + nameData.count + entry.data.count)
    }

    let centralOffset = offset
    let centralSize = UInt32(central.count)
    out.append(central)

    // EOCD
    out.appendLittleEndian(UInt32(0x0605_4B50))
    out.appendLittleEndian(UInt16(0))
    out.appendLittleEndian(UInt16(0))
    out.appendLittleEndian(UInt16(entries.count))
    out.appendLittleEndian(UInt16(entries.count))
    out.appendLittleEndian(centralSize)
    out.appendLittleEndian(centralOffset)
    out.appendLittleEndian(UInt16(0))
    return out
}

/// 在系统临时目录下新建一个唯一目录。
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("fws-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 在指定目录下写入一个文件,返回其 URL。
@discardableResult
func writeTempFile(named name: String, data: Data, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url)
    return url
}
