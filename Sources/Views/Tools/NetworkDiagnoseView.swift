import SwiftUI

/// 网络诊断:连通性 / DNS 解析 / 延迟测试结果。
struct NetworkDiagnoseView: View {
    @StateObject private var viewModel = ToolViewModel()

    var body: some View {
        List {
            Section {
                Button {
                    Task { await viewModel.runNetworkDiagnostics() }
                } label: {
                    if viewModel.isNetworkDiagnosing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(String(localized: "network.diag.running"))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Label(String(localized: "network.diag.start"), systemImage: "play.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(viewModel.isNetworkDiagnosing)
            }

            if !viewModel.pingResults.isEmpty {
                Section(String(localized: "network.diag.ping")) {
                    ForEach(viewModel.pingResults) { result in
                        pingRow(result)
                    }
                }
            }

            if !viewModel.dnsResults.isEmpty {
                Section(String(localized: "network.diag.dns")) {
                    ForEach(viewModel.dnsResults, id: \.self) { ip in
                        Text(ip)
                            .font(.subheadline)
                    }
                }
            }

            if let latency = viewModel.averageLatencyMs {
                Section(String(localized: "network.diag.latency")) {
                    HStack {
                        Text(String(localized: "network.diag.latency.avg"))
                        Spacer()
                        Text(String(format: "%.0f ms", latency))
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }

            if viewModel.pingResults.isEmpty && !viewModel.isNetworkDiagnosing {
                Section {
                    Text(String(localized: "network.diag.no.results"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle(String(localized: "network.diag.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.runNetworkDiagnostics()
        }
    }

    private func pingRow(_ result: PingResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.host)
                .font(.subheadline.weight(.semibold))
            HStack {
                Text("\(String(localized: "network.diag.status.code")) \(result.statusCode.map { String($0) } ?? "—")")
                Spacer()
                if let ms = result.latencyMs {
                    Text(String(format: "%.0f ms", ms))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = result.errorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.unsupported)
            }

            if !result.resolvedIPs.isEmpty {
                Text("\(String(localized: "network.diag.dns")) \(result.resolvedIPs.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
