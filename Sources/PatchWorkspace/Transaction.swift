import CryptoKit
import Foundation

// MARK: - 事务回执

struct PatchTransactionReceipt: Equatable, Identifiable, Sendable {
    let id: UUID
    let projectID: UUID
    let journalURL: URL
}

// MARK: - 目标变化

enum PatchTargetChangeKind: Equatable, Sendable {
    case modified
    case missing
}

struct PatchTargetChange: Equatable, Sendable {
    let relativePath: String
    let kind: PatchTargetChangeKind
}

// MARK: - 事务

/// 应用/回滚事务。
///
/// apply 目标根默认 `Documents/Patches/Applied/<projectName>/`,journal 写到
/// `Documents/Patches/.Journal/<projectID>/<transactionID>/`;apply 前把将被覆盖/删除的
/// 原文备份到 journal,restore 按 journal 字节级还原并删除新增目录。
enum PatchTransaction {
    // MARK: - 默认根路径

    static func defaultAppliedRoot(projectName: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Patches/Applied", isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
    }

    static func defaultJournalRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Patches/.Journal", isDirectory: true)
    }

    // MARK: - 内部结构

    private enum Status: String, Codable {
        case prepared
        case applied
        case rolledBack
        case restored
    }

    private struct Record: Codable {
        let ruleID: UUID
        let relativePath: String
        let action: PatchAction
        let originalExisted: Bool
        let backupFilename: String?
        let originalDigest: Data?
        let replacementDigest: Data?
    }

    private struct Journal: Codable {
        let schemaVersion: Int
        let transactionID: UUID
        let projectID: UUID
        let appliedRootPath: String
        let createdAt: Date
        var status: Status
        let records: [Record]
        let createdDirectories: [String]
    }

    private static let schemaVersion = 1
    private static let journalFilename = "journal.plist"

    // MARK: - apply

    static func apply(
        project: PatchProject,
        appliedRoot: URL,
        journalRoot: URL,
        fileManager: FileManager = .default
    ) throws -> PatchTransactionReceipt {
        guard !project.rules.isEmpty else {
            throw PatchWorkspaceError.invalidProject
        }
        guard latestReceipt(projectID: project.id, journalRoot: journalRoot, fileManager: fileManager) == nil else {
            throw PatchWorkspaceError.projectAlreadyApplied
        }

        // 解析目标(防穿越 + 去重)。
        var targets: [(rule: PatchRule, url: URL)] = []
        var targetKeys = Set<String>()
        for rule in project.rules {
            let path = try PatchPathValidator.canonicalRelativePath(rule.relativePath)
            guard targetKeys.insert(path).inserted else {
                throw PatchWorkspaceError.duplicateTarget
            }
            let url = try PatchPathValidator.resolveTargetURL(relativePath: path, within: appliedRoot)
            targets.append((rule, url))
        }

        // 需要创建的目录(显式 addFolder + 隐式父目录),按深度升序。
        let createdDirectories = missingDirectories(
            for: project,
            within: appliedRoot,
            fileManager: fileManager
        )

        let transactionID = UUID()
        let transactionDirectory = journalRoot
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
            .appendingPathComponent(transactionID.uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: transactionDirectory, withIntermediateDirectories: true)
        } catch {
            throw PatchWorkspaceError.applyFailed
        }

        // 备份将被覆盖/删除的原文。
        var records: [Record] = []
        do {
            for (rule, url) in targets {
                switch rule.action {
                case .replaceFile:
                    let existed = fileManager.fileExists(atPath: url.path)
                    var backupFilename: String?
                    var originalDigest: Data?
                    if existed {
                        backupFilename = "\(rule.id.uuidString).original"
                        let backupURL = transactionDirectory.appendingPathComponent(backupFilename!)
                        try fileManager.copyItem(at: url, to: backupURL)
                        originalDigest = try digestFile(backupURL)
                    }
                    records.append(Record(
                        ruleID: rule.id,
                        relativePath: rule.relativePath,
                        action: .replaceFile,
                        originalExisted: existed,
                        backupFilename: backupFilename,
                        originalDigest: originalDigest,
                        replacementDigest: digest(rule.replacementData ?? Data())
                    ))
                case .deleteFile:
                    let existed = fileManager.fileExists(atPath: url.path)
                    var backupFilename: String?
                    var originalDigest: Data?
                    if existed {
                        backupFilename = "\(rule.id.uuidString).original"
                        let backupURL = transactionDirectory.appendingPathComponent(backupFilename!)
                        try fileManager.copyItem(at: url, to: backupURL)
                        originalDigest = try digestFile(backupURL)
                    }
                    records.append(Record(
                        ruleID: rule.id,
                        relativePath: rule.relativePath,
                        action: .deleteFile,
                        originalExisted: existed,
                        backupFilename: backupFilename,
                        originalDigest: originalDigest,
                        replacementDigest: nil
                    ))
                case .addFolder:
                    // 目录创建由 createdDirectories 负责,无需文件记录。
                    break
                }
            }
        } catch let error as PatchWorkspaceError {
            throw error
        } catch {
            throw PatchWorkspaceError.applyFailed
        }

        let journalURL = transactionDirectory.appendingPathComponent(journalFilename)
        var journal = Journal(
            schemaVersion: schemaVersion,
            transactionID: transactionID,
            projectID: project.id,
            appliedRootPath: appliedRoot.standardizedFileURL.path,
            createdAt: Date(),
            status: .prepared,
            records: records,
            createdDirectories: createdDirectories
        )
        do {
            try writeJournal(journal, to: journalURL)
        } catch {
            throw PatchWorkspaceError.applyFailed
        }

        // 执行写入。
        do {
            for relativePath in createdDirectories {
                let dir = try PatchPathValidator.resolveTargetURL(relativePath: relativePath, within: appliedRoot)
                if !fileManager.fileExists(atPath: dir.path) {
                    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                }
            }
            for item in targets {
                switch item.rule.action {
                case .replaceFile:
                    try atomicWrite(item.rule.replacementData ?? Data(), to: item.url)
                    let record = records.first { $0.ruleID == item.rule.id }
                    if let record, let expected = record.replacementDigest {
                        guard try digestFile(item.url) == expected else {
                            throw PatchWorkspaceError.applyFailed
                        }
                    }
                case .deleteFile:
                    if fileManager.fileExists(atPath: item.url.path) {
                        try fileManager.removeItem(at: item.url)
                    }
                case .addFolder:
                    try fileManager.createDirectory(at: item.url, withIntermediateDirectories: true)
                }
            }
            journal.status = .applied
            try writeJournal(journal, to: journalURL)
        } catch {
            // 回滚已写入部分。
            try? rollback(
                records: records,
                transactionDirectory: transactionDirectory,
                appliedRoot: appliedRoot,
                createdDirectories: createdDirectories,
                fileManager: fileManager
            )
            journal.status = .rolledBack
            try? writeJournal(journal, to: journalURL)
            throw PatchWorkspaceError.applyFailed
        }

        return PatchTransactionReceipt(
            id: transactionID,
            projectID: project.id,
            journalURL: journalURL
        )
    }

    // MARK: - 检查 / 回滚

    static func inspectRestore(
        receipt: PatchTransactionReceipt,
        fileManager: FileManager = .default
    ) throws -> [PatchTargetChange] {
        do {
            let journal = try activeJournal(for: receipt)
            guard journal.status == .applied else { return [] }
            let appliedRoot = URL(fileURLWithPath: journal.appliedRootPath, isDirectory: true)
            let resolved = try resolvedRecords(journal.records, appliedRoot: appliedRoot)
            return try changedTargets(in: resolved, fileManager: fileManager)
        } catch {
            throw PatchWorkspaceError.restoreFailed
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false,
        fileManager: FileManager = .default
    ) throws {
        do {
            var journal = try activeJournal(for: receipt)
            let transactionDirectory = receipt.journalURL.deletingLastPathComponent()
            let appliedRoot = URL(fileURLWithPath: journal.appliedRootPath, isDirectory: true)
            let resolved = try resolvedRecords(journal.records, appliedRoot: appliedRoot)

            if journal.status == .applied {
                let changes = try changedTargets(in: resolved, fileManager: fileManager)
                if !changes.isEmpty && !allowChangedTargets {
                    throw PatchWorkspaceError.restoreTargetsChanged(changes.map(\.relativePath))
                }
            }

            // 逆序还原(新增的删除,已存在的从备份还原)。
            for item in resolved.reversed() {
                if item.record.originalExisted {
                    guard let backupFilename = item.record.backupFilename else {
                        throw PatchWorkspaceError.restoreFailed
                    }
                    let backupURL = transactionDirectory.appendingPathComponent(backupFilename)
                    let data = try Data(contentsOf: backupURL)
                    try data.write(to: item.target, options: .atomic)
                } else if fileManager.fileExists(atPath: item.target.path) {
                    try fileManager.removeItem(at: item.target)
                }
            }

            journal.status = .restored
            try writeJournal(journal, to: receipt.journalURL)

            removeEmptyCreatedDirectories(journal.createdDirectories, appliedRoot: appliedRoot, fileManager: fileManager)
        } catch let error as PatchWorkspaceError {
            if case .restoreTargetsChanged = error { throw error }
            throw PatchWorkspaceError.restoreFailed
        } catch {
            throw PatchWorkspaceError.restoreFailed
        }
    }

    static func isApplied(projectID: UUID, journalRoot: URL, fileManager: FileManager = .default) -> Bool {
        latestReceipt(projectID: projectID, journalRoot: journalRoot, fileManager: fileManager) != nil
    }

    static func latestReceipt(
        projectID: UUID,
        journalRoot: URL,
        fileManager: FileManager = .default
    ) -> PatchTransactionReceipt? {
        let projectDirectory = journalRoot.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: projectDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return directories.compactMap { directory -> (Journal, URL)? in
            let url = directory.appendingPathComponent(journalFilename)
            guard let journal = try? readJournal(url),
                  journal.schemaVersion == schemaVersion,
                  journal.status == .applied || journal.status == .prepared else { return nil }
            return (journal, url)
        }
        .sorted { $0.0.createdAt > $1.0.createdAt }
        .first
        .map {
            PatchTransactionReceipt(
                id: $0.0.transactionID,
                projectID: $0.0.projectID,
                journalURL: $0.1
            )
        }
    }

    // MARK: - 内部辅助

    private static func missingDirectories(
        for project: PatchProject,
        within appliedRoot: URL,
        fileManager: FileManager
    ) -> [String] {
        var needed = Set<String>()
        for rule in project.rules {
            guard let components = try? PatchPathValidator.canonicalRelativePath(rule.relativePath)
                .split(separator: "/").map(String.init) else { continue }
            switch rule.action {
            case .replaceFile:
                for i in 1..<components.count {
                    needed.insert(components.prefix(i).joined(separator: "/"))
                }
            case .addFolder:
                for i in 1...components.count {
                    needed.insert(components.prefix(i).joined(separator: "/"))
                }
            case .deleteFile:
                break
            }
        }
        let sorted = needed.sorted { lhs, rhs in
            let leftDepth = lhs.filter { $0 == "/" }.count
            let rightDepth = rhs.filter { $0 == "/" }.count
            return leftDepth == rightDepth ? lhs < rhs : leftDepth < rightDepth
        }
        return sorted.filter { relativePath in
            guard let url = try? PatchPathValidator.resolveTargetURL(relativePath: relativePath, within: appliedRoot) else {
                return false
            }
            return !fileManager.fileExists(atPath: url.path)
        }
    }

    private static func resolvedRecords(
        _ records: [Record],
        appliedRoot: URL
    ) throws -> [(record: Record, target: URL)] {
        try records.map { record in
            let target = try PatchPathValidator.resolveTargetURL(relativePath: record.relativePath, within: appliedRoot)
            return (record, target)
        }
    }

    private static func changedTargets(
        in resolved: [(record: Record, target: URL)],
        fileManager: FileManager
    ) throws -> [PatchTargetChange] {
        try resolved.compactMap { item in
            switch item.record.action {
            case .replaceFile:
                guard fileManager.fileExists(atPath: item.target.path) else {
                    return PatchTargetChange(relativePath: item.record.relativePath, kind: .missing)
                }
                guard let expected = item.record.replacementDigest,
                      try digestFile(item.target) == expected else {
                    return PatchTargetChange(relativePath: item.record.relativePath, kind: .modified)
                }
                return nil
            case .deleteFile:
                if fileManager.fileExists(atPath: item.target.path) {
                    return PatchTargetChange(relativePath: item.record.relativePath, kind: .modified)
                }
                return nil
            case .addFolder:
                return nil
            }
        }
    }

    private static func rollback(
        records: [Record],
        transactionDirectory: URL,
        appliedRoot: URL,
        createdDirectories: [String],
        fileManager: FileManager
    ) throws {
        for record in records.reversed() {
            let target = try PatchPathValidator.resolveTargetURL(relativePath: record.relativePath, within: appliedRoot)
            if record.originalExisted {
                guard let backupFilename = record.backupFilename else { continue }
                let backupURL = transactionDirectory.appendingPathComponent(backupFilename)
                let data = try Data(contentsOf: backupURL)
                try data.write(to: target, options: .atomic)
            } else if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
        }
        removeEmptyCreatedDirectories(createdDirectories, appliedRoot: appliedRoot, fileManager: fileManager)
    }

    private static func removeEmptyCreatedDirectories(
        _ directories: [String],
        appliedRoot: URL,
        fileManager: FileManager
    ) {
        for relativePath in directories.reversed() {
            guard let url = try? PatchPathValidator.resolveTargetURL(relativePath: relativePath, within: appliedRoot),
                  fileManager.fileExists(atPath: url.path) else { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true,
                  values?.isDirectory == true,
                  let contents = try? fileManager.contentsOfDirectory(atPath: url.path),
                  contents.isEmpty else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private static func activeJournal(for receipt: PatchTransactionReceipt) throws -> Journal {
        let journal = try readJournal(receipt.journalURL)
        guard journal.schemaVersion == schemaVersion,
              journal.transactionID == receipt.id,
              journal.projectID == receipt.projectID,
              journal.status == .applied || journal.status == .prepared else {
            throw PatchWorkspaceError.restoreFailed
        }
        return journal
    }

    private static func atomicWrite(_ data: Data, to target: URL) throws {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: target, options: .atomic)
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func digestFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    private static func writeJournal(_ journal: Journal, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(journal).write(to: url, options: .atomic)
    }

    private static func readJournal(_ url: URL) throws -> Journal {
        try PropertyListDecoder().decode(Journal.self, from: Data(contentsOf: url))
    }
}
