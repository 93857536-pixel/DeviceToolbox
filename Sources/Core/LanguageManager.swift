import Foundation
import SwiftUI

/// 受支持的 App 语言选项。
///
/// rawValue 是 BCP-47 语言标签,与 `Sources/Resources/<tag>.lproj` 目录一一对应。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system          // 跟随系统
    case zhHans = "zh-Hans"   // 简体中文
    case zhHant = "zh-Hant"   // 繁体中文
    case en              // English
    case ja              // 日本語
    case ko              // 한국어

    var id: String { rawValue }

    /// 用户可见的显示名(各语言用自身文字书写,不做翻译)。
    var displayName: String {
        switch self {
        case .system: return String(localized: "language.system")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en:     return "English"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        }
    }
}

/// App 语言选择管理器。
///
/// 机制说明:iOS 在**进程启动时**按 `AppleLanguages` 用户偏好(优先级高于系统语言)
/// 选择 App 语言。因此选择后需要**重启 App** 才生效——这是 App 级覆盖,
/// 不修改系统全局语言设置。
///
/// 持久化:`AppStorageKeys.appLanguage` 保存用户选择;"AppleLanguages"
/// (UserDefaults 系统键)保存启动时生效的语言表。
/// 单例仅由主线程(UI)访问,标记 @unchecked Sendable 以满足 Swift 并发检查。
final class LanguageManager: ObservableObject, @unchecked Sendable {
    /// 共享单例(由 Settings 页与 App 入口使用)。
    static let shared = LanguageManager()

    /// 当前用户选择的语言(UI 状态,变化时驱动视图刷新)。
    @Published private(set) var selected: AppLanguage

    /// `AppleLanguages` 是 iOS 保留的系统级 UserDefaults 键,应用级覆盖即写此键。
    static let appleLanguagesKey = "AppleLanguages"

    init() {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.appLanguage) ?? ""
        selected = AppLanguage(rawValue: raw) ?? .system
    }

    /// 当前进程实际生效的语言标识(如 "zh-Hans"、"ja")。
    ///
    /// 取 `Bundle.main.preferredLocalizations` —— 进程启动时 iOS 按
    /// AppleLanguages / 系统语言实际选中的本地化,是确定性的单一值。
    var appliedLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// 用户选择是否已实际生效(已重启过,或选择为"跟随系统")。
    var isSelectionApplied: Bool {
        switch selected {
        case .system:
            return true
        default:
            return appliedLanguage.hasPrefix(selected.rawValue)
        }
    }

    /// 选择语言。写入 `AppleLanguages` 用户偏好,**App 下次启动时生效**。
    @discardableResult
    func select(_ language: AppLanguage) -> Bool {
        let defaults = UserDefaults.standard
        switch language {
        case .system:
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        default:
            defaults.set([language.rawValue], forKey: Self.appleLanguagesKey)
        }
        defaults.set(language.rawValue, forKey: AppStorageKeys.appLanguage)
        selected = language
        return true
    }
}
