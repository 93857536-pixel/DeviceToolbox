import Foundation

/// 补丁工作台(域 B)服务层错误集合。
enum PatchWorkspaceError: Error, Equatable, Sendable {
    case unsupportedFormat
    case unsupportedVersion
    case invalidPasswordOrCorruptedPackage
    case invalidProject
    case invalidBundleIdentifier
    case unsafeTargetPath
    case duplicateTarget
    case projectAlreadyApplied
    case restoreTargetsChanged([String])
    case privatePatchRequiresPassword
    case notFound
    case writeFailed
    case applyFailed
    case restoreFailed
}

extension PatchWorkspaceError: LocalizedError {
    /// 本地化 key(值由主会话在集成期合并进 Localizable.strings)。
    var localizationKey: String {
        switch self {
        case .unsupportedFormat: return "patch.error.unsupported_format"
        case .unsupportedVersion: return "patch.error.unsupported_version"
        case .invalidPasswordOrCorruptedPackage: return "patch.error.password_or_corrupt"
        case .invalidProject: return "patch.error.invalid_project"
        case .invalidBundleIdentifier: return "patch.error.invalid_bundle"
        case .unsafeTargetPath: return "patch.error.unsafe_path"
        case .duplicateTarget: return "patch.error.duplicate_target"
        case .projectAlreadyApplied: return "patch.error.already_applied"
        case .restoreTargetsChanged: return "patch.error.restore_targets_changed"
        case .privatePatchRequiresPassword: return "patch.error.private_password"
        case .notFound: return "patch.error.not_found"
        case .writeFailed: return "patch.error.write_failed"
        case .applyFailed: return "patch.error.apply"
        case .restoreFailed: return "patch.error.restore"
        }
    }

    var errorDescription: String? {
        let message = String(localized: String.LocalizationValue(localizationKey))
        if case .restoreTargetsChanged(let paths) = self {
            return message + "\n" + paths.joined(separator: "\n")
        }
        return message
    }
}
