import CryptoKit
import Foundation

// MARK: - 仓库源存储

/// 仓库源 CRUD + 索引抓取(缓存 + ETag)+ 包下载(大小上限校验)。
/// 持久化于 UserDefaults suite `patch.repositories`。
struct RepositoryStore: Sendable {
    let suiteName: String

    static let defaultSuiteName = "patch.repositories"

    init(suiteName: String = RepositoryStore.defaultSuiteName) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static let sourcesKey = "sources.v1"

    private static func indexCacheKey(_ id: UUID) -> String {
        "index.cache.\(id.uuidString)"
    }

    private static func etagKey(_ id: UUID) -> String {
        "index.etag.\(id.uuidString)"
    }

    // MARK: - 源 CRUD

    func listSources() -> [RepositorySource] {
        guard let data = defaults.data(forKey: Self.sourcesKey),
              let sources = try? JSONDecoder().decode([RepositorySource].self, from: data) else {
            return []
        }
        return sources
    }

    func source(id: UUID) -> RepositorySource? {
        listSources().first { $0.id == id }
    }

    func addSource(name: String, baseURL: URL) throws -> RepositorySource {
        let url = try Self.validateURL(baseURL)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw RepositoryError.insecureURL
        }
        var sources = listSources()
        guard !sources.contains(where: {
            $0.baseURL.absoluteString.caseInsensitiveCompare(url.absoluteString) == .orderedSame
        }) else {
            throw RepositoryError.sourceAlreadyExists
        }
        let source = RepositorySource(name: trimmedName, baseURL: url)
        sources.append(source)
        try persist(sources)
        return source
    }

    func removeSource(id: UUID) {
        var sources = listSources()
        sources.removeAll { $0.id == id }
        try? persist(sources)
        defaults.removeObject(forKey: Self.indexCacheKey(id))
        defaults.removeObject(forKey: Self.etagKey(id))
    }

    private func persist(_ sources: [RepositorySource]) throws {
        do {
            let data = try JSONEncoder().encode(sources)
            defaults.set(data, forKey: Self.sourcesKey)
        } catch {
            throw RepositoryError.invalidIndex
        }
    }

    // MARK: - 索引抓取

    func fetchIndex(from source: RepositorySource) async throws -> [RepositoryIndexEntry] {
        let url = try Self.validateURL(source.baseURL)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = defaults.string(forKey: Self.etagKey(source.id)) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RepositoryError.downloadFailed
        }
        guard let http = response as? HTTPURLResponse else {
            throw RepositoryError.downloadFailed
        }
        if http.statusCode == 304 {
            guard let cached = defaults.data(forKey: Self.indexCacheKey(source.id)),
                  let index = try? JSONDecoder().decode(RepositoryIndex.self, from: cached) else {
                throw RepositoryError.downloadFailed
            }
            return index.entries
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RepositoryError.downloadFailed
        }
        guard data.count <= RepositoryLimits.maximumIndexBytes else {
            throw RepositoryError.invalidIndex
        }
        let index = try decodeIndex(data)
        defaults.set(data, forKey: Self.indexCacheKey(source.id))
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            defaults.set(etag, forKey: Self.etagKey(source.id))
        }
        return index.entries
    }

    private func decodeIndex(_ data: Data) throws -> RepositoryIndex {
        let index: RepositoryIndex
        do {
            index = try JSONDecoder().decode(RepositoryIndex.self, from: data)
        } catch {
            throw RepositoryError.invalidIndex
        }
        guard index.schemaVersion == 1 else {
            throw RepositoryError.invalidIndex
        }
        // 校验每条下载地址为 https。
        for entry in index.entries {
            _ = try Self.validateURL(entry.downloadURL)
        }
        return index
    }

    // MARK: - 包下载

    func download(_ entry: RepositoryIndexEntry) async throws -> Data {
        let url = try Self.validateURL(entry.downloadURL)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw RepositoryError.downloadFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RepositoryError.downloadFailed
        }
        guard data.count <= RepositoryLimits.maximumDownloadBytes else {
            throw RepositoryError.sizeLimitExceeded
        }
        if let expected = entry.sha256, !expected.isEmpty {
            let actual = Self.sha256Hex(data)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                throw RepositoryError.checksumMismatch
            }
        }
        return data
    }

    // MARK: - URL 策略

    static func validateURL(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              host != "localhost",
              !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local")
        else {
            throw RepositoryError.insecureURL
        }
        return url.absoluteURL
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
