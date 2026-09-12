# DeviceToolbox 架构说明

## 概述

DeviceToolbox 是一款 iOS 系统诊断与设备信息检测工具箱,仅使用 Apple 公开 API / 公开 URL Scheme。
零第三方依赖,纯 SwiftUI + Foundation,Swift 6 语言模式,iOS 17.0+。

## 分层结构

```
Sources/
  DeviceToolboxApp.swift     # @main 入口,根视图按免责声明状态切换
  Core/                      # 主题(Theme)、UserDefaults 键、日志(Log)、能力状态枚举
  Models/                    # 值类型模型:DeviceInfo / CompatibilityItem / FeatureItem
  Services/                  # 数据采集层(设备/电池/存储/网络/能力/权限/诊断等)
  ViewModels/                # @MainActor ObservableObject,业务状态与数据编排
  Views/                     # SwiftUI 视图层(Root/Home/Device/Features/Tools/Settings + Components)
  Resources/                 # Assets.xcassets + 中英 Localizable.strings + 兼容性库 JSON
```

## 数据流

```
View (SwiftUI)
  └─ @StateObject / @EnvironmentObject 持有 ViewModel
      └─ ViewModel (@MainActor ObservableObject,async/await)
          └─ Services (@MainActor final class,采集/评估)
              └─ Models (Codable + Sendable 值类型)
```

- **单向数据流**:View 只读 ViewModel 的 `@Published` 状态并派发动作;ViewModel 调用 Services,
  把结果写回自身状态;Services 返回不可变值类型模型。
- **并发**:全部 ViewModel/Service 用 `@MainActor` 隔离;网络等耗时操作经 async/await 挂起,不阻塞主线程。

## 首次启动免责声明

`RootViewModel` 持有 `hasAcceptedDisclaimer`(来源 `AppStorageKeys.disclaimerAccepted`)。
根视图按该状态切换 `DisclaimerView` / `MainTabView`:

- 未同意 → 全屏 `DisclaimerView`(不可跳过),点同意写 UserDefaults → 进入主界面。
- 设置页可重置该状态(`RootViewModel.resetDisclaimer()`),重置后重新显示免责声明。
- UI 测试通过 `-resetDisclaimer` launch argument 在启动时清除状态,稳定复现首次启动。

## 本地化

- 默认语言 `zh-Hans`,英文跟随系统。
- 全部 UI 文案经 `String(localized:)` 取键,键在 `en.lproj` / `zh-Hans.lproj` 的
  `Localizable.strings` 中英成对维护。
- 状态徽章文案(`status.*`)、权限(`permission.*`)、设备字段(`device.*`)等均走本地化。

## 主题与组件

- 主色 `Theme.accent`(#FF9500);状态色 `CapabilityStatus.themeColor`
  (✓ 绿 #34C759 / △ 橙 / × 红 #FF3B30 / ? 灰)。
- 卡片圆角 16(`Theme.cornerRadius`)、内边距 16(`Theme.cardPadding`)。
- 通用组件:StatCard / BadgeView / ProgressBarView / SectionCard / FeatureRowView。
- 背景用 `systemGroupedBackground`,卡片用 `secondarySystemGroupedBackground`,天然支持深色模式;
  系统字体 + Dynamic Type,横竖屏自适应(不锁方向)。
