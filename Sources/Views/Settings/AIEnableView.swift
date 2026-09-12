import SwiftUI

/// 设置页「Apple Intelligence 强开」:版本×机型判定 → 分步执行 → 结果指引/恢复。
/// 依赖特权引擎(沙盒逃逸)激活;模拟器与不可行版本不显示执行按钮。
@MainActor
struct AIEnableView: View {
    @ObservedObject private var controller = AIEnableController.shared
    @ObservedObject private var exploit = ExploitController.shared

    private var verdict: AIEnablePolicy.Verdict {
        AIEnablePolicy.verdict(
            model: DeviceProbe.modelIdentifier,
            major: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            minor: ProcessInfo.processInfo.operatingSystemVersion.minorVersion,
            patch: ProcessInfo.processInfo.operatingSystemVersion.patchVersion,
            build: SupportPolicy.currentBuildNumber,
            isSimulator: DeviceProbe.isSimulator
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            verdictRow
            if verdict.isActionable || controller.phase != .idle {
                stateRow
                controls
            } else {
                noteText(verdict.note)
            }
        }
        .onAppear { _ = controller.hasBackup }
    }

    // MARK: - 判定

    @ViewBuilder
    private var verdictRow: some View {
        HStack {
            Label(String(localized: "aienable.verdict.label"), systemImage: verdictIcon)
                .foregroundStyle(verdictTint)
            Spacer()
            if verdict.experimental {
                Text(String(localized: "aienable.badge.experimental"))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            Text(verdictTitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        if verdict.isActionable {
            noteText(verdict.note)
        }
    }

    private var verdictIcon: String {
        switch verdict.target {
        case .official: return "checkmark.seal.fill"
        case .regionUnlock: return "globe.asia.australia.fill"
        case .hardwareSpoof: return "cpu.fill"
        case .unavailable: return "xmark.octagon.fill"
        }
    }

    private var verdictTint: Color {
        switch verdict.target {
        case .official: return Theme.supported
        case .regionUnlock, .hardwareSpoof: return Theme.accent
        case .unavailable: return Theme.unsupported
        }
    }

    private var verdictTitle: String {
        switch verdict.target {
        case .official: return String(localized: "aienable.verdict.official")
        case .regionUnlock: return String(localized: "aienable.verdict.region")
        case .hardwareSpoof: return String(localized: "aienable.verdict.hardware")
        case .unavailable: return String(localized: "aienable.verdict.unavailable")
        }
    }

    // MARK: - 状态与操作

    @ViewBuilder
    private var stateRow: some View {
        switch controller.phase {
        case .idle:
            LabeledContent(String(localized: "aienable.state"), value: String(localized: "aienable.state.idle"))
        case .running:
            HStack(spacing: 8) {
                ProgressView()
                Text(stepTitle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .active:
            LabeledContent(String(localized: "aienable.state"), value: String(localized: "aienable.state.active"))
                .foregroundStyle(Theme.supported)
        case .failed:
            LabeledContent(String(localized: "aienable.state"), value: String(localized: "aienable.state.failed"))
                .foregroundStyle(Theme.unsupported)
        }
    }

    private var stepTitle: String {
        switch controller.step {
        case .preflight: return String(localized: "aienable.step.preflight")
        case .backup: return String(localized: "aienable.step.backup")
        case .write: return String(localized: "aienable.step.write")
        case .eligibility: return String(localized: "aienable.step.eligibility")
        case .done: return String(localized: "aienable.step.done")
        }
    }

    @ViewBuilder
    private var controls: some View {
        if case .failed(let msg) = controller.phase {
            noteText(msg)
        }
        if case .active = controller.phase, let note = controller.outcomeNote, !note.isEmpty {
            noteText(note)
        }

        if controller.phase == .idle || controller.phase == .active {
            runButton
        }
        if controller.hasBackup {
            Button(String(localized: "aienable.restore")) {
                Task { await controller.restoreOriginal() }
            }
            .font(.footnote)
        }
        if controller.phase != .idle && controller.phase != .running {
            Button(String(localized: "aienable.reset")) {
                controller.reset()
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var runButton: some View {
        if verdict.isActionable {
            if verdict.requiresEscape && !escapeActive {
                Button(String(localized: "aienable.run.need_escape")) {}
                .buttonStyle(.borderedProminent)
                .disabled(true)
            } else {
                Button(String(localized: "aienable.run.trigger")) {
                    confirmRun = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .confirmationDialog(
                    String(localized: "aienable.run.confirm.title"),
                    isPresented: $confirmRun,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "aienable.run.trigger"), role: .destructive) {
                        controller.run(verdict: verdict)
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "aienable.run.confirm.body"))
                }
            }
        }
    }

    private var escapeActive: Bool {
        exploit.state == .active && ExploitController.isSandboxActive()
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @State private var confirmRun = false
}
