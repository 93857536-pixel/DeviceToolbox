import SwiftUI
import Foundation

/// 文件浏览器导航目标(根目录或已导入目录)。
struct FileBrowserRoute: Hashable {
    let url: URL
    let title: String
}

/// 文件工作台根页:三个沙盒根目录卡片 + 已导入入口 + 导入/新建文件夹工具按钮。
/// 沙盒逃逸激活后额外显示「系统 App 容器」入口(SystemContainerRoute → SystemContainerView)。
@MainActor
struct FilesTabView: View {
    @StateObject private var viewModel = WorkspaceViewModel()

    @State private var showImport = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.defaultSpacing) {
                rootsSection
                // 系统能力入口常显(与 3105 行为一致):进页面后由视图内探针显示真实
                // 可用状态与引导,避免入口被隐藏导致"看不到功能"。
                systemContainerSection
                wholeDeviceSection
                importedSection
            }
            .padding(Theme.defaultSpacing)
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "files.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: FileBrowserRoute.self) { route in
            FileBrowserView(route: route, viewModel: viewModel)
        }
        .navigationDestination(for: SystemContainerRoute.self) { _ in
            SystemContainerView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel(String(localized: "files.action.new_folder"))

                Button {
                    showImport = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel(String(localized: "files.action.import"))
            }
        }
        .sheet(isPresented: $showImport) {
            ImportView { urls in
                Task { await viewModel.importFiles(urls) }
            }
        }
        .background { newFolderAnchor }
        .background { errorAnchor }
        .task {
            viewModel.loadRoots()
        }
    }

    // MARK: - 根目录卡片

    private var rootsSection: some View {
        SectionCard(title: String(localized: "files.section.roots"), systemImage: "internaldrive") {
            VStack(spacing: 10) {
                ForEach(viewModel.roots) { root in
                    NavigationLink(value: FileBrowserRoute(url: root.url, title: root.name)) {
                        rootCard(root)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rootCard(_ root: WorkspaceViewModel.RootLocation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: root.systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(root.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(root.childCount) \(String(localized: "files.count.items"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassRowFill()
    }

    // MARK: - 系统容器(入口常显;视图内自检可用状态)

    private var systemContainerSection: some View {
        SectionCard(title: String(localized: "system.container.title"), systemImage: "externaldrive.fill.badge.checkmark") {
            NavigationLink(value: SystemContainerRoute()) {
                HStack(spacing: 12) {
                    Image(systemName: "apps.iphone")
                        .font(.title3)
                        .foregroundStyle(Theme.supported)
                        .frame(width: 40, height: 40)
                        .background(Theme.supported.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "system.container.entry"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(String(localized: "system.container.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .glassRowFill()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 整机文件(沙盒逃逸激活后可见)

    /// 整个设备文件系统浏览(URL "/");读取能力取决于逃逸后实际权限,
    /// root 属主且 0600 的文件可能无法打开(后续版本可加提权读取)。
    private var wholeDeviceSection: some View {
        SectionCard(title: String(localized: "files.section.device_root"), systemImage: "internaldrive.fill") {
            NavigationLink(value: FileBrowserRoute(url: URL(fileURLWithPath: "/"), title: String(localized: "files.section.device_root"))) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "files.section.device_root"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(String(localized: "files.section.device_root.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .glassRowFill()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 已导入

    private var importedSection: some View {
        SectionCard(title: String(localized: "files.section.imported"), systemImage: "tray.and.arrow.down") {
            NavigationLink(
                value: FileBrowserRoute(url: viewModel.importedURL, title: String(localized: "files.section.imported"))
            ) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "files.section.imported"))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(importedSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .glassRowFill()
            }
            .buttonStyle(.plain)
        }
    }

    private var importedSummary: String {
        if viewModel.importedEntries.isEmpty {
            return String(localized: "files.imported.empty")
        }
        return "\(viewModel.importedEntries.count) \(String(localized: "files.count.items"))"
    }

    // MARK: - 弹窗锚点(分散到不同节点,避免多个 alert/sheet 冲突)

    private var newFolderAnchor: some View {
        Color.clear
            .alert(String(localized: "files.action.new_folder"), isPresented: $showNewFolder) {
                TextField(String(localized: "files.prompt.folder_name"), text: $newFolderName)
                Button(String(localized: "common.close"), role: .cancel) {
                    newFolderName = ""
                }
                Button(String(localized: "files.action.create")) {
                    let name = newFolderName
                    newFolderName = ""
                    Task { await viewModel.createFolderInDocuments(named: name) }
                }
            } message: {
                Text(String(localized: "files.prompt.folder_message"))
            }
    }

    private var errorAnchor: some View {
        Color.clear
            .alert(String(localized: "files.error.title"), isPresented: errorBinding) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }
}
