// 来源: YangJiiii/3105 (GPLv3),搬运/改写自 ThreeOneOSFive/helpers/WallpaperLabService.swift。
import Foundation
import Darwin

struct WallpaperAccessReport: Equatable, Sendable {
    let layout: WallpaperPosterLayout
    let descriptorCount: Int
    let customDescriptorCount: Int
    let canInstall: Bool
    let deniedExtensionIdentifiers: [String]
}

enum WallpaperAccessProbe {
    static func probe(
        containerURL: URL,
        rootValidator: WallpaperLayoutScanner.RootValidator,
        requiredExtensionIdentifiers: Set<String>? = nil,
        fileManager: FileManager = .default
    ) throws -> WallpaperAccessReport {
        let layout = try WallpaperLayoutScanner.scan(
            containerURL: containerURL,
            rootValidator: rootValidator,
            fileManager: fileManager
        )
        var descriptorCount = 0
        var customDescriptorCount = 0
        for descriptorDirectory in layout.extensionDescriptorDirectories.values {
            let children = (try? fileManager.contentsOfDirectory(
                at: descriptorDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )) ?? []
            for child in children {
                let name = child.lastPathComponent
                if name.hasPrefix(".") && !name.hasPrefix(".3105-wallpaper-") { continue }
                let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                descriptorCount += 1
                if WallpaperDescriptorIdentity.isCustom(at: child, fileManager: fileManager) {
                    customDescriptorCount += 1
                }
            }
        }

        let requiredIdentifiers: [String]
        if let requiredExtensionIdentifiers {
            requiredIdentifiers = requiredExtensionIdentifiers.sorted()
        } else if layout.supportsCollections {
            requiredIdentifiers = [WallpaperPosterLayout.collectionsExtension]
        } else {
            requiredIdentifiers = layout.extensionDescriptorDirectories.keys.sorted()
        }
        var deniedIdentifiers = requiredIdentifiers.filter {
            layout.extensionDescriptorDirectories[$0] == nil
        }

        for identifier in requiredIdentifiers where !deniedIdentifiers.contains(identifier) {
            guard let descriptorDirectory = layout.extensionDescriptorDirectories[identifier] else {
                continue
            }

            let probeURL = descriptorDirectory.appendingPathComponent(
                ".3105-wallpaper-probe-\(UUID().uuidString)",
                isDirectory: true
            )
            let created = mkdir(probeURL.path, 0o700) == 0
            if created {
                let descriptor = open(
                    probeURL.path,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
                if descriptor >= 0 { close(descriptor) }
                if rmdir(probeURL.path) != 0 || descriptor < 0 {
                    deniedIdentifiers.append(identifier)
                    try? fileManager.removeItem(at: probeURL)
                }
            } else {
                deniedIdentifiers.append(identifier)
            }
        }

        return WallpaperAccessReport(
            layout: layout,
            descriptorCount: descriptorCount,
            customDescriptorCount: customDescriptorCount,
            canInstall: !requiredIdentifiers.isEmpty
                && deniedIdentifiers.isEmpty,
            deniedExtensionIdentifiers: deniedIdentifiers
        )
    }
}

enum WallpaperDeviceAccessService {
    static func report(
        requiredExtensionIdentifiers: Set<String>? = nil
    ) throws -> WallpaperAccessReport {
        guard let path = PosterBoardResolver.resolveContainerPath(
            bundleID: PosterBoardResolver.posterBoardBundleID
        ) else {
            throw WallpaperLabError.accessDenied
        }
        return try WallpaperAccessProbe.probe(
            containerURL: URL(fileURLWithPath: path, isDirectory: true),
            rootValidator: { PosterBoardResolver.isApplicationContainerPath($0.path) },
            requiredExtensionIdentifiers: requiredExtensionIdentifiers
        )
    }

    static func install(
        _ package: WallpaperStagedPackage
    ) throws -> (WallpaperInstallReceipt, WallpaperAccessReport) {
        let requiredExtensions = Set(
            package.payload.descriptors.map(\.extensionIdentifier)
        )
        let currentReport = try report(
            requiredExtensionIdentifiers: requiredExtensions
        )
        guard currentReport.canInstall else {
            throw WallpaperLabError.accessDenied
        }
        let backupRoot = try WallpaperPackageStore.backupRoot()
        let receipt = try WallpaperInstaller.install(
            payload: package.payload,
            layout: currentReport.layout,
            backupRoot: backupRoot
        )
        do {
            try WallpaperPackageStore.delete(package)
        } catch {
            Log.info("wallpaper: staged package leftover after apply")
        }
        return (
            receipt,
            try report(requiredExtensionIdentifiers: requiredExtensions)
        )
    }

    static func resetCustomCollections() throws -> (Int, WallpaperAccessReport) {
        let currentReport = try report()
        guard currentReport.canInstall else {
            throw WallpaperLabError.accessDenied
        }
        guard let path = PosterBoardResolver.resolveContainerPath(
            bundleID: PosterBoardResolver.posterBoardBundleID
        ) else {
            throw WallpaperLabError.accessDenied
        }
        let containerURL = URL(fileURLWithPath: path, isDirectory: true)
        let backupRoot = try WallpaperPackageStore.backupRoot()
        let removed = try WallpaperInstaller.resetCustomDescriptors(
            layout: currentReport.layout,
            containerURL: containerURL,
            rootValidator: { PosterBoardResolver.isApplicationContainerPath($0.path) },
            backupRoot: backupRoot
        )
        return (removed, try report())
    }
}

struct WallpaperStagedPackage: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let repositoryIdentity: String?
    let packageDirectoryURL: URL
    let archiveURL: URL
    let extractedURL: URL
    let payload: TendiesPayload
    let importedAt: Date
}

enum WallpaperPackageStore {
    private static let archiveName = "wallpaper.tendies"
    private static let extractedName = "Extracted"
    private static let metadataName = "metadata.plist"

    static func stagingRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try applicationSupportURL(fileManager: fileManager)
        let url = base.appendingPathComponent("WallpaperLab/Packages", isDirectory: true)
        try createApprovedDirectory(url, fileManager: fileManager)
        return url
    }

    static func backupRoot(fileManager: FileManager = .default) throws -> URL {
        let base = try applicationSupportURL(fileManager: fileManager)
        let url = base.appendingPathComponent("WallpaperLab/Backups", isDirectory: true)
        try createApprovedDirectory(url, fileManager: fileManager)
        return url
    }

    static func importPackage(
        from sourceURL: URL,
        displayName: String? = nil,
        repositoryIdentity: String? = nil,
        fileManager: FileManager = .default
    ) throws -> WallpaperStagedPackage {
        guard sourceURL.pathExtension.lowercased() == "tendies" else {
            Log.warning(
                "wallpaper: import rejected \(sourceURL.lastPathComponent): " +
                    "extension '\(sourceURL.pathExtension)' is not .tendies"
            )
            throw WallpaperLabError.unsupportedPackage
        }
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let values: URLResourceValues
        do {
            values = try sourceURL.resourceValues(
                forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
                ]
            )
        } catch {
            // 安全域 URL 失效 / 读取失败,此前被误报为"不支持的包"。
            Log.warning("wallpaper: import rejected \(sourceURL.lastPathComponent): properties unreadable (\(error.localizedDescription))")
            throw WallpaperLabError.importReadFailed
        }
        // iCloud 占位符显式检测:属性可读、体积看似正常,但内容未落地 —— 复制时才失败且报错含糊,
        // 用户侧表现为"选完文件点打开后一片安静"。这里提前给出明确原因并尽力请求系统开始下载。
        if values.isUbiquitousItem == true,
           let status = values.ubiquitousItemDownloadingStatus,
           status != .current, status != .downloaded {
            Log.warning(
                "wallpaper: import rejected \(sourceURL.lastPathComponent): " +
                    "iCloud item not downloaded (status=\(status.rawValue)); requesting download"
            )
            try? fileManager.startDownloadingUbiquitousItem(at: sourceURL)
            throw WallpaperLabError.importCloudNotDownloaded
        }
        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            if values.isSymbolicLink == true {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            Log.warning("wallpaper: import rejected \(sourceURL.lastPathComponent): not a readable regular file (regular=\(String(describing: values.isRegularFile)))")
            throw WallpaperLabError.importReadFailed
        }
        let size = Int64(values.fileSize ?? 0)
        guard size > 0 else {
            // 0 字节 = 空文件(真正的 iCloud 占位符已在上面的 ubiquitous 分支单独识别)。
            Log.warning(
                "wallpaper: import rejected \(sourceURL.lastPathComponent): " +
                    "zero-byte source (empty file)"
            )
            throw WallpaperLabError.importReadFailed
        }
        guard size <= WallpaperLabLimits.maximumArchiveBytes else {
            Log.warning(
                "wallpaper: import rejected \(sourceURL.lastPathComponent): " +
                    "size=\(size) exceeds limit=\(WallpaperLabLimits.maximumArchiveBytes)"
            )
            throw WallpaperLabError.packageTooLarge
        }
        let resolvedDisplayName = (
            displayName ?? sourceURL.deletingPathExtension().lastPathComponent
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidMetadataText(resolvedDisplayName, maximumBytes: 255),
              repositoryIdentity.map({
                  isValidMetadataText($0, maximumBytes: 4_096)
              }) ?? true else {
            Log.warning(
                "wallpaper: import rejected \(sourceURL.lastPathComponent): " +
                    "invalid display name (bytes=\(resolvedDisplayName.utf8.count))"
            )
            throw WallpaperLabError.unsupportedPackage
        }

        let root = try stagingRoot(fileManager: fileManager)
        let id = UUID()
        let importingURL = root.appendingPathComponent(
            ".importing-\(id.uuidString)",
            isDirectory: true
        )
        let finalURL = root.appendingPathComponent(id.uuidString, isDirectory: true)
        // 记录失败发生在哪个阶段:外层 catch 据此给出**正确**的错误类别,
        // 不再把磁盘/写入问题一律误导成"读不到文件"(或反之)。
        var stage = "staging"
        do {
            try fileManager.createDirectory(
                at: importingURL,
                withIntermediateDirectories: false
            )
            stage = "copy"
            let archiveURL = importingURL.appendingPathComponent(archiveName)
            try fileManager.copyItem(at: sourceURL, to: archiveURL)
            Log.info(
                "wallpaper: staged source bytes=\(size) \(sourceURL.lastPathComponent)"
            )
            stage = "extract"
            let extractedURL = importingURL.appendingPathComponent(
                extractedName,
                isDirectory: true
            )
            // 复用 DeviceToolbox 自带 ZIP 栈(自带 CRC/zip-slip/大小/条目上限校验)。
            do {
                _ = try ZipArchiveService.extract(archive: archiveURL, to: extractedURL)
            } catch let error as FileOperationError {
                // 解压失败此前无日志、且一律映射成"不支持的包"(把磁盘满/解压中断/I-O 全说成格式问题)。
                Log.warning(
                    "wallpaper: extract failed \(sourceURL.lastPathComponent): " +
                        "\(error.localizedDescription)"
                )
                switch error {
                case .unsafeArchive: throw WallpaperLabError.unsafeArchive
                case .symbolicLinkUnsupported: throw WallpaperLabError.symbolicLinkUnsupported
                case .cannotExtract, .cannotRead, .cannotArchive, .cannotCreate,
                     .cannotImport, .cannotCopy, .cannotMove, .cannotDelete,
                     .destinationMissing, .insufficientSpace:
                    // 解压/落盘侧 I/O 失败:单独 case,不要误报成"不支持的包"。
                    throw WallpaperLabError.importWriteFailed
                default: throw WallpaperLabError.unsupportedPackage
                }
            }
            _ = try TendiesPackageInspector.inspectExtractedPackage(
                at: extractedURL,
                fileManager: fileManager
            )
            let metadata = PackageMetadata(
                id: id,
                displayName: resolvedDisplayName,
                repositoryIdentity: repositoryIdentity,
                importedAt: Date()
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            stage = "metadata"
            try encoder.encode(metadata).write(
                to: importingURL.appendingPathComponent(metadataName),
                options: .atomic
            )
            stage = "commit"
            guard rename(importingURL.path, finalURL.path) == 0 else {
                throw WallpaperLabError.importWriteFailed
            }
            stage = "verify"
            let importedPackage = try loadPackage(
                at: finalURL,
                fileManager: fileManager
            )
            if let repositoryIdentity {
                for existingPackage in packages(fileManager: fileManager)
                where existingPackage.id != importedPackage.id
                    && existingPackage.repositoryIdentity == repositoryIdentity {
                    do {
                        try delete(existingPackage, fileManager: fileManager)
                    } catch {
                        Log.warning(
                            "wallpaper: previous staged package kept " +
                                "\(existingPackage.id.uuidString): \(error.localizedDescription)"
                        )
                    }
                }
            }
            return importedPackage
        } catch let error as WallpaperLabError {
            try? fileManager.removeItem(at: importingURL)
            throw error
        } catch {
            // 底层(非 WallpaperLabError)失败:此前无日志地吞成 unsupportedPackage,
            // 用户拿到的是完全不着边际的"不支持的包"。现在带上失败阶段 + 原始描述。
            Log.warning(
                "wallpaper: import failed stage=\(stage) " +
                    "\(sourceURL.lastPathComponent): \(error.localizedDescription)"
            )
            try? fileManager.removeItem(at: importingURL)
            // 只有"取副本"这一步的失败才是读取侧问题(iCloud 未落地 / 安全域 URL 失效);
            // 建暂存目录、写元数据、提交改名、落盘之类都是写入侧问题 —— 分开报,别互相误导。
            throw stage == "copy"
                ? WallpaperLabError.importReadFailed
                : WallpaperLabError.importWriteFailed
        }
    }

    static func packages(fileManager: FileManager = .default) -> [WallpaperStagedPackage] {
        guard let root = try? stagingRoot(fileManager: fileManager),
              let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return directories.compactMap { directory in
            guard UUID(uuidString: directory.lastPathComponent) != nil else { return nil }
            do {
                return try loadPackage(at: directory, fileManager: fileManager)
            } catch {
                // 之前是 `try?`:导入"成功"但列表里不出现的现象没有任何线索(静默丢弃)。
                Log.warning(
                    "wallpaper: staged package unreadable \(directory.lastPathComponent): " +
                        "\(error.localizedDescription)"
                )
                return nil
            }
        }.sorted { $0.importedAt > $1.importedAt }
    }

    static func contains(
        repositoryIdentity: String,
        fileManager: FileManager = .default
    ) -> Bool {
        packages(fileManager: fileManager).contains {
            $0.repositoryIdentity == repositoryIdentity
        }
    }

    static func delete(
        _ package: WallpaperStagedPackage,
        fileManager: FileManager = .default
    ) throws {
        let root = try stagingRoot(fileManager: fileManager)
        guard package.packageDirectoryURL.deletingLastPathComponent().standardizedFileURL
                == root.standardizedFileURL,
              package.packageDirectoryURL.lastPathComponent == package.id.uuidString else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(
            package.packageDirectoryURL,
            fileManager: fileManager
        )
        try fileManager.removeItem(at: package.packageDirectoryURL)
    }

    private static func loadPackage(
        at directory: URL,
        fileManager: FileManager
    ) throws -> WallpaperStagedPackage {
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let metadataData = try Data(contentsOf: directory.appendingPathComponent(metadataName))
        let metadata = try PropertyListDecoder().decode(PackageMetadata.self, from: metadataData)
        guard directory.lastPathComponent == metadata.id.uuidString,
              !metadata.displayName.isEmpty,
              metadata.displayName.utf8.count <= 255 else {
            throw WallpaperLabError.unsupportedPackage
        }
        let archiveURL = directory.appendingPathComponent(archiveName)
        let extractedURL = directory.appendingPathComponent(extractedName, isDirectory: true)
        let payload = try TendiesPackageInspector.inspectExtractedPackage(
            at: extractedURL,
            fileManager: fileManager
        )
        return WallpaperStagedPackage(
            id: metadata.id,
            displayName: metadata.displayName,
            repositoryIdentity: metadata.repositoryIdentity,
            packageDirectoryURL: directory,
            archiveURL: archiveURL,
            extractedURL: extractedURL,
            payload: payload,
            importedAt: metadata.importedAt
        )
    }

    private static func applicationSupportURL(fileManager: FileManager) throws -> URL {
        guard let url = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw WallpaperLabError.accessDenied
        }
        try createApprovedDirectory(url, fileManager: fileManager)
        return url
    }

    private static func createApprovedDirectory(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: url.path) {
            try WallpaperLayoutScanner.validateDirectory(url, fileManager: fileManager)
        } else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func isValidMetadataText(
        _ value: String,
        maximumBytes: Int
    ) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            )
    }
}

private struct PackageMetadata: Codable {
    let id: UUID
    let displayName: String
    let repositoryIdentity: String?
    let importedAt: Date
}
