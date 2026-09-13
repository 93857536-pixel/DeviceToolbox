import Foundation
import XCTest
@testable import DeviceToolbox

/// 壁纸实验室 .tendies 包结构解析测试(3105/Pocket-Poster 事实格式)。
///
/// 对照 3105 `TendiesPackageInspector.collectDescriptorSources`(搬运自 Pocket-Poster
/// `getDescriptorsFromTendie`)验证三类真实包结构都能被合法识别:
///   - `descriptors/`(静态 Collections)
///   - `video-descriptors/`(动态/实况照片 → PhotosPosterProvider)
///   - `container/`(完整 PosterBoard 布局,CollectionsPoster 或 PhotosPosterProvider)
/// 并验证"真正无法识别"的内容仍被拒(noDescriptors),符号链接等安全检查不因放行动态包而放宽。
final class WallpaperLabImportTests: XCTestCase {

    private var packageRoots: [URL] = []

    override func tearDown() {
        for root in packageRoots {
            try? FileManager.default.removeItem(at: root)
        }
        packageRoots.removeAll()
        super.tearDown()
    }

    // MARK: - 结构构造辅助

    /// 新建一个包根目录(测试结束后由 tearDown 清理)。
    private func makePackageRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallpaperlab-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        packageRoots.append(url)
        return url
    }

    /// 构造一个最小 descriptor bundle(含 descriptor 标识文件,可选加 .mov 视频载荷)。
    private func makeDescriptorBundle(
        in parent: URL,
        name: String = "BUNDLE-1",
        includeVideo: Bool = false
    ) throws -> URL {
        let bundle = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data("74000000".utf8)
            .write(to: bundle.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"))
        try Data("22".utf8)
            .write(to: bundle.appendingPathComponent("com.apple.posterkit.role.identifier"))
        try Data("<plist/>".utf8)
            .write(to: bundle.appendingPathComponent("Wallpaper.plist"))
        if includeVideo {
            try Data("VIDEO-PAYLOAD".utf8)
                .write(to: bundle.appendingPathComponent("live.mov"))
        }
        return bundle
    }

    /// 构造 `container/` 完整布局:PRBPosterExtensionDataStore/<gen>/Extensions/<ext>/descriptors/<bundle>。
    private func makeContainerStructure(
        extensionID: String,
        generation: String = "61",
        bundleName: String = "BUNDLE-1",
        includeVideo: Bool = false
    ) throws -> URL {
        let root = try makePackageRoot()
        let container = root.appendingPathComponent("Container", isDirectory: true)
        let descriptors = container
            .appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore", isDirectory: true)
            .appendingPathComponent(generation, isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent(extensionID, isDirectory: true)
            .appendingPathComponent("descriptors", isDirectory: true)
        try FileManager.default.createDirectory(at: descriptors, withIntermediateDirectories: true)
        _ = try makeDescriptorBundle(in: descriptors, name: bundleName, includeVideo: includeVideo)
        return root
    }

    /// 运行 inspector 并返回 payload(供断言)。
    private func inspect(_ root: URL) throws -> TendiesPayload {
        try TendiesPackageInspector.inspectExtractedPackage(at: root)
    }

    // MARK: - 静态回归

    func testStaticDescriptorsStructureMapsToCollections() throws {
        let root = try makePackageRoot()
        let descriptorsDir = root.appendingPathComponent("descriptors", isDirectory: true)
        try FileManager.default.createDirectory(at: descriptorsDir, withIntermediateDirectories: true)
        _ = try makeDescriptorBundle(in: descriptorsDir)

        let payload = try inspect(root)
        XCTAssertEqual(payload.descriptors.count, 1)
        XCTAssertEqual(
            payload.descriptors.first?.extensionIdentifier,
            WallpaperPosterLayout.collectionsExtension
        )
    }

    // MARK: - 动态/实况壁纸放行

    func testVideoDescriptorsStructureMapsToPhotosProvider() throws {
        let root = try makePackageRoot()
        let videoDir = root.appendingPathComponent("video-descriptors", isDirectory: true)
        try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
        _ = try makeDescriptorBundle(in: videoDir, includeVideo: true)

        let payload = try inspect(root)
        XCTAssertEqual(payload.descriptors.count, 1)
        XCTAssertEqual(
            payload.descriptors.first?.extensionIdentifier,
            WallpaperPosterLayout.photosExtension
        )
        // .mov 载荷作为普通文件计入,不因扩展名被拒。
        XCTAssertEqual(payload.fileCount, 4)
    }

    func testContainerWithCollectionsVideoImports() throws {
        let root = try makeContainerStructure(
            extensionID: WallpaperPosterLayout.collectionsExtension,
            includeVideo: true
        )
        let payload = try inspect(root)
        XCTAssertEqual(payload.descriptors.count, 1)
        XCTAssertEqual(
            payload.descriptors.first?.extensionIdentifier,
            WallpaperPosterLayout.collectionsExtension
        )
    }

    func testContainerWithPhotosProviderImports() throws {
        let root = try makeContainerStructure(
            extensionID: WallpaperPosterLayout.photosExtension,
            includeVideo: true
        )
        let payload = try inspect(root)
        XCTAssertEqual(payload.descriptors.count, 1)
        XCTAssertEqual(
            payload.descriptors.first?.extensionIdentifier,
            WallpaperPosterLayout.photosExtension
        )
    }

    // MARK: - 真正无法识别的内容仍被拒(noDescriptors,而非动态特判)

    func testUnrecognizedStructureWithVideoFileThrowsNoDescriptors() throws {
        let root = try makePackageRoot()
        // 顶层目录名不匹配任何已知布局(不含 "container" 也不含 "descriptor"),
        // 即使内含视频文件,也应统一抛 noDescriptors —— 不再有 dynamicContentUnsupported 特判。
        let mystery = root.appendingPathComponent("mystery", isDirectory: true)
        try FileManager.default.createDirectory(at: mystery, withIntermediateDirectories: true)
        try Data("VIDEO".utf8).write(to: mystery.appendingPathComponent("clip.mov"))

        XCTAssertThrowsError(try inspect(root)) { error in
            XCTAssertEqual(error as? WallpaperLabError, .noDescriptors)
        }
    }

    // MARK: - 安全检查不因放行动态包而放宽

    func testSymlinkInsideDescriptorBundleStillRejected() throws {
        let root = try makePackageRoot()
        let descriptorsDir = root.appendingPathComponent("video-descriptors", isDirectory: true)
        try FileManager.default.createDirectory(at: descriptorsDir, withIntermediateDirectories: true)
        let bundle = try makeDescriptorBundle(in: descriptorsDir, includeVideo: true)
        // 在 descriptor bundle 内放一个指向包外文件的符号链接 → 必须仍抛 symbolicLinkUnsupported。
        let outside = root.appendingPathComponent("outside.txt", isDirectory: false)
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: bundle.appendingPathComponent("escape-link"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try inspect(root)) { error in
            XCTAssertEqual(error as? WallpaperLabError, .symbolicLinkUnsupported)
        }
    }
}
