import SwiftUI

/// 主界面 5 个 Tab。
enum MainTab: Hashable {
    case home
    case device
    case files
    case patches
    case settings
}

/// 5 Tab 主界面:首页 / 设备 / 文件 / 补丁 / 设置。
struct MainTabView: View {
    @State private var selection: MainTab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(selectedTab: $selection)
            }
            .tabItem { Label(String(localized: "tab.home"), systemImage: "house") }
            .tag(MainTab.home)

            NavigationStack {
                DeviceView()
            }
            .tabItem { Label(String(localized: "tab.device"), systemImage: "iphone") }
            .tag(MainTab.device)

            NavigationStack {
                FilesTabView()
            }
            .tabItem { Label(String(localized: "tab.files"), systemImage: "folder") }
            .tag(MainTab.files)

            NavigationStack {
                PatchesTabView()
            }
            .tabItem { Label(String(localized: "tab.patches"), systemImage: "square.and.pencil") }
            .tag(MainTab.patches)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(String(localized: "tab.settings"), systemImage: "gearshape") }
            .tag(MainTab.settings)
        }
        .tint(Theme.accent)
        .background(Theme.pageBackdrop)
    }
}
