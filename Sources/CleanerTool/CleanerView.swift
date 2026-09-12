import SwiftUI

/// 清理器:分区展示「沙盒可清理」与「系统缓存(仅预览)」,勾选后双确认删除。
/// 系统区仅在逃逸激活后出现;模拟器下系统区隐藏。
@MainActor
struct CleanerView: View {
    @State private var scan: CleanerService.ScanResult?
    @State private var selected: Set<String> = []
    @State private var isScanning = false
    @State private var isDeleting = false
    @State private var showConfirm = false
    @State private var resultMessage: String?

    private var escapeActive: Bool {
        ExploitController.isSandboxActive() || SystemContainerService.isSystemRootAccessible()
    }

    var body: some View {
        List {
            dangerSection

            if let scan {
                sandboxSection(scan)
                if escapeActive {
                    systemSection(scan)
                }
                actionSection(scan)
            } else if isScanning {
                HStack {
                    ProgressView()
                    Text(String(localized: "cleaner.scanning"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "cleaner.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await rescan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isScanning || isDeleting)
                .accessibilityLabel(String(localized: "cleaner.scan"))
            }
        }
        .alert(String(localized: "cleaner.confirm.title"), isPresented: $showConfirm) {
            Button(String(localized: "cleaner.delete.selected"), role: .destructive) {
                Task { await deleteSelected() }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "cleaner.confirm.body"))
        }
        .alert(String(localized: "cleaner.result.title"), isPresented: resultBinding) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
        .task {
            await rescan()
        }
    }

    // MARK: - 危险提示

    private var dangerSection: some View {
        Section {
            Label(String(localized: "cleaner.danger"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.unsupported)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 沙盒区

    private func sandboxSection(_ scan: CleanerService.ScanResult) -> some View {
        Section {
            if scan.sandboxItems.isEmpty {
                Text(String(localized: "cleaner.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scan.sandboxItems) { item in
                    selectableRow(item)
                }
            }
        } header: {
            Text(String(localized: "cleaner.section.sandbox"))
        } footer: {
            if !scan.sandboxItems.isEmpty {
                Text("\(String(localized: "cleaner.total")) \(CleanerService.formatBytes(scan.sandboxTotalBytes))")
            }
        }
    }

    // MARK: - 系统区(仅预览)

    private func systemSection(_ scan: CleanerService.ScanResult) -> some View {
        Section {
            if scan.systemItems.isEmpty {
                Text(String(localized: "cleaner.system.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scan.systemItems) { item in
                    selectableRow(item)
                }
            }
        } header: {
            Text(String(localized: "cleaner.section.system"))
        } footer: {
            if !scan.systemItems.isEmpty {
                Text("\(String(localized: "cleaner.total")) \(CleanerService.formatBytes(scan.systemTotalBytes))")
            }
        }
    }

    // MARK: - 行

    private func selectableRow(_ item: CleanerService.CleanableItem) -> some View {
        Button {
            toggle(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(item.isSystem ? Theme.unknown : Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if item.isSystem && !item.deletable {
                        Text(String(localized: "cleaner.system.preview.only"))
                            .font(.caption2)
                            .foregroundStyle(Theme.unknown)
                    }
                }
                Spacer()
                Text(CleanerService.formatBytes(item.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                selectionIndicator(item)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDeleting || (item.isSystem && !item.deletable))
    }

    @ViewBuilder
    private func selectionIndicator(_ item: CleanerService.CleanableItem) -> some View {
        if item.isSystem && !item.deletable {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(Theme.unknown)
        } else if selected.contains(item.id) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 操作区

    @ViewBuilder
    private func actionSection(_ scan: CleanerService.ScanResult) -> some View {
        Section {
            if isDeleting {
                HStack {
                    ProgressView()
                    Text(String(localized: "cleaner.deleting"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Label(
                        "\(String(localized: "cleaner.delete.selected")) (\(selected.count))",
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.unsupported)
                .disabled(selected.isEmpty)
            }
        } footer: {
            if selected.isEmpty {
                Text(String(localized: "cleaner.select.hint"))
            }
        }
    }

    // MARK: - 动作

    private func toggle(_ item: CleanerService.CleanableItem) {
        guard item.deletable else { return }
        if selected.contains(item.id) {
            selected.remove(item.id)
        } else {
            selected.insert(item.id)
        }
    }

    private func rescan() async {
        isScanning = true
        selected.removeAll()
        scan = await CleanerService.scan()
        isScanning = false
    }

    private func deleteSelected() async {
        guard let scan else { return }
        let chosen = (scan.sandboxItems + scan.systemItems).filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        isDeleting = true
        let result = await CleanerService.delete(items: chosen)
        isDeleting = false
        selected.removeAll()
        resultMessage = String(localized: "cleaner.result.body \(result.deletedCount) \(result.failedCount) \(CleanerService.formatBytes(result.freedBytes))")
        // 删除后刷新体积
        self.scan = await CleanerService.scan()
    }

    private var resultBinding: Binding<Bool> {
        Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )
    }
}
