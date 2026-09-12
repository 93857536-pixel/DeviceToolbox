import SwiftUI
import Foundation

/// 自绘沙盒目录树选择器:供复制/移动/压缩选择目标文件夹。
/// 根层固定展示三个沙盒根(Documents / Caches / tmp),进入后仅列出子目录。
struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onPick: (URL) -> Void

    @State private var pathStack: [URL] = []
    @State private var directories: [FileEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentURL: URL? { pathStack.last }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if currentURL == nil {
                    rootList
                } else if directories.isEmpty {
                    emptyState
                } else {
                    directoryList
                }
            }
            .navigationTitle(title)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "files.picker.confirm")) {
                        if let url = currentURL {
                            onPick(url)
                            dismiss()
                        }
                    }
                    .disabled(currentURL == nil)
                }
            }
        }
        .alert(String(localized: "files.error.title"), isPresented: errorBinding) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 根列表

    private var rootList: some View {
        List {
            Section {
                rootRow(name: String(localized: "files.root.documents"), icon: "doc.fill", url: SandboxRoots.documents,
                        available: isAvailable(SandboxRoots.documents))
                rootRow(name: String(localized: "files.root.caches"), icon: "shippingbox.fill", url: SandboxRoots.caches,
                        volatile: true, available: isAvailable(SandboxRoots.caches))
                rootRow(name: String(localized: "files.root.temporary"), icon: "clock.fill", url: SandboxRoots.temporary,
                        volatile: true, available: isAvailable(SandboxRoots.temporary))
            } footer: {
                Text(String(localized: "files.picker.hint"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func isAvailable(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func rootRow(name: String, icon: String, url: URL, volatile: Bool = false, available: Bool = true) -> some View {
        HStack {
            Button {
                enter(url)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        if volatile {
                            Text(String(localized: "files.picker.volatile"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: icon)
                }
            }
            .buttonStyle(.plain)
            .disabled(!available)
            .opacity(available ? 1 : 0.45)

            Spacer()

            Button(String(localized: "files.picker.confirm")) {
                onPick(url)
                dismiss()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.accent)
            .disabled(!available)
            .opacity(available ? 1 : 0.45)
        }
    }

    // MARK: - 目录列表

    private var directoryList: some View {
        List {
            Section {
                ForEach(directories, id: \.path) { dir in
                    Button {
                        enter(URL(fileURLWithPath: dir.path))
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
            } footer: {
                Text(String(localized: "files.picker.hint"))
            }
        }
        .listStyle(.insetGrouped)
        
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text(String(localized: "files.picker.empty"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 逻辑

    private func enter(_ url: URL) {
        pathStack.append(url)
        loadDirectories(at: url)
    }

    private func goBack() {
        pathStack.removeLast()
        if let url = currentURL {
            loadDirectories(at: url)
        }
    }

    private func loadDirectories(at url: URL) {
        isLoading = true
        defer { isLoading = false }
        do {
            directories = try WorkspaceService.listDirectory(at: url).filter(\.isDirectory)
        } catch {
            directories = []
            errorMessage = filesErrorMessage(for: error)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
