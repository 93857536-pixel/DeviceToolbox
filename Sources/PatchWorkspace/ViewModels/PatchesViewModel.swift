import Combine
import Foundation

/// 把补丁服务层错误转成用户可见文案:优先使用 `LocalizedError` 自带的中英文案,否则用通用兜底。
/// 与域 C1 的 `filesErrorMessage` 各司其职,避免跨域耦合。
func patchErrorMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(localized: "patch.error.generic")
}

/// 补丁项目库共享状态:项目列表 + 新建草稿 / 删除 / 导入操作。
/// 所有持久化都经由域 B 的 `ProjectStore` / `PatchPackageCodec`,UI 层不直接碰磁盘细节。
@MainActor
final class PatchesViewModel: ObservableObject {

    @Published private(set) var projects: [ProjectIndexEntry] = []
    /// 已应用项目的 id 集合(load 时一次计算,避免列表渲染时反复读盘)。
    @Published private(set) var appliedProjectIDs: Set<UUID> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var busyMessage: String?

    private let store = ProjectStore()

    var isBusy: Bool { busyMessage != nil }

    // MARK: - 列表

    /// 加载项目库,按更新时间倒序,并计算已应用集合。
    func load() {
        projects = store.list().sorted { $0.updatedAt > $1.updatedAt }
        let journalRoot = PatchTransaction.defaultJournalRoot()
        appliedProjectIDs = Set(projects.filter {
            PatchTransaction.isApplied(projectID: $0.projectID, journalRoot: journalRoot)
        }.map(\.projectID))
    }

    // MARK: - 新建草稿

    /// 新建一个非私密、空规则的草稿项目并保存;成功后刷新列表并返回项目。
    @discardableResult
    func createDraft(named rawName: String, author: String = "") async -> PatchProject? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = String(localized: "patch.error.empty_name")
            return nil
        }
        let project = PatchProject(name: name, author: author, isPrivate: false, rules: [])
        do {
            try store.save(project, password: nil)
            load()
            return project
        } catch {
            errorMessage = patchErrorMessage(for: error)
            return nil
        }
    }

    // MARK: - 删除

    func delete(_ entry: ProjectIndexEntry) async {
        do {
            try store.delete(id: entry.projectID)
            load()
        } catch {
            errorMessage = patchErrorMessage(for: error)
        }
    }

    // MARK: - 导入

    /// 从 `.dtbp` / `.3105` 文件导入补丁包(私密包需密码)。
    func importPackage(from url: URL, password: String?) async {
        setBusy(String(localized: "patch.busy.importing"))
        defer { clearBusy() }
        do {
            let data = try Data(contentsOf: url)
            let project: PatchProject
            switch PatchPackageCodec.detectFormat(data) {
            case .dtbp:
                project = try PatchPackageCodec.decodePackage(data, password: password).project
            case .legacy3105:
                project = try PatchPackageCodec.import3105Package(data, password: password, origin: nil)
            case nil:
                throw PatchWorkspaceError.unsupportedFormat
            }
            try store.save(project, password: password)
            load()
        } catch {
            errorMessage = patchErrorMessage(for: error)
        }
    }

    // MARK: - 错误与进行中

    func dismissError() {
        errorMessage = nil
    }

    private func setBusy(_ message: String) {
        busyMessage = message
    }

    private func clearBusy() {
        busyMessage = nil
    }
}
