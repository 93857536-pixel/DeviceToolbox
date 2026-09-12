import Combine
import Foundation

/// 把底层错误转成用户可见文案:优先使用服务层 `LocalizedError` 自带的中英文案,否则用通用兜底。
/// 放在此文件顶层,供 WorkspaceViewModel 与 FolderPickerView 等复用(不依赖兄弟域类型细节)。
func filesErrorMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return String(localized: "files.error.generic")
}

/// 文件工作台共享状态:根目录卡片、当前目录路径栈、条目、多选集合,
/// 以及文件操作(新建/重命名/删除/复制/移动/压缩/导入)的执行与错误呈现。
/// 所有磁盘读写都经由域 A 的契约服务(WorkspaceService / ImportService / ZipArchiveService)。
@MainActor
final class WorkspaceViewModel: ObservableObject {

    // MARK: - 根目录

    /// 根位置卡片(Documents / Caches / tmp)。
    struct RootLocation: Identifiable {
        let name: String
        let url: URL
        let systemImage: String
        let childCount: Int
        var id: String { url.path }
    }

    @Published private(set) var roots: [RootLocation] = []
    /// 已导入目录(Documents/Imported)内的条目。
    @Published private(set) var importedEntries: [FileEntry] = []
    /// 已导入目录地址。
    var importedURL: URL {
        SandboxRoots.imported
    }

    // MARK: - 浏览状态

    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var currentPath: URL?
    @Published private(set) var pathStack: [URL] = []
    @Published private(set) var isLoading = false

    // MARK: - 多选

    @Published private(set) var isSelecting = false
    @Published private(set) var selection: Set<String> = []

    // MARK: - 错误与进行中

    @Published private(set) var errorMessage: String?
    @Published private(set) var busyMessage: String?

    var isBusy: Bool { busyMessage != nil }

    // MARK: - 根目录加载

    func loadRoots() {
        roots = [
            makeRoot(
                name: String(localized: "files.root.documents"),
                url: SandboxRoots.documents,
                systemImage: "doc.fill"
            ),
            makeRoot(
                name: String(localized: "files.root.caches"),
                url: SandboxRoots.caches,
                systemImage: "shippingbox.fill"
            ),
            makeRoot(
                name: String(localized: "files.root.temporary"),
                url: SandboxRoots.temporary,
                systemImage: "clock.fill"
            ),
        ]
        refreshImported()
    }

    private func makeRoot(name: String, url: URL, systemImage: String) -> RootLocation {
        let count = (try? WorkspaceService.listDirectory(at: url))?.count ?? 0
        return RootLocation(name: name, url: url, systemImage: systemImage, childCount: count)
    }

    func refreshImported() {
        do {
            importedEntries = try WorkspaceService.listDirectory(at: importedURL)
        } catch {
            importedEntries = []
        }
    }

    // MARK: - 导航

    /// 面包屑:祖先目录 + 当前目录。
    var breadcrumb: [URL] {
        var result = pathStack
        if let currentPath { result.append(currentPath) }
        return result
    }

    /// 从根页进入某个根目录(清空路径栈)。
    func openRoot(_ url: URL) async {
        pathStack = []
        await navigate(to: url)
    }

    /// 进入子目录。
    func drillInto(_ entry: FileEntry) async {
        if let currentPath { pathStack.append(currentPath) }
        await navigate(to: entry.url)
    }

    /// 返回上级目录。
    func goBack() async {
        guard let parent = pathStack.popLast() else { return }
        await navigate(to: parent)
    }

    private func navigate(to directory: URL) async {
        isLoading = true
        defer { isLoading = false }
        do {
            currentPath = directory
            entries = try WorkspaceService.listDirectory(at: directory)
            selection.removeAll()
        } catch {
            showError(error)
        }
    }

    /// 重新加载当前目录。
    func refresh() async {
        if let currentPath {
            await navigate(to: currentPath)
        } else {
            loadRoots()
        }
    }

    // MARK: - 多选

    func enterSelectionMode() {
        isSelecting = true
        selection.removeAll()
    }

    func exitSelectionMode() {
        isSelecting = false
        selection.removeAll()
    }

    func toggleSelection(_ entry: FileEntry) {
        if selection.contains(entry.path) {
            selection.remove(entry.path)
        } else {
            selection.insert(entry.path)
        }
    }

    func selectAll() {
        selection = Set(entries.map(\.path))
    }

    var selectedEntries: [FileEntry] {
        entries.filter { selection.contains($0.path) }
    }

    // MARK: - 文件操作

    /// 在当前目录新建文件夹。
    func createFolder(named name: String) async {
        guard let directory = currentPath else { return }
        do {
            _ = try WorkspaceService.makeDirectory(named: name, in: directory)
            await navigate(to: directory)
        } catch {
            showError(error)
        }
    }

    /// 在 Documents 根目录新建文件夹(根页「新建文件夹」按钮)。
    func createFolderInDocuments(named name: String) async {
        do {
            _ = try WorkspaceService.makeDirectory(named: name, in: SandboxRoots.documents)
            loadRoots()
        } catch {
            showError(error)
        }
    }

    /// 重命名条目。
    func rename(_ entry: FileEntry, to newName: String) async {
        guard let directory = currentPath else { return }
        do {
            _ = try WorkspaceService.renameItem(at: entry.url, to: newName)
            await navigate(to: directory)
        } catch {
            showError(error)
        }
    }

    /// 删除若干条目。
    func delete(_ targets: [FileEntry]) async {
        guard let directory = currentPath else { return }
        do {
            for entry in targets {
                try WorkspaceService.deleteItem(at: entry.url)
            }
            selection.removeAll()
            await navigate(to: directory)
        } catch {
            showError(error)
        }
    }

    /// 复制若干条目到目标目录。
    func copy(_ targets: [FileEntry], to directory: URL) async {
        await transfer(targets, to: directory, mode: .copy)
    }

    /// 移动若干条目到目标目录。
    func move(_ targets: [FileEntry], to directory: URL) async {
        await transfer(targets, to: directory, mode: .move)
    }

    private func transfer(_ targets: [FileEntry], to directory: URL, mode: FileTransferMode) async {
        guard !targets.isEmpty else { return }
        setBusy(mode == .move ? String(localized: "files.busy.moving") : String(localized: "files.busy.copying"))
        defer { clearBusy() }
        do {
            let urls = targets.map(\.url)
            let result = try WorkspaceService.transferItems(
                urls,
                into: directory,
                mode: mode,
                conflictPolicy: .keepBoth
            )
            if !result.failures.isEmpty {
                errorMessage = String(localized: "files.error.partial")
            }
            selection.removeAll()
            isSelecting = false
            if let currentPath { await navigate(to: currentPath) }
        } catch {
            showError(error)
        }
    }

    /// 将若干条目压缩为 zip,写入目标目录。
    func archive(_ targets: [FileEntry], to directory: URL) async {
        guard !targets.isEmpty else { return }
        setBusy(String(localized: "files.busy.archiving"))
        defer { clearBusy() }
        do {
            let urls = targets.map(\.url)
            let baseName = targets.count == 1
                ? targets[0].name
                : String(localized: "files.archive.default_name")
            let destination = makeUniqueArchiveURL(in: directory, baseName: baseName)
            _ = try ZipArchiveService.write(files: urls, to: destination)
            selection.removeAll()
            isSelecting = false
        } catch {
            showError(error)
        }
    }

    private func makeUniqueArchiveURL(in directory: URL, baseName: String) -> URL {
        let stem = baseName.hasSuffix(".zip") ? String(baseName.dropLast(4)) : baseName
        var url = directory.appendingPathComponent(stem + ".zip")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem)-\(counter).zip")
            counter += 1
        }
        return url
    }

    /// 导入文件到已导入目录。
    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        setBusy(String(localized: "files.busy.importing"))
        defer { clearBusy() }
        do {
            _ = try ImportService.importIntoImportedFiles(urls)
            refreshImported()
        } catch {
            showError(error)
        }
    }

    // MARK: - 错误与进行中

    private func setBusy(_ message: String) {
        busyMessage = message
    }

    private func clearBusy() {
        busyMessage = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    private func showError(_ error: Error) {
        errorMessage = filesErrorMessage(for: error)
    }
}
