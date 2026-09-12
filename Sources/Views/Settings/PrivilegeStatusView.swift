import SwiftUI

/// 设置页「特权引擎」状态区:探测设备型号/芯片/系统,展示可用漏洞链判定。
@MainActor
struct PrivilegeStatusView: View {
    @StateObject private var access = KernelAccess()
    @ObservedObject private var exploit = ExploitController.shared

    var body: some View {
        Group {
            LabeledContent(String(localized: "privilege.model"), value: access.modelIdentifier.isEmpty ? "—" : access.modelIdentifier)
            LabeledContent(String(localized: "privilege.soc"), value: socTitle)
            LabeledContent(String(localized: "privilege.ios"), value: osVersionText)
            verdictRow
            exploitStateRow
            if canRun { runControls }
        }
        .task {
            if access.phase == .idle {
                access.probe()
            }
        }
    }

    /// 仅在支持矩阵命中且非模拟器时允许触发(模拟器/不支持设备上不出现)。
    private var canRun: Bool {
        guard let verdict = access.verdict, verdict.isSupported else { return false }
        return !DeviceProbe.isSimulator
    }

    @ViewBuilder
    private var exploitStateRow: some View {
        LabeledContent(String(localized: "privilege.run.state"), value: exploitStateText)
    }

    @ViewBuilder
    private var runControls: some View {
        if case .failed = exploit.state {
            Text(exploitFailureNote)
                .font(.caption)
                .foregroundStyle(Theme.unsupported)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if case .active = exploit.state {
            Text(String(localized: "privilege.state.active.note"))
                .font(.caption)
                .foregroundStyle(Theme.supported)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        Button(String(localized: "privilege.run.trigger")) {
            confirmRun = true
        }
        .buttonStyle(.borderedProminent)
        .disabled(exploit.isRunning)
        .confirmationDialog(
            String(localized: "privilege.run.confirm"),
            isPresented: $confirmRun,
            titleVisibility: .visible
        ) {
            Button(String(localized: "privilege.run.trigger"), role: .destructive) {
                exploit.trigger(verdictSupported: true)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        if exploit.state != .idle && exploit.state != .running {
            Button(String(localized: "privilege.run.reset")) {
                exploit.reset()
            }
            .font(.footnote)
        }
    }

    @State private var confirmRun = false

    private var exploitStateText: String {
        switch exploit.state {
        case .idle: return String(localized: "privilege.state.idle")
        case .running: return String(localized: "privilege.state.running")
        case .active: return String(localized: "privilege.state.active")
        case .failed(let msg): return "\(String(localized: "privilege.state.failed")) · \(msg)"
        }
    }

    private var exploitFailureNote: String {
        if case .failed(let msg) = exploit.state { return msg }
        return ""
    }

    private var socTitle: String {
        access.soC == .unknown ? "—" : access.soC.rawValue.uppercased()
    }

    private var osVersionText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    @ViewBuilder
    private var verdictRow: some View {
        if let verdict = access.verdict {
            HStack {
                Label(String(localized: "privilege.chain"), systemImage: verdict.isSupported ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(verdict.isSupported ? Theme.supported : Theme.unsupported)
                Spacer()
                Text(chainText(verdict))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            if !verdict.isSupported {
                Text(verdict.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            LabeledContent(String(localized: "privilege.chain"), value: "…")
        }
    }

    private func chainText(_ verdict: SupportMatrix.Verdict) -> String {
        guard verdict.isSupported else {
            return String(localized: "privilege.unsupported")
        }
        let tierText: String
        switch verdict.tier {
        case .verified: tierText = String(localized: "privilege.verified")
        case .claimed: tierText = String(localized: "privilege.claimed")
        case .experimental: tierText = String(localized: "privilege.experimental")
        case nil: tierText = ""
        }
        return "\(verdict.chain.rawValue) · \(tierText)"
    }
}
