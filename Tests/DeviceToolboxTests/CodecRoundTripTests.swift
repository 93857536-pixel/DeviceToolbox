import XCTest
import Foundation
@testable import DeviceToolbox

/// DTBP 编解码往返测试(无密码/带密码/错误密码/截断/非法数据/私密约束)。
final class CodecRoundTripTests: XCTestCase {

    private func makeProject(isPrivate: Bool = false) -> PatchProject {
        PatchProject(
            name: "Test Patch",
            author: "Tester",
            isPrivate: isPrivate,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            rules: [
                PatchRule(
                    relativePath: "Library/Preferences/com.example.plist",
                    action: .replaceFile,
                    replacementFilename: "com.example.plist",
                    replacementData: Data("hello world".utf8)
                ),
                PatchRule(relativePath: "Library/Preferences/remove.plist", action: .deleteFile),
                PatchRule(relativePath: "Documents/Extra", action: .addFolder)
            ]
        )
    }

    func testRoundTripNoPassword() throws {
        let project = makeProject()
        let data = try PatchPackageCodec.encodePackage(project: project, password: nil)
        XCTAssertEqual(PatchPackageCodec.detectFormat(data), .dtbp)
        let decoded = try PatchPackageCodec.decodePackage(data, password: nil)
        XCTAssertEqual(decoded.format, .dtbp)
        XCTAssertEqual(decoded.project, project)
    }

    func testRoundTripWithPassword() throws {
        let project = makeProject()
        let data = try PatchPackageCodec.encodePackage(project: project, password: "s3cret")
        let decoded = try PatchPackageCodec.decodePackage(data, password: "s3cret")
        XCTAssertEqual(decoded.project, project)
    }

    func testWrongPasswordThrows() throws {
        let project = makeProject()
        let data = try PatchPackageCodec.encodePackage(project: project, password: "right")
        XCTAssertThrowsError(try PatchPackageCodec.decodePackage(data, password: "wrong")) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .invalidPasswordOrCorruptedPackage)
        }
    }

    func testMissingPasswordThrows() throws {
        let project = makeProject()
        let data = try PatchPackageCodec.encodePackage(project: project, password: "right")
        XCTAssertThrowsError(try PatchPackageCodec.decodePackage(data, password: nil)) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .invalidPasswordOrCorruptedPackage)
        }
    }

    func testTruncatedDataThrows() throws {
        let data = try PatchPackageCodec.encodePackage(project: makeProject(), password: nil)
        let truncated = Data(data.prefix(data.count / 2))
        XCTAssertThrowsError(try PatchPackageCodec.decodePackage(truncated, password: nil))
    }

    func testGarbageDataThrows() {
        XCTAssertThrowsError(try PatchPackageCodec.decodePackage(Data("not a package".utf8), password: nil)) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .unsupportedFormat)
        }
    }

    func testPrivateRequiresPassword() {
        let project = makeProject(isPrivate: true)
        XCTAssertThrowsError(try PatchPackageCodec.encodePackage(project: project, password: nil)) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .privatePatchRequiresPassword)
        }
    }

    func testPrivateRoundTrip() throws {
        let project = makeProject(isPrivate: true)
        let data = try PatchPackageCodec.encodePackage(project: project, password: "p")
        let decoded = try PatchPackageCodec.decodePackage(data, password: "p")
        XCTAssertEqual(decoded.project, project)
    }

    func testDuplicateTargetRejected() {
        var project = makeProject()
        project.rules.append(PatchRule(
            relativePath: "Library/Preferences/com.example.plist",
            action: .replaceFile,
            replacementData: Data("other".utf8)
        ))
        XCTAssertThrowsError(try PatchPackageCodec.encodePackage(project: project, password: nil)) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .duplicateTarget)
        }
    }

    func testUnsafePathRejected() {
        var project = makeProject()
        project.rules = [PatchRule(
            relativePath: "../escape",
            action: .replaceFile,
            replacementData: Data("x".utf8)
        )]
        XCTAssertThrowsError(try PatchPackageCodec.encodePackage(project: project, password: nil)) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .unsafeTargetPath)
        }
    }
}
