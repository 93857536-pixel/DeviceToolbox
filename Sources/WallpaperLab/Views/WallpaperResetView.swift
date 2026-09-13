// 来源: YangJiiii/3105 (GPLv3),搬运/改写自 ThreeOneOSFive/views/WallpaperLabView.swift(WallpaperResetSettingsView)。
import SwiftUI

/// 壁纸重置页:显示已添加的自定义壁纸数量,并可删除全部自定义 descriptor(保留 Apple 默认)。
@MainActor
struct WallpaperResetView: View {
    @State private var report: WallpaperAccessReport?
    /// 探针与重置各自独立(共享标志会把并发操作静默丢弃)。
    @State private var isProbing = false
    @State private var isResetting = false
    @State private var operationKey = "wallpaper.checking"
    @State private var alert: WallpaperResetAlert?

    private var isWorking: Bool { isProbing || isResetting }

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
                } else if !isWorking {
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
                        // 不再 `.disabled(!report.canInstall)`:禁用按钮 = 点了完全没反应。
                        // 常显 + 守卫命中时给出"未确认可写"的明确原因与指引。
                        guard report.canInstall else {
                            Log.warning("wallpaper: reset blocked — PosterBoard not writable (read-only)")
                            deliver(
                                WallpaperResetAlert(
                                    kind: .failure(
                                        String(localized: "wallpaper.install_blocked_message")
                                    )
                                )
                            )
                            return
                        }
                        alert = WallpaperResetAlert(kind: .confirm)
                    } label: {
                        Label(
                            String(localized: "wallpaper.reset"),
                            systemImage: "arrow.counterclockwise"
                        )
                    }
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
                // 常显且不禁用:进行中再点会弹"稍后重试",而不是一个按不动的按钮。
                Button(action: checkAccess) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "wallpaper.try_again"))
            }
        }
        .overlay { busyOverlay }
        .alert(item: $alert, content: alertContent)
        .onAppear(perform: checkAccess)
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if isWorking {
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
        guard !isProbing else {
            // 守卫命中弹提示,不再静默 return(点了没反应)。
            Log.info("wallpaper: reset probe blocked — already probing")
            presentBusy()
            return
        }
        isProbing = true
        operationKey = "wallpaper.checking"
        Task {
            // defer 保证任何路径都复位(卡死的 busy 会让之后所有操作被守卫拦)。
            defer { isProbing = false }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.report() }
            }.value
            switch result {
            case .success(let newReport):
                report = newReport
            case .failure(let error):
                report = nil
                Log.warning("wallpaper: reset probe failed \(error.localizedDescription)")
                deliver(WallpaperResetAlert(kind: .failure(wallpaperErrorMessage(error))))
            }
        }
    }

    private func resetCollections() {
        guard !isResetting else {
            Log.info("wallpaper: reset blocked — busy (isResetting)")
            presentBusy()
            return
        }
        isResetting = true
        operationKey = "wallpaper.restoring"
        Task {
            defer { isResetting = false }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.resetCustomCollections() }
            }.value
            switch result {
            case .success(let (removed, refreshedReport)):
                report = refreshedReport
                Log.info("wallpaper: reset removed \(removed) custom descriptors")
                deliver(WallpaperResetAlert(kind: .success))
            case .failure(let error):
                Log.warning("wallpaper: reset failed \(error.localizedDescription)")
                deliver(WallpaperResetAlert(kind: .failure(wallpaperErrorMessage(error))))
            }
        }
    }

    private func presentBusy() {
        deliver(
            WallpaperResetAlert(kind: .failure(String(localized: "wallpaper.busy_message")))
        )
    }

    /// 延迟交付 alert:确认弹窗被点掉后的同一帧里请求新 alert 会被 UIKit 静默丢弃
    /// (旧版"点了没反应"的同一类问题),等一格 runloop + 200ms 再交付。
    private func deliver(_ newAlert: WallpaperResetAlert) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            alert = newAlert
        }
    }
}

private struct WallpaperResetAlert: Identifiable, Sendable {
    let id = UUID()
    let kind: Kind

    enum Kind: Sendable {
        case confirm
        case success
        case failure(String)
    }
}
