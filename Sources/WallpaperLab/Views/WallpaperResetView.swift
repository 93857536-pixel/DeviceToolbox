// 来源: YangJiiii/3105 (GPLv3),搬运/改写自 ThreeOneOSFive/views/WallpaperLabView.swift(WallpaperResetSettingsView)。
import SwiftUI

/// 壁纸重置页:显示已添加的自定义壁纸数量,并可删除全部自定义 descriptor(保留 Apple 默认)。
@MainActor
struct WallpaperResetView: View {
    @State private var report: WallpaperAccessReport?
    @State private var isBusy = false
    @State private var operationKey = "wallpaper.checking"
    @State private var alert: WallpaperResetAlert?

    var body: some View {
        List {
            Section(String(localized: "wallpaper.access")) {
                if let report {
                    Label(
                        String(localized: report.canInstall
                            ? "wallpaper.access_ready"
                            : "wallpaper.access_read_only"),
                        systemImage: report.canInstall
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.canInstall ? Theme.supported : Theme.partial)
                    LabeledContent(String(localized: "wallpaper.custom_count")) {
                        Text("\(report.customDescriptorCount)")
                            .monospacedDigit()
                    }
                } else if !isBusy {
                    Label(
                        String(localized: "wallpaper.error.access"),
                        systemImage: "xmark.shield.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            if let report, report.customDescriptorCount > 0 {
                Section {
                    Button(role: .destructive) {
                        alert = WallpaperResetAlert(kind: .confirm)
                    } label: {
                        Label(
                            String(localized: "wallpaper.reset"),
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .disabled(isBusy || !report.canInstall)
                } footer: {
                    Text(String(localized: "wallpaper.reset_footer"))
                }
            } else if report != nil {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Theme.accent)
                        Text(String(localized: "wallpaper.no_custom_title"))
                            .font(.headline)
                        Text(String(localized: "wallpaper.no_custom_message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(String(localized: "wallpaper.reset"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: checkAccess) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isBusy)
                .accessibilityLabel(String(localized: "wallpaper.try_again"))
            }
        }
        .overlay { busyOverlay }
        .alert(item: $alert, content: alertContent)
        .onAppear(perform: checkAccess)
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if isBusy {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: String.LocalizationValue(operationKey)))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
    }

    private func alertContent(_ alert: WallpaperResetAlert) -> Alert {
        switch alert.kind {
        case .confirm:
            return Alert(
                title: Text(String(localized: "wallpaper.reset_title")),
                message: Text(
                    String(localized: "wallpaper.reset_message \(Int64(report?.customDescriptorCount ?? 0))")
                ),
                primaryButton: .destructive(
                    Text(String(localized: "wallpaper.reset")),
                    action: resetCollections
                ),
                secondaryButton: .cancel(Text(String(localized: "common.cancel")))
            )
        case .success:
            return Alert(
                title: Text(String(localized: "wallpaper.reset_done_title")),
                message: Text(String(localized: "wallpaper.reset_done_message")),
                dismissButton: .default(Text(String(localized: "common.ok")))
            )
        case .failure(let message):
            return Alert(
                title: Text(String(localized: "wallpaper.operation_failed")),
                message: Text(message),
                dismissButton: .default(Text(String(localized: "common.ok")))
            )
        }
    }

    private func checkAccess() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.checking"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.report() }
            }.value
            isBusy = false
            switch result {
            case .success(let newReport):
                report = newReport
            case .failure(let error):
                report = nil
                alert = WallpaperResetAlert(kind: .failure(wallpaperErrorMessage(error)))
            }
        }
    }

    private func resetCollections() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.restoring"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.resetCustomCollections() }
            }.value
            isBusy = false
            switch result {
            case .success(let (removed, refreshedReport)):
                report = refreshedReport
                Log.info("wallpaper: reset removed \(removed) custom descriptors")
                alert = WallpaperResetAlert(kind: .success)
            case .failure(let error):
                alert = WallpaperResetAlert(kind: .failure(wallpaperErrorMessage(error)))
            }
        }
    }
}

private struct WallpaperResetAlert: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case confirm
        case success
        case failure(String)
    }
}
