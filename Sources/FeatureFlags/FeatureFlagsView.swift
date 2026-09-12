import SwiftUI

/// Feature Flags 编辑器:读取/切换 /var/preferences/FeatureFlags/Global.plist 的常用开关。
/// 未逃逸时只读展示(可尝试读取);逃逸激活后 elevate 到 root 才可写。模拟器显示不可用。
@MainActor
struct FeatureFlagsView: View {
    @State private var values: [String: Bool] = [:]
    @State private var isLoaded = false
    @State private var busyFlagID: String?
    @State private var noticeMessage: String?

    private var escapeActive: Bool {
        ExploitController.isSandboxActive()
    }

    private var writable: Bool {
        FeatureFlagsService.isAvailable && escapeActive
    }

    var body: some View {
        List {
            statusSection
            if isLoaded {
                ForEach(FeatureFlagsService.catalog) { group in
                    groupSection(group)
                }
            } else {
                ProgressView(String(localized: "featureflags.loading"))
                    .frame(maxWidth: .infinity)
            }
            sourceSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "featureflags.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "featureflags.refresh"))
            }
        }
        .onAppear { reload() }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            if !FeatureFlagsService.isAvailable {
                Label(String(localized: "featureflags.unavailable"), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Theme.unsupported)
            } else if writable {
                Label(String(localized: "featureflags.writable"), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.supported)
            } else {
                Label(String(localized: "featureflags.readonly"), systemImage: "lock.fill")
                    .foregroundStyle(Theme.unknown)
            }
            if let noticeMessage {
                Text(noticeMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 分组

    private func groupSection(_ group: FeatureFlagsService.FlagGroup) -> some View {
        Section {
            ForEach(group.flags) { def in
                flagRow(def)
            }
        } header: {
            Text(NSLocalizedString(group.titleKey, comment: ""))
        } footer: {
            Text(String(localized: "featureflags.experimental.footer"))
        }
    }

    private func flagRow(_ def: FeatureFlagsService.FlagDefinition) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(NSLocalizedString(def.titleKey, comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if def.experimental {
                        Text(String(localized: "featureflags.badge.experimental"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text("\(def.category).\(def.key)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if busyFlagID == def.id {
                ProgressView()
            } else {
                Toggle("", isOn: binding(for: def))
                    .labelsHidden()
                    .disabled(!writable)
            }
        }
    }

    // MARK: - 来源

    private var sourceSection: some View {
        Section {
            Text(String(localized: "featureflags.source.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            Text(String(localized: "featureflags.restart.hint"))
        }
    }

    // MARK: - 逻辑

    private func binding(for def: FeatureFlagsService.FlagDefinition) -> Binding<Bool> {
        Binding(
            get: { values[def.id] ?? false },
            set: { newValue in
                values[def.id] = newValue
                commit(def, value: newValue)
            }
        )
    }

    private func reload() {
        isLoaded = false
        let dict = FeatureFlagsService.readGlobal()
        var result: [String: Bool] = [:]
        for group in FeatureFlagsService.catalog {
            for flag in group.flags {
                result[flag.id] = dict?[flag.category]?[flag.key] as? Bool ?? false
            }
        }
        values = result
        isLoaded = true
    }

    private func commit(_ def: FeatureFlagsService.FlagDefinition, value: Bool) {
        busyFlagID = def.id
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Bool, OperationFailure> in
                do {
                    _ = ExploitController.elevateToRootIfEscaped()
                    try FeatureFlagsService.writeFlag(category: def.category, flag: def.key, value: value)
                    return .success(value)
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    return .failure(OperationFailure(message: msg))
                }
            }.value
            busyFlagID = nil
            switch result {
            case .success(let v):
                values[def.id] = v
                noticeMessage = String(localized: "featureflags.restart.hint")
            case .failure(let error):
                // 回滚 UI 到真实值
                values[def.id] = FeatureFlagsService.currentBool(category: def.category, flag: def.key)
                noticeMessage = String(localized: "featureflags.write.failed") + " · " + error.message
            }
        }
    }
}
