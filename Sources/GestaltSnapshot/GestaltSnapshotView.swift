import SwiftUI
import UniformTypeIdentifiers

/// 生成时间戳文件名片段(yyyyMMdd-HHmmss)。自由函数,主线程/后台均可调用。
func gestaltSnapshotTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: Date())
}

/// Gestalt 快照管理:查看缓存/备份状态,导出到文件工作台,导入并恢复。
/// 模拟器全部禁用;恢复写回需逃逸激活(elevate 到 root)。
@MainActor
struct GestaltSnapshotView: View {
    @State private var cacheExists = false
    @State private var cacheSize: Int64 = 0
    @State private var backupExists = false
    @State private var backupSize: Int64 = 0
    @State private var backupDate: Date?
    @State private var isWorking = false
    @State private var noticeMessage: String?
    @State private var showImporter = false

    private var isSimulator: Bool { DeviceProbe.isSimulator }
    private var escapeActive: Bool { ExploitController.isSandboxActive() }

    var body: some View {
        List {
            statusSection
            exportSection
            restoreSection
            if isSimulator {
                simulatorNote
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "gestalt.title"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.propertyList, .data]) { result in
            switch result {
            case .success(let url):
                restore(from: url)
            case .failure:
                noticeMessage = String(localized: "gestalt.restore.pick.failed")
            }
        }
        .alert(String(localized: "gestalt.result.title"), isPresented: noticeBinding) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(noticeMessage ?? "")
        }
        .onAppear { refresh() }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            LabeledContent(String(localized: "gestalt.cache.status")) {
                Text(cacheExists
                     ? "\(String(localized: "gestalt.exists")) · \(CleanerService.formatBytes(cacheSize))"
                     : String(localized: "gestalt.not.exists"))
                    .foregroundStyle(cacheExists ? Theme.supported : Theme.unknown)
            }
            LabeledContent(String(localized: "gestalt.backup.status")) {
                if backupExists {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(CleanerService.formatBytes(backupSize))
                        if let backupDate {
                            Text(backupDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(String(localized: "gestalt.not.exists"))
                        .foregroundStyle(Theme.unknown)
                }
            }
        } header: {
            Text(String(localized: "gestalt.section.status"))
        }
    }

    // MARK: - 导出

    private var exportSection: some View {
        Section {
            Button {
                exportCurrentCache()
            } label: {
                Label(String(localized: "gestalt.export.cache"), systemImage: "square.and.arrow.down")
            }
            .disabled(isWorking || isSimulator || !cacheExists)

            Button {
                exportBackup()
            } label: {
                Label(String(localized: "gestalt.export.backup"), systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(isWorking || isSimulator || !backupExists)

            if backupExists && !isSimulator {
                ShareLink(item: MobileGestaltService.backupFileURL) {
                    Label(String(localized: "gestalt.share"), systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text(String(localized: "gestalt.section.export"))
        } footer: {
            Text(String(localized: "gestalt.export.footer"))
        }
    }

    // MARK: - 恢复

    private var restoreSection: some View {
        Section {
            if isWorking {
                HStack {
                    ProgressView()
                    Text(String(localized: "gestalt.working"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    showImporter = true
                } label: {
                    Label(String(localized: "gestalt.restore"), systemImage: "arrow.down.doc")
                }
                .disabled(isSimulator || !escapeActive)
            }
        } header: {
            Text(String(localized: "gestalt.section.restore"))
        } footer: {
            Text(restoreFooterText)
        }
    }

    private var restoreFooterText: String {
        if isSimulator {
            return String(localized: "gestalt.simulator.note")
        }
        if !escapeActive {
            return String(localized: "gestalt.restore.need.escape")
        }
        return String(localized: "gestalt.restore.footer")
    }

    private var simulatorNote: some View {
        Section {
            Label(String(localized: "gestalt.simulator.note"), systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(Theme.unsupported)
        }
    }

    // MARK: - 动作

    private func refresh() {
        cacheSize = Self.fileSize(atPath: MobileGestaltService.gestaltCachePath)
        cacheExists = cacheSize >= 0
        backupExists = MobileGestaltService.hasBackup()
        if backupExists {
            backupSize = Self.fileSize(atPath: MobileGestaltService.backupFileURL.path)
            backupDate = Self.modificationDate(atPath: MobileGestaltService.backupFileURL.path)
        }
    }

    private func exportCurrentCache() {
        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, OperationFailure> in
                do {
                    guard let data = MobileGestaltService.readGestaltData() else {
                        return .failure(OperationFailure(message: String(localized: "gestalt.export.cache.empty")))
                    }
                    let imported = try SandboxRoots.ensureImportedDirectory()
                    let name = "gestalt-\(gestaltSnapshotTimestamp()).plist"
                    try data.write(to: imported.appendingPathComponent(name), options: .atomic)
                    return .success(name)
                } catch {
                    return .failure(OperationFailure(message: error.localizedDescription))
                }
            }.value
            isWorking = false
            switch result {
            case .success(let name):
                noticeMessage = String(localized: "gestalt.export.done \(name)")
            case .failure(let error):
                noticeMessage = String(localized: "gestalt.export.failed") + " · " + error.message
            }
        }
    }

    private func exportBackup() {
        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, OperationFailure> in
                do {
                    guard let data = MobileGestaltService.readBackupData() else {
                        return .failure(OperationFailure(message: String(localized: "gestalt.export.backup.empty")))
                    }
                    let imported = try SandboxRoots.ensureImportedDirectory()
                    let name = "gestalt-backup-\(gestaltSnapshotTimestamp()).plist"
                    try data.write(to: imported.appendingPathComponent(name), options: .atomic)
                    return .success(name)
                } catch {
                    return .failure(OperationFailure(message: error.localizedDescription))
                }
            }.value
            isWorking = false
            switch result {
            case .success(let name):
                noticeMessage = String(localized: "gestalt.export.done \(name)")
            case .failure(let error):
                noticeMessage = String(localized: "gestalt.export.failed") + " · " + error.message
            }
        }
    }

    private func restore(from url: URL) {
        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, OperationFailure> in
                do {
                    // 安全作用域读取(文件导入器返回的 URL 可能需 startAccessingSecurityScopedResource)
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                    guard let data = try? Data(contentsOf: url),
                          (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil
                    else {
                        return .failure(OperationFailure(message: String(localized: "gestalt.restore.invalid")))
                    }
                    guard ExploitController.isSandboxActive() else {
                        return .failure(OperationFailure(message: String(localized: "gestalt.restore.need.escape")))
                    }
                    _ = ExploitController.elevateToRootIfEscaped()
                    // 写回前备份当前(幂等)
                    if let current = MobileGestaltService.readGestaltData() {
                        _ = try? MobileGestaltService.backupGestalt(data: current)
                    }
                    let original = MobileGestaltService.readGestaltData()
                    try MobileGestaltService.writeFileAtomically(data, to: MobileGestaltService.gestaltCachePath, original: original)
                    return .success(())
                } catch {
                    return .failure(OperationFailure(message: error.localizedDescription))
                }
            }.value
            isWorking = false
            switch result {
            case .success:
                noticeMessage = String(localized: "gestalt.restore.done")
                refresh()
            case .failure(let error):
                noticeMessage = String(localized: "gestalt.restore.failed") + " · " + error.message
            }
        }
    }

    // MARK: - 文件元信息(自由辅助)

    private static func fileSize(atPath path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return -1 }
        return size.int64Value
    }

    private static func modificationDate(atPath path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { noticeMessage != nil },
            set: { if !$0 { noticeMessage = nil } }
        )
    }
}
