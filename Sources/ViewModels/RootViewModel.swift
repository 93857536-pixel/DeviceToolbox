import Combine
import Foundation

/// 根视图状态:免责声明同意态 + 设备信息加载态。
@MainActor
final class RootViewModel: ObservableObject {
    /// 是否已同意免责声明。true 时根视图进入主界面。
    @Published private(set) var hasAcceptedDisclaimer: Bool

    /// 免责声明加载态(预留,当前仅本地 UserDefaults 读取,同步完成)。
    @Published private(set) var isLoadingDisclaimer = false

    init() {
        hasAcceptedDisclaimer = UserDefaults.standard.bool(forKey: AppStorageKeys.disclaimerAccepted)
    }

    /// 同意免责声明:写入 UserDefaults 并切换根视图到主界面。
    func acceptDisclaimer() {
        UserDefaults.standard.set(true, forKey: AppStorageKeys.disclaimerAccepted)
        hasAcceptedDisclaimer = true
        Log.info("免责声明已同意")
    }

    /// 重置免责声明状态(设置页调用):下次启动或立即重新显示免责声明。
    func resetDisclaimer() {
        UserDefaults.standard.set(false, forKey: AppStorageKeys.disclaimerAccepted)
        hasAcceptedDisclaimer = false
        Log.info("免责声明状态已重置")
    }
}
