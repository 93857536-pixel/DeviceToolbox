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
    /// 每个操作独立 busy 标志:共享单一 isBusy 时,并发的第二个操作会被
    /// `guard !isBusy else { return }` 静默丢弃(旧版"点了没反应"的根因之一)。
    @State private var isImporting = false
    @State private var isInstalling = false
    @State private var isProbing = false
    @State private var operationKey = "wallpaper.checking"
    @State private var showImporter = false
    @State private var alert: WallpaperLabAlert?
    /// 内联结果卡片:`.fileImporter` 退场瞬间交付的 alert 可能被 UIKit 丢弃,
    /// 内联卡片保证任何分支(空选择 / picker 失败 / 动态壁纸不支持 / 完成)都有可见结果。
    @State private var notice: WallpaperLabNotice?
    @State private var hasLoaded = false

    /// 遮罩与按钮态只看导入/安装;探针(isProbing)不阻塞导入(与 v1.0.1 的解耦保持一致)。
    private var isWorking: Bool { isImporting || isInstalling }

    var body: some View {
        List {
            accessSection
            if let notice {
                noticeSection(notice)
            }
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
            switch result {
            case .success(let urls):
                if urls.isEmpty {
                    // 之前只有一行日志:用户点完「打开」什么都看不到。
                    Log.info("wallpaper: picker returned empty selection")
                    present(
                        titleKey: "wallpaper.picker_empty_title",
                        message: String(localized: "wallpaper.picker_empty_message"),
                        isFailure: true
                    )
                } else {
                    Log.info("wallpaper: picker returned \(urls.count) url(s)")
                    importPackages(urls)
                }
            case .failure(let error):
                // 之前静默吞掉:选完文件点「打开」后系统取文件失败时无任何反馈。
                Log.warning("wallpaper: file picker failed: \(error.localizedDescription)")
                present(
                    titleKey: "wallpaper.picker_failed_title",
                    message: String(localized: "wallpaper.picker_failed_message"),
                    isFailure: true
                )
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
                    Button(String(localized: "wallpaper.import")) {
                        // 与探针(isProbing)解耦:导入写自己的暂存目录,探针只读 PosterBoard,
                        // 并行安全,不再被探针静默丢弃(旧版共用 isBusy → 点了没反应)。
                        // 忙时不再静默禁用/静默 return:走 beginImport() 弹"稍后重试"。
                        beginImport()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(packages) { package in
                    NavigationLink {
                        WallpaperPackageDetailView(
                            package: package,
                            // 只按真实可写性判断:忙态不再禁用按钮(禁用 = 点了没反应),
                            // 由 install() 的守卫弹"稍后重试"。
                            canInstall: report?.canInstall == true,
                            onApply: {
                                // 可写性未确认时不静默禁用按钮,点一下给明确原因 + 指引。
                                guard report?.canInstall == true else {
                                    Log.warning(
                                        "wallpaper: install blocked — PosterBoard writability " +
                                            "not confirmed (report=\(report == nil ? "nil" : "read-only"))"
                                    )
                                    present(
                                        titleKey: "wallpaper.install_blocked_title",
                                        message: String(localized: "wallpaper.install_blocked_message"),
                                        isFailure: true
                                    )
                                    return
                                }
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

    /// 内联结果卡片:不依赖弹窗时序的可见反馈(可手动关闭)。
    private func noticeSection(_ notice: WallpaperLabNotice) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: notice.isFailure
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .foregroundStyle(notice.isFailure ? Theme.partial : Theme.supported)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: String.LocalizationValue(notice.titleKey)))
                        .font(.subheadline.weight(.semibold))
                    Text(notice.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    self.notice = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "wallpaper.notice_dismiss"))
            }
            .padding(.vertical, 2)
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
            // 常显且不禁用:探针进行中再点会弹"稍后重试",而不是一个按不动的按钮。
            Button { checkAccess() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel(String(localized: "wallpaper.try_again"))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            // 入口常显(铁律 2):忙时不隐藏/不静默禁用,点一下给"稍后重试"提示。
            Button { beginImport() } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "wallpaper.import"))
        }
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
        guard !isProbing else {
            // 守卫命中不再静默 return(旧版:点重试没反应)。
            Log.info("wallpaper: probe blocked — already probing")
            present(
                titleKey: "wallpaper.busy_title",
                message: String(localized: "wallpaper.busy_message"),
                isFailure: true
            )
            return
        }
        isProbing = true
        operationKey = "wallpaper.checking"
        accessError = nil
        Task {
            defer { isProbing = false }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.report() }
            }.value
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

    /// 导入入口(空态按钮与工具栏共用)。入口常显:忙时给可见提示而非静默丢弃。
    private func beginImport() {
        guard !isImporting, !isInstalling else {
            Log.info(
                "wallpaper: import entry blocked (importing=\(isImporting) installing=\(isInstalling))"
            )
            present(
                titleKey: "wallpaper.busy_title",
                message: String(localized: "wallpaper.busy_message"),
                isFailure: true
            )
            return
        }
        notice = nil
        showImporter = true
    }

    private func importPackages(_ urls: [URL]) {
        guard !isImporting else {
            // 旧版静默 return(点了没反应):现在至少弹出提示。
            Log.info("wallpaper: import blocked — busy (isImporting)")
            present(
                titleKey: "wallpaper.busy_title",
                message: String(localized: "wallpaper.busy_message"),
                isFailure: true
            )
            return
        }
        guard !isInstalling else {
            Log.info("wallpaper: import blocked — install in progress")
            present(
                titleKey: "wallpaper.busy_title",
                message: String(localized: "wallpaper.busy_message"),
                isFailure: true
            )
            return
        }
        isImporting = true
        operationKey = "wallpaper.importing"
        Task {
            // 无论正常结束、提前 return 还是异常路径,都保证复位 isImporting ——
            // 卡死的 busy 标志会让之后所有导入被守卫拦下(用户侧仍然是"点了没反应")。
            defer { isImporting = false }
            let outcome = await Task.detached(priority: .userInitiated) {
                () -> WallpaperImportOutcome in
                var imported = 0
                var failures: [String] = []
                var dynamicRejections: [String] = []
                for url in urls {
                    do {
                        _ = try WallpaperPackageStore.importPackage(from: url)
                        imported += 1
                        Log.info("wallpaper: staged \(url.lastPathComponent)")
                    } catch {
                        // 每条失败都带原始错误进日志(便于定位"哪一步静默了")。
                        let reason = wallpaperErrorMessage(error)
                        failures.append("\(url.lastPathComponent): \(reason)")
                        if let labError = error as? WallpaperLabError,
                           case .dynamicContentUnsupported(_) = labError {
                            dynamicRejections.append(url.lastPathComponent)
                        }
                        Log.warning(
                            "wallpaper: import rejected \(url.lastPathComponent): " +
                                "\(error.localizedDescription) → \(reason)"
                        )
                    }
                }
                return WallpaperImportOutcome(
                    attempted: urls.count,
                    imported: imported,
                    failures: failures,
                    dynamicRejections: dynamicRejections
                )
            }.value
            reloadLocalData()
            let titleKey: String
            let message: String
            if outcome.failures.isEmpty {
                titleKey = "wallpaper.import_done_title"
                message = String(localized: "wallpaper.import_done_message \(Int64(outcome.imported))")
            } else {
                // 动态/实况壁纸整体不受支持时给专门标题 + 原因说明,而不是笼统"导入结果"。
                titleKey = outcome.dynamicRejections.isEmpty
                    ? "wallpaper.import_result_title"
                    : "wallpaper.import_dynamic_title"
                message = outcome.dynamicRejections.isEmpty
                    ? outcome.failures.joined(separator: "\n")
                    : outcome.failures.joined(separator: "\n")
                        + "\n\n"
                        + String(localized: "wallpaper.import_dynamic_hint")
            }
            Log.info(
                "wallpaper: import finished attempted=\(outcome.attempted) " +
                    "imported=\(outcome.imported) failed=\(outcome.failures.count) " +
                    "dynamicRejected=\(outcome.dynamicRejections.count)"
            )
            present(titleKey: titleKey, message: message, isFailure: !outcome.failures.isEmpty)
        }
    }

    private func install(_ package: WallpaperStagedPackage) {
        guard !isInstalling else {
            Log.info("wallpaper: install blocked — busy (isInstalling)")
            present(
                titleKey: "wallpaper.busy_title",
                message: String(localized: "wallpaper.busy_message"),
                isFailure: true
            )
            return
        }
        isInstalling = true
        operationKey = "wallpaper.installing"
        Task {
            // 同导入:defer 保证任何路径都复位 isInstalling(卡死会让安装/导入全被守卫拦)。
            defer { isInstalling = false }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WallpaperDeviceAccessService.install(package) }
            }.value
            switch result {
            case .success(let (receipt, refreshedReport)):
                reloadLocalData()
                report = refreshedReport
                Log.info("wallpaper: installed descriptors=\(receipt.installedDescriptors.count)")
                // 不做自动拉起 PosterBoard(去掉私有 API 依赖),提示用户手动打开。
                present(
                    titleKey: "wallpaper.install_done_title",
                    message: String(localized: "wallpaper.install_done_manual"),
                    isFailure: false
                )
            case .failure(let error):
                Log.warning("wallpaper: install failed \(error.localizedDescription)")
                present(
                    titleKey: "wallpaper.operation_failed",
                    message: message(for: error),
                    isFailure: true
                )
            }
        }
    }

    /// 统一反馈出口:内联卡片立即上屏 + 延迟交付 alert。
    ///
    /// 为什么延迟:`.fileImporter` 回调与 picker 退场是同一帧,UIKit 的 presentation
    /// 协调器还在收尾,此时请求 alert 会被**静默丢弃**(无弹窗、无日志、无提示)。
    /// 动态壁纸包常在解压前就被校验拒绝(秒失败),正好落在这个窗口里 —— 这就是
    /// "点了打开完全没有反应"的剩余静默路径。等一格 runloop + 200ms 再交付即可稳定弹出。
    private func present(titleKey: String, message: String, isFailure: Bool) {
        notice = WallpaperLabNotice(titleKey: titleKey, message: message, isFailure: isFailure)
        // 只跨边界传 Sendable 值(String),避免把非 Sendable 的 alert 模型捕获进 @Sendable 闭包。
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            alert = WallpaperLabAlert(
                kind: .message(titleKey: titleKey, message: message)
            )
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
                // 不再 `.disabled(!canInstall)`:禁用按钮 = 点了完全没反应(静默 no-op),
                // 改为常显,点击时由 onApply 给出"未确认可写"的明确提示。
            } footer: {
                if canInstall {
                    Text(String(localized: "wallpaper.after_apply_guide"))
                } else {
                    Text(String(localized: "wallpaper.install_blocked_message"))
                        .foregroundStyle(Theme.partial)
                }
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

/// 内联结果卡片模型(不依赖弹窗时序的可见反馈)。
private struct WallpaperLabNotice: Identifiable {
    let id = UUID()
    let titleKey: String
    let message: String
    let isFailure: Bool
}

/// 跨 detached 任务边界传回的导入结果(值类型,Swift 6 严格并发要求 Sendable)。
private struct WallpaperImportOutcome: Sendable {
    let attempted: Int
    let imported: Int
    let failures: [String]
    let dynamicRejections: [String]
}

/// 壁纸实验室错误 → 本地化文案(非隔离自由函数,可在 detached Task 内调用)。
/// 动态内容不支持时附带探测到的标记(哪类内容不支持),其余沿用 localizationKey。
/// 非 WallpaperLabError 的底层错误回落到系统 `localizedDescription`,避免只显示"未知错误"。
func wallpaperErrorMessage(_ error: Error) -> String {
    if let wallpaperError = error as? WallpaperLabError {
        if case .dynamicContentUnsupported(let detail) = wallpaperError, !detail.isEmpty {
            return String(localized: "wallpaper.error.dynamic_unsupported_detail \(detail)")
        }
        return String(localized: String.LocalizationValue(wallpaperError.localizationKey))
    }
    if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
        return description
    }
    if !error.localizedDescription.isEmpty {
        return error.localizedDescription
    }
    return String(localized: "wallpaper.error.unknown")
}
