import SwiftUI
import UIKit

/// 操作日志页:展示内存环形缓冲中的最近日志,级别着色,顶部过滤(全部/错误),
/// 底部复制(UIPasteboard)/分享(ShareLink)。
@MainActor
struct LogView: View {
    @State private var showErrorsOnly = false
    @State private var entries: [LogEntry] = []
    @State private var showCopied = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showErrorsOnly) {
                Text(String(localized: "logviewer.filter.all")).tag(false)
                Text(String(localized: "logviewer.filter.error")).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if entries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            bottomBar
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "logviewer.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Log.clearBuffer()
                    reload()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(String(localized: "logviewer.clear"))
            }
        }
        .alert(String(localized: "logviewer.copied"), isPresented: $showCopied) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
        .onAppear { reload() }
        .onChange(of: showErrorsOnly) { _, _ in reload() }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent.opacity(0.6))
            Text(String(localized: "logviewer.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 行

    private func row(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(entry.level.tag)
                    .font(.caption2.bold())
                    .foregroundStyle(levelColor(entry.level))
                Spacer()
            }
            Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Text("\(entry.file):\(entry.line)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return Theme.accent
        case .warning: return Theme.partial
        case .error: return Theme.unsupported
        }
    }

    // MARK: - 底栏

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = exportText
                showCopied = true
            } label: {
                Label(String(localized: "logviewer.copy"), systemImage: "doc.on.doc")
            }
            .disabled(entries.isEmpty)

            if !exportText.isEmpty {
                ShareLink(item: exportText) {
                    Label(String(localized: "logviewer.share"), systemImage: "square.and.arrow.up")
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - 逻辑

    private func reload() {
        entries = Log.entries(levelFilter: showErrorsOnly ? .error : nil)
    }

    private var exportText: String {
        Log.exportText(levelFilter: showErrorsOnly ? .error : nil)
    }
}
