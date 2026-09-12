import XCTest
import Foundation
@testable import DeviceToolbox

/// ZIP 写入→读取往返测试:小文件 / 空目录 / 中文文件名 / 嵌套结构,以及 deflate 是否真正生效。
final class ZipRoundTripTests: XCTestCase {

    func testSmallFileRoundTrip() throws {
        let source = try makeTempDirectory()
        let payload = Data("hello world".utf8)
        try writeTempFile(named: "hello.txt", data: payload, in: source)

        let archive = source.appendingPathComponent("out.zip")
        _ = try ZipArchiveService.write(files: [source.appendingPathComponent("hello.txt")], to: archive)

        let destination = try makeTempDirectory()
        let result = try ZipArchiveService.extract(archive: archive, to: destination)

        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(result.byteCount, Int64(payload.count))

        let extracted = try Data(contentsOf: destination.appendingPathComponent("hello.txt"))
        XCTAssertEqual(extracted, payload)
    }

    func testEmptyDirectoryRoundTrip() throws {
        let source = try makeTempDirectory()
        let emptyDir = source.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let archive = source.appendingPathComponent("out.zip")
        _ = try ZipArchiveService.write(files: [source], to: archive)

        let destination = try makeTempDirectory()
        _ = try ZipArchiveService.extract(archive: archive, to: destination)

        // 归档根名为 source 的最后一段,空目录应被重建。
        let extractedEmpty = destination.appendingPathComponent(source.lastPathComponent)
            .appendingPathComponent("empty", isDirectory: true)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedEmpty.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testChineseFilenameRoundTrip() throws {
        let source = try makeTempDirectory()
        let payload = Data("你好,世界".utf8)
        try writeTempFile(named: "中文文件名.txt", data: payload, in: source)

        let archive = source.appendingPathComponent("out.zip")
        _ = try ZipArchiveService.write(files: [source.appendingPathComponent("中文文件名.txt")], to: archive)

        let destination = try makeTempDirectory()
        _ = try ZipArchiveService.extract(archive: archive, to: destination)

        let extracted = try Data(contentsOf: destination.appendingPathComponent("中文文件名.txt"))
        XCTAssertEqual(extracted, payload)
    }

    func testNestedStructureRoundTrip() throws {
        let source = try makeTempDirectory()
        let sub = source.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let deep = sub.appendingPathComponent("deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

        let a = Data("file-a".utf8)
        let b = Data("file-b-b-b".utf8)
        try writeTempFile(named: "a.txt", data: a, in: source)
        try writeTempFile(named: "b.txt", data: b, in: sub)
        try writeTempFile(named: "c.txt", data: Data("c".utf8), in: deep)

        let archive = source.appendingPathComponent("out.zip")
        _ = try ZipArchiveService.write(files: [source], to: archive)

        let destination = try makeTempDirectory()
        let result = try ZipArchiveService.extract(archive: archive, to: destination)
        XCTAssertEqual(result.fileCount, 3)

        let root = destination.appendingPathComponent(source.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("a.txt")), a)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sub/b.txt")), b)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sub/deeper/c.txt")), Data("c".utf8))
    }

    func testDeflateEngagesForCompressibleContent() throws {
        // 高重复内容应走 deflate,压缩包体积明显小于源文件体积。
        let source = try makeTempDirectory()
        let payload = Data(repeating: 0x41, count: 200_000)
        let fileURL = try writeTempFile(named: "repeat.bin", data: payload, in: source)

        let archive = source.appendingPathComponent("out.zip")
        _ = try ZipArchiveService.write(files: [fileURL], to: archive)

        let archiveSize = (try? FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber) ?? 0
        XCTAssertLessThan(Int(truncating: archiveSize ?? 0), payload.count / 10, "高重复内容应被显著压缩")

        // 往返内容仍需字节级一致。
        let destination = try makeTempDirectory()
        _ = try ZipArchiveService.extract(archive: archive, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("repeat.bin")), payload)
    }
}
