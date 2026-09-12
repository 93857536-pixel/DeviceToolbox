import Combine
import Foundation

/// 把仓库服务层错误转成用户可见文案:优先使用 `LocalizedError`,否则用通用兜底。
func repoErrorMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(localized: "repo.error.generic")
}

/// 仓库共享状态:源列表 / 索引浏览 / 下载导入。
/// 全部网络与持久化经由域 B 的 `RepositoryStore` 与 `RepositoryImportService`。
@MainActor
final class RepositoryViewModel: ObservableObject {

    @Published private(set) var sources: [RepositorySource] = []
    @Published private(set) var selectedSource: RepositorySource?
    @Published private(set) var entries: [RepositoryIndexEntry] = []
    @Published private(set) var isLoadingIndex = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var busyMessage: String?
    /// 正在下载导入的条目 id(行内进度)。
    @Published private(set) var importingEntryID: String?

    private let repository = RepositoryStore()
    private let projectStore = ProjectStore()

    var isBusy: Bool { busyMessage != nil }

    // MARK: - 源

    func loadSources() {
        sources = repository.listSources()
        if selectedSource == nil {
            selectedSource = sources.first
        }
    }

    /// 添加源:名称 + HTTPS 地址。地址先做基础校验,其余交给服务层 validateURL。
    func addSource(name: String, urlString: String) async {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme?.lowercased() == "https" else {
            errorMessage = String(localized: "repo.error.invalid_url")
            return
        }
        do {
            _ = try repository.addSource(name: name, baseURL: url)
            loadSources()
        } catch {
            errorMessage = repoErrorMessage(for: error)
        }
    }

    func removeSource(_ source: RepositorySource) {
        repository.removeSource(id: source.id)
        if selectedSource?.id == source.id {
            selectedSource = nil
            entries = []
        }
        loadSources()
    }

    // MARK: - 索引

    func select(_ source: RepositorySource) async {
        selectedSource = source
        await refreshIndex(for: source)
    }

    func refreshIndex(for source: RepositorySource) async {
        isLoadingIndex = true
        defer { isLoadingIndex = false }
        do {
            entries = try await repository.fetchIndex(from: source)
        } catch {
            entries = []
            errorMessage = repoErrorMessage(for: error)
        }
    }

    // MARK: - 下载导入

    /// 下载并导入单个包到项目库。私密包需密码。
    func downloadAndImport(
        _ entry: RepositoryIndexEntry,
        from source: RepositorySource,
        password: String?
    ) async {
        importingEntryID = entry.id
        defer { importingEntryID = nil }
        do {
            _ = try await RepositoryImportService.importPackage(
                from: entry,
                source: source,
                repository: repository,
                projectStore: projectStore,
                password: password
            )
            resultMessage = String(localized: "repo.import.done")
        } catch {
            errorMessage = repoErrorMessage(for: error)
        }
    }

    @Published private(set) var resultMessage: String?

    // MARK: - 错误与进行中

    func dismissError() {
        errorMessage = nil
    }

    func dismissResult() {
        resultMessage = nil
    }
}
