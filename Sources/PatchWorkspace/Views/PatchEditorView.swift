import SwiftUI
import Foundation

/// 补丁项目详情与规则编辑器:项目信息 + 规则列表(增删改)+ 保存/应用/回滚。
struct PatchEditorView: View {
    let projectID: UUID
    @StateObject private var viewModel: PatchEditorViewModel

    @State private var showRuleEditor = false
    @State private var editingRule: PatchRule?

    @State private var showNamePrompt = false
    @State private var nameInput = ""

    @State private var passwordInput = ""

    @State private var deleteRuleTarget: PatchRule?

    init(projectID: UUID) {
        self.projectID = projectID
        _viewModel = StateObject(wrappedValue: PatchEditorViewModel(projectID: projectID))
    }

    var body: some View {
        Group {
            if let project = viewModel.project {
                content(project)
            } else if !viewModel.hasLoaded {
                ProgressView(String(localized: "patch.editor.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.needsPassword {
                passwordPrompt
            } else {
                loadFailed
            }
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(viewModel.project?.name ?? String(localized: "patch.editor.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "patch.action.save")) {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.project == nil)
            }
        }
        .safeAreaInset(edge: .bottom) { applyBar }
        .task {
            viewModel.load()
        }
        .overlay { busyOverlay }
        .sheet(isPresented: $showRuleEditor) {
            PatchRuleEditSheet(
                projectName: viewModel.project?.name ?? "",
                existingRule: editingRule
            ) { rule in
                if let editingRule {
                    viewModel.updateRule(id: editingRule.id, with: rule)
                } else {
                    viewModel.addRule(rule)
                }
            }
        }
        .background { nameAnchor }
        .background { deleteRuleAnchor }
        .background { errorAnchor }
        .background { resultAnchor }
    }

    // MARK: - 内容

    private func content(_ project: PatchProject) -> some View {
        List {
            Section(String(localized: "patch.editor.section.info")) {
                Button {
                    nameInput = project.name
                    showNamePrompt = true
                } label: {
                    HStack {
                        Text(String(localized: "patch.editor.name"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(project.name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if !project.author.isEmpty {
                    infoRow(label: String(localized: "patch.editor.author"), value: project.author)
                }
                infoRow(
                    label: String(localized: "patch.editor.updated"),
                    value: project.updatedAt.formatted(date: .abbreviated, time: .shortened)
                )
                HStack {
                    Text(String(localized: "patch.editor.status"))
                        .foregroundStyle(.primary)
                    Spacer()
                    if viewModel.isApplied {
                        Label(String(localized: "patch.badge.applied"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.supported)
                    } else {
                        Text(String(localized: "patch.badge.not_applied"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(project.rules) { rule in
                    ruleRow(rule)
                }
                Button {
                    editingRule = nil
                    showRuleEditor = true
                } label: {
                    Label(String(localized: "patch.action.add_rule"), systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            } header: {
                Text(String(localized: "patch.editor.section.rules"))
            } footer: {
                if project.rules.isEmpty {
                    Text(String(localized: "patch.editor.rules_empty"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - 规则行

    private func ruleRow(_ rule: PatchRule) -> some View {
        Button {
            editingRule = rule
            showRuleEditor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: actionIcon(for: rule.action))
                    .font(.body)
                    .foregroundStyle(actionColor(for: rule.action))
                    .frame(width: 28, height: 28)
                    .background(actionColor(for: rule.action).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.relativePath)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if rule.action == .replaceFile, let filename = rule.replacementFilename {
                        Text(filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteRuleTarget = rule
            } label: {
                Label(String(localized: "patch.action.delete"), systemImage: "trash")
            }
        }
    }

    private func actionIcon(for action: PatchAction) -> String {
        switch action {
        case .replaceFile: return "arrow.2.squarepath"
        case .deleteFile: return "trash"
        case .addFolder: return "folder.badge.plus"
        }
    }

    private func actionColor(for action: PatchAction) -> Color {
        switch action {
        case .replaceFile: return Theme.accent
        case .deleteFile: return Theme.unsupported
        case .addFolder: return Theme.supported
        }
    }

    // MARK: - 应用 / 回滚栏

    @ViewBuilder
    private var applyBar: some View {
        if viewModel.project != nil {
            HStack(spacing: 12) {
                if viewModel.isApplied {
                    Button {
                        Task { await viewModel.restore() }
                    } label: {
                        Label(String(localized: "patch.action.restore"), systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.unsupported)
                } else {
                    Button {
                        Task { await viewModel.apply() }
                    } label: {
                        Label(String(localized: "patch.action.apply"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(viewModel.project?.rules.isEmpty ?? true)
                }
            }
            .padding(Theme.defaultSpacing)
            .background(.regularMaterial)
        }
    }

    // MARK: - 私密密码提示

    private var passwordPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(String(localized: "patch.editor.password_title"))
                .font(.headline)
            SecureField(String(localized: "patch.editor.password_prompt"), text: $passwordInput)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, Theme.cardPadding)
            Button(String(localized: "patch.editor.password_unlock")) {
                viewModel.load(withPassword: passwordInput)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(passwordInput.isEmpty)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadFailed: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Theme.unsupported)
            Text(String(localized: "patch.editor.load_failed"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Button(String(localized: "patch.editor.retry")) {
                viewModel.load()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var nameAnchor: some View {
        Color.clear
            .alert(String(localized: "patch.editor.name"), isPresented: $showNamePrompt) {
                TextField(String(localized: "patch.editor.name_prompt"), text: $nameInput)
                Button(String(localized: "common.close"), role: .cancel) {}
                Button(String(localized: "common.ok")) {
                    viewModel.updateName(nameInput)
                }
            } message: {
                Text(String(localized: "patch.editor.name_message"))
            }
    }

    private var deleteRuleAnchor: some View {
        Color.clear
            .confirmationDialog(
                String(localized: "patch.action.delete"),
                isPresented: deleteRuleBinding,
                titleVisibility: .visible
            ) {
                Button(String(localized: "patch.action.delete"), role: .destructive) {
                    if let target = deleteRuleTarget {
                        viewModel.deleteRule(id: target.id)
                    }
                    deleteRuleTarget = nil
                }
                Button(String(localized: "common.close"), role: .cancel) {
                    deleteRuleTarget = nil
                }
            } message: {
                Text(String(localized: "patch.confirm.delete_rule"))
            }
    }

    private var deleteRuleBinding: Binding<Bool> {
        Binding(get: { deleteRuleTarget != nil }, set: { if !$0 { deleteRuleTarget = nil } })
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

    private var resultAnchor: some View {
        Color.clear
            .alert(String(localized: "patch.result.title"), isPresented: resultBinding) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(viewModel.resultMessage ?? "")
            }
    }

    private var resultBinding: Binding<Bool> {
        Binding(
            get: { viewModel.resultMessage != nil },
            set: { if !$0 { viewModel.dismissResult() } }
        )
    }
}
