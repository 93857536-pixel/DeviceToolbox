import Foundation
import UIKit

/// URL Scheme 跳转结果。
struct SchemeActionResult: Sendable, Equatable {
    let succeeded: Bool
    let message: String
}

/// 设置快捷入口:仅使用公开 URL Scheme 与 openSettingsURLString。
/// 第三方 App 深链跳转在 iOS 10+ 多数已失效,失败时诚实提示手动前往。
@MainActor
final class URLSchemeService {
    /// 打开 App 自身设置页(openSettingsURLString 一定可用)。
    static func openAppSettings() async -> SchemeActionResult {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return SchemeActionResult(succeeded: false, message: String(localized: "settings.jump.denied"))
        }
        let success = await UIApplication.shared.open(url)
        if success {
            return SchemeActionResult(succeeded: true, message: String(localized: "settings.open"))
        }
        return SchemeActionResult(succeeded: false, message: String(localized: "settings.jump.denied"))
    }

    /// 打开系统设置指定子页(如 App-Prefs:root=WIFI)。
    /// iOS 10+ 第三方深链可能失效;open 返回 false 时返回诚实失败文案。
    static func openPreferences(root: String) async -> SchemeActionResult {
        guard let url = URL(string: "App-Prefs:root=\(root)") else {
            return SchemeActionResult(succeeded: false, message: String(localized: "settings.jump.denied"))
        }
        let success = await UIApplication.shared.open(url)
        if success {
            return SchemeActionResult(succeeded: true, message: String(localized: "settings.open"))
        }
        return SchemeActionResult(succeeded: false, message: String(localized: "settings.jump.denied"))
    }
}
