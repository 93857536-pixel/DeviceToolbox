import CommonCrypto
import CryptoKit
import Foundation
import Security
import XCTest
@testable import DeviceToolbox

/// 3105 兼容导入测试:用独立构造的 3105 v1/v2/v3 包(按 3105 格式事实自产)验证
/// `import3105Package` 的格式还原正确性与 bundleID 语义映射。
final class ThreeOneFiveImportTests: XCTestCase {

    // MARK: - 独立 fixture 结构(镜像 3105 字段布局,非复用产品代码)

    private struct FixtureProject: Codable {
        var id: UUID
        var name: String
        var author: String
        var isPrivate: Bool
        var createdAt: Date
        var updatedAt: Date
        var bundleIdentifiers: [String]
        var directories: [FixtureDirectory]
        var rules: [FixtureRule]
    }

    private struct FixtureDirectory: Codable {
        var id: UUID
        var bundleID: String
        var relativePath: String
    }

    private struct FixtureRule: Codable {
        var id: UUID
        var bundleID: String
        var relativePath: String
        var replacementFilename: String
        var replacementData: Data
    }

    private struct FixturePayload: Codable {
        var project: FixtureProject
        var replacementDigests: [String: Data]
    }

    private struct FixtureEnvelope: Codable {
        var schemaVersion: Int
        var keyAADVersion: Int?
        var packageID: UUID
        var isPasswordProtected: Bool
        var kdfSalt: Data?
        var kdfIterations: Int?
        var wrappedContentKey: Data?
        var publicContentKey: Data?
        var keyFingerprint: Data
        var encryptedPayload: Data
    }

    private let magic = Data("3105PATCH\0".utf8)
    private let bundleID = "com.example.app"
    private let projectID = UUID()

    private func fixtureProject(isPrivate: Bool) -> FixtureProject {
        FixtureProject(
            id: projectID,
            name: "3105 Patch",
            author: "3105 Author",
            isPrivate: isPrivate,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            bundleIdentifiers: [bundleID],
            directories: [
                FixtureDirectory(id: UUID(), bundleID: bundleID, relativePath: "Library")
            ],
            rules: [
                FixtureRule(
                    id: UUID(),
                    bundleID: bundleID,
                    relativePath: "Library/Preferences/a.plist",
                    replacementFilename: "a.plist",
                    replacementData: Data("AAA".utf8)
                )
            ]
        )
    }

    /// 独立构造一个 3105 格式包(参考源码事实,非调用产品代码)。
    private func make3105Package(
        schemaVersion: Int,
        isPrivate: Bool,
        password: String?
    ) throws -> Data {
        let project = fixtureProject(isPrivate: isPrivate)
        let contentKey = try randomData(32)
        let protected = !(password ?? "").isEmpty

        let salt: Data?
        let iterations: Int?
        let wrappedKey: Data?
        let publicKey: Data?
        if protected {
            salt = try randomData(16)
            iterations = 100_000
            let wrappingKey = try deriveKey(password: password!, salt: salt!, iterations: iterations!)
            wrappedKey = try seal(contentKey, key: wrappingKey, aad: keyAAD(version: schemaVersion))
            publicKey = nil
        } else {
            salt = nil
            iterations = nil
            wrappedKey = nil
            publicKey = contentKey
        }

        let digests = Dictionary(uniqueKeysWithValues: project.rules.map {
            ($0.id.uuidString, Data(SHA256.hash(data: $0.replacementData)))
        })
        let payloadData = try PropertyListEncoder().encode(
            FixturePayload(project: project, replacementDigests: digests)
        )
        let encryptedPayload = try seal(payloadData, key: contentKey, aad: payloadAAD(version: schemaVersion))

        let envelope = FixtureEnvelope(
            schemaVersion: schemaVersion,
            keyAADVersion: protected ? schemaVersion : nil,
            packageID: projectID,
            isPasswordProtected: protected,
            kdfSalt: salt,
            kdfIterations: iterations,
            wrappedContentKey: wrappedKey,
            publicContentKey: publicKey,
            keyFingerprint: Data(SHA256.hash(data: contentKey)),
            encryptedPayload: encryptedPayload
        )
        var data = magic
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        data.append(try encoder.encode(envelope))
        return data
    }

    private func keyAAD(version: Int) -> Data {
        Data("3105PATCH/v\(version)/key/\(projectID.uuidString)".utf8)
    }

    private func payloadAAD(version: Int) -> Data {
        Data("3105PATCH/v\(version)/payload/\(projectID.uuidString)".utf8)
    }

    private func seal(_ plaintext: Data, key: Data, aad: Data) throws -> Data {
        try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: aad).combined!
    }

    private func deriveKey(password: String, salt: Data, iterations: Int) throws -> Data {
        let passwordData = Data(password.utf8)
        var output = Data(count: 32)
        let status = output.withUnsafeMutableBytes { out in
            passwordData.withUnsafeBytes { pw in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pw.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        s.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        out.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw NSError(domain: "test", code: 1) }
        return output
    }

    private func randomData(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw NSError(domain: "test", code: 2) }
        return data
    }

    // MARK: - 断言辅助

    private func assertImportedProject(_ project: PatchProject, isPrivate: Bool) {
        XCTAssertEqual(project.id, projectID)
        XCTAssertEqual(project.name, "3105 Patch")
        XCTAssertEqual(project.author, "3105 Author")
        XCTAssertEqual(project.isPrivate, isPrivate)
        XCTAssertEqual(project.rules.count, 2)

        let folder = project.rules[0]
        XCTAssertEqual(folder.action, .addFolder)
        XCTAssertEqual(folder.relativePath, "com.example.app/Library")

        let file = project.rules[1]
        XCTAssertEqual(file.action, .replaceFile)
        XCTAssertEqual(file.relativePath, "com.example.app/Library/Preferences/a.plist")
        XCTAssertEqual(file.replacementFilename, "a.plist")
        XCTAssertEqual(file.replacementData, Data("AAA".utf8))
    }

    // MARK: - 测试

    func testImportV1Unprotected() throws {
        let data = try make3105Package(schemaVersion: 1, isPrivate: false, password: nil)
        XCTAssertEqual(PatchPackageCodec.detectFormat(data), .legacy3105)
        assertImportedProject(try PatchPackageCodec.import3105Package(data, password: nil), isPrivate: false)
    }

    func testImportV2Unprotected() throws {
        let data = try make3105Package(schemaVersion: 2, isPrivate: false, password: nil)
        assertImportedProject(try PatchPackageCodec.import3105Package(data, password: nil), isPrivate: false)
    }

    func testImportV3Protected() throws {
        let data = try make3105Package(schemaVersion: 3, isPrivate: true, password: "pw")
        assertImportedProject(try PatchPackageCodec.import3105Package(data, password: "pw"), isPrivate: true)
    }

    func testImportV3ProtectedWrongPassword() throws {
        let data = try make3105Package(schemaVersion: 3, isPrivate: true, password: "pw")
        XCTAssertThrowsError(try PatchPackageCodec.import3105Package(data, password: "nope")) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .invalidPasswordOrCorruptedPackage)
        }
    }

    func testImportRejectsGarbage() {
        XCTAssertThrowsError(try PatchPackageCodec.import3105Package(Data("garbage".utf8), password: nil)) { error in
            XCTAssertEqual(error as? PatchWorkspaceError, .unsupportedFormat)
        }
    }

    func testOriginIsRecorded() throws {
        let data = try make3105Package(schemaVersion: 3, isPrivate: false, password: nil)
        let origin = PatchProjectOrigin(repositoryName: "Repo", repositoryURL: "https://x/repo.json", packageIdentifier: "pkg-1")
        let project = try PatchPackageCodec.import3105Package(data, password: nil, origin: origin)
        XCTAssertEqual(project.origin, origin)
    }
}
