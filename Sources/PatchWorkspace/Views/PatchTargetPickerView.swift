import SwiftUI
import Foundation

/// 自绘沙盒目录树选择器:用于补丁规则的目标路径选择。
/// 根固定为应用的沙盒根 `Documents/Patches/Applied/<projectName>/`,不允许向上越出;
/// 目录可进入,文件可点选,也可「选择此目录」把当前目录作为目标。
/// 相对路径由调用方(规则编辑 sheet)相对应用根换算。
struct PatchTargetPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let projectName: String
    let onPick: (URL) -> Void

    @State private var pathStack: [URL] = []
    @State private var directories: [FileEntry] = []
    @State private var files: [FileEntry] = []
    @State private var selectedFile: FileEntry?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var root: URL {
        PatchTransaction.defaultAppliedRoot(projectName: projectName)
    }

    private var currentURL: URL {
        pathStack.last ?? root
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(String(localized: "patch.picker.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if directories.isEmpty && files.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
            .navigationTitle(String(localized: "patch.picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !pathStack.isEmpty {
                        Button {
                            goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(String(localized: "files.action.back"))
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "patch.picker.confirm")) {
                        onPick(selectedFile?.url ?? currentURL)
                        dismiss()
                    }
                }
            }
            .task {
                await ensureRootAndLoad()
            }
        }
        .alert(String(localized: "patch.error.title"), isPresented: errorBinding) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 列表

    private var entryList: some View {
        List {
            Section {
                ForEach(directories, id: \.path) { dir in
                    Button {
                        enter(dir.url)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.accent)
                            Text(dir.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                ForEach(files, id: \.path) { file in
                    Button {
                        selectedFile = file
                    } label: {
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(file.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedFile?.path == file.path {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            } footer: {
                Text(String(localized: "patch.picker.hint"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text(String(localized: "patch.picker.empty"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "patch.picker.empty_hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 逻辑

    private func ensureRootAndLoad() async {
        do {
            if !FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
        } catch {
            // 创建失败不致命,继续尝试列出。
        }
        loadChildren(at: root)
    }

    private func enter(_ url: URL) {
        pathStack.append(url)
        selectedFile = nil
        loadChildren(at: url)
    }

    private func goBack() {
        pathStack.removeLast()
        selectedFile = nil
        loadChildren(at: currentURL)
    }

    private func loadChildren(at url: URL) {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try WorkspaceService.listDirectory(at: url)
            directories = all.filter(\.isDirectory)
            files = all.filter { !$0.isDirectory }
        } catch {
            directories = []
            files = []
            errorMessage = filesErrorMessage(for: error)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
