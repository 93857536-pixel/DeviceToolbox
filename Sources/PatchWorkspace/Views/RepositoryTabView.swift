import SwiftUI
import Foundation

/// 仓库标签页:仓库源列表(添加/删除)+ 包索引浏览 + 下载导入(进度/错误态)。
struct RepositoryTabView: View {
    @StateObject private var viewModel = RepositoryViewModel()

    @State private var showAddSource = false
    @State private var sourceName = ""
    @State private var sourceURL = ""

    @State private var removeSourceTarget: RepositorySource?

    @State private var pendingImportEntry: RepositoryIndexEntry?
    @State private var pendingImportSource: RepositorySource?
    @State private var importPassword = ""

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.defaultSpacing) {
                sourcesSection
                packagesSection
            }
            .padding(Theme.defaultSpacing)
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "repo.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sourceName = ""
                    sourceURL = ""
                    showAddSource = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "repo.action.add_source"))
            }
        }
        .task {
            viewModel.loadSources()
        }
        .background { addSourceAnchor }
        .background { removeSourceAnchor }
        .background { importPasswordAnchor }
        .background { errorAnchor }
        .background { resultAnchor }
    }

    // MARK: - 源列表

    private var sourcesSection: some View {
        SectionCard(title: String(localized: "repo.section.sources"), systemImage: "shippingbox") {
            if viewModel.sources.isEmpty {
                Text(String(localized: "repo.empty.sources"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.sources) { source in
                        sourceRow(source)
                    }
                }
            }
        }
    }

    private func sourceRow(_ source: RepositorySource) -> some View {
        Button {
            Task { await viewModel.select(source) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(source.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if viewModel.selectedSource?.id == source.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(12)
            .glassRowFill()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                removeSourceTarget = source
            } label: {
                Label(String(localized: "repo.action.remove_source"), systemImage: "trash")
            }
        }
    }

    // MARK: - 包索引

    private var packagesSection: some View {
        SectionCard(title: String(localized: "repo.section.packages"), systemImage: "shippingbox.and.arrow.backward") {
            if viewModel.selectedSource == nil {
                Text(String(localized: "repo.empty.no_source"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if viewModel.isLoadingIndex {
                HStack {
                    Spacer()
                    ProgressView(String(localized: "repo.busy.fetching"))
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if viewModel.entries.isEmpty {
                Text(String(localized: "repo.empty.packages"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.entries) { entry in
                        packageRow(entry)
                    }
                }
            }
        }
    }

    private func packageRow(_ entry: RepositoryIndexEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let bundleIDs = entry.bundleIDs, !bundleIDs.isEmpty {
                    Text(bundleIDs.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if viewModel.importingEntryID == entry.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    beginImport(entry)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "repo.action.import"))
            }
        }
        .padding(12)
        .glassRowFill()
    }

    private func beginImport(_ entry: RepositoryIndexEntry) {
        guard let source = viewModel.selectedSource else { return }
        pendingImportEntry = entry
        pendingImportSource = source
        importPassword = ""
    }

    // MARK: - 弹窗锚点

    private var addSourceAnchor: some View {
        Color.clear
            .alert(String(localized: "repo.add_source.title"), isPresented: $showAddSource) {
                TextField(String(localized: "repo.add_source.name_prompt"), text: $sourceName)
                TextField(String(localized: "repo.add_source.url_prompt"), text: $sourceURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(String(localized: "common.close"), role: .cancel) {}
                Button(String(localized: "repo.action.add_source")) {
                    let name = sourceName
                    let url = sourceURL
                    sourceName = ""
                    sourceURL = ""
                    Task { await viewModel.addSource(name: name, urlString: url) }
                }
            } message: {
                Text(String(localized: "repo.add_source.message"))
            }
    }

    private var removeSourceAnchor: some View {
        Color.clear
            .confirmationDialog(
                String(localized: "repo.action.remove_source"),
                isPresented: removeSourceBinding,
                titleVisibility: .visible
            ) {
                Button(String(localized: "repo.action.remove_source"), role: .destructive) {
                    if let source = removeSourceTarget {
                        viewModel.removeSource(source)
                    }
                    removeSourceTarget = nil
                }
                Button(String(localized: "common.close"), role: .cancel) {
                    removeSourceTarget = nil
                }
            } message: {
                Text(String(localized: "repo.confirm.remove_source"))
            }
    }

    private var removeSourceBinding: Binding<Bool> {
        Binding(get: { removeSourceTarget != nil }, set: { if !$0 { removeSourceTarget = nil } })
    }

    private var importPasswordAnchor: some View {
        Color.clear
            .alert(String(localized: "repo.import.password_title"), isPresented: importPasswordBinding) {
                SecureField(String(localized: "repo.import.password_prompt"), text: $importPassword)
                Button(String(localized: "common.close"), role: .cancel) {
                    pendingImportEntry = nil
                    pendingImportSource = nil
                    importPassword = ""
                }
                Button(String(localized: "repo.action.import")) {
                    let entry = pendingImportEntry
                    let source = pendingImportSource
                    let pwd = importPassword
                    pendingImportEntry = nil
                    pendingImportSource = nil
                    importPassword = ""
                    if let entry, let source {
                        Task {
                            await viewModel.downloadAndImport(entry, from: source, password: pwd.isEmpty ? nil : pwd)
                        }
                    }
                }
            } message: {
                Text(String(localized: "repo.import.password_message"))
            }
    }

    private var importPasswordBinding: Binding<Bool> {
        Binding(
            get: { pendingImportEntry != nil },
            set: {
                if !$0 {
                    pendingImportEntry = nil
                    pendingImportSource = nil
                    importPassword = ""
                }
            }
        )
    }

    private var errorAnchor: some View {
        Color.clear
            .alert(String(localized: "repo.error.title"), isPresented: errorBinding) {
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
            .alert(String(localized: "repo.result.title"), isPresented: resultBinding) {
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
