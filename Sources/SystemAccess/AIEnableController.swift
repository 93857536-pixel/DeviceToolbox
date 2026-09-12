import Foundation
import Combine

/// Apple Intelligence 强开执行控制器(仿 ExploitController 风格)。
///
/// 分步:校验通道 → 备份 gestalt → 改写 CacheExtra(AI 键/地区键/机型伪装)→ 同 inode 原子写回
/// → 写 eligibility(GREYMATTER/CALCIUM,需 root)→ 汇报结果(重启 + 联网等待指引)。
///
/// 通道:
/// - 内核逃逸激活(ExploitController):gestalt 以 mobile 可写;eligibility 需 root 提权
///   (sandbox_elevate_to_root)。覆盖 iOS 17.0–26.0.x。
/// - bad_query(27.0b1–4,mond 同源):仅换取 mobilegestaltcache 容器写权限,资格表不可写 → 降级提示。
@MainActor
final class AIEnableController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case running
        case active
        case failed(String)
    }

    enum Step: String {
        case preflight, backup, write, eligibility, done
    }

    static let shared = AIEnableController()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var step: Step = .preflight
    /// 结果说明(成功指引 / 失败原因已含在 phase)。
    @Published private(set) var outcomeNote: String?
    /// 资格表是否被跳过(27.0b1–4 bad_query 通道无 root)。
    @Published private(set) var eligibilitySkipped = false

    private static let backupKey = "aienable.backupExists"

    private init() {
        eligibilitySkipped = false
        // 备份存在性持久化(跨启动可恢复)
        outcomeNote = nil
    }

    var isRunning: Bool { phase == .running }
    var hasBackup: Bool { MobileGestaltService.hasBackup() }

    // MARK: - 触发

    /// verdict 需已 isActionable。
    func run(verdict: AIEnablePolicy.Verdict) {
        guard !isRunning else { return }
        resetState()
        phase = .running
        step = .preflight
        Task {
            await execute(verdict: verdict)
        }
    }

    // MARK: - 复位 / 恢复

    func reset() {
        guard !isRunning else { return }
        resetState()
    }

    /// 用 Application Support 里的备份恢复原始 gestalt(需对应写入通道仍可用)。
    func restoreOriginal() async {
        guard !isRunning, hasBackup else { return }
        phase = .running
        step = .write
        let ok = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try MobileGestaltService.restoreGestaltFromBackup()
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        phase = .idle
        switch ok {
        case .success:
            outcomeNote = String(localized: "aienable.restore.done")
        case .failure(let error):
            let msg = (error as? AIEnableError)?.errorDescription ?? error.localizedDescription
            outcomeNote = String(localized: "aienable.restore.failed") + " · " + msg
        }
    }

    // MARK: - 执行

    private func execute(verdict: AIEnablePolicy.Verdict) async {
        step = .preflight

        // 1. 通道校验
        let escapeActive = ExploitController.isSandboxActive()
        var badQueryHandle: Int64?

        if verdict.requiresEscape {
            guard escapeActive else {
                fail(.failed(String(localized: "aienable.escape.missing")))
                return
            }
        } else {
            // 27.0b1–4 bad_query 通道
            step = .preflight
            let granted = await Task.detached(priority: .userInitiated) { () -> Int64? in
                MobileGestaltService.badQueryGrantGestalt()
            }.value
            guard let handle = granted else {
                fail(.failed(String(localized: "aienable.escape.missing")))
                return
            }
            badQueryHandle = handle
        }

        // 2. root 提权(内核通道;仅资格表需要)
        var haveRoot = false
        if escapeActive {
            haveRoot = MobileGestaltService.isRoot
            if !haveRoot {
                let elevated = await Task.detached(priority: .userInitiated) { () -> Bool in
                    guard sandbox_access_is_active() == 1 else { return false }
                    _ = sandbox_elevate_to_root(proc_self())
                    return MobileGestaltService.isRoot
                }.value
                haveRoot = elevated
            }
        }

        // 3. 备份 + 读取原始
        step = .backup
        let prep = await Task.detached(priority: .userInitiated) { () -> Result<Data, AIEnableError> in
            guard let original = MobileGestaltService.readGestaltData() else {
                return .failure(.gestaltParseFailed)
            }
            do {
                _ = try MobileGestaltService.backupGestalt(data: original)
                return .success(original)
            } catch {
                return .failure(.gestaltParseFailed)
            }
        }.value
        guard case .success(let original) = prep else {
            fail(.failed(String(localized: "aienable.fail.read")))
            cleanup(handle: badQueryHandle)
            return
        }

        // 4. 改写 gestalt + 原子写
        step = .write
        let writeResult = await Task.detached(priority: .userInitiated) { () -> Result<Bool, AIEnableError> in
            do {
                let patched = try MobileGestaltService.patchedGestaltData(original: original, target: verdict.target)
                if patched.changed {
                    try MobileGestaltService.writeFileAtomically(patched.data,
                                                                 to: MobileGestaltService.gestaltCachePath,
                                                                 original: original)
                }
                return .success(patched.changed)
            } catch let e as AIEnableError {
                return .failure(e)
            } catch {
                return .failure(.atomicWriteFailed(path: MobileGestaltService.gestaltCachePath))
            }
        }.value

        guard case .success = writeResult else {
            if case .failure(let e) = writeResult {
                fail(.failed(e.errorDescription ?? String(localized: "aienable.fail.write")))
            }
            cleanup(handle: badQueryHandle)
            return
        }

        // 5. eligibility(仅 root 通道)
        step = .eligibility
        var skipped = false
        if haveRoot {
            let elig = await Task.detached(priority: .userInitiated) { () -> Result<Void, AIEnableError> in
                do {
                    let data = try MobileGestaltService.makeEligibilityData()
                    try MobileGestaltService.writeEligibilityFile(data: data)
                    return .success(())
                } catch let e as AIEnableError {
                    return .failure(e)
                } catch {
                    return .failure(.atomicWriteFailed(path: MobileGestaltService.eligibilityPath))
                }
            }.value
            if case .failure = elig {
                skipped = true
            }
        } else {
            skipped = true
        }

        cleanup(handle: badQueryHandle)
        eligibilitySkipped = skipped
        step = .done

        switch verdict.target {
        case .hardwareSpoof:
            outcomeNote = String(localized: skipped ? "aienable.result.hardware.partial" : "aienable.result.hardware")
        case .regionUnlock:
            outcomeNote = String(localized: skipped ? "aienable.result.region.partial" : "aienable.result.region")
        default:
            outcomeNote = ""
        }
        phase = .active
    }

    private func cleanup(handle: Int64?) {
        guard let handle else { return }
        Task.detached(priority: .utility) {
            MobileGestaltService.badQueryRelease(handle)
        }
    }

    private func fail(_ phase: Phase) {
        self.phase = phase
        self.step = .preflight
    }

    private func resetState() {
        phase = .idle
        step = .preflight
        outcomeNote = nil
        eligibilitySkipped = false
    }
}
