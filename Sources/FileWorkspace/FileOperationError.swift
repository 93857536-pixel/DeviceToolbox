import Foundation

/// 文件工作台服务层错误。
/// 每个 case 附带中文 + 英文双语文案(内联,不依赖本地化表)。
enum FileOperationError: Error, Equatable, Sendable, LocalizedError {
    case invalidName
    case nameTooLong
    case itemAlreadyExists
    case sourceMissing
    case destinationMissing
    case sourceIsDirectory
    case destinationIsDirectory
    case destinationNotDirectory
    case symbolicLinkUnsupported
    case recursiveDestination
    case sourceTooLarge
    case cannotRead
    case cannotCreate
    case cannotRename
    case cannotDelete
    case cannotImport
    case cannotCopy
    case cannotMove
    case cannotArchive
    case cannotExtract
    case unsafeArchive
    case insufficientSpace

    var errorDescription: String? {
        switch self {
        case .invalidName: return "无效的文件或文件夹名 · Invalid file or folder name"
        case .nameTooLong: return "名称过长 · The name is too long"
        case .itemAlreadyExists: return "同名项目已存在 · An item with this name already exists"
        case .sourceMissing: return "源文件不可用 · Source item is unavailable"
        case .destinationMissing: return "目标文件夹不存在或已被系统清理,请重新选择 · Destination no longer exists. It may have been cleared by iOS (Caches/tmp are cleared automatically); pick another folder."
        case .sourceIsDirectory: return "请选择文件,而非文件夹 · Select a file, not a folder"
        case .destinationIsDirectory: return "同名文件夹已存在 · A folder with this name already exists"
        case .destinationNotDirectory: return "目标不是文件夹 · Destination is not a folder"
        case .symbolicLinkUnsupported: return "不支持符号链接 · Symbolic links are not supported"
        case .recursiveDestination: return "文件夹不能复制或移动到自身内部 · A folder cannot be copied or moved into itself"
        case .sourceTooLarge: return "文件过大 · The file is too large"
        case .cannotRead: return "无法读取内容 · Cannot read contents"
        case .cannotCreate: return "无法创建项目 · The item could not be created"
        case .cannotRename: return "无法重命名 · The item could not be renamed"
        case .cannotDelete: return "无法删除 · The item could not be deleted"
        case .cannotImport: return "无法安全导入文件 · The file could not be imported safely"
        case .cannotCopy: return "无法复制所选项目 · The items could not be copied"
        case .cannotMove: return "无法移动所选项目 · The items could not be moved"
        case .cannotArchive: return "无法创建 ZIP 压缩包 · The ZIP archive could not be created"
        case .cannotExtract: return "无法解压 ZIP 压缩包 · The ZIP archive could not be extracted"
        case .unsafeArchive: return "ZIP 压缩包含不安全或不支持的条目 · The ZIP archive contains unsafe or unsupported entries"
        case .insufficientSpace: return "可用空间不足 · There is not enough free space"
        }
    }
}

/// ZIP 底层编解码错误(内部使用)。
/// 由 `ZipArchiveService` 映射为面向 UI 的 `FileOperationError`。
enum ZIPCodecError: Error, Equatable, Sendable {
    case emptySelection
    case invalidSource
    case invalidArchive
    case unsupportedCompression
    case unsafeEntry
    case entryTooLarge
    case tooManyEntries
    case archiveTooLarge
    case crcMismatch
    case writeFailed
    case readFailed
}
