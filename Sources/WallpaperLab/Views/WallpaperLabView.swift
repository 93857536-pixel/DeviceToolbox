// 来源: YangJiiii/3105 (GPLv3),搬运/改写自 ThreeOneOSFive/views/WallpaperLabView.swift。
import SwiftUI
import UniformTypeIdentifiers

private enum WallpaperPickerPolicy {
    static let packageType = UTType(filenameExtension: "tendies") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
}

/// PosterBoard 壁纸实验室:导入 .tendies 壁纸包并写入 PosterBoard 扩展数据存储。
/// 模拟器上 `PosterBoardResolver` 恒返回 nil,入口显示「仅真机可用」而不崩溃。
@MainActor
struct WallpaperLabView: View {
    @State private var report: WallpaperAccessReport?
    @State private var accessError: String?
    @State private var packages: [WallpaperStagedPackage] = []
    @State private var isBusy = false
    @State private var operationKey = "wallpaper.checking"
    @State private var showImporter = false
    @State private var alert: WallpaperLabAlert?
    @State private var hasLoaded = false

    var body: some View {
        List {
            accessSection
            packagesSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(String(localized: "wallpaper.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay { busyOverlay }
        .alert(item: $alert, content: alertContent)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: WallpaperPickerPolicy.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            showImporter = false
            if case .success(let urls) = result, !urls.isEmpty {
                importPackages(urls)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            reloadLocalData()
            checkAccess()
        }
    }

    private var accessSection: some View {
        Section {
            if let report {
                HStack {
                    Label(
                        String(localized: report.canInstall
                            ? "wallpaper.access_ready"
                            : "wallpaper.access_read_only"),
                        systemImage: report.canInstall
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.canInstall ? Theme.supported : Theme.partial)
                    Spacer()
                    Text("MHA-C2")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(
                    String(localized: "wallpaper.store_summary \(report.layout.generation) \(Int64(report.layout.extensionDescriptorDirectories.count)) \(Int64(report.descriptorCount))")
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            } else if let accessError {
                Label(accessError, systemImage: "xmark.shield.fill")
                    .foregroundStyle(.red)
                Button(String(localized: "wallpaper.try_again")) { checkAccess() }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(String(localized: "wallpaper.checking"))
                }
            }
        } header: { Text(String(localized: "wallpaper.access")) }
    }

    private var packagesSection: some View {
        Section {
            if packages.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Theme.accent)
                    Text(String(localized: "wallpaper.empty_packages"))
                        .font(.headline)
                    Text(String(localized: "wallpaper.empty_packages_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "wallpaper.import")) { showImporter = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(packages) { package in
                    NavigationLink {
                        WallpaperPackageDetailView(
                            package: package,
                            canInstall: report?.canInstall == true && !isBusy,
                            onApply: {
                                alert = WallpaperLabAlert(kind: .install(package))
                            }
                        )
                    } label: {
                        packageRow(package)
                    }
                }
            }
        } header: {
            Text(String(localized: "wallpaper.packages"))
        } footer: {
            Text(String(localized: "wallpaper.after_apply_guide"))
        }
    }

    private func packageRow(_ package: WallpaperStagedPackage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(package.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(
                    String(localized: "wallpaper.package_summary \(Int64(package.payload.descriptors.count)) \(sizeText(package.payload.totalBytes))")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { checkAccess() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isBusy)
            .accessibilityLabel(String(localized: "wallpaper.try_again"))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showImporter = true } label: {
                Image(systemName: "plus")
            }
            .disabled(isBusy)
            .accessibilityLabel(String(localized: "wallpaper.import"))
        }
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func alertContent(_ alert: WallpaperLabAlert) -> Alert {
        switch alert.kind {
        case .install(let package):
            return Alert(
                title: Text(String(localized: "wallpaper.install_warning_title")),
                message: Text(
                    String(localized: "wallpaper.install_warning_message \(package.displayName) \(Int64(package.payload.descriptors.count)) \(osVersion) \(osBuild)")
                ),
                primaryButton: .destructive(Text(String(localized: "wallpaper.install"))) {
                    install(package)
                },
                secondaryButton: .cancel(Text(String(localized: "common.cancel")))
            )
        case .message(let titleKey, let message):
            return Alert(
                title: Text(String(localized: String.LocalizationValue(titleKey))),
                message: Text(message),
                dismissButton: .default(Text(String(localized: "common.ok")))
            )
        }
    }

    private func reloadLocalData() {
        packages = WallpaperPackageStore.packages()
    }

    private func checkAccess() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.checking"
        accessError = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.report() }
            }.value
            isBusy = false
            switch result {
            case .success(let newReport):
                report = newReport
                Log.info(
                    "wallpaper: probe generation=\(newReport.layout.generation) " +
                        "extensions=\(newReport.layout.extensionDescriptorDirectories.count) " +
                        "writable=\(newReport.canInstall)"
                )
            case .failure(let error):
                report = nil
                accessError = message(for: error)
                Log.info("wallpaper: probe failed \(error.localizedDescription)")
            }
        }
    }

    private func importPackages(_ urls: [URL]) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.importing"
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (imported: Int, failures: [String]) in
                var imported = 0
                var failures: [String] = []
                for url in urls {
                    do {
                        _ = try WallpaperPackageStore.importPackage(from: url)
                        imported += 1
                        Log.info("wallpaper: staged \(url.lastPathComponent)")
                    } catch {
                        failures.append("\(url.lastPathComponent): \(wallpaperErrorMessage(error))")
                        Log.info("wallpaper: import rejected \(url.lastPathComponent)")
                    }
                }
                return (imported, failures)
            }.value
            isBusy = false
            reloadLocalData()
            alert = WallpaperLabAlert(
                kind: .message(
                    titleKey: outcome.failures.isEmpty
                        ? "wallpaper.import_done_title" : "wallpaper.import_result_title",
                    message: outcome.failures.isEmpty
                        ? String(localized: "wallpaper.import_done_message \(Int64(outcome.imported))")
                        : outcome.failures.joined(separator: "\n")
                )
            )
        }
    }

    private func install(_ package: WallpaperStagedPackage) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.installing"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.install(package) }
            }.value
            isBusy = false
            switch result {
            case .success(let (receipt, refreshedReport)):
                reloadLocalData()
                report = refreshedReport
                Log.info("wallpaper: installed descriptors=\(receipt.installedDescriptors.count)")
                // 不做自动拉起 PosterBoard(去掉私有 API 依赖),提示用户手动打开。
                alert = WallpaperLabAlert(
                    kind: .message(
                        titleKey: "wallpaper.install_done_title",
                        message: String(localized: "wallpaper.install_done_manual")
                    )
                )
            case .failure(let error):
                Log.info("wallpaper: install failed \(error.localizedDescription)")
                alert = WallpaperLabAlert(
                    kind: .message(
                        titleKey: "wallpaper.operation_failed",
                        message: message(for: error)
                    )
                )
            }
        }
    }

    private var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private var osBuild: String {
        SupportPolicy.currentBuildNumber ?? "-"
    }

    private func message(for error: Error) -> String {
        wallpaperErrorMessage(error)
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct WallpaperPackageDetailView: View {
    let package: WallpaperStagedPackage
    let canInstall: Bool
    let onApply: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 52, height: 52)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(package.displayName)
                            .font(.title3.weight(.bold))
                        Text(String(localized: "wallpaper.package_summary \(Int64(package.payload.descriptors.count)) \(sizeText(package.payload.totalBytes))"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "wallpaper.package_files \(Int64(package.payload.fileCount))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section(String(localized: "wallpaper.package_details")) {
                ForEach(package.payload.descriptors) { descriptor in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(descriptor.directoryURL.lastPathComponent)
                            .font(.body.weight(.semibold))
                        Text(descriptor.extensionIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(
                            "\(descriptor.fileCount) · \(sizeText(descriptor.byteCount))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                Button(action: onApply) {
                    Text(String(localized: "wallpaper.install"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall)
            } footer: {
                Text(String(localized: "wallpaper.after_apply_guide"))
            }
        }
        .listStyle(.insetGrouped)
        
        .navigationTitle(package.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct WallpaperLabAlert: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case install(WallpaperStagedPackage)
        case message(titleKey: String, message: String)
    }
}

/// 壁纸实验室错误 → 本地化文案(非隔离自由函数,可在 detached Task 内调用)。
func wallpaperErrorMessage(_ error: Error) -> String {
    if let wallpaperError = error as? WallpaperLabError {
        return String(localized: String.LocalizationValue(wallpaperError.localizationKey))
    }
    return String(localized: "wallpaper.error.unknown")
}
