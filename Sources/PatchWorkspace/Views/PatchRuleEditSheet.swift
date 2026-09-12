import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// 单条规则的编辑 sheet:选择动作(replaceFile/deleteFile/addFolder)、
/// 输入/浏览目标相对路径,replaceFile 时用系统 .fileImporter 选择替换载荷文件。
struct PatchRuleEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let projectName: String
    let existingRule: PatchRule?
    let onSave: (PatchRule) -> Void

    @State private var action: PatchAction
    @State private var relativePath: String
    @State private var replacementFilename: String?
    @State private var replacementData: Data?

    @State private var showTargetPicker = false
    @State private var showFileImporter = false
    @State private var errorMessage: String?

    private var appliedRoot: URL {
        PatchTransaction.defaultAppliedRoot(projectName: projectName)
    }

    init(projectName: String, existingRule: PatchRule?, onSave: @escaping (PatchRule) -> Void) {
        self.projectName = projectName
        self.existingRule = existingRule
        self.onSave = onSave
        _action = State(initialValue: existingRule?.action ?? .replaceFile)
        _relativePath = State(initialValue: existingRule?.relativePath ?? "")
        _replacementFilename = State(initialValue: existingRule?.replacementFilename)
        _replacementData = State(initialValue: existingRule?.replacementData)
    }

    var body: some View {
        NavigationStack {
            Form {
                actionSection
                pathSection
                if action == .replaceFile {
                    payloadSection
                }
            }
            .navigationTitle(existingRule == nil
                             ? String(localized: "patch.rule.title.add")
                             : String(localized: "patch.rule.title.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "patch.rule.save")) {
                        commit()
                    }
                }
            }
            .sheet(isPresented: $showTargetPicker) {
                PatchTargetPickerView(projectName: projectName) { url in
                    relativePath = relativePath(from: url)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let didStart = url.startAccessingSecurityScopedResource()
                    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        replacementData = data
                        replacementFilename = url.lastPathComponent
                    }
                case .failure:
                    break
                }
            }
            .alert(String(localized: "patch.error.title"), isPresented: errorBinding) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 动作

    private var actionSection: some View {
        Section(String(localized: "patch.rule.action")) {
            Picker(String(localized: "patch.rule.action"), selection: $action) {
                Text(String(localized: "patch.rule.action.replace")).tag(PatchAction.replaceFile)
                Text(String(localized: "patch.rule.action.delete")).tag(PatchAction.deleteFile)
                Text(String(localized: "patch.rule.action.add_folder")).tag(PatchAction.addFolder)
            }
            .pickerStyle(.segmented)
            .onChange(of: action) { _, _ in
                // 切换动作时清空不适用字段。
                if action != .replaceFile {
                    replacementData = nil
                    replacementFilename = nil
                }
            }
        }
    }

    // MARK: - 目标路径

    private var pathSection: some View {
        Section(String(localized: "patch.rule.path")) {
            HStack(spacing: 8) {
                TextField(String(localized: "patch.rule.path_prompt"), text: $relativePath)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button {
                    showTargetPicker = true
                } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel(String(localized: "patch.rule.browse"))
            }
        }
    }

    // MARK: - 替换载荷

    private var payloadSection: some View {
        Section(String(localized: "patch.rule.payload")) {
            Button {
                showFileImporter = true
            } label: {
                HStack {
                    Text(replacementFilename ?? String(localized: "patch.rule.payload_empty"))
                        .foregroundStyle(replacementFilename == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.accent)
                }
            }
            .accessibilityLabel(String(localized: "patch.rule.payload_choose"))
        }
    }

    // MARK: - 提交

    private func commit() {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical: String
        do {
            canonical = try PatchPathValidator.canonicalRelativePath(trimmed)
        } catch {
            errorMessage = patchErrorMessage(for: error)
            return
        }

        if action == .replaceFile {
            guard replacementData != nil else {
                errorMessage = String(localized: "patch.rule.error.no_payload")
                return
            }
        }

        let rule = PatchRule(
            id: existingRule?.id ?? UUID(),
            relativePath: canonical,
            action: action,
            replacementFilename: action == .replaceFile ? replacementFilename : nil,
            replacementData: action == .replaceFile ? replacementData : nil
        )
        onSave(rule)
        dismiss()
    }

    private func relativePath(from url: URL) -> String {
        let rootPath = appliedRoot.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if targetPath == rootPath { return "" }
        guard targetPath.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(targetPath.dropFirst(rootPath.count + 1))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
