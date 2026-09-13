import SwiftUI

/// 设置页导航目标(数据与日志)。
enum SettingsRoute: Hashable {
    case gestaltSnapshot
    case operationLog
}

/// 设置:关于 / 免责声明 / 隐私 / 开源许可 / 检查更新 / 清除缓存 / 重置免责声明。
struct SettingsView: View {
    @EnvironmentObject private var rootViewModel: RootViewModel
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var activeSheet: SettingsSheet?
    @State private var showClearCacheDone = false

    private enum SettingsSheet: Identifiable {
        case disclaimer
        case privacy
        case licenses
        case update

        var id: Self { self }
    }

    var body: some View {
        List {
            Section(String(localized: "settings.about")) {
                LabeledContent(String(localized: "settings.about.version"), value: appVersion)
                LabeledContent(String(localized: "settings.about.min.ios"), value: "17.0")
            }

            Section(String(localized: "privilege.title")) {
                PrivilegeStatusView()
            }

            Section(String(localized: "aienable.title")) {
                AIEnableView()
            }

            Section(String(localized: "modelspoof.title")) {
                ModelSpoofView()
            }

            Section(String(localized: "settings.data.section")) {
                NavigationLink(value: SettingsRoute.gestaltSnapshot) {
                    Label(String(localized: "settings.data.gestalt"), systemImage: "doc.badge.clock")
                }
                NavigationLink(value: SettingsRoute.operationLog) {
                    Label(String(localized: "settings.data.logs"), systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("settings.logLink")
            }

            Section(String(localized: "settings.general")) {
                Button(String(localized: "settings.disclaimer")) {
                    activeSheet = .disclaimer
                }
                Button(String(localized: "settings.privacy")) {
                    activeSheet = .privacy
                }
                Button(String(localized: "settings.licenses")) {
                    activeSheet = .licenses
                }
            }

            languageSection

            Section(String(localized: "settings.actions")) {
                Button(String(localized: "settings.check.update")) {
                    activeSheet = .update
                }
                Button(String(localized: "settings.clear.cache")) {
                    clearCache()
                }
            }

            Section {
                Button(String(localized: "settings.reset.disclaimer"), role: .destructive) {
                    rootViewModel.resetDisclaimer()
                }
            }
        }
        .navigationTitle(String(localized: "settings.title"))
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .gestaltSnapshot: GestaltSnapshotView()
            case .operationLog: LogView()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .disclaimer:
                NavigationStack {
                    DisclaimerView()
                        .navigationTitle(String(localized: "settings.disclaimer"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            case .privacy:
                NavigationStack {
                    infoSheet(
                        title: String(localized: "settings.privacy"),
                        body: String(localized: "settings.privacy.body"),
                        icon: "lock.shield"
                    )
                }
            case .licenses:
                NavigationStack {
                    infoSheet(
                        title: String(localized: "settings.licenses"),
                        body: String(localized: "settings.licenses.body"),
                        icon: "doc.text"
                    )
                }
            case .update:
                NavigationStack {
                    infoSheet(
                        title: String(localized: "settings.check.update"),
                        body: String(localized: "settings.check.update.result"),
                        icon: "arrow.triangle.2.circlepath"
                    )
                }
            }
        }
        .alert(String(localized: "settings.clear.cache.done"), isPresented: $showClearCacheDone) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// 语言切换区:Picker 选中即写入 `AppleLanguages`(应用级偏好),重启 App 后生效;
    /// 未重启时显示提示。
    private var languageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Picker(
                    String(localized: "settings.language"),
                    selection: Binding(
                        get: { languageManager.selected },
                        set: { languageManager.select($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings.languagePicker")
                if !languageManager.isSelectionApplied {
                    Label(String(localized: "settings.language.restartHint"), systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.languageRestartHint")
                }
            }
        } header: {
            Text(String(localized: "settings.language"))
        }
    }

    private func clearCache() {
        // 清除非必要缓存,保留免责声明状态等关键项。
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.lastDeviceScanDate)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.lowPowerModeNotified)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.compatibilityCacheVersion)
        Log.info("缓存已清除")
        showClearCacheDone = true
    }

    private func infoSheet(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text(body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.pageBackdrop)
    }
}
