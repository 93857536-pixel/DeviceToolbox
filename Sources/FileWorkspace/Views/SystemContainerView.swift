import SwiftUI
import Foundation

/// 系统容器入口路由(仅沙盒逃逸激活时在文件页出现)。
struct SystemContainerRoute: Hashable {}

/// 系统 App 容器列表:沙盒逃逸激活后,列出全部系统已装 App 及其数据容器,
/// 点按复用 FileBrowserView(route:) 浏览对应目录(纯文件系统,无 MCM token 依赖)。
struct SystemContainerView: View {
    @State private var apps: [SystemContainerService.SystemAppEntry] = []
    @State private var isLoading = true
    @State private var rootAccessible = true
    @State private var exportingIDs: Set<String> = []
    @State private var exportMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView(String(localized: "system.container.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !rootAccessible {
                messageState(
                    icon: "lock.shield",
                    title: String(localized: "system.container.notactive"),
                    hint: String(localized: "system.container.notactive.hint")
                )
            } else if apps.isEmpty {
                messageState(
                    icon: "apps.iphone",
                    title: String(localized: "system.container.empty"),
                    hint: nil
                )
            } else {
                appList
            }
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "system.container.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var appList: some View {
        List {
            Section {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        NavigationLink(value: FileBrowserRoute(url: app.dataContainerURL ?? app.bundleURL, title: app.name)) {
                            appRow(app)
                        }
                        exportButton(app)
                    }
                }
            } footer: {
                Text(String(localized: "system.container.footer"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .alert(String(localized: "system.container.export.result.title"), isPresented: exportBinding) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private func appRow(_ app: SystemContainerService.SystemAppEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(app.dataContainerURL != nil
                 ? String(localized: "system.container.has.data")
                 : String(localized: "system.container.bundle.only"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func messageState(icon: String, title: String, hint: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func load() async {
        ExploitController.elevateToRootIfEscaped()
        rootAccessible = SystemContainerService.isSystemRootAccessible()
        apps = await SystemContainerService.listInstalledApps()
        isLoading = false
    }

    // MARK: - 一键导出

    @ViewBuilder
    private func exportButton(_ app: SystemContainerService.SystemAppEntry) -> some View {
        if exportingIDs.contains(app.id) {
            ProgressView()
                .padding(.horizontal, 4)
        } else {
            Button {
                export(app)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "system.container.export"))
        }
    }

    private func export(_ app: SystemContainerService.SystemAppEntry) {
        guard !exportingIDs.contains(app.id) else { return }
        exportingIDs.insert(app.id)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.exportSync(app)
            }.value
            exportingIDs.remove(app.id)
            switch result {
            case .success(let name):
                exportMessage = String(localized: "system.container.export.done \(name)")
            case .failure(let error):
                exportMessage = String(localized: "system.container.export.failed") + " · " + error.message
            }
        }
    }

    /// 后台同步导出:把 dataContainerURL(或 bundleURL)整树 zip 到 Documents/Imported。
    private nonisolated static func exportSync(_ app: SystemContainerService.SystemAppEntry) -> Result<String, OperationFailure> {
        do {
            let source = app.dataContainerURL ?? app.bundleURL
            let size = Self.directorySize(at: source)
            guard size >= 0, size <= Self.maxExportBytes else {
                return .failure(OperationFailure(message: String(localized: "system.container.export.too.large")))
            }
            let imported = try SandboxRoots.ensureImportedDirectory()
            let fileName = "\(Self.sanitize(app.name))-\(app.bundleID).zip"
            let dest = imported.appendingPathComponent(fileName)
            _ = try ZipArchiveService.write(files: [source], to: dest)
            return .success(fileName)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failure(OperationFailure(message: msg))
        }
    }

    private nonisolated static let maxExportBytes: Int64 = 512 * 1_024 * 1_024

    private nonisolated static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<> ")
        let cleaned = name.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "_")
        return cleaned.isEmpty ? "app" : cleaned
    }

    private nonisolated static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return -1 }
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else { return -1 }
        var count = 0
        for case let child as URL in enumerator {
            guard count < 200_000 else { break }
            count += 1
            guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
            if total > Self.maxExportBytes { break }
        }
        return total
    }

    private var exportBinding: Binding<Bool> {
        Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )
    }
}
