import CommonCrypto
import CryptoKit
import Foundation
import Security

// MARK: - 包格式识别

/// 补丁包格式。
enum PatchPackageFormat: Equatable, Sendable {
    /// 自有 DTBP 格式。
    case dtbp
    /// 3105 兼容格式(v1-v3)。
    case legacy3105
}

/// 解码结果。
struct DecodedPackage: Sendable {
    let project: PatchProject
    let contentKey: Data
    let format: PatchPackageFormat
}

// MARK: - 编解码器

/// 补丁包编解码器。
///
/// 自有格式 "DTBP":magic `DTBP1PACK\0` + JSON 编码的 envelope(schema 1),payload 为
/// JSON 的 `{project, replacementDigests}`,AES-GCM 加密;密码经 PBKDF2-HMAC-SHA256
/// 派生 wrapping key 后包裹 32 字节 contentKey。envelope 思路参照 3105 但字段/序列化自设计。
///
/// 兼容导入:能还原 3105 v1-v3 真实包(见 `import3105Package`),其格式事实(仅格式,代码原创):
/// magic `3105PATCH\0`、envelope 与 payload 均为二进制 plist、AES-GCM + PBKDF2、
/// AAD 字符串 `3105PATCH/v<ver>/key/<id>` 与 `3105PATCH/v<ver>/payload/<id>`。
enum PatchPackageCodec {
    // MARK: - 常量

    private static let dtbpMagic = Data("DTBP1PACK\0".utf8)
    private static let legacyMagic = Data("3105PATCH\0".utf8)
    private static let latestSchemaVersion = 1
    private static let legacyMinimumSchemaVersion = 1
    private static let legacyLatestSchemaVersion = 3
    private static let contentKeyLength = 32
    private static let saltLength = 16

    // MARK: - envelope / payload(DTBP 用 JSON,3105 用二进制 plist,字段同名)

    private struct Envelope: Codable {
        let schemaVersion: Int
        let keyAADVersion: Int?
        let packageID: UUID
        let isPasswordProtected: Bool
        let kdfSalt: Data?
        let kdfIterations: Int?
        let wrappedContentKey: Data?
        let publicContentKey: Data?
        let keyFingerprint: Data
        let encryptedPayload: Data
    }

    private struct Payload: Codable {
        let project: PatchProject
        let replacementDigests: [String: Data]
    }

    // MARK: - 3105 兼容解码结构(payload 内的 3105 PatchProject 字段布局)

    private struct LegacyPayload: Codable {
        let project: LegacyProject
        let replacementDigests: [String: Data]
    }

    private struct LegacyProject: Codable {
        let id: UUID
        let name: String
        let author: String
        let isPrivate: Bool
        let createdAt: Date
        let updatedAt: Date
        let bundleIdentifiers: [String]
        let directories: [LegacyDirectory]
        let rules: [LegacyRule]
    }

    private struct LegacyDirectory: Codable {
        let id: UUID
        let bundleID: String
        let relativePath: String
    }

    private struct LegacyRule: Codable {
        let id: UUID
        let bundleID: String
        let relativePath: String
        let replacementFilename: String
        let replacementData: Data
    }

    // MARK: - 格式识别

    static func detectFormat(_ data: Data) -> PatchPackageFormat? {
        if data.prefix(dtbpMagic.count) == dtbpMagic { return .dtbp }
        if data.prefix(legacyMagic.count) == legacyMagic { return .legacy3105 }
        return nil
    }

    // MARK: - 自有 DTBP 编码

    static func encodePackage(
        project: PatchProject,
        password: String?,
        kdfIterations: Int = PatchPackageLimits.defaultKDFIterations
    ) throws -> Data {
        try validate(project)
        let contentKey = try randomData(count: contentKeyLength)
        let protected = !(password ?? "").isEmpty
        if project.isPrivate && !protected {
            throw PatchWorkspaceError.privatePatchRequiresPassword
        }

        let salt: Data?
        let iterations: Int?
        let wrappedKey: Data?
        let publicKey: Data?
        if protected {
            guard let password,
                  password.utf8.count <= PatchPackageLimits.maximumPasswordBytes,
                  (PatchPackageLimits.minimumKDFIterations...PatchPackageLimits.maximumKDFIterations)
                    .contains(kdfIterations)
            else {
                throw PatchWorkspaceError.invalidProject
            }
            salt = try randomData(count: saltLength)
            iterations = kdfIterations
            let wrappingKey = try deriveKey(password: password, salt: salt!, iterations: kdfIterations)
            wrappedKey = try aesSeal(
                contentKey,
                key: wrappingKey,
                aad: dtbpKeyAAD(packageID: project.id, version: latestSchemaVersion)
            )
            publicKey = nil
        } else {
            salt = nil
            iterations = nil
            wrappedKey = nil
            publicKey = contentKey
        }

        let digests = Dictionary(uniqueKeysWithValues: project.rules.compactMap { rule -> (String, Data)? in
            guard let replacementData = rule.replacementData else { return nil }
            return (rule.id.uuidString, Data(SHA256.hash(data: replacementData)))
        })
        let payload = Payload(project: project, replacementDigests: digests)
        let payloadData = try jsonEncoder().encode(payload)
        let encryptedPayload = try aesSeal(
            payloadData,
            key: contentKey,
            aad: dtbpPayloadAAD(packageID: project.id, version: latestSchemaVersion)
        )

        let envelope = Envelope(
            schemaVersion: latestSchemaVersion,
            keyAADVersion: protected ? latestSchemaVersion : nil,
            packageID: project.id,
            isPasswordProtected: protected,
            kdfSalt: salt,
            kdfIterations: iterations,
            wrappedContentKey: wrappedKey,
            publicContentKey: publicKey,
            keyFingerprint: fingerprint(contentKey),
            encryptedPayload: encryptedPayload
        )
        var result = dtbpMagic
        result.append(try jsonEncoder().encode(envelope))
        return result
    }

    // MARK: - 自有 DTBP 解码

    static func decodePackage(_ data: Data, password: String?) throws -> DecodedPackage {
        do {
            let envelope = try parseDTBPEnvelope(data)
            let contentKey = try unwrapContentKey(
                envelope: envelope,
                password: password,
                keyAAD: { dtbpKeyAAD(packageID: envelope.packageID, version: $0) }
            )
            let payloadData = try aesOpen(
                envelope.encryptedPayload,
                key: contentKey,
                aad: dtbpPayloadAAD(packageID: envelope.packageID, version: envelope.schemaVersion)
            )
            let payload = try jsonDecoder().decode(Payload.self, from: payloadData)
            guard payload.project.id == envelope.packageID else {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
            if payload.project.isPrivate && !envelope.isPasswordProtected {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
            try validate(payload.project)
            try verifyDigests(project: payload.project, digests: payload.replacementDigests)
            return DecodedPackage(project: payload.project, contentKey: contentKey, format: .dtbp)
        } catch let error as PatchWorkspaceError {
            switch error {
            case .unsupportedFormat, .unsupportedVersion:
                throw error
            default:
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
        } catch {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
    }

    // MARK: - 3105 兼容导入

    static func import3105Package(
        _ data: Data,
        password: String?,
        origin: PatchProjectOrigin? = nil
    ) throws -> PatchProject {
        do {
            let envelope = try parseLegacyEnvelope(data)
            let contentKey = try unwrapContentKey(
                envelope: envelope,
                password: password,
                keyAAD: { legacyKeyAAD(packageID: envelope.packageID, version: $0) }
            )
            let payloadData = try aesOpen(
                envelope.encryptedPayload,
                key: contentKey,
                aad: legacyPayloadAAD(packageID: envelope.packageID, version: envelope.schemaVersion)
            )
            let payload = try PropertyListDecoder().decode(LegacyPayload.self, from: payloadData)
            guard payload.project.id == envelope.packageID else {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
            if payload.project.isPrivate && !(envelope.schemaVersion >= 3 && envelope.isPasswordProtected) {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
            try verifyLegacyDigests(project: payload.project, digests: payload.replacementDigests)
            return convert(legacy: payload.project, origin: origin)
        } catch let error as PatchWorkspaceError {
            switch error {
            case .unsupportedFormat, .unsupportedVersion:
                throw error
            default:
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
        } catch {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
    }

    // MARK: - 校验

    static func validate(_ project: PatchProject) throws {
        let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = project.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.utf8.count <= 120,
              author == project.author,
              author.utf8.count <= PatchPackageLimits.maximumAuthorBytes,
              !author.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw PatchWorkspaceError.invalidProject
        }

        var targets = Set<String>()
        var ruleIDs = Set<UUID>()
        for rule in project.rules {
            let path = try PatchPathValidator.canonicalRelativePath(rule.relativePath)
            guard path == rule.relativePath, ruleIDs.insert(rule.id).inserted else {
                throw PatchWorkspaceError.invalidProject
            }
            switch rule.action {
            case .replaceFile:
                guard rule.replacementData != nil else { throw PatchWorkspaceError.invalidProject }
                if let filename = rule.replacementFilename {
                    guard !filename.isEmpty,
                          filename.utf8.count <= 255,
                          !filename.contains("/"),
                          !filename.contains("\\"),
                          !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                    else {
                        throw PatchWorkspaceError.invalidProject
                    }
                }
            case .deleteFile, .addFolder:
                guard rule.replacementData == nil else { throw PatchWorkspaceError.invalidProject }
            }
            guard targets.insert(path).inserted else {
                throw PatchWorkspaceError.duplicateTarget
            }
        }
    }

    // MARK: - 3105 → 自有模型映射

    private static func convert(legacy: LegacyProject, origin: PatchProjectOrigin?) -> PatchProject {
        var rules: [PatchRule] = []
        for directory in legacy.directories {
            rules.append(PatchRule(
                relativePath: directory.bundleID + "/" + directory.relativePath,
                action: .addFolder
            ))
        }
        for rule in legacy.rules {
            let filename = rule.replacementFilename.isEmpty ? nil : rule.replacementFilename
            rules.append(PatchRule(
                relativePath: rule.bundleID + "/" + rule.relativePath,
                action: .replaceFile,
                replacementFilename: filename,
                replacementData: rule.replacementData
            ))
        }
        return PatchProject(
            id: legacy.id,
            name: legacy.name,
            author: legacy.author,
            isPrivate: legacy.isPrivate,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt,
            targetRootName: "Patches",
            origin: origin,
            rules: rules
        )
    }

    private static func verifyDigests(project: PatchProject, digests: [String: Data]) throws {
        let expected = Dictionary(uniqueKeysWithValues: project.rules.compactMap { rule -> (String, Data)? in
            guard let replacementData = rule.replacementData else { return nil }
            return (rule.id.uuidString, Data(SHA256.hash(data: replacementData)))
        })
        guard expected.count == digests.count else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        for (key, value) in expected where digests[key] != value {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
    }

    private static func verifyLegacyDigests(project: LegacyProject, digests: [String: Data]) throws {
        let expected = Dictionary(uniqueKeysWithValues: project.rules.map {
            ($0.id.uuidString, Data(SHA256.hash(data: $0.replacementData)))
        })
        guard expected.count == digests.count else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        for (key, value) in expected where digests[key] != value {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
    }

    // MARK: - envelope 解析

    private static func parseDTBPEnvelope(_ data: Data) throws -> Envelope {
        guard data.count > dtbpMagic.count, data.prefix(dtbpMagic.count) == dtbpMagic else {
            throw PatchWorkspaceError.unsupportedFormat
        }
        let body = Data(data.dropFirst(dtbpMagic.count))
        let envelope: Envelope
        do {
            envelope = try jsonDecoder().decode(Envelope.self, from: body)
        } catch {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        guard envelope.schemaVersion == latestSchemaVersion else {
            throw PatchWorkspaceError.unsupportedVersion
        }
        try validateEnvelopeShape(envelope)
        return envelope
    }

    private static func parseLegacyEnvelope(_ data: Data) throws -> Envelope {
        guard data.count > legacyMagic.count, data.prefix(legacyMagic.count) == legacyMagic else {
            throw PatchWorkspaceError.unsupportedFormat
        }
        let body = Data(data.dropFirst(legacyMagic.count))
        let envelope: Envelope
        do {
            envelope = try PropertyListDecoder().decode(Envelope.self, from: body)
        } catch {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        guard (legacyMinimumSchemaVersion...legacyLatestSchemaVersion).contains(envelope.schemaVersion) else {
            throw PatchWorkspaceError.unsupportedVersion
        }
        try validateEnvelopeShape(envelope)
        return envelope
    }

    private static func validateEnvelopeShape(_ envelope: Envelope) throws {
        guard envelope.keyFingerprint.count == contentKeyLength,
              envelope.encryptedPayload.count >= 28
        else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        if envelope.isPasswordProtected {
            guard envelope.publicContentKey == nil,
                  envelope.kdfSalt?.count == saltLength,
                  let iterations = envelope.kdfIterations,
                  (PatchPackageLimits.minimumKDFIterations...PatchPackageLimits.maximumKDFIterations)
                    .contains(iterations),
                  envelope.wrappedContentKey != nil
            else {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
        } else {
            guard envelope.kdfSalt == nil,
                  envelope.kdfIterations == nil,
                  envelope.wrappedContentKey == nil,
                  envelope.publicContentKey?.count == contentKeyLength
            else {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
        }
    }

    private static func unwrapContentKey(
        envelope: Envelope,
        password: String?,
        keyAAD: (Int) -> Data
    ) throws -> Data {
        let contentKey: Data
        if envelope.isPasswordProtected {
            guard let password,
                  !password.isEmpty,
                  password.utf8.count <= PatchPackageLimits.maximumPasswordBytes,
                  let salt = envelope.kdfSalt,
                  let iterations = envelope.kdfIterations,
                  let wrappedKey = envelope.wrappedContentKey
            else {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
            let wrappingKey = try deriveKey(password: password, salt: salt, iterations: iterations)
            contentKey = try aesOpen(
                wrappedKey,
                key: wrappingKey,
                aad: keyAAD(envelope.keyAADVersion ?? envelope.schemaVersion)
            )
        } else {
            guard let storedKey = envelope.publicContentKey else {
                throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
            }
            contentKey = storedKey
        }
        guard contentKey.count == contentKeyLength,
              fingerprint(contentKey) == envelope.keyFingerprint
        else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        return contentKey
    }

    // MARK: - 加密原语

    private static func aesSeal(_ plaintext: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == contentKeyLength else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: aad)
        guard let combined = sealed.combined else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        return combined
    }

    private static func aesOpen(_ ciphertext: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == contentKeyLength else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> Data {
        guard (PatchPackageLimits.minimumKDFIterations...PatchPackageLimits.maximumKDFIterations)
            .contains(iterations) else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        let passwordData = Data(password.utf8)
        var output = Data(count: contentKeyLength)
        let status = output.withUnsafeMutableBytes { outputBuffer in
            passwordData.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                        contentKeyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw PatchWorkspaceError.invalidPasswordOrCorruptedPackage
        }
        return output
    }

    private static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PatchWorkspaceError.writeFailed
        }
        return data
    }

    private static func fingerprint(_ key: Data) -> Data {
        Data(SHA256.hash(data: key))
    }

    private static func dtbpKeyAAD(packageID: UUID, version: Int) -> Data {
        Data("DTBP/v\(version)/key/\(packageID.uuidString)".utf8)
    }

    private static func dtbpPayloadAAD(packageID: UUID, version: Int) -> Data {
        Data("DTBP/v\(version)/payload/\(packageID.uuidString)".utf8)
    }

    private static func legacyKeyAAD(packageID: UUID, version: Int) -> Data {
        Data("3105PATCH/v\(version)/key/\(packageID.uuidString)".utf8)
    }

    private static func legacyPayloadAAD(packageID: UUID, version: Int) -> Data {
        Data("3105PATCH/v\(version)/payload/\(packageID.uuidString)".utf8)
    }

    // MARK: - JSON 编解码器

    private static func jsonEncoder() -> JSONEncoder {
        JSONEncoder()
    }

    private static func jsonDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
