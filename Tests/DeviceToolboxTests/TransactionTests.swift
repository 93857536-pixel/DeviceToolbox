import XCTest
import Foundation
@testable import DeviceToolbox

/// 补丁事务测试:apply 后文件变化、restore 后字节级还原、targetChanged 冲突、已应用冲突。
final class TransactionTests: XCTestCase {

    private var tempRoots: [URL] = []

    override func tearDown() {
        for url in tempRoots {
            try? FileManager.default.removeItem(at: url)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("txn-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func write(_ string: String, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url)
    }

    private func read(_ relativePath: String, in root: URL) -> String? {
        let url = root.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func exists(_ relativePath: String, in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }

    private func makeProject() -> PatchProject {
        PatchProject(
            name: "Txn Patch",
            author: "Tester",
            rules: [
                PatchRule(relativePath: "existing.txt", action: .replaceFile, replacementData: Data("patched".utf8)),
                PatchRule(relativePath: "new.txt", action: .replaceFile, replacementData: Data("new content".utf8)),
                PatchRule(relativePath: "to-delete.txt", action: .deleteFile),
                PatchRule(relativePath: "created-dir", action: .addFolder)
            ]
        )
    }

    func testApplyChangesFiles() throws {
        let appliedRoot = makeTempDir()
        let journalRoot = makeTempDir()
        let project = makeProject()
        try write("original content", to: "existing.txt", in: appliedRoot)
        try write("bye", to: "to-delete.txt", in: appliedRoot)

        let receipt = try PatchTransaction.apply(
            project: project,
            appliedRoot: appliedRoot,
            journalRoot: journalRoot
        )

        XCTAssertNotNil(receipt)
        XCTAssertEqual(read("existing.txt", in: appliedRoot), "patched")
        XCTAssertEqual(read("new.txt", in: appliedRoot), "new content")
        XCTAssertFalse(exists("to-delete.txt", in: appliedRoot))
        XCTAssertTrue(exists("created-dir", in: appliedRoot))
        XCTAssertTrue(PatchTransaction.isApplied(projectID: project.id, journalRoot: journalRoot))
    }

    func testRestoreByteLevel() throws {
        let appliedRoot = makeTempDir()
        let journalRoot = makeTempDir()
        let project = makeProject()
        try write("original content", to: "existing.txt", in: appliedRoot)
        try write("bye", to: "to-delete.txt", in: appliedRoot)

        let receipt = try PatchTransaction.apply(
            project: project,
            appliedRoot: appliedRoot,
            journalRoot: journalRoot
        )

        try PatchTransaction.restore(receipt: receipt)

        XCTAssertEqual(read("existing.txt", in: appliedRoot), "original content")
        XCTAssertEqual(read("to-delete.txt", in: appliedRoot), "bye")
        XCTAssertFalse(exists("new.txt", in: appliedRoot))
        XCTAssertFalse(exists("created-dir", in: appliedRoot))
    }

    func testApplyTwiceThrowsAlreadyApplied() throws {
        let appliedRoot = makeTempDir()
        let journalRoot = makeTempDir()
        let project = makeProject()
        try write("original content", to: "existing.txt", in: appliedRoot)

        _ = try PatchTransaction.apply(project: project, appliedRoot: appliedRoot, journalRoot: journalRoot)
        XCTAssertThrowsError(
            try PatchTransaction.apply(project: project, appliedRoot: appliedRoot, journalRoot: journalRoot)
        ) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .projectAlreadyApplied)
        }
    }

    func testRestoreDetectsTargetChanged() throws {
        let appliedRoot = makeTempDir()
        let journalRoot = makeTempDir()
        let project = makeProject()
        try write("original content", to: "existing.txt", in: appliedRoot)

        let receipt = try PatchTransaction.apply(
            project: project,
            appliedRoot: appliedRoot,
            journalRoot: journalRoot
        )

        // 外部篡改已打补丁的文件。
        try write("tampered", to: "existing.txt", in: appliedRoot)

        let changes = try PatchTransaction.inspectRestore(receipt: receipt)
        XCTAssertFalse(changes.isEmpty)

        XCTAssertThrowsError(try PatchTransaction.restore(receipt: receipt)) { error in
            guard case PatchWorkspaceError.restoreTargetsChanged(let paths) = error else {
                return XCTFail("expected restoreTargetsChanged, got \(error)")
            }
            XCTAssertEqual(paths, ["existing.txt"])
        }

        // 允许覆盖后仍可还原。
        try PatchTransaction.restore(receipt: receipt, allowChangedTargets: true)
        XCTAssertEqual(read("existing.txt", in: appliedRoot), "original content")
    }

    func testUnsafePathRejectedOnApply() {
        let appliedRoot = makeTempDir()
        let journalRoot = makeTempDir()
        let project = PatchProject(
            name: "Bad",
            author: "",
            rules: [PatchRule(relativePath: "../escape", action: .replaceFile, replacementData: Data("x".utf8))]
        )
        XCTAssertThrowsError(try PatchTransaction.apply(
            project: project,
            appliedRoot: appliedRoot,
            journalRoot: journalRoot
        ))
    }

    func testEmptyProjectRejectedOnApply() {
        let appliedRoot = makeTempDir()
        let journalRoot = makeTempDir()
        let project = PatchProject(name: "Empty", author: "", rules: [])
        XCTAssertThrowsError(try PatchTransaction.apply(
            project: project,
            appliedRoot: appliedRoot,
            journalRoot: journalRoot
        )) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .invalidProject)
        }
    }
}
