import SwiftUI

/// 设置页「型号伪装」(3105 Gestalt 编辑器 model_spoof 语义移植,自写实现):
/// 改写 MobileGestalt 的 ProductType/HardwareModel/HardwarePlatform 三键,
/// 让系统把本机识别为另一机型(设置→通用→关于本机 显示变化;部分机型判定功能随之变化)。
/// 写入需沙盒逃逸激活;首次写入自动备份,可随时还原。
@MainActor
struct ModelSpoofView: View {
    @State private var selectedID: String = MobileGestaltService.spoofCatalog[0].id
    @State private var isBusy = false
    @State private var note: String?
    @State private var confirmApply = false

    private var currentModel: String { DeviceProbe.modelIdentifier }

    var body: some View {
        VStack(spacing: 10) {
            LabeledContent(String(localized: "modelspoof.current"), value: currentModel.isEmpty ? "—" : currentModel)
            Divider()
            ForEach(MobileGestaltService.spoofCatalog) { target in
                spoofRow(target)
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls
            Text(String(localized: "modelspoof.footer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 行

    private func spoofRow(_ target: MobileGestaltService.ModelSpoofTarget) -> some View {
        Button {
            selectedID = target.id
        } label: {
            HStack {
                Image(systemName: selectedID == target.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedID == target.id ? Theme.accent : .secondary)
                Text(target.name)
                    .foregroundStyle(.primary)
                if target.experimental {
                    Text(String(localized: "modelspoof.experimental"))
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Text(target.id)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 操作

    @ViewBuilder
    private var controls: some View {
        if escapeActive {
            Button(String(localized: "modelspoof.apply")) {
                confirmApply = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(isBusy)
            .confirmationDialog(
                String(localized: "modelspoof.confirm.title"),
                isPresented: $confirmApply,
                titleVisibility: .visible
            ) {
                Button(String(localized: "modelspoof.apply"), role: .destructive) {
                    Task { await applySpoof() }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "modelspoof.confirm.body"))
            }
        } else {
            Text(String(localized: "modelspoof.need_escape"))
                .font(.caption)
                .foregroundStyle(Theme.unsupported)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if isBusy {
            HStack(spacing: 8) {
                ProgressView()
                Text(String(localized: "modelspoof.applying"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if MobileGestaltService.hasBackup() {
            Button(String(localized: "modelspoof.restore")) {
                Task { await restoreOriginal() }
            }
            .font(.footnote)
            .disabled(isBusy)
        }
    }

    private var escapeActive: Bool {
        ExploitController.isSandboxActive()
    }

    // MARK: - 动作

    private func applySpoof() async {
        guard let target = MobileGestaltService.spoofCatalog.first(where: { $0.id == selectedID }) else { return }
        isBusy = true
        defer { isBusy = false }

        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, AIEnableError> in
            guard let original = MobileGestaltService.readGestaltData() else {
                return .failure(.gestaltParseFailed)
            }
            do {
                _ = try MobileGestaltService.backupGestalt(data: original)
                let patched = try MobileGestaltService.patchedGestaltData(original: original, spoof: target)
                try MobileGestaltService.writeFileAtomically(patched.data,
                                                             to: MobileGestaltService.gestaltCachePath,
                                                             original: original)
                return .success(())
            } catch let e as AIEnableError {
                return .failure(e)
            } catch {
                return .failure(.atomicWriteFailed(path: MobileGestaltService.gestaltCachePath))
            }
        }.value

        switch outcome {
        case .success:
            note = String(localized: "modelspoof.done") + " " + target.name
        case .failure(let e):
            note = e.errorDescription
        }
    }

    private func restoreOriginal() async {
        isBusy = true
        defer { isBusy = false }
        guard MobileGestaltService.hasBackup() else {
            note = String(localized: "modelspoof.no_backup")
            return
        }
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, AIEnableError> in
            do {
                try MobileGestaltService.restoreGestaltFromBackup()
                return .success(())
            } catch let e as AIEnableError {
                return .failure(e)
            } catch {
                return .failure(.noBackup)
            }
        }.value
        switch outcome {
        case .success:
            note = String(localized: "modelspoof.restore.done")
        case .failure(let e):
            note = e.errorDescription
        }
    }
}
