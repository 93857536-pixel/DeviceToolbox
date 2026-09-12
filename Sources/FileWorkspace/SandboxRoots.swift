import Foundation

/// 沙盒根目录入口:Documents / Caches / tmp,以及「已导入」子目录 Documents/Imported。
struct SandboxRoot: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable, Hashable, CaseIterable {
        case documents
        case caches
        case temporary
        case imported
    }

    let kind: Kind
    let url: URL

    var id: String { kind.rawValue }

    /// 展示名称(走本地化,key 前缀 files.root.*)。
    var title: String {
        String(localized: "files.root.\(kind.rawValue)")
    }
}

/// 沙盒根目录解析器:只暴露 FileManager 可达范围,不做任何绝对路径越权。
enum SandboxRoots: Sendable {
    /// 文档目录。
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// 缓存目录。
    static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    /// 临时目录。
    static var temporary: URL {
        FileManager.default.temporaryDirectory
    }

    /// 「已导入」目录:Documents/Imported。
    static var imported: URL {
        documents.appendingPathComponent("Imported", isDirectory: true)
    }

    /// 三个主根 + 已导入目录的入口列表。
    static func roots() -> [SandboxRoot] {
        [
            SandboxRoot(kind: .documents, url: documents),
            SandboxRoot(kind: .caches, url: caches),
            SandboxRoot(kind: .temporary, url: temporary),
            SandboxRoot(kind: .imported, url: imported),
        ]
    }

    /// 确保「已导入」目录存在,返回其 URL。
    @discardableResult
    static func ensureImportedDirectory() throws -> URL {
        let url = imported
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw FileOperationError.cannotCreate
            }
        }
        return url
    }
}
