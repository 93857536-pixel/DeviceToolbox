import Foundation

// MARK: - 仓库源

/// 一个仓库源(指向一个索引 JSON 的根地址)。
struct RepositorySource: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var baseURL: URL
    var addedAt: Date

    init(id: UUID = UUID(), name: String, baseURL: URL, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.addedAt = addedAt
    }
}

// MARK: - 索引条目

/// 仓库索引中的单个补丁包条目。
struct RepositoryIndexEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var summary: String?
    var downloadURL: URL
    var sha256: String?
    var bundleIDs: [String]?

    init(
        id: String,
        title: String,
        summary: String? = nil,
        downloadURL: URL,
        sha256: String? = nil,
        bundleIDs: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.bundleIDs = bundleIDs
    }
}

// MARK: - 索引文档

/// 仓库索引文档(自有 JSON 格式)。
struct RepositoryIndex: Codable, Sendable {
    let schemaVersion: Int
    let entries: [RepositoryIndexEntry]
}

// MARK: - 错误

enum RepositoryError: Error, Equatable, Sendable {
    case insecureURL
    case invalidIndex
    case sourceAlreadyExists
    case sourceNotFound
    case downloadFailed
    case sizeLimitExceeded
    case checksumMismatch
    case importFailed
}

extension RepositoryError: LocalizedError {
    var localizationKey: String {
        switch self {
        case .insecureURL: return "repo.error.insecure_url"
        case .invalidIndex: return "repo.error.invalid_index"
        case .sourceAlreadyExists: return "repo.error.source_exists"
        case .sourceNotFound: return "repo.error.source_not_found"
        case .downloadFailed: return "repo.error.download_failed"
        case .sizeLimitExceeded: return "repo.error.size_limit"
        case .checksumMismatch: return "repo.error.checksum"
        case .importFailed: return "repo.error.import_failed"
        }
    }

    var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

// MARK: - 上限

enum RepositoryLimits {
    /// 索引 JSON 上限(5 MB)。
    static let maximumIndexBytes = 5 * 1_024 * 1_024
    /// 单个补丁包下载上限(200 MB)。
    static let maximumDownloadBytes = 200 * 1_024 * 1_024
}
