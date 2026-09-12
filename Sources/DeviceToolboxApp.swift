import SwiftUI
import UIKit

/// App 入口。
///
/// 根视图按「免责声明状态」切换:未同意时显示全屏 `DisclaimerView`,
/// 同意后进入 `MainTabView`(5 Tab 主界面)。状态持久化在 UserDefaults,
/// 键使用 `AppStorageKeys.disclaimerAccepted`。
@main
struct DeviceToolboxApp: App {
    @StateObject private var rootViewModel: RootViewModel

    init() {
        // UI 测试支持:通过 launch argument 重置首次启动状态,
        // 让测试能稳定复现「首次启动 → 免责声明 → 同意 → 主界面」流程。
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetDisclaimer") {
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.disclaimerAccepted)
        }
        _rootViewModel = StateObject(wrappedValue: RootViewModel())

        // 液态玻璃外观:Tab 栏透明 + 超薄材质(浅色/深色模式自适应)。
        let tabBar = UITabBarAppearance()
        tabBar.configureWithTransparentBackground()
        tabBar.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(rootViewModel)
        }
    }
}

/// 根视图:根据免责声明同意状态决定进入主界面还是免责声明页。
struct RootView: View {
    @EnvironmentObject private var rootViewModel: RootViewModel

    var body: some View {
        if rootViewModel.hasAcceptedDisclaimer {
            MainTabView()
        } else {
            DisclaimerView(onAccept: { rootViewModel.acceptDisclaimer() })
        }
    }
}
