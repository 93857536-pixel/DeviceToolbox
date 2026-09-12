import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// 补丁编辑器导航目标。
struct PatchEditorRoute: Hashable {
    let projectID: UUID
}

/// 补丁工作台根页:项目库列表(名称/作者/私密锁/更新时间/已应用徽标)+ 工具栏(新建草稿/导入包)。
struct PatchesTabView: View {
    @StateObject private var viewModel = PatchesViewModel()

    @State private var showNewDraft = false
    @State private var draftName = ""

    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var importPassword = ""

    @State private var deleteTarget: ProjectIndexEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.defaultSpacing) {
                projectsSection
            }
            .padding(Theme.defaultSpacing)
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "patch.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: PatchEditorRoute.self) { route in
            PatchEditorView(projectID: route.projectID)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    draftName = ""
                    showNewDraft = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "patch.action.new"))

                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel(String(localized: "patch.action.import"))
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingImportURL = url
                importPassword = ""
            case .failure:
                // 取消选择或系统错误:静默忽略,真正的解码/写入错误由 importPackage 在 VM 内呈现。
                break
            }
        }
        .task {
            viewModel.load()
        }
        .overlay { busyOverlay }
        .background { newDraftAnchor }
        .background { importPasswordAnchor }
        .background { deleteAnchor }
        .background { errorAnchor }
    }

    // MARK: - 项目列表

    @ViewBuilder
    private var projectsSection: some View {
        if viewModel.projects.isEmpty {
            emptyState
        } else {
            SectionCard(title: String(localized: "patch.section.projects"), systemImage: "puzzlepiece.extension") {
                VStack(spacing: 10) {
                    ForEach(viewModel.projects) { entry in
                        NavigationLink(value: PatchEditorRoute(projectID: entry.projectID)) {
                            projectRow(entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteTarget = entry
                            } label: {
                                Label(String(localized: "patch.action.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func projectRow(_ entry: ProjectIndexEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isPrivate ? "lock.fill" : "puzzlepiece.fill")
                .font(.title3)
                .foregroundStyle(entry.isPrivate ? Color(.systemOrange) : Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if entry.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if viewModel.appliedProjectIDs.contains(entry.projectID) {
                Text(String(localized: "patch.badge.applied"))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.supported.opacity(0.15))
                    .foregroundStyle(Theme.supported)
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .glassRowFill()
    }

    private func subtitle(for entry: ProjectIndexEntry) -> String {
        var parts: [String] = []
        if !entry.author.isEmpty {
            parts.append(entry.author)
        }
        parts.append("\(entry.ruleCount) \(String(localized: "patch.count.rules"))")
        return parts.joined(separator: " · ")
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text(String(localized: "patch.empty.title"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "patch.empty.hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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

    // MARK: - 弹窗锚点

    private var newDraftAnchor: some View {
        Color.clear
            .alert(String(localized: "patch.draft.title"), isPresented: $showNewDraft) {
                TextField(String(localized: "patch.draft.name_prompt"), text: $draftName)
                Button(String(localized: "common.close"), role: .cancel) {
                    draftName = ""
                }
                Button(String(localized: "patch.action.create")) {
                    let name = draftName
                    draftName = ""
                    Task { await viewModel.createDraft(named: name) }
                }
            } message: {
                Text(String(localized: "patch.draft.message"))
            }
    }

    private var importPasswordAnchor: some View {
        Color.clear
            .alert(String(localized: "patch.import.password_title"), isPresented: importPasswordBinding) {
                SecureField(String(localized: "patch.import.password_prompt"), text: $importPassword)
                Button(String(localized: "common.close"), role: .cancel) {
                    pendingImportURL = nil
                    importPassword = ""
                }
                Button(String(localized: "patch.action.import")) {
                    let url = pendingImportURL
                    let pwd = importPassword
                    pendingImportURL = nil
                    importPassword = ""
                    if let url {
                        Task { await viewModel.importPackage(from: url, password: pwd.isEmpty ? nil : pwd) }
                    }
                }
            } message: {
                Text(String(localized: "patch.import.password_message"))
            }
    }

    private var importPasswordBinding: Binding<Bool> {
        Binding(
            get: { pendingImportURL != nil },
            set: { if !$0 { pendingImportURL = nil; importPassword = "" } }
        )
    }

    private var deleteAnchor: some View {
        Color.clear
            .confirmationDialog(
                String(localized: "patch.action.delete"),
                isPresented: deleteBinding,
                titleVisibility: .visible
            ) {
                Button(String(localized: "patch.action.delete"), role: .destructive) {
                    let target = deleteTarget
                    deleteTarget = nil
                    if let target {
                        Task { await viewModel.delete(target) }
                    }
                }
                Button(String(localized: "common.close"), role: .cancel) {
                    deleteTarget = nil
                }
            } message: {
                Text(String(localized: "patch.confirm.delete"))
            }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var errorAnchor: some View {
        Color.clear
            .alert(String(localized: "patch.error.title"), isPresented: errorBinding) {
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
