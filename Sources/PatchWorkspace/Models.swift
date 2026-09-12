import Foundation

// MARK: - 补丁动作

/// 单条补丁规则的动作类型。
enum PatchAction: String, Codable, Sendable, Hashable {
    /// 用 replacementData 覆盖目标文件(可携带零字节载荷)。
    case replaceFile
    /// 删除目标文件。
    case deleteFile
    /// 新增目录(相对路径即目录路径)。
    case addFolder
}

// MARK: - 补丁规则

/// 单条补丁规则。relativePath 为目标根内的相对路径;
/// 对从 3105 导入的包,relativePath 前缀为 "<bundleID>/"。
struct PatchRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var relativePath: String
    var action: PatchAction
    /// 替换文件的原始文件名(仅 replaceFile 有意义,可为 nil)。
    var replacementFilename: String?
    /// 替换文件的内容(仅 replaceFile 有意义,零字节文件为空的 Data)。
    var replacementData: Data?

    init(
        id: UUID = UUID(),
        relativePath: String,
        action: PatchAction,
        replacementFilename: String? = nil,
        replacementData: Data? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.action = action
        self.replacementFilename = replacementFilename
        self.replacementData = replacementData
    }
}

// MARK: - 项目来源

/// 记录包从仓库导入时的来源信息;直接文件导入时为 nil。
struct PatchProjectOrigin: Codable, Hashable, Sendable {
    var repositoryName: String?
    var repositoryURL: String?
    var packageIdentifier: String?

    init(
        repositoryName: String? = nil,
        repositoryURL: String? = nil,
        packageIdentifier: String? = nil
    ) {
        self.repositoryName = repositoryName
        self.repositoryURL = repositoryURL
        self.packageIdentifier = packageIdentifier
    }
}

// MARK: - 补丁项目

/// 补丁项目(即一个补丁包的核心数据模型)。
struct PatchProject: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var author: String
    var isPrivate: Bool
    var createdAt: Date
    var updatedAt: Date
    /// 沙盒内目标基目录名,默认 "Patches"。
    var targetRootName: String
    /// 从仓库导入时的来源信息(直接文件导入为 nil)。
    var origin: PatchProjectOrigin?
    var rules: [PatchRule]

    init(
        id: UUID = UUID(),
        name: String,
        author: String = "",
        isPrivate: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        targetRootName: String = "Patches",
        origin: PatchProjectOrigin? = nil,
        rules: [PatchRule]
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.targetRootName = targetRootName
        self.origin = origin
        self.rules = rules
    }
}

// MARK: - 路径校验

/// 补丁相对路径校验与目标解析(仅限本 App 沙盒内)。
enum PatchPathValidator {
    /// 规范化相对路径;拒绝绝对路径、反斜杠、".."、"."、空段与控制字符。
    static func canonicalRelativePath(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= PatchPackageLimits.maximumPathBytes,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              !value.contains("//"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw PatchWorkspaceError.unsafeTargetPath
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PatchWorkspaceError.unsafeTargetPath
        }
        return components.joined(separator: "/")
    }

    /// 将相对路径解析到 root 之下的绝对 URL,并防止路径穿越(root 之外)。
    static func resolveTargetURL(relativePath: String, within root: URL) throws -> URL {
        let path = try canonicalRelativePath(relativePath)
        let root = root.standardizedFileURL
        var target = root
        for component in path.split(separator: "/") {
            target.appendPathComponent(String(component), isDirectory: false)
        }
        target = target.standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else {
            throw PatchWorkspaceError.unsafeTargetPath
        }
        return target
    }
}

// MARK: - 上限常量

enum PatchPackageLimits {
    static let maximumPathBytes = 4_096
    static let maximumAuthorBytes = 160
    static let maximumPasswordBytes = 1_024
    static let minimumKDFIterations = 100_000
    static let defaultKDFIterations = 250_000
    static let maximumKDFIterations = 1_000_000
}
