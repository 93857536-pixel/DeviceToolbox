// 来源: YangJiiii/3105 (GPLv3),搬运/改写自 ThreeOneOSFive/helpers/WallpaperLabModels.swift。
import Foundation

enum WallpaperLabError: Error, Equatable, Sendable {
    case unsafeContainerRoot
    case posterStoreUnavailable
    case unsupportedPosterLayout
    case unsupportedPackage
    case unsafeArchive
    case symbolicLinkUnsupported
    case packageTooLarge
    case noDescriptors
    case accessDenied
    case importReadFailed
    case backupFailed
    case installFailed
    case restoreFailed
}

extension WallpaperLabError: LocalizedError {
    var localizationKey: String {
        switch self {
        case .unsafeContainerRoot: return "wallpaper.error.unsafe_container"
        case .posterStoreUnavailable: return "wallpaper.error.store_unavailable"
        case .unsupportedPosterLayout: return "wallpaper.error.layout"
        case .unsupportedPackage: return "wallpaper.error.package"
        case .unsafeArchive: return "wallpaper.error.archive"
        case .symbolicLinkUnsupported: return "wallpaper.error.symlink"
        case .packageTooLarge: return "wallpaper.error.size"
        case .noDescriptors: return "wallpaper.error.no_descriptors"
        case .accessDenied: return "wallpaper.error.access"
        case .importReadFailed: return "wallpaper.error.read_failed"
        case .backupFailed: return "wallpaper.error.backup"
        case .installFailed: return "wallpaper.error.install"
        case .restoreFailed: return "wallpaper.error.restore"
        }
    }

    var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

enum WallpaperLabLimits {
    static let maximumArchiveBytes: Int64 = 512 * 1_024 * 1_024
    static let maximumExpandedBytes: Int64 = 768 * 1_024 * 1_024
    static let maximumEntryBytes: Int64 = 256 * 1_024 * 1_024
    static let maximumEntryCount = 20_000
    static let maximumDescriptorCount = 64
    static let maximumPathBytes = 4_096
}

struct WallpaperPosterLayout: Equatable, Sendable {
    static let collectionsExtension = "com.apple.WallpaperKit.CollectionsPoster"
    static let photosExtension = "com.apple.PhotosUIPrivate.PhotosPosterProvider"
    static let mercuryExtension = "com.apple.MercuryPoster"

    let generation: String
    let storeURL: URL
    let extensionDescriptorDirectories: [String: URL]

    var supportsCollections: Bool {
        extensionDescriptorDirectories[Self.collectionsExtension] != nil
    }

    var supportsVideo: Bool {
        extensionDescriptorDirectories[Self.photosExtension] != nil
    }
}

struct WallpaperDescriptorSource: Equatable, Identifiable, Sendable {
    let extensionIdentifier: String
    let directoryURL: URL
    let byteCount: Int64
    let fileCount: Int
    let isOrdered: Bool

    var id: String { "\(extensionIdentifier):\(directoryURL.path)" }
}

struct TendiesPayload: Equatable, Sendable {
    let descriptors: [WallpaperDescriptorSource]
    let totalBytes: Int64
    let fileCount: Int
}

enum WallpaperLayoutScanner {
    static let storeRelativePath = "Library/Application Support/PRBPosterExtensionDataStore"

    typealias RootValidator = (URL) -> Bool

    static func scan(
        containerURL rawContainerURL: URL,
        rootValidator: RootValidator,
        fileManager: FileManager = .default
    ) throws -> WallpaperPosterLayout {
        let containerURL = rawContainerURL.standardizedFileURL
        guard containerURL.isFileURL,
              containerURL.path.hasPrefix("/"),
              containerURL.path != "/",
              rootValidator(containerURL) else {
            Log.info("[WallpaperLabScan] reject: rootValidator failed for \(containerURL.path)")
            throw WallpaperLabError.unsafeContainerRoot
        }
        Log.info("[WallpaperLabScan] container=\(containerURL.path)")
        if #available(iOS 15.0, *) {
            Log.info(
                "[WallpaperLabScan] device=\(ProcessInfo.processInfo.operatingSystemVersionString) " +
                "build=\(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil ? "device" : "simulator")"
            )
        }
        try validateDirectory(containerURL, fileManager: fileManager)

        let storeURL = containerURL.appendingPathComponent(
            storeRelativePath,
            isDirectory: true
        )
        Log.info("[WallpaperLabScan] store=\(storeURL.path) exists=\(fileManager.fileExists(atPath: storeURL.path)) storeRelative=\(storeRelativePath)")
        guard isContained(storeURL, in: containerURL),
              fileManager.fileExists(atPath: storeURL.path) else {
            throw WallpaperLabError.posterStoreUnavailable
        }
        try validatePathComponents(
            relativePath: storeRelativePath,
            root: containerURL,
            fileManager: fileManager
        )

        let allStoreEntries = (try? fileManager.contentsOfDirectory(atPath: storeURL.path)) ?? []
        Log.info("[WallpaperLabScan] store entries (\(allStoreEntries.count)): \(allStoreEntries.prefix(20).joined(separator: ", "))")
        let generationURLs = try fileManager.contentsOfDirectory(
            at: storeURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard Int(url.lastPathComponent) != nil else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }.sorted {
            (Int($0.lastPathComponent) ?? -1) > (Int($1.lastPathComponent) ?? -1)
        }
        Log.info("[WallpaperLabScan] integer generations=\(generationURLs.map(\.lastPathComponent).joined(separator: ","))")

        guard !generationURLs.isEmpty else {
            throw WallpaperLabError.unsupportedPosterLayout
        }

        for generationURL in generationURLs {
            let extensionsURL = generationURL.appendingPathComponent("Extensions", isDirectory: true)
            guard fileManager.fileExists(atPath: extensionsURL.path) else {
                Log.info("[WallpaperLabScan] gen \(generationURL.lastPathComponent): no Extensions dir")
                continue
            }
            try validateDirectory(extensionsURL, fileManager: fileManager)

            var descriptorDirectories: [String: URL] = [:]
            let extensions = try fileManager.contentsOfDirectory(
                at: extensionsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            let genName = generationURL.lastPathComponent
            let registryURL = generationURL.appendingPathComponent(
                "PBFPosterExtensionDataStoreSQLiteDatabase.sqlite3"
            )
            Log.info(
                "[WallpaperLabScan] gen \(genName) Extensions entries=\(extensions.count) " +
                "registryDB=\(fileManager.fileExists(atPath: registryURL.path) ? 1 : 0)"
            )
            for (index, extensionURL) in extensions.enumerated() {
                let values = try extensionURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                let isDir = values.isDirectory == true
                let isSym = values.isSymbolicLink == true
                guard isDir, !isSym else {
                    Log.info(
                        "[WallpaperLabScan]   #\(index) non-dir (dir=\(isDir ? 1 : 0) sym=\(isSym ? 1 : 0)) skipped"
                    )
                    continue
                }
                let extName = extensionURL.lastPathComponent
                let idOK = validExtensionIdentifier(extName)

                // descriptor-container 探测:descriptors(iOS ≤26 世代 / 3105 写路径)
                // 与 configurations(iOS 26/27 PosterBoard 自维护布局)双兼容,
                // 仅作数据解析兼容,不放宽任何校验。
                let foundURL = WallpaperLayoutScanner.descriptorContainerURL(
                    in: extensionURL,
                    fileManager: fileManager
                )
                let foundKind = foundURL?.lastPathComponent

                let rejected = rejectedScalars(in: extName, valid: idOK)
                if let kind = foundKind, let dir = foundURL {
                    let children = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
                    Log.info(
                        "[WallpaperLabScan]   #\(index) len=\(extName.utf8.count) id=\(idOK ? "OK" : "BAD") " +
                        "bad=\(rejected) store=\(kind) n=\(children.count) name=\(Self.logEscaped(extName))"
                    )
                    guard idOK else { continue }
                    try validateDirectory(dir, fileManager: fileManager)
                    let sample = children.prefix(2).map(Self.logEscaped).joined(separator: ", ")
                    if !children.isEmpty {
                        Log.info("[WallpaperLabScan]   #\(index) sample=[\(sample)]")
                    }
                    descriptorDirectories[extName] = dir
                } else {
                    Log.info(
                        "[WallpaperLabScan]   #\(index) len=\(extName.utf8.count) id=\(idOK ? "OK" : "BAD") " +
                        "bad=\(rejected) store=none name=\(Self.logEscaped(extName))"
                    )
                }
            }

            if !descriptorDirectories.isEmpty {
                return WallpaperPosterLayout(
                    generation: generationURL.lastPathComponent,
                    storeURL: storeURL,
                    extensionDescriptorDirectories: descriptorDirectories
                )
            }
        }
        Log.info("[WallpaperLabScan] no usable generation found → unsupportedPosterLayout")
        throw WallpaperLabError.unsupportedPosterLayout
    }

    static func validExtensionIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255, value.contains(".") else { return false }
        return value.unicodeScalars.allSatisfy(isAllowedBundleIdentifierScalar)
    }

    /// 扩展标识符的允许字符域:bundle identifier 按 Apple 约定为 ASCII 反向域名。
    /// 用纯标量区间判断而非 CharacterSet:实测 iOS 26.6.1(23G83)真机上
    /// `CharacterSet.alphanumerics.union(...).contains(Unicode.Scalar)` 链对纯 ASCII
    /// 字符串返回 false(macOS 同代码正常),疑似运行时/工具链差异;区间判断跨版本确定。
    /// 语义上比 CharacterSet.alphanumerics(含非 ASCII 字母)更严格,属收紧而非放宽。
    static func isAllowedBundleIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2E, 0x2D, 0x5F:
            return true
        default:
            return false
        }
    }

    /// PosterBoard 扩展目录下的 descriptor 容器目录名。
    /// iOS ≤26(3105/Nugget/mond/Pocket-Poster 写路径)= descriptors;
    /// iOS 26/27 PosterBoard 自维护 = configurations(实测于真机备份与模拟器活体,
    /// Tendies-Restorer 佐证)。探测顺序 descriptors 优先,保持与 3105 的写入目标一致。
    static let descriptorContainerKinds = ["descriptors", "configurations"]

    /// 返回扩展目录下实际存在的 descriptor 容器目录(descriptors 优先),都不存在则 nil。
    static func descriptorContainerURL(
        in extensionURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        for kind in descriptorContainerKinds {
            let candidate = extensionURL.appendingPathComponent(kind, isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// 校验失败时,给出被拒的具体 scalar(idOK 时返回 "-")。
    /// 与 validExtensionIdentifier 共用同一谓词(单一事实来源,不可能互相矛盾)。
    static func rejectedScalars(in value: String, valid idOK: Bool) -> String {
        guard !idOK else { return "-" }
        if value.isEmpty || value.utf8.count > 255 || !value.contains(".") {
            return "(structural)"
        }
        let bad = value.unicodeScalars
            .filter { !isAllowedBundleIdentifierScalar($0) }
            .prefix(4)
        guard !bad.isEmpty else { return "(unexpected)" }
        return bad.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }

    /// 日志转义:仅保留可打印 ASCII,其余 scalar 输出为 \uXXXX,防止隐形字符在日志里被吞。
    static func logEscaped(_ value: String) -> String {
        var out = "\""
        out.reserveCapacity(value.utf8.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x20...0x7E:
                if scalar.value == 0x22 || scalar.value == 0x5C {
                    out.append("\\")
                }
                out.unicodeScalars.append(scalar)
            default:
                out.append(String(format: "\\u{%04X}", scalar.value))
            }
        }
        out.append("\"")
        return out
    }

    static func validateDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw WallpaperLabError.posterStoreUnavailable
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw WallpaperLabError.symbolicLinkUnsupported
        }
        guard values.isDirectory == true else {
            throw WallpaperLabError.unsupportedPosterLayout
        }
    }

    static func validatePathComponents(
        relativePath: String,
        root: URL,
        fileManager: FileManager = .default
    ) throws {
        var cursor = root
        for component in relativePath.split(separator: "/").map(String.init) {
            cursor.appendPathComponent(component, isDirectory: true)
            guard isContained(cursor, in: root) else {
                throw WallpaperLabError.unsafeContainerRoot
            }
            try validateDirectory(cursor, fileManager: fileManager)
        }
    }

    static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}

enum TendiesPackageInspector {
    static func inspectExtractedPackage(
        at packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> TendiesPayload {
        try WallpaperLayoutScanner.validateDirectory(packageURL, fileManager: fileManager)
        let descriptors = try collectDescriptorSources(
            in: packageURL,
            packageRoot: packageURL,
            fileManager: fileManager
        )

        guard !descriptors.isEmpty else { throw WallpaperLabError.noDescriptors }
        guard descriptors.count <= WallpaperLabLimits.maximumDescriptorCount else {
            throw WallpaperLabError.packageTooLarge
        }
        let totalBytes = descriptors.reduce(Int64(0)) { $0 + $1.byteCount }
        let fileCount = descriptors.reduce(0) { $0 + $1.fileCount }
        guard totalBytes <= WallpaperLabLimits.maximumExpandedBytes,
              fileCount <= WallpaperLabLimits.maximumEntryCount else {
            throw WallpaperLabError.packageTooLarge
        }
        return TendiesPayload(
            descriptors: descriptors,
            totalBytes: totalBytes,
            fileCount: fileCount
        )
    }

    private static func collectDescriptorSources(
        in directory: URL,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> [WallpaperDescriptorSource] {
        guard WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WallpaperDescriptorSource] = []

        for child in children where child.lastPathComponent != "__MACOSX" {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else { continue }

            let name = child.lastPathComponent.lowercased()
            if name == "container" {
                let layout = try WallpaperLayoutScanner.scan(
                    containerURL: child,
                    rootValidator: { $0.standardizedFileURL == child.standardizedFileURL },
                    fileManager: fileManager
                )
                for (identifier, descriptorDirectory) in layout.extensionDescriptorDirectories
                    .sorted(by: { $0.key < $1.key }) {
                    result += try descriptorSources(
                        in: descriptorDirectory,
                        extensionIdentifier: identifier,
                        isOrdered: false,
                        packageRoot: packageRoot,
                        fileManager: fileManager
                    )
                }
            } else if name.contains("descriptor") {
                let extensionIdentifier: String
                if name.contains("video") || name.contains("photos") {
                    extensionIdentifier = WallpaperPosterLayout.photosExtension
                } else if name.contains("mercury") {
                    extensionIdentifier = WallpaperPosterLayout.mercuryExtension
                } else {
                    extensionIdentifier = WallpaperPosterLayout.collectionsExtension
                }
                result += try descriptorSources(
                    in: child,
                    extensionIdentifier: extensionIdentifier,
                    isOrdered: name.contains("ordered"),
                    packageRoot: packageRoot,
                    fileManager: fileManager
                )
            } else {
                result += try collectDescriptorSources(
                    in: child,
                    packageRoot: packageRoot,
                    fileManager: fileManager
                )
            }
        }
        return result
    }

    private static func descriptorSources(
        in directory: URL,
        extensionIdentifier: String,
        isOrdered: Bool,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> [WallpaperDescriptorSource] {
        guard WallpaperLayoutScanner.validExtensionIdentifier(extensionIdentifier),
              WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WallpaperDescriptorSource] = []
        for child in children where child.lastPathComponent != "__MACOSX" {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else { continue }
            let summary = try validateTree(
                at: child,
                packageRoot: packageRoot,
                fileManager: fileManager
            )
            result.append(
                WallpaperDescriptorSource(
                    extensionIdentifier: extensionIdentifier,
                    directoryURL: child,
                    byteCount: summary.bytes,
                    fileCount: summary.files,
                    isOrdered: isOrdered
                )
            )
        }
        return result
    }

    private static func validateTree(
        at directory: URL,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> (bytes: Int64, files: Int) {
        guard WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        var bytes: Int64 = 0
        var files = 0
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw WallpaperLabError.unsupportedPackage
        }
        for case let itemURL as URL in enumerator {
            guard WallpaperLayoutScanner.isContained(itemURL, in: packageRoot),
                  itemURL.path.utf8.count <= WallpaperLabLimits.maximumPathBytes else {
                throw WallpaperLabError.unsafeArchive
            }
            let values = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ])
            if values.isSymbolicLink == true {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard size >= 0, size <= WallpaperLabLimits.maximumEntryBytes else {
                    throw WallpaperLabError.packageTooLarge
                }
                bytes += size
                files += 1
                guard bytes <= WallpaperLabLimits.maximumExpandedBytes,
                      files <= WallpaperLabLimits.maximumEntryCount else {
                    throw WallpaperLabError.packageTooLarge
                }
            } else if values.isDirectory != true {
                throw WallpaperLabError.unsupportedPackage
            }
        }
        return (bytes, files)
    }
}
