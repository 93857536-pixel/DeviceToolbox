import Combine
import Foundation

/// 编辑单个补丁项目的共享状态:项目详情加载 / 规则增删改 / 保存 / 应用 / 回滚。
/// 应用与回滚经由域 B 的 `PatchTransaction`(目标根 `Documents/Patches/Applied/<name>/`、
/// journal 根 `Documents/Patches/.Journal/`)。
@MainActor
final class PatchEditorViewModel: ObservableObject {

    @Published private(set) var project: PatchProject?
    /// 首次加载是否已完成(用于区分「加载中」与「加载失败」)。
    @Published private(set) var hasLoaded = false
    @Published private(set) var isApplied = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var busyMessage: String?
    @Published private(set) var resultMessage: String?

    private let store = ProjectStore()
    private let projectID: UUID
    /// 私密项目解码所需密码(非私密为 nil)。
    private var password: String?

    var isBusy: Bool { busyMessage != nil }

    /// 应用目标根(与目标树选择器一致)。
    var appliedRoot: URL {
        PatchTransaction.defaultAppliedRoot(projectName: project?.name ?? "")
    }

    init(projectID: UUID) {
        self.projectID = projectID
    }

    // MARK: - 加载

    func load() {
        do {
            project = try store.load(id: projectID, password: password)
            errorMessage = nil
        } catch {
            project = nil
            errorMessage = patchErrorMessage(for: error)
        }
        hasLoaded = true
        refreshAppliedStatus()
    }

    /// 使用密码重载(私密项目)。
    func load(withPassword rawPassword: String) {
        let pwd = rawPassword.isEmpty ? nil : rawPassword
        do {
            project = try store.load(id: projectID, password: pwd)
            password = pwd
            errorMessage = nil
        } catch {
            errorMessage = patchErrorMessage(for: error)
        }
        refreshAppliedStatus()
    }

    /// 是否因私密包缺少密码而无法加载。
    var needsPassword: Bool {
        guard hasLoaded, project == nil else { return false }
        return store.entry(id: projectID)?.isPrivate == true
    }

    func refreshAppliedStatus() {
        isApplied = PatchTransaction.isApplied(
            projectID: projectID,
            journalRoot: PatchTransaction.defaultJournalRoot()
        )
    }

    // MARK: - 规则编辑

    func addRule(_ rule: PatchRule) {
        guard var current = project else { return }
        current.rules.append(rule)
        current.updatedAt = Date()
        project = current
    }

    func updateRule(id: UUID, with rule: PatchRule) {
        guard var current = project else { return }
        if let index = current.rules.firstIndex(where: { $0.id == id }) {
            current.rules[index] = rule
            current.updatedAt = Date()
            project = current
        }
    }

    func deleteRule(id: UUID) {
        guard var current = project else { return }
        current.rules.removeAll { $0.id == id }
        current.updatedAt = Date()
        project = current
    }

    func updateName(_ rawName: String) {
        guard var current = project else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        current.name = name
        current.updatedAt = Date()
        project = current
    }

    // MARK: - 保存

    func save() async {
        guard let current = project else { return }
        setBusy(String(localized: "patch.busy.saving"))
        defer { clearBusy() }
        do {
            try store.save(current, password: password)
            resultMessage = String(localized: "patch.result.saved")
        } catch {
            errorMessage = patchErrorMessage(for: error)
        }
    }

    // MARK: - 应用 / 回滚

    func apply() async {
        guard let current = project else { return }
        guard !current.rules.isEmpty else {
            errorMessage = String(localized: "patch.error.no_rules")
            return
        }
        setBusy(String(localized: "patch.busy.applying"))
        defer { clearBusy() }
        do {
            _ = try PatchTransaction.apply(
                project: current,
                appliedRoot: PatchTransaction.defaultAppliedRoot(projectName: current.name),
                journalRoot: PatchTransaction.defaultJournalRoot()
            )
            refreshAppliedStatus()
            resultMessage = String(localized: "patch.result.applied")
        } catch {
            errorMessage = patchErrorMessage(for: error)
        }
    }

    func restore() async {
        guard let current = project else { return }
        setBusy(String(localized: "patch.busy.restoring"))
        defer { clearBusy() }
        do {
            guard let receipt = PatchTransaction.latestReceipt(
                projectID: current.id,
                journalRoot: PatchTransaction.defaultJournalRoot()
            ) else {
                errorMessage = String(localized: "patch.error.not_applied")
                return
            }
            try PatchTransaction.restore(receipt: receipt)
            refreshAppliedStatus()
            resultMessage = String(localized: "patch.result.restored")
        } catch {
            errorMessage = patchErrorMessage(for: error)
        }
    }

    // MARK: - 错误与进行中

    func dismissError() {
        errorMessage = nil
    }

    func dismissResult() {
        resultMessage = nil
    }

    private func setBusy(_ message: String) {
        busyMessage = message
    }

    private func clearBusy() {
        busyMessage = nil
    }
}
