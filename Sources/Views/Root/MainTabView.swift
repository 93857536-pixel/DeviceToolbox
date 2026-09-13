import SwiftUI

/// 主界面 5 个 Tab。
enum MainTab: Hashable {
    case home
    case device
    case files
    case patches   // 实验工具页(补丁工作台 + 两个实验室)
    case settings
}

/// 5 Tab 主界面:首页 / 设备 / 文件 / 实验 / 设置。
struct MainTabView: View {
    @State private var selection: MainTab = .home
    /// 全应用折叠玻璃特效引擎(App 入口经 `.environment()` 注入)。
    /// 开关开启时整棵主界面子树按设备倾角渲染成"透过倾斜玻璃窗"的效果;
    /// 关闭或平放(angle≈0)时 shader 自动失效,零采样开销。
    @Environment(FoldEffectEngine.self) private var foldEffect

    var body: some View {
        TabView(selection: $selection) {
            tabContent(.home) {
                HomeView(selectedTab: $selection)
            }
            .tabItem { Label(String(localized: "tab.home"), systemImage: "house") }
            .tag(MainTab.home)

            tabContent(.device) {
                DeviceView()
            }
            .tabItem { Label(String(localized: "tab.device"), systemImage: "iphone") }
            .tag(MainTab.device)

            tabContent(.files) {
                FilesTabView()
            }
            .tabItem { Label(String(localized: "tab.files"), systemImage: "folder") }
            .tag(MainTab.files)

            tabContent(.patches) {
                PatchesTabView()
            }
            .tabItem { Label(String(localized: "tab.experiments"), systemImage: "flask") }
            .tag(MainTab.patches)

            tabContent(.settings) {
                SettingsView()
            }
            .tabItem { Label(String(localized: "tab.settings"), systemImage: "gearshape") }
            .tag(MainTab.settings)
        }
        .tint(Theme.accent)
        .background(Theme.pageBackdrop)
    }

    /// 单个 tab 页内容 + 条件折叠玻璃特效。
    ///
    /// 特效套在**页内容**上而不是整个 TabView 外层:对 TabView 整体压平
    /// (compositingGroup + layerEffect)会在 iOS 26 的 AX 树里把 tab 栏按钮
    /// 数成两倍(UI 测试实测 10 vs 5)。套在页内容上则 tab 栏不受影响,
    /// 且只有**当前选中**的页才套效果(angle 条件),离屏页 angle=0 →
    /// shader 自动禁用,零采样开销。
    private func tabContent<Content: View>(
        _ tab: MainTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
        }
        .glassFold(angle: selection == tab ? foldEffect.currentAngle : 0)
    }
}
