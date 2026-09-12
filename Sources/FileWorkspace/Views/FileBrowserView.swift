import SwiftUI
import Foundation
import UIKit
import QuickLook

/// 目录浏览器:面包屑返回、文件行(图标/名称/大小/日期)、多选模式,
/// 支持复制/移动/压缩 zip/删除/重命名/新建文件夹,文件点按 QuickLook 预览。
struct FileBrowserView: View {
    let route: FileBrowserRoute
    @ObservedObject var viewModel: WorkspaceViewModel

    // MARK: - 待执行动作(复制/移动/压缩,目标目录由 FolderPickerView 提供)

    private enum PendingAction {
        case copy
        case move
        case archive
    }

    // MARK: - 文本输入弹窗(重命名/新建文件夹,合并为单一 alert)

    private enum TextPrompt: Identifiable {
        case rename(FileEntry)
        case newFolder

        var id: Int {
            switch self {
            case .rename: return 0
            case .newFolder: return 1
            }
        }
    }

    @State private var pendingTargets: [FileEntry] = []
    @State private var pendingAction: PendingAction?
    @State private var showFolderPicker = false

    @State private var textPrompt: TextPrompt?
    @State private var textInput = ""

    @State private var deleteTargets: [FileEntry] = []
    @State private var previewItem: QuickLookItem?

    var body: some View {
        content
            .background(Theme.pageBackdrop)
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { selectionBar }
            .overlay { busyOverlay }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(title: folderPickerTitle) { url in
                    commitPendingAction(to: url)
                }
            }
            .background { previewAnchor }
            .background { textPromptAnchor }
            .background { deleteAnchor }
            .background { errorAnchor }
            .task {
                // 逃逸激活时自动提权 root:整机/系统容器路径的 root 专属文件也可读。
                ExploitController.elevateToRootIfEscaped()
                await viewModel.openRoot(route.url)
            }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.entries.isEmpty {
            ProgressView(String(localized: "files.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.entries.isEmpty {
            emptyState
        } else {
            entryList
        }
    }

    private var entryList: some View {
        List {
            ForEach(viewModel.entries, id: \.path) { entry in
                entryRow(entry)
                    .contextMenu { contextMenu(for: entry) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text(String(localized: "files.empty.folder"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "files.empty.folder_hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 标题

    private var currentTitle: String {
        guard let current = viewModel.currentPath else { return route.title }
        if current.path == route.url.path {
            return route.title
        }
        return current.lastPathComponent
    }

    // MARK: - 行

    @ViewBuilder
    private func entryRow(_ entry: FileEntry) -> some View {
        if viewModel.isSelecting {
            Button {
                viewModel.toggleSelection(entry)
            } label: {
                FileRowContent(entry: entry, isSelected: viewModel.selection.contains(entry.path))
            }
            .buttonStyle(.plain)
        } else if entry.isDirectory {
            Button {
                Task { await viewModel.drillInto(entry) }
            } label: {
                FileRowContent(entry: entry, isSelected: nil)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                previewItem = QuickLookItem(url: entry.url)
            } label: {
                FileRowContent(entry: entry, isSelected: nil)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 上下文菜单

    @ViewBuilder
    private func contextMenu(for entry: FileEntry) -> some View {
        Button {
            prepareAction(.copy, targets: [entry])
        } label: {
            Label(String(localized: "files.action.copy"), systemImage: "doc.on.doc")
        }
        Button {
            prepareAction(.move, targets: [entry])
        } label: {
            Label(String(localized: "files.action.move"), systemImage: "folder")
        }
        Button {
            prepareAction(.archive, targets: [entry])
        } label: {
            Label(String(localized: "files.action.archive"), systemImage: "archivebox")
        }
        Divider()
        Button {
            textPrompt = .rename(entry)
            textInput = entry.name
        } label: {
            Label(String(localized: "files.action.rename"), systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            deleteTargets = [entry]
        } label: {
            Label(String(localized: "files.action.delete"), systemImage: "trash")
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !viewModel.pathStack.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.goBack() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(String(localized: "files.action.back"))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if viewModel.isSelecting {
                    viewModel.exitSelectionMode()
                } else {
                    viewModel.enterSelectionMode()
                }
            } label: {
                Text(viewModel.isSelecting
                     ? String(localized: "common.close")
                     : String(localized: "files.action.select"))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    textPrompt = .newFolder
                    textInput = ""
                } label: {
                    Label(String(localized: "files.action.new_folder"), systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "files.action.new_folder"))
        }
    }

    // MARK: - 多选操作栏

    @ViewBuilder
    private var selectionBar: some View {
        if viewModel.isSelecting {
            HStack(spacing: 8) {
                actionButton(String(localized: "files.action.copy"), "doc.on.doc") {
                    prepareAction(.copy, targets: viewModel.selectedEntries)
                }
                actionButton(String(localized: "files.action.move"), "folder") {
                    prepareAction(.move, targets: viewModel.selectedEntries)
                }
                actionButton(String(localized: "files.action.archive"), "archivebox") {
                    prepareAction(.archive, targets: viewModel.selectedEntries)
                }
                actionButton(String(localized: "files.action.delete"), "trash", destructive: true) {
                    deleteTargets = viewModel.selectedEntries
                }
            }
            .padding(Theme.defaultSpacing)
            .background(.regularMaterial)
        }
    }

    private func actionButton(
        _ title: String,
        _ systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(destructive ? Color.red : Theme.accent)
        }
        .disabled(viewModel.selectedEntries.isEmpty)
    }

    // MARK: - 动作流转

    private func prepareAction(_ action: PendingAction, targets: [FileEntry]) {
        guard !targets.isEmpty else { return }
        pendingTargets = targets
        pendingAction = action
        showFolderPicker = true
    }

    private func commitPendingAction(to directory: URL) {
        guard let action = pendingAction else { return }
        let targets = pendingTargets
        pendingTargets = []
        pendingAction = nil
        showFolderPicker = false
        switch action {
        case .copy:
            Task { await viewModel.copy(targets, to: directory) }
        case .move:
            Task { await viewModel.move(targets, to: directory) }
        case .archive:
            Task { await viewModel.archive(targets, to: directory) }
        }
    }

    private var folderPickerTitle: String {
        switch pendingAction {
        case .copy: return String(localized: "files.picker.copy_title")
        case .move: return String(localized: "files.picker.move_title")
        case .archive: return String(localized: "files.picker.archive_title")
        case nil: return String(localized: "files.picker.title")
        }
    }

    // MARK: - 文本弹窗

    private var textPromptTitle: String {
        switch textPrompt {
        case .newFolder, nil: return String(localized: "files.action.new_folder")
        case .rename: return String(localized: "files.action.rename")
        }
    }

    private var textPromptPlaceholder: String {
        switch textPrompt {
        case .newFolder, nil: return String(localized: "files.prompt.folder_name")
        case .rename: return String(localized: "files.prompt.name")
        }
    }

    private var textPromptConfirmTitle: String {
        switch textPrompt {
        case .newFolder, nil: return String(localized: "files.action.create")
        case .rename: return String(localized: "files.action.rename")
        }
    }

    private var textPromptMessage: String {
        switch textPrompt {
        case .newFolder, nil: return String(localized: "files.prompt.folder_message")
        case .rename: return String(localized: "files.prompt.name_message")
        }
    }

    private func commitTextPrompt() {
        guard let prompt = textPrompt else { return }
        let value = textInput
        textPrompt = nil
        switch prompt {
        case .rename(let entry):
            Task { await viewModel.rename(entry, to: value) }
        case .newFolder:
            Task { await viewModel.createFolder(named: value) }
        }
    }

    private var textPromptBinding: Binding<Bool> {
        Binding(get: { textPrompt != nil }, set: { if !$0 { textPrompt = nil } })
    }

    // MARK: - 删除确认

    private var deleteBinding: Binding<Bool> {
        Binding(get: { !deleteTargets.isEmpty }, set: { if !$0 { deleteTargets = [] } })
    }

    private var deleteMessage: String {
        if deleteTargets.count == 1, let name = deleteTargets.first?.name {
            return String(localized: "files.confirm.delete_one") + "「" + name + "」"
        }
        return String(localized: "files.confirm.delete_many")
    }

    // MARK: - 错误弹窗

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    // MARK: - 进行中遮罩

    @ViewBuilder
    private var busyOverlay: some View {
        if let busy = viewModel.busyMessage {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                ProgressView(busy)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - 弹窗锚点(分散到不同节点,避免多个 alert/sheet 冲突)

    private var previewAnchor: some View {
        Color.clear
            .fullScreenCover(item: $previewItem) { item in
                NavigationStack {
                    QuickLookPreview(url: item.url)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: "common.close")) {
                                    previewItem = nil
                                }
                            }
                        }
                }
            }
    }

    private var textPromptAnchor: some View {
        Color.clear
            .alert(textPromptTitle, isPresented: textPromptBinding) {
                TextField(textPromptPlaceholder, text: $textInput)
                Button(String(localized: "common.close"), role: .cancel) {
                    textPrompt = nil
                }
                Button(textPromptConfirmTitle) {
                    commitTextPrompt()
                }
            } message: {
                Text(textPromptMessage)
            }
    }

    private var deleteAnchor: some View {
        Color.clear
            .confirmationDialog(
                String(localized: "files.action.delete"),
                isPresented: deleteBinding,
                titleVisibility: .visible
            ) {
                Button(String(localized: "files.action.delete"), role: .destructive) {
                    let targets = deleteTargets
                    deleteTargets = []
                    Task { await viewModel.delete(targets) }
                }
                Button(String(localized: "common.close"), role: .cancel) {
                    deleteTargets = []
                }
            } message: {
                Text(deleteMessage)
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
}

// MARK: - 文件行内容

private struct FileRowContent: View {
    let entry: FileEntry
    let isSelected: Bool?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !entry.isDirectory {
                        Text(formattedSize)
                    }
                    Text(formattedDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Color(.systemGray3))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        if entry.isDirectory { return "folder.fill" }
        switch ext {
        case "zip": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "mp3", "m4a", "wav": return "music.note"
        case "mp4", "mov": return "film"
        case "txt", "md", "json", "xml", "plist": return "doc.text"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if entry.isDirectory { return Theme.accent }
        switch ext {
        case "zip": return Theme.accent
        case "jpg", "jpeg", "png", "gif", "heic": return .green
        case "mp3", "m4a", "wav", "mp4", "mov": return .blue
        default: return Color(.systemGray)
        }
    }

    private var ext: String {
        (entry.name as NSString).pathExtension.lowercased()
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    private var formattedDate: String {
        entry.modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - QuickLook 预览(公开 API 包装)

private struct QuickLookItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
