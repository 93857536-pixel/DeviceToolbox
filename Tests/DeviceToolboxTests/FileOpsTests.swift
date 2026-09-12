import XCTest
import Foundation
@testable import DeviceToolbox

/// 文件操作测试:复制冲突 keepBoth 命名规则、replace / fail 策略、删除、新建目录、重命名、列表排序。
final class FileOpsTests: XCTestCase {

    func testCopyKeepBothNaming() throws {
        let dir = try makeTempDirectory()
        try writeTempFile(named: "report.txt", data: Data("v1".utf8), in: dir)

        let first = try WorkspaceService.copyItem(
            at: dir.appendingPathComponent("report.txt"),
            into: dir,
            conflictPolicy: .keepBoth
        )
        XCTAssertEqual(first.destinationURL.lastPathComponent, "report 2.txt")
        XCTAssertEqual(first.disposition, .renamed)

        let second = try WorkspaceService.copyItem(
            at: dir.appendingPathComponent("report.txt"),
            into: dir,
            conflictPolicy: .keepBoth
        )
        XCTAssertEqual(second.destinationURL.lastPathComponent, "report 3.txt")
    }

    func testCopyKeepBothPreservesExtension() throws {
        let dir = try makeTempDirectory()
        try writeTempFile(named: "photo.png", data: Data("p".utf8), in: dir)

        let result = try WorkspaceService.copyItem(
            at: dir.appendingPathComponent("photo.png"),
            into: dir,
            conflictPolicy: .keepBoth
        )
        XCTAssertEqual(result.destinationURL.lastPathComponent, "photo 2.png")
    }

    func testCopyReplaceOverwrites() throws {
        let sourceDir = try makeTempDirectory()
        let destinationDir = try makeTempDirectory()
        let src = try writeTempFile(named: "same.txt", data: Data("new".utf8), in: sourceDir)
        let dst = try writeTempFile(named: "same.txt", data: Data("old".utf8), in: destinationDir)

        let result = try WorkspaceService.copyItem(at: src, into: destinationDir, conflictPolicy: .replace)
        XCTAssertEqual(result.destinationURL.lastPathComponent, "same.txt")
        XCTAssertEqual(result.disposition, .replaced)
        XCTAssertEqual(try Data(contentsOf: dst), Data("new".utf8))
    }

    func testCopyFailThrowsWhenExists() throws {
        let sourceDir = try makeTempDirectory()
        let destinationDir = try makeTempDirectory()
        let src = try writeTempFile(named: "same.txt", data: Data("new".utf8), in: sourceDir)
        try writeTempFile(named: "same.txt", data: Data("old".utf8), in: destinationDir)

        XCTAssertThrowsError(try WorkspaceService.copyItem(at: src, into: destinationDir, conflictPolicy: .fail)) { error in
            XCTAssertEqual(error as? FileOperationError, .itemAlreadyExists)
        }
    }

    func testDeleteRemovesItem() throws {
        let dir = try makeTempDirectory()
        let file = try writeTempFile(named: "gone.txt", data: Data("x".utf8), in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        try WorkspaceService.deleteItem(at: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testDeleteMissingThrows() throws {
        let dir = try makeTempDirectory()
        let missing = dir.appendingPathComponent("nope.txt")
        XCTAssertThrowsError(try WorkspaceService.deleteItem(at: missing)) { error in
            XCTAssertEqual(error as? FileOperationError, .sourceMissing)
        }
    }

    func testMakeDirectoryAndRenameAndList() throws {
        let dir = try makeTempDirectory()
        let created = try WorkspaceService.makeDirectory(named: "newfolder", in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))

        let renamed = try WorkspaceService.renameItem(at: created, to: "renamed")
        XCTAssertEqual(renamed.lastPathComponent, "renamed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))

        try writeTempFile(named: "zzz.txt", data: Data("z".utf8), in: dir)
        try writeTempFile(named: "aaa.txt", data: Data("a".utf8), in: dir)

        let entries = try WorkspaceService.listDirectory(at: dir)
        // 目录在前,随后按名称排序。
        let names = entries.map(\.name)
        XCTAssertEqual(names, ["renamed", "aaa.txt", "zzz.txt"])
        XCTAssertEqual(entries.first?.isDirectory, true)
    }

    func testStatReturnsMetadata() throws {
        let dir = try makeTempDirectory()
        let file = try writeTempFile(named: "meta.txt", data: Data("12345".utf8), in: dir)

        let entry = try WorkspaceService.stat(at: file)
        XCTAssertEqual(entry.name, "meta.txt")
        XCTAssertEqual(entry.size, 5)
        XCTAssertFalse(entry.isDirectory)
    }
}
