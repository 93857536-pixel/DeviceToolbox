import XCTest
import Foundation
@testable import DeviceToolbox

/// 恶意 / 损坏归档拒绝测试:路径穿越、绝对路径、超大声明、CRC 损坏、条目数上限、总量上限。
final class UnsafeZipRejectTests: XCTestCase {

    func testRejectsPathTraversal() throws {
        let archive = buildStoredZIP(entries: [
            ZIPTestEntry(name: "../evil.txt", data: Data("x".utf8)),
        ])
        try assertUnsafeExtract(archive)
    }

    func testRejectsAbsolutePath() throws {
        let archive = buildStoredZIP(entries: [
            ZIPTestEntry(name: "/tmp/evil.txt", data: Data("x".utf8)),
        ])
        try assertUnsafeExtract(archive)
    }

    func testRejectsOversizedEntryDeclaration() throws {
        // 声明未压缩大小为 300MB(超单条 256MB 上限),实际数据极小。
        let archive = buildStoredZIP(entries: [
            ZIPTestEntry(name: "big.bin", data: Data("tiny".utf8), sizeOverride: 300 * 1024 * 1024),
        ])
        try assertUnsafeExtract(archive)
    }

    func testRejectsCRC32Corruption() throws {
        // 数据保持不变,但声明的 CRC 错误 → 校验失败拒绝。
        let archive = buildStoredZIP(entries: [
            ZIPTestEntry(name: "a.txt", data: Data("payload".utf8), crcOverride: 0xDEAD_BEEF),
        ])
        try assertUnsafeExtract(archive)
    }

    func testRejectsTooManyEntries() throws {
        // 5001 条(超上限 5000)。
        var entries: [ZIPTestEntry] = []
        for index in 0..<5_001 {
            entries.append(ZIPTestEntry(name: "f\(index).txt", data: Data("x".utf8)))
        }
        let archive = buildStoredZIP(entries: entries)
        try assertUnsafeExtract(archive)
    }

    func testRejectsTotalSizeOverflow() throws {
        // 两条各声明 600MB,总量超 1GB 上限。
        let archive = buildStoredZIP(entries: [
            ZIPTestEntry(name: "a.bin", data: Data("a".utf8), sizeOverride: 600 * 1024 * 1024),
            ZIPTestEntry(name: "b.bin", data: Data("b".utf8), sizeOverride: 600 * 1024 * 1024),
        ])
        try assertUnsafeExtract(archive)
    }

    // MARK: - helpers

    private func assertUnsafeExtract(
        _ archiveData: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let directory = try makeTempDirectory()
        let archiveURL = directory.appendingPathComponent("bad.zip")
        try archiveData.write(to: archiveURL)
        let destination = try makeTempDirectory()

        var caught: FileOperationError?
        do {
            _ = try ZipArchiveService.extract(archive: archiveURL, to: destination)
        } catch let error as FileOperationError {
            caught = error
        } catch {
            XCTFail("期望 FileOperationError,实际 \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(caught, .unsafeArchive, file: file, line: line)
    }
}
