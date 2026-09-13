import SwiftUI
import UIKit

/// App 入口。
///
/// 根视图按「免责声明状态」切换:未同意时显示全屏 `DisclaimerView`,
/// 同意后进入 `MainTabView`(6 Tab 主界面)。状态持久化在 UserDefaults,
/// 键使用 `AppStorageKeys.disclaimerAccepted`。
@main
struct DeviceToolboxApp: App {
    @StateObject private var rootViewModel: RootViewModel
    /// 全应用折叠玻璃特效引擎:App 级单例,经 `.environment()` 注入主界面,
    /// 主界面整棵子树按设备倾角渲染成"透过倾斜玻璃窗"的效果(用户可全局开关)。
    @State private var foldEffect: FoldEffectEngine = {
        // UI 测试支持:launch argument 直接开启特效(persist=false,不写默认值),
        // 避免测试里依赖"点开关"这种会被玻璃压平污染命中测试的脆弱路径。
        if ProcessInfo.processInfo.arguments.contains("-enableFoldEffect") {
            let engine = FoldEffectEngine()
            engine.setEnabled(true, persist: false)
            return engine
        }
        return FoldEffectEngine()
    }()

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
                .environment(foldEffect)
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
